//! Device→host notifications (firmware notification protocol v2).
//!
//! The firmware pushes a packet on bulk IN endpoint 0x83 whenever a parameter
//! changes, whoever changed it: this app (source HOST_SET), a hardware
//! control (GPIO), the OS volume slider (UAC1), UART/I2C, or a preset load.
//! A listener thread reads the endpoint into a queue and wakes the GUI, which
//! applies the queue on its own thread with `DspiCore::process_notifications`.
//!
//! PARAM_CHANGED addresses a field by its offset into the bulk image, so one
//! generic path covers every parameter: patch the bytes into an image of the
//! current state and decode it. BULK_INVALIDATED, a sequence gap or a queue
//! overflow re-reads everything.

use std::collections::VecDeque;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use log::{debug, warn};
use rusb::{DeviceHandle, GlobalContext};

use crate::protocol::*;
use crate::state::COMPAT_OK;
use crate::types::*;
use crate::monitor::MonitorLog;
use crate::DspiCore;

/// Bulk IN notification endpoint on the vendor interface.
pub const NOTIFY_ENDPOINT: u8 = 0x83;
const NOTIFY_PACKET_MAX: usize = 64;
/// The firmware sends a keep-alive after 100 ms idle, so reads return often
/// and a stop request is seen quickly.
const READ_TIMEOUT: Duration = Duration::from_millis(200);
/// More unprocessed packets than this means the GUI fell behind: drop them
/// and re-read everything instead.
const QUEUE_LIMIT: usize = 512;

const NOTIFY_V2: u8 = 0x02;
const EVT_PARAM_CHANGED: u8 = 0x02;
const EVT_BULK_INVALIDATED: u8 = 0x03;
const EVT_PRESET_LOADED: u8 = 0x04;
const EVT_INPUT_FORMAT: u8 = 0x05;
const EVT_SIGGEN_STATE: u8 = 0x07;
const EVT_CS_IR_LEARN: u8 = 0x0A;
const EVT_CS_AUX: u8 = 0x0C;
/// ParamSource: our own EP0 writes echo back with this tag.
const SRC_HOST_SET: u8 = 1;

/// `NotifyResult.flags`: some parameter changed; re-read the state.
pub const NOTIFY_STATE: u32 = 1 << 0;
/// A change that moves the graph (filters, gains, bypass, output enable).
pub const NOTIFY_CURVES: u32 = 1 << 1;
/// Everything was re-read from the device (preset load, bulk SET, missed packets).
pub const NOTIFY_REFRESHED: u32 = 1 << 2;
/// The active USB input channel count changed.
pub const NOTIFY_INPUT_FORMAT: u32 = 1 << 3;
/// A preset was loaded on the device.
pub const NOTIFY_PRESET: u32 = 1 << 4;
/// The signal generator started or stopped (re-read its status). Not a
/// parameter change: comes without NOTIFY_STATE.
pub const NOTIFY_SIGGEN: u32 = 1 << 5;
/// An auxiliary output changed state or level (already in the control
/// surfaces snapshot).
pub const NOTIFY_CS_AUX: u32 = 1 << 6;
/// IR learning finished: a code was captured or the window timed out
/// (the result is in the control surfaces snapshot).
pub const NOTIFY_IR_LEARN: u32 = 1 << 7;

/// What a batch of notifications changed.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct NotifyResult {
    /// `NOTIFY_*` bits.
    pub flags: u32,
    /// Wire channels whose PEQ or crossover bands changed (bit per channel).
    pub filter_channels: u32,
}

/// Called from the listener thread when packets are waiting. Must only
/// schedule `dspi_process_notifications` on the GUI thread.
pub type NotifyCallback = extern "C" fn(user_data: *mut c_void);

struct Waker(NotifyCallback, *mut c_void);
// SAFETY: the callback is documented as thread-safe; user_data is the
// caller's and only handed back to the callback.
unsafe impl Send for Waker {}

/// Packets shared between the listener thread and the core.
#[derive(Default)]
pub struct NotifyHub {
    queue: Mutex<VecDeque<Vec<u8>>>,
    /// Every packet, decoded, for the Interrupt Monitor.
    pub monitor: MonitorLog,
    overflow: AtomicBool,
    last_seq: Mutex<Option<u8>>,
    waker: Mutex<Option<Waker>>,
}

impl NotifyHub {
    pub fn set_waker(&self, callback: NotifyCallback, user_data: *mut c_void) {
        *self.waker.lock().unwrap() = Some(Waker(callback, user_data));
    }

    /// Forget everything from a previous connection.
    fn reset(&self) {
        self.queue.lock().unwrap().clear();
        self.overflow.store(false, Ordering::SeqCst);
        *self.last_seq.lock().unwrap() = None;
    }

    fn push(&self, packet: Vec<u8>) {
        let was_empty = {
            let mut q = self.queue.lock().unwrap();
            let was_empty = q.is_empty();
            if q.len() >= QUEUE_LIMIT {
                q.clear();
                self.overflow.store(true, Ordering::SeqCst);
            }
            q.push_back(packet);
            was_empty
        };
        // Wake once per batch: the GUI drains the whole queue.
        if was_empty {
            if let Some(Waker(callback, user_data)) = *self.waker.lock().unwrap() {
                callback(user_data);
            }
        }
    }

    fn drain(&self) -> (Vec<Vec<u8>>, bool) {
        let packets = self.queue.lock().unwrap().drain(..).collect();
        (packets, self.overflow.swap(false, Ordering::SeqCst))
    }

    /// Record a packet's sequence number; true if packets were lost before it.
    fn sequence_gap(&self, seq: u8) -> bool {
        let mut last = self.last_seq.lock().unwrap();
        let gap = matches!(*last, Some(prev) if seq != prev.wrapping_add(1));
        *last = Some(seq);
        gap
    }
}

/// The thread reading the notification endpoint of one connection.
pub struct NotifyListener {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl NotifyListener {
    pub fn start(handle: Arc<DeviceHandle<GlobalContext>>, hub: Arc<NotifyHub>) -> Self {
        hub.reset();
        let stop = Arc::new(AtomicBool::new(false));
        let stop_flag = Arc::clone(&stop);
        let thread = thread::Builder::new()
            .name("dspi-notify".into())
            .spawn(move || read_loop(&handle, &hub, &stop_flag))
            .ok();
        Self { stop, thread }
    }
}

impl Drop for NotifyListener {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn read_loop(handle: &DeviceHandle<GlobalContext>, hub: &NotifyHub, stop: &AtomicBool) {
    let mut buf = [0u8; NOTIFY_PACKET_MAX];
    while !stop.load(Ordering::SeqCst) {
        match handle.read_bulk(NOTIFY_ENDPOINT, &mut buf, READ_TIMEOUT) {
            // Everything but the 1-byte keep-alive goes to the monitor log;
            // only v2 packets are applied (the v1 master volume has a v2 twin)
            Ok(n) if n > 1 => {
                debug!("Notification {:02x?}", &buf[..n]);
                hub.monitor.record(&buf[..n]);
                if n >= 4 && buf[0] == NOTIFY_V2 {
                    hub.push(buf[..n].to_vec())
                }
            }
            Ok(_) | Err(rusb::Error::Timeout) | Err(rusb::Error::Interrupted) => {}
            Err(rusb::Error::Pipe) => {
                let _ = handle.clear_halt(NOTIFY_ENDPOINT);
            }
            Err(rusb::Error::NoDevice) | Err(rusb::Error::NotFound) => break,
            Err(e) => {
                warn!("Notification endpoint read failed: {e}");
                thread::sleep(Duration::from_millis(100));
            }
        }
    }
    debug!("Notification listener stopped");
}

impl DspiCore {
    /// Apply every queued notification to the state.
    pub fn process_notifications(&mut self) -> NotifyResult {
        let mut r = NotifyResult::default();
        let hub = self.device_manager.notify_hub();
        let (packets, overflow) = hub.drain();
        let mut refresh = overflow;
        let usable = self.state.bulk_valid && self.state.compat == COMPAT_OK;
        // The patched image starts from the state, not the last raw image:
        // the setters change the state only, and decoding a stale image
        // would undo them.
        let mut image: Option<Vec<u8>> = None;

        for p in &packets {
            if hub.sequence_gap(p[3]) {
                refresh = true;
            }
            match p[1] {
                EVT_PARAM_CHANGED if p.len() >= 12 => {
                    let off = read_u16_le(p, 4) as usize;
                    let size = read_u16_le(p, 6) as usize;
                    // Our own writes are already in the state.
                    if p[8] == SRC_HOST_SET || !usable || 12 + size > p.len() {
                        continue;
                    }
                    if off < OFF_GLOBAL || off + size > BULK_PARAMS_SIZE {
                        refresh = true;
                        continue;
                    }
                    let img = image.get_or_insert_with(|| encode_bulk(&self.state));
                    img[off..off + size].copy_from_slice(&p[12..12 + size]);
                    r.flags |= NOTIFY_STATE | classify(off, &mut r.filter_channels);
                }
                EVT_BULK_INVALIDATED => refresh = true,
                EVT_PRESET_LOADED if p.len() > 4 => {
                    self.state.active_preset_slot = p[4];
                    r.flags |= NOTIFY_STATE | NOTIFY_PRESET;
                }
                EVT_INPUT_FORMAT => r.flags |= NOTIFY_STATE | NOTIFY_INPUT_FORMAT,
                EVT_SIGGEN_STATE => r.flags |= NOTIFY_SIGGEN,
                // Our own aux writes are already in the state
                EVT_CS_AUX if p.len() >= 9 => {
                    let slot = p[4] as usize;
                    if slot < 16 && p[8] != SRC_HOST_SET {
                        self.cs.aux_state[slot] = p[5];
                        self.cs.aux_level[slot] = read_u16_le(p, 6);
                        r.flags |= NOTIFY_CS_AUX;
                    }
                }
                EVT_CS_IR_LEARN if p.len() >= 12 => {
                    self.cs.learn = Some((p[4], p[5], read_u32_le(p, 8)));
                    r.flags |= NOTIFY_IR_LEARN;
                }
                _ => {}
            }
        }

        if refresh && usable {
            // Supersedes any patches.
            if self.refresh_params().is_ok() {
                self.fetch_preset_directory_internal();
                r.flags |= NOTIFY_STATE | NOTIFY_CURVES | NOTIFY_REFRESHED;
            }
        } else if let Some(img) = image {
            if decode_bulk(&img, &mut self.state).is_err() {
                warn!("Could not apply a parameter notification");
            }
        }
        r
    }
}

/// Graph-affecting sections; marks the channel of a changed filter band.
fn classify(off: usize, filter_channels: &mut u32) -> u32 {
    const EQ_END: usize = OFF_EQ + MAX_CHANNELS * FIRMWARE_BANDS_PER_CHANNEL * BAND_SIZE;
    const XOVER_END: usize = OFF_CROSSOVER + MAX_CHANNELS * MAX_XOVER_BANDS * BAND_SIZE;
    if (OFF_EQ..EQ_END).contains(&off) {
        *filter_channels |= 1 << ((off - OFF_EQ) / BAND_SIZE / FIRMWARE_BANDS_PER_CHANNEL);
        NOTIFY_CURVES
    } else if (OFF_CROSSOVER..XOVER_END).contains(&off) {
        *filter_channels |= 1 << ((off - OFF_CROSSOVER) / BAND_SIZE / MAX_XOVER_BANDS);
        NOTIFY_CURVES
    } else if (OFF_GLOBAL..OFF_CROSSFEED).contains(&off)
        || (OFF_OUTPUTS..OFF_PINS).contains(&off)
        || (OFF_PREAMP..OFF_MASTER_VOLUME).contains(&off)
    {
        NOTIFY_CURVES
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn core() -> DspiCore {
        let mut d = vec![0u8; BULK_PARAMS_SIZE];
        d[0] = WIRE_FORMAT_VERSION;
        d[1] = 1;
        d[2] = 17;
        d[3] = 9;
        d[4] = 8;
        d[5] = 12;
        let mut c = DspiCore::new();
        decode_bulk(&d, &mut c.state).unwrap();
        c.state.compat = COMPAT_OK;
        c
    }

    fn param(seq: u8, off: usize, src: u8, value: &[u8]) -> Vec<u8> {
        let mut p = vec![NOTIFY_V2, EVT_PARAM_CHANGED, 0, seq];
        p.extend_from_slice(&(off as u16).to_le_bytes());
        p.extend_from_slice(&(value.len() as u16).to_le_bytes());
        p.extend_from_slice(&[src, 0, 0, 0]);
        p.extend_from_slice(value);
        p
    }

    #[test]
    fn applies_hardware_change_and_keeps_local_edits() {
        let mut c = core();
        c.state.filters[0][0].gain = 4.5; // set locally, not yet in the raw image
        let hub = c.device_manager.notify_hub();
        hub.push(param(1, OFF_MASTER_VOLUME, 5, &(-12.0f32).to_le_bytes()));
        let r = c.process_notifications();
        assert_eq!(c.state.master_volume_db, -12.0);
        assert_eq!(c.state.filters[0][0].gain, 4.5);
        assert_eq!(r.flags & NOTIFY_STATE, NOTIFY_STATE);
        assert_eq!(r.flags & NOTIFY_CURVES, 0);
    }

    #[test]
    fn ignores_own_echoes() {
        let mut c = core();
        let hub = c.device_manager.notify_hub();
        hub.push(param(1, OFF_MASTER_VOLUME, SRC_HOST_SET, &(-3.0f32).to_le_bytes()));
        let r = c.process_notifications();
        assert_eq!(r.flags, 0);
        assert_ne!(c.state.master_volume_db, -3.0);
    }

    #[test]
    fn band_change_marks_its_channel() {
        let mut c = core();
        let hub = c.device_manager.notify_hub();
        let band = [1u8, 0, 0, 0, 0, 0, 0x7a, 0x44, 0, 0, 0x80, 0x3f, 0, 0, 0x40, 0x40];
        hub.push(param(7, OFF_EQ + (3 * FIRMWARE_BANDS_PER_CHANNEL + 2) * BAND_SIZE, 5, &band));
        let r = c.process_notifications();
        assert_eq!(r.filter_channels, 1 << 3);
        assert_eq!(r.flags & NOTIFY_CURVES, NOTIFY_CURVES);
        assert_eq!(c.state.filters[3][2].freq, 1000.0);
        assert_eq!(c.state.filters[3][2].gain, 3.0);
    }

    #[test]
    fn detects_sequence_gaps() {
        let hub = NotifyHub::default();
        assert!(!hub.sequence_gap(254));
        assert!(!hub.sequence_gap(255));
        assert!(!hub.sequence_gap(0));
        assert!(hub.sequence_gap(2));
    }
}
