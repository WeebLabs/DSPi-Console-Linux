//! Spectrum analyser (RTA), firmware protocol V3.
//!
//! The analyser runs on the device: it taps one point of the pipeline
//! (inputs after their PEQ, or outputs after gain and delay), rotates one
//! FFT over the selected channels, and keeps third-octave band levels
//! (average and decaying peak) per channel plus the bins of the last frame.
//! The host polls EP0 vendor requests; reading frames starts the analyser
//! and keeps it alive, and it stops itself 5 s after the last read.
//!
//! A worker thread does the polling so USB never blocks the GUI. The GUI
//! states what it wants (`RtaRequest`) and copies the latest `RtaSnapshot`;
//! the worker wakes it only when the picture or the telemetry changed.
//! RTA requests abort an open chunked bulk-parameter session on the device,
//! so each tick holds the connection's bus lock, which the chunked
//! transfers hold for their whole session.

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use log::{debug, warn};
use rusb::{DeviceHandle, GlobalContext};

use crate::protocol::*;

pub const RTA_VERSION: u8 = 3;
pub const RTA_MAX_BANDS: usize = 37;
/// Channels at one tap the snapshot holds (the mask is 16 bits).
pub const RTA_MAX_CHANNELS: usize = 16;
pub const RTA_MAX_BINS: usize = 512;
pub const RTA_TAP_INPUT: u8 = 0;
pub const RTA_TAP_OUTPUT: u8 = 1;
/// Level byte of the band and bin frames at the floor: -121.5 dBFS.
pub const RTA_FLOOR_DB: f32 = -121.5;

const CTL_STOP: u16 = 0;
const CONFIG_SIZE: usize = 12;
const CAPS_SIZE: usize = 16;
const STATUS_SIZE: usize = 24;
const BIN_HEADER: usize = 16;
const TIMEOUT: Duration = Duration::from_millis(500);
const TICK: Duration = Duration::from_millis(60);
const STATUS_EVERY: Duration = Duration::from_millis(500);
/// A STOP clears the device's averaging, so a view that comes straight back
/// (a page change) keeps it.
const STOP_GRACE: Duration = Duration::from_millis(300);
/// Pushes of one config the device may decline before we give up on it.
const MAX_PUSHES: u32 = 3;

// ═══════════════════════════════════════════════════════════════════
// Wire
// ═══════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct RtaConfig {
    pub tap: u8,
    pub mask: u16,
    pub fft_order: u8,
    pub avg_ms: u16,
    pub peak_decay_db_s: u8,
}

impl RtaConfig {
    pub fn encode(&self) -> [u8; CONFIG_SIZE] {
        let mut b = [0u8; CONFIG_SIZE];
        b[0] = RTA_VERSION;
        b[1] = self.tap;
        b[2..4].copy_from_slice(&self.mask.to_le_bytes());
        b[4] = self.fft_order;
        b[6..8].copy_from_slice(&self.avg_ms.to_le_bytes());
        b[8] = self.peak_decay_db_s;
        b
    }

    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < CONFIG_SIZE || b[0] != RTA_VERSION {
            return None;
        }
        Some(Self {
            tap: b[1],
            mask: read_u16_le(b, 2),
            fft_order: b[4],
            avg_ms: read_u16_le(b, 6),
            peak_decay_db_s: b[8],
        })
    }

    /// What the device must have taken as given: it clamps averaging and
    /// decay instead of refusing them.
    fn same_routing(&self, other: &Self, valid_mask: u16) -> bool {
        self.tap == other.tap
            && self.fft_order == other.fft_order
            && self.mask & valid_mask == other.mask & valid_mask
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Caps {
    pub input_channels: u8,
    pub output_channels: u8,
    pub order_min: u8,
    pub order_max: u8,
    pub order_default: u8,
    pub bass_bands: u8,
    pub max_bands: u8,
    pub level_zero: u8,
    pub dynamic_range_db: u8,
    pub max_bin_frame: u16,
    pub bass_dynamic_range_db: u16,
}

impl Caps {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < CAPS_SIZE || b[0] != RTA_VERSION {
            return None;
        }
        let c = Self {
            input_channels: b[1],
            output_channels: b[2],
            order_min: b[3],
            order_max: b[4],
            order_default: b[5],
            bass_bands: b[6],
            max_bands: b[7],
            level_zero: b[8],
            dynamic_range_db: b[9],
            max_bin_frame: read_u16_le(b, 12),
            bass_dynamic_range_db: read_u16_le(b, 14),
        };
        let sane = c.order_min >= 8
            && c.order_max <= 10
            && c.order_min <= c.order_default
            && c.order_default <= c.order_max
            && c.max_bands > 0
            && c.max_bands as usize <= RTA_MAX_BANDS
            && c.bass_bands <= c.max_bands;
        sane.then_some(c)
    }

    fn band_frame_size(&self) -> usize {
        8 + 2 * self.max_bands as usize
    }

    fn tap_width(&self, tap: u8) -> u8 {
        if tap == RTA_TAP_INPUT {
            self.input_channels
        } else {
            self.output_channels
        }
    }

    fn valid_mask(&self, tap: u8) -> u16 {
        let w = self.tap_width(tap).min(16) as u32;
        ((1u32 << w) - 1) as u16
    }

    fn level_db(&self, v: u8) -> f32 {
        (v as f32 - self.level_zero as f32) * 0.5
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BandFrame {
    pub channel: u8,
    pub seq: u8,
    pub n_bands: u8,
    /// Since the channel's last publish; 0xFFFF = never.
    pub age_ms: u16,
    pub avg: [u8; RTA_MAX_BANDS],
    pub peak: [u8; RTA_MAX_BANDS],
}

impl BandFrame {
    pub fn parse(b: &[u8], max_bands: usize) -> Option<Self> {
        if b.len() < 8 + 2 * max_bands || b[0] != RTA_VERSION {
            return None;
        }
        let mut avg = [0u8; RTA_MAX_BANDS];
        let mut peak = [0u8; RTA_MAX_BANDS];
        avg[..max_bands].copy_from_slice(&b[8..8 + max_bands]);
        peak[..max_bands].copy_from_slice(&b[8 + max_bands..8 + 2 * max_bands]);
        Some(Self { channel: b[1], seq: b[2], n_bands: b[3], age_ms: read_u16_le(b, 4), avg, peak })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BinFrame {
    pub channel: u8,
    pub seq: u8,
    pub fft_order: u8,
    pub sample_rate: u32,
    pub bins: Vec<u8>,
}

impl BinFrame {
    /// None for a frame being written (seq 0xFF), torn (tail differs from
    /// seq), or not published since the last restart.
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < BIN_HEADER || b[0] != RTA_VERSION {
            return None;
        }
        let n = read_u16_le(b, 8) as usize;
        let total = BIN_HEADER + n + 1;
        if n == 0 || n > RTA_MAX_BINS || b.len() < total {
            return None;
        }
        let seq = b[2];
        if seq == 0xFF || b[total - 1] != seq {
            return None;
        }
        Some(Self {
            channel: b[1],
            seq,
            fft_order: b[3],
            sample_rate: read_u32_le(b, 4),
            bins: b[BIN_HEADER..BIN_HEADER + n].to_vec(),
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Status {
    pub state: u8,
    pub tap: u8,
    pub live_count: u8,
    pub live_mask: u16,
    pub frames_per_s: u16,
    pub busy_us_per_s: u16,
    pub last_frame_us: u16,
    pub sample_rate: u32,
    pub first_band: u8,
    pub bass_busy_us_per_s: u16,
}

impl Status {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < STATUS_SIZE || b[0] != RTA_VERSION {
            return None;
        }
        Some(Self {
            state: b[1],
            tap: b[2],
            live_count: b[5],
            live_mask: read_u16_le(b, 6),
            frames_per_s: read_u16_le(b, 8),
            busy_us_per_s: read_u16_le(b, 10),
            last_frame_us: read_u16_le(b, 12),
            sample_rate: read_u32_le(b, 16),
            first_band: b[20],
            bass_busy_us_per_s: read_u16_le(b, 22),
        })
    }
}

// ═══════════════════════════════════════════════════════════════════
// Host-side processing
// ═══════════════════════════════════════════════════════════════════

/// Exact centre of FFT band `b` (the firmware's geometry).
fn band_centre(b: usize) -> f64 {
    1000.0 * 10f64.powf((b as f64 - 20.0) / 10.0)
}

/// Bands that carry a level: the bass bank always, an FFT band only when a
/// bin centre falls inside its edges; none below `first_band`.
pub fn populated_bands(caps: &Caps, n_bands: u8, first_band: u8, sample_rate: u32, fft_order: u8) -> u64 {
    if first_band == 0xFF || sample_rate == 0 || !(8..=10).contains(&fft_order) {
        return 0;
    }
    let n = 1usize << fft_order;
    let df = sample_rate as f64 / n as f64;
    let mut mask = 0u64;
    for b in (first_band as usize)..(n_bands as usize).min(RTA_MAX_BANDS) {
        let on = if b < caps.bass_bands as usize {
            true
        } else {
            let fc = band_centre(b);
            let lo = ((fc * 10f64.powf(-0.05)) / df).ceil().max(1.0);
            let hi = ((fc * 10f64.powf(0.05)) / df).floor().min((n / 2 - 1) as f64);
            lo <= hi
        };
        if on {
            mask |= 1 << b;
        }
    }
    mask
}

/// The device does not time-average its bins: average them in power with
/// the same real-time constant it uses for the bands.
#[derive(Default)]
struct BinAverage {
    key: Option<(u8, u8, u32, usize)>,
    seq: u8,
    at: Option<Instant>,
    power: Vec<f64>,
}

impl BinAverage {
    fn reset(&mut self) {
        *self = Self::default();
    }

    fn add(&mut self, frame: &BinFrame, caps: &Caps, avg_ms: u16, now: Instant) {
        let key = (frame.channel, frame.fft_order, frame.sample_rate, frame.bins.len());
        let fresh: Vec<f64> = frame.bins.iter().map(|&v| 10f64.powf(caps.level_db(v) as f64 / 10.0)).collect();
        if self.key != Some(key) || avg_ms == 0 || self.at.is_none() {
            self.key = Some(key);
            self.power = fresh;
        } else if frame.seq != self.seq {
            let dt = now.duration_since(self.at.unwrap()).as_secs_f64();
            let a = dt / (avg_ms as f64 / 1000.0 + dt);
            for (p, f) in self.power.iter_mut().zip(fresh) {
                *p += (f - *p) * a;
            }
        } else {
            return;
        }
        self.seq = frame.seq;
        self.at = Some(now);
    }
}

/// Mean power over 1/6 octave around each bin, in dB. Bins whose window is
/// narrower than a bin are left as they are.
pub fn smooth_bins(power: &[f64], sample_rate: u32, n_bins: usize) -> Vec<f32> {
    let n = power.len();
    let df = sample_rate as f64 / (2.0 * n_bins as f64);
    let mut prefix = vec![0.0f64; n + 1];
    for i in 0..n {
        prefix[i + 1] = prefix[i] + power[i];
    }
    let half = 2f64.powf(1.0 / 12.0);
    (0..n)
        .map(|k| {
            let p = if k == 0 || df <= 0.0 {
                power[k]
            } else {
                let f = k as f64 * df;
                let lo = ((f / half) / df).ceil().max(1.0) as usize;
                let hi = (((f * half) / df).floor() as usize).min(n - 1);
                if hi > lo {
                    (prefix[hi + 1] - prefix[lo]) / (hi + 1 - lo) as f64
                } else {
                    power[k]
                }
            };
            (10.0 * p.max(1e-13).log10()) as f32
        })
        .collect()
}

// ═══════════════════════════════════════════════════════════════════
// FFI types
// ═══════════════════════════════════════════════════════════════════

/// What the GUI wants. A zero mask releases the analyser.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct RtaRequest {
    /// RTA_TAP_INPUT or RTA_TAP_OUTPUT.
    pub tap: u8,
    /// Bit i = channel i at that tap (input index or output index).
    pub mask: u16,
    /// Also read the FFT bins (single-channel selections only).
    pub wants_bins: bool,
    pub fft_order: u8,
    pub avg_ms: u16,
    pub peak_decay_db_s: u8,
}

/// The device's analyser. `supported` is false until probed, and stays
/// false on firmware without one.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RtaCapsInfo {
    pub supported: bool,
    pub input_channels: u8,
    pub output_channels: u8,
    pub order_min: u8,
    pub order_max: u8,
    pub order_default: u8,
    pub bass_bands: u8,
    pub max_bands: u8,
    pub dynamic_range_db: u8,
    pub bass_dynamic_range_db: u16,
    /// Nominal band centres in Hz (max_bands of them).
    pub centres: [u16; RTA_MAX_BANDS],
}

impl Default for RtaCapsInfo {
    fn default() -> Self {
        Self {
            supported: false,
            input_channels: 0,
            output_channels: 0,
            order_min: 0,
            order_max: 0,
            order_default: 0,
            bass_bands: 0,
            max_bands: 0,
            dynamic_range_db: 0,
            bass_dynamic_range_db: 0,
            centres: [0; RTA_MAX_BANDS],
        }
    }
}

/// One channel's band levels in dBFS. A silent channel (no audio, or not
/// published yet) reads the floor.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RtaChannelFrame {
    /// Channel at the snapshot's tap.
    pub channel: u8,
    pub n_bands: u8,
    pub silent: bool,
    pub avg_db: [f32; RTA_MAX_BANDS],
    pub peak_db: [f32; RTA_MAX_BANDS],
}

impl Default for RtaChannelFrame {
    fn default() -> Self {
        Self {
            channel: 0,
            n_bands: 0,
            silent: true,
            avg_db: [RTA_FLOOR_DB; RTA_MAX_BANDS],
            peak_db: [RTA_FLOOR_DB; RTA_MAX_BANDS],
        }
    }
}

/// The latest picture and telemetry. `version` changes only when what is
/// drawn changed; `telemetry_version` when the status line did.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RtaSnapshot {
    pub version: u32,
    pub telemetry_version: u32,
    pub tap: u8,
    pub count: u8,
    pub frames: [RtaChannelFrame; RTA_MAX_CHANNELS],
    /// Bands with a level at this rate and transform size (bit per band).
    pub populated: u64,
    /// Averaged and 1/6-octave smoothed bins in dBFS; bin k at
    /// k * bins_sample_rate / (2 * bins_count). 0 = none.
    pub bins_count: u16,
    pub bins_channel: u8,
    pub bins_sample_rate: u32,
    pub bins_db: [f32; RTA_MAX_BINS],
    // Telemetry
    pub running: bool,
    pub live_count: u8,
    pub live_mask: u16,
    pub frames_per_s: u16,
    pub busy_us_per_s: u16,
    pub last_frame_us: u16,
    pub bass_busy_us_per_s: u16,
    pub sample_rate: u32,
    pub first_band: u8,
    pub fft_order: u8,
    /// The device would not take the requested configuration.
    pub config_rejected: bool,
    /// How often each channel gets a new frame, in seconds.
    pub refresh_interval_s: f32,
}

impl Default for RtaSnapshot {
    fn default() -> Self {
        Self {
            version: 0,
            telemetry_version: 0,
            tap: 0,
            count: 0,
            frames: [RtaChannelFrame::default(); RTA_MAX_CHANNELS],
            populated: 0,
            bins_count: 0,
            bins_channel: 0,
            bins_sample_rate: 0,
            bins_db: [RTA_FLOOR_DB; RTA_MAX_BINS],
            running: false,
            live_count: 0,
            live_mask: 0,
            frames_per_s: 0,
            busy_us_per_s: 0,
            last_frame_us: 0,
            bass_busy_us_per_s: 0,
            sample_rate: 0,
            first_band: 0xFF,
            fft_order: 0,
            config_rejected: false,
            refresh_interval_s: 0.0,
        }
    }
}

impl RtaSnapshot {
    fn same_picture(&self, o: &Self) -> bool {
        self.tap == o.tap
            && self.count == o.count
            && self.frames[..self.count as usize] == o.frames[..o.count as usize]
            && self.populated == o.populated
            && self.bins_count == o.bins_count
            && self.bins_channel == o.bins_channel
            && self.bins_sample_rate == o.bins_sample_rate
            && self.bins_db[..self.bins_count as usize] == o.bins_db[..o.bins_count as usize]
    }

    fn same_telemetry(&self, o: &Self) -> bool {
        self.running == o.running
            && self.live_count == o.live_count
            && self.live_mask == o.live_mask
            && self.frames_per_s == o.frames_per_s
            && self.busy_us_per_s == o.busy_us_per_s
            && self.last_frame_us == o.last_frame_us
            && self.bass_busy_us_per_s == o.bass_busy_us_per_s
            && self.sample_rate == o.sample_rate
            && self.first_band == o.first_band
            && self.fft_order == o.fft_order
            && self.config_rejected == o.config_rejected
    }
}

/// Called from the worker thread when the snapshot or caps changed. Must
/// only schedule work on the GUI thread.
pub type RtaCallback = extern "C" fn(user_data: *mut c_void);

struct Waker(RtaCallback, *mut c_void);
// SAFETY: the callback is documented as thread-safe; user_data is the
// caller's and only handed back to it.
unsafe impl Send for Waker {}

// ═══════════════════════════════════════════════════════════════════
// Shared state
// ═══════════════════════════════════════════════════════════════════

/// Shared between the GUI and the worker of the current connection.
#[derive(Default)]
pub struct RtaHub {
    request: Mutex<RtaRequest>,
    request_changed: Condvar,
    caps: Mutex<RtaCapsInfo>,
    snapshot: Mutex<RtaSnapshot>,
    waker: Mutex<Option<Waker>>,
}

impl RtaHub {
    /// None stops the calls (the GUI side is going away).
    pub fn set_waker(&self, callback: Option<RtaCallback>, user_data: *mut c_void) {
        *self.waker.lock().unwrap() = callback.map(|c| Waker(c, user_data));
    }

    pub fn set_request(&self, r: RtaRequest) {
        let mut req = self.request.lock().unwrap();
        if *req != r {
            *req = r;
            self.request_changed.notify_all();
        }
    }

    pub fn caps(&self) -> RtaCapsInfo {
        *self.caps.lock().unwrap()
    }

    pub fn snapshot(&self) -> RtaSnapshot {
        *self.snapshot.lock().unwrap()
    }

    fn wake(&self) {
        if let Some(Waker(callback, user_data)) = *self.waker.lock().unwrap() {
            callback(user_data);
        }
    }

    /// Forget the previous connection (keeps the request and waker).
    fn reset(&self) {
        *self.caps.lock().unwrap() = RtaCapsInfo::default();
        let mut s = self.snapshot.lock().unwrap();
        let (v, t) = (s.version, s.telemetry_version);
        *s = RtaSnapshot { version: v.wrapping_add(1), telemetry_version: t.wrapping_add(1), ..Default::default() };
    }

    /// Store `next`, bumping the versions that changed; true if any did.
    fn publish(&self, mut next: RtaSnapshot) -> bool {
        let mut s = self.snapshot.lock().unwrap();
        let picture = !next.same_picture(&s);
        let telemetry = !next.same_telemetry(&s);
        next.version = s.version.wrapping_add(picture as u32);
        next.telemetry_version = s.telemetry_version.wrapping_add(telemetry as u32);
        *s = next;
        picture || telemetry
    }
}

// ═══════════════════════════════════════════════════════════════════
// Worker
// ═══════════════════════════════════════════════════════════════════

/// Polls the analyser of one connection.
pub struct RtaWorker {
    stop: Arc<AtomicBool>,
    hub: Arc<RtaHub>,
    thread: Option<JoinHandle<()>>,
}

impl RtaWorker {
    pub fn start(handle: Arc<DeviceHandle<GlobalContext>>, bus: Arc<Mutex<()>>, hub: Arc<RtaHub>) -> Self {
        hub.reset();
        hub.wake();
        let stop = Arc::new(AtomicBool::new(false));
        let (flag, h) = (Arc::clone(&stop), Arc::clone(&hub));
        let thread = thread::Builder::new()
            .name("dspi-rta".into())
            .spawn(move || Poller::new(handle, bus, h, flag).run())
            .ok();
        Self { stop, hub, thread }
    }
}

impl Drop for RtaWorker {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        // Wake a worker waiting for a request
        let _guard = self.hub.request.lock().unwrap();
        self.hub.request_changed.notify_all();
        drop(_guard);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        self.hub.reset();
        self.hub.wake();
    }
}

struct Poller {
    handle: Arc<DeviceHandle<GlobalContext>>,
    bus: Arc<Mutex<()>>,
    hub: Arc<RtaHub>,
    stop: Arc<AtomicBool>,
    caps: Caps,
    running: bool,
    released_at: Option<Instant>,
    // Config
    pushed: Option<RtaConfig>,
    applied: Option<RtaConfig>,
    verify_at: Option<Instant>,
    pushes: u32,
    rejected: Option<RtaConfig>,
    // Data
    frames: Vec<BandFrame>,
    status: Option<Status>,
    status_at: Option<Instant>,
    bins_at: Option<Instant>,
    bin_avg: BinAverage,
    last_tap: Option<u8>,
}

impl Poller {
    fn new(handle: Arc<DeviceHandle<GlobalContext>>, bus: Arc<Mutex<()>>, hub: Arc<RtaHub>, stop: Arc<AtomicBool>) -> Self {
        Self {
            handle,
            bus,
            hub,
            stop,
            caps: Caps::default(),
            running: false,
            released_at: None,
            pushed: None,
            applied: None,
            verify_at: None,
            pushes: 0,
            rejected: None,
            frames: Vec::new(),
            status: None,
            status_at: None,
            bins_at: None,
            bin_avg: BinAverage::default(),
            last_tap: None,
        }
    }

    fn get(&self, request: u8, value: u16, len: usize) -> rusb::Result<Vec<u8>> {
        let mut buf = vec![0u8; len];
        let n = self.handle.read_control(REQ_TYPE_IN, request, value, VENDOR_INTERFACE as u16, &mut buf, TIMEOUT)?;
        buf.truncate(n);
        Ok(buf)
    }

    fn put(&self, request: u8, value: u16, data: &[u8]) -> rusb::Result<()> {
        self.handle.write_control(REQ_TYPE_OUT, request, value, VENDOR_INTERFACE as u16, data, TIMEOUT)?;
        Ok(())
    }

    fn run(mut self) {
        if !self.probe() {
            return;
        }
        while !self.stop.load(Ordering::SeqCst) {
            let started = Instant::now();
            let req = *self.hub.request.lock().unwrap();
            if req.mask == 0 {
                self.idle();
            } else {
                self.released_at = None;
                if let Err(e) = self.tick(&req) {
                    debug!("RTA tick: {e}");
                    if e == rusb::Error::NoDevice {
                        return;
                    }
                }
            }
            // Sleep out the tick, waking early for a new request
            let left = TICK.saturating_sub(started.elapsed());
            let guard = self.hub.request.lock().unwrap();
            if *guard == req && !self.stop.load(Ordering::SeqCst) {
                let _ = self.hub.request_changed.wait_timeout(guard, left);
            }
        }
    }

    /// Read the caps and band centres; false if there is no analyser.
    fn probe(&mut self) -> bool {
        let _bus = self.bus.lock().unwrap_or_else(|e| e.into_inner());
        let Some(caps) = self.get(REQ_RTA_GET_CAPS, 0, CAPS_SIZE).ok().and_then(|b| Caps::parse(&b)) else {
            debug!("No spectrum analyser on this firmware");
            return false;
        };
        let mut centres = Vec::new();
        for chunk in 1u16..16 {
            match self.get(REQ_RTA_GET_CAPS, chunk, 64) {
                Ok(b) if b.len() >= 2 => centres.extend(b.chunks_exact(2).map(|c| u16::from_le_bytes([c[0], c[1]]))),
                _ => break,
            }
            if centres.len() >= caps.max_bands as usize {
                break;
            }
        }
        if centres.len() < caps.max_bands as usize {
            warn!("Spectrum analyser band table is short ({} of {})", centres.len(), caps.max_bands);
            return false;
        }
        self.caps = caps;
        let mut info = RtaCapsInfo {
            supported: true,
            input_channels: caps.input_channels,
            output_channels: caps.output_channels,
            order_min: caps.order_min,
            order_max: caps.order_max,
            order_default: caps.order_default,
            bass_bands: caps.bass_bands,
            max_bands: caps.max_bands,
            dynamic_range_db: caps.dynamic_range_db,
            bass_dynamic_range_db: caps.bass_dynamic_range_db,
            centres: [0; RTA_MAX_BANDS],
        };
        info.centres[..caps.max_bands as usize].copy_from_slice(&centres[..caps.max_bands as usize]);
        *self.hub.caps.lock().unwrap() = info;
        self.hub.wake();
        true
    }

    /// Nobody is watching: stop the analyser after a grace period.
    fn idle(&mut self) {
        if !self.running {
            return;
        }
        let at = *self.released_at.get_or_insert_with(Instant::now);
        if at.elapsed() < STOP_GRACE {
            return;
        }
        {
            let _bus = self.bus.lock().unwrap_or_else(|e| e.into_inner());
            let _ = self.get(REQ_RTA_CONTROL, CTL_STOP, 1);
        }
        self.running = false;
        self.released_at = None;
        self.frames.clear();
        self.bin_avg.reset();
        if self.hub.publish(RtaSnapshot::default()) {
            self.hub.wake();
        }
    }

    fn tick(&mut self, req: &RtaRequest) -> rusb::Result<()> {
        let caps = self.caps;
        let valid = caps.valid_mask(req.tap);
        let want = RtaConfig {
            tap: req.tap,
            mask: req.mask & valid,
            fft_order: req.fft_order.clamp(caps.order_min, caps.order_max),
            avg_ms: req.avg_ms,
            peak_decay_db_s: req.peak_decay_db_s,
        };
        if want.mask == 0 {
            return Ok(());
        }
        if self.last_tap != Some(want.tap) {
            // A new tap: nothing held belongs to it
            self.last_tap = Some(want.tap);
            self.frames.clear();
            self.bin_avg.reset();
        }
        let now = Instant::now();
        let _bus = self.bus.lock().unwrap_or_else(|e| e.into_inner());

        // Configuration: push what we want, then check the device took it
        if self.rejected != Some(want) && self.pushed != Some(want) {
            if self.pushed.map_or(true, |p| !p.same_routing(&want, valid)) {
                self.pushes = 0;
            }
            self.put(REQ_RTA_SET_CONFIG, 0, &want.encode())?;
            self.pushed = Some(want);
            self.rejected = None;
            // The device applies a config from its main loop
            self.verify_at = Some(now + Duration::from_millis(50));
        }
        let routed_before = self.applied.is_some_and(|a| a.same_routing(&want, valid));
        let mut status_due = self.status_at.map_or(true, |t| now.duration_since(t) >= STATUS_EVERY);
        if status_due || self.verify_at.is_some_and(|t| now >= t) {
            self.verify_at = None;
            if let Some(applied) = self.get(REQ_RTA_GET_CONFIG, 0, CONFIG_SIZE).ok().and_then(|b| RtaConfig::parse(&b)) {
                // What the device runs, which the frames belong to
                self.applied = Some(applied);
                if applied.same_routing(&want, valid) {
                    self.pushes = 0;
                } else if self.pushed == Some(want) {
                    self.pushes += 1;
                    if self.pushes >= MAX_PUSHES {
                        warn!("The device refused the spectrum analyser configuration {want:?}");
                        self.rejected = Some(want);
                    } else {
                        self.pushed = None;
                    }
                }
            }
        }

        // Frames belong to the config the device runs: until it runs ours
        // (applied from its main loop, or refused), show none of them
        let routed = self.applied.is_some_and(|a| a.same_routing(&want, valid));
        if routed && !routed_before {
            status_due = true;        // the live channels of the new tap
        }

        // Band frames: every live channel in one read, or the one channel
        let max_bands = caps.max_bands as usize;
        let stride = caps.band_frame_size();
        if want.mask.count_ones() > 1 {
            match self.get(REQ_RTA_GET_BANDS_ALL, 0, stride * RTA_MAX_CHANNELS) {
                Ok(buf) => {
                    self.frames = buf.chunks_exact(stride).filter_map(|c| BandFrame::parse(c, max_bands)).collect();
                }
                // Busy (bulk lock on the device): one channel at a time
                Err(rusb::Error::Pipe) => {
                    let mut frames = Vec::new();
                    for ch in 0..16u16 {
                        if want.mask & (1 << ch) != 0 {
                            if let Some(f) = self.get(REQ_RTA_GET_BANDS, ch, stride).ok().and_then(|b| BandFrame::parse(&b, max_bands)) {
                                frames.push(f);
                            }
                        }
                    }
                    self.frames = frames;
                }
                Err(e) => return Err(e),
            }
        } else {
            let ch = want.mask.trailing_zeros() as u16;
            self.frames = self.get(REQ_RTA_GET_BANDS, ch, stride).ok().and_then(|b| BandFrame::parse(&b, max_bands)).into_iter().collect();
        }
        if !routed {
            self.frames.clear();
        }
        self.running = true;

        if status_due {
            if let Some(s) = self.get(REQ_RTA_GET_STATUS, 0, STATUS_SIZE).ok().and_then(|b| Status::parse(&b)) {
                self.status = Some(s);
            }
            self.status_at = Some(now);
        }
        let order = self.applied.map_or(want.fft_order, |a| a.fft_order);
        let refresh = self.refresh_interval(order);

        // Bins, for a single channel, no faster than it gets new frames
        let single = want.mask.count_ones() == 1;
        let bins_due = self.bins_at.map_or(true, |t| now.duration_since(t).as_secs_f32() >= refresh.max(0.05));
        if req.wants_bins && single && routed && bins_due {
            self.bins_at = Some(now);
            let len = (caps.max_bin_frame as usize).max(BIN_HEADER + RTA_MAX_BINS + 1);
            let mut frame = self.get(REQ_RTA_GET_BINS, 0, len).ok().and_then(|b| BinFrame::parse(&b));
            if frame.is_none() {
                frame = self.get(REQ_RTA_GET_BINS, 0, len).ok().and_then(|b| BinFrame::parse(&b));
            }
            if let Some(f) = frame.filter(|f| f.channel as u32 == want.mask.trailing_zeros()) {
                self.bin_avg.add(&f, &caps, want.avg_ms, now);
            }
        } else if !(req.wants_bins && single && routed) {
            self.bin_avg.reset();
        }
        drop(_bus);

        let snapshot = self.build(&want, refresh, order);
        if self.hub.publish(snapshot) {
            self.hub.wake();
        }
        Ok(())
    }

    /// Seconds between frames of one channel.
    fn refresh_interval(&self, order: u8) -> f32 {
        match self.status {
            Some(s) if s.frames_per_s > 0 => s.live_count.max(1) as f32 / s.frames_per_s as f32,
            Some(s) if s.sample_rate > 0 => (1u32 << order) as f32 / s.sample_rate as f32 * s.live_count.max(1) as f32,
            _ => 0.1,
        }
    }

    fn build(&mut self, want: &RtaConfig, refresh: f32, order: u8) -> RtaSnapshot {
        let caps = self.caps;
        let status = self.status.unwrap_or_default();
        let mut s = RtaSnapshot { tap: want.tap, ..Default::default() };
        // A frame that stopped updating (no audio) reads as silence: the
        // device keeps its last levels and only the age grows
        let stale_ms = (refresh * 4000.0).max(500.0);
        let live = if self.status.is_some_and(|s| s.tap == want.tap) { status.live_mask } else { want.mask };
        let mut n = 0;
        for f in self.frames.iter().filter(|f| f.channel < 16 && want.mask & live & (1 << f.channel) != 0) {
            if n >= RTA_MAX_CHANNELS {
                break;
            }
            let mut out = RtaChannelFrame { channel: f.channel, n_bands: f.n_bands, ..Default::default() };
            let stale = f.age_ms == 0xFFFF || f.age_ms as f32 > stale_ms;
            if !stale {
                out.silent = false;
                for b in 0..(f.n_bands as usize).min(RTA_MAX_BANDS) {
                    out.avg_db[b] = caps.level_db(f.avg[b]);
                    out.peak_db[b] = caps.level_db(f.peak[b]);
                }
            } else if self.bin_avg.key.is_some_and(|k| k.0 == f.channel) {
                self.bin_avg.reset();
            }
            s.frames[n] = out;
            n += 1;
        }
        s.count = n as u8;
        let n_bands = s.frames[..n].iter().map(|f| f.n_bands).max().unwrap_or(0);
        s.populated = populated_bands(&caps, n_bands, status.first_band, status.sample_rate, order);
        if let Some((ch, _, rate, count)) = self.bin_avg.key {
            s.bins_count = count as u16;
            s.bins_channel = ch;
            s.bins_sample_rate = rate;
            let db = smooth_bins(&self.bin_avg.power, rate, count);
            s.bins_db[..count].copy_from_slice(&db);
        }
        s.running = self.running && status.state != 0;
        s.live_count = status.live_count;
        s.live_mask = status.live_mask;
        s.frames_per_s = status.frames_per_s;
        s.busy_us_per_s = status.busy_us_per_s;
        s.last_frame_us = status.last_frame_us;
        s.bass_busy_us_per_s = status.bass_busy_us_per_s;
        s.sample_rate = status.sample_rate;
        s.first_band = if self.status.is_some() { status.first_band } else { 0xFF };
        s.fft_order = order;
        s.config_rejected = self.rejected.is_some();
        s.refresh_interval_s = refresh;
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn caps() -> Caps {
        let mut b = [0u8; 16];
        b[..10].copy_from_slice(&[3, 8, 9, 8, 10, 10, 14, 37, 243, 120]);
        b[10..12].copy_from_slice(&5000u16.to_le_bytes());
        b[12..14].copy_from_slice(&529u16.to_le_bytes());
        b[14..16].copy_from_slice(&70u16.to_le_bytes());
        Caps::parse(&b).unwrap()
    }

    #[test]
    fn config_round_trip() {
        let c = RtaConfig { tap: 1, mask: 0b101, fft_order: 10, avg_ms: 300, peak_decay_db_s: 12 };
        let b = c.encode();
        assert_eq!(b, [3, 1, 5, 0, 10, 0, 44, 1, 12, 0, 0, 0]);
        assert_eq!(RtaConfig::parse(&b), Some(c));
        assert_eq!(RtaConfig::parse(&b[..11]), None);
    }

    #[test]
    fn caps_are_checked() {
        let c = caps();
        assert_eq!((c.input_channels, c.output_channels, c.max_bands, c.max_bin_frame), (8, 9, 37, 529));
        assert_eq!(c.valid_mask(RTA_TAP_OUTPUT), 0x1FF);
        let mut b = [3u8, 8, 9, 8, 11, 10, 14, 37, 243, 120, 0, 0, 0, 0, 0, 0];
        assert!(Caps::parse(&b).is_none(), "order max above 10");
        b[4] = 10;
        b[6] = 38;
        assert!(Caps::parse(&b).is_none(), "bass bands above max bands");
    }

    #[test]
    fn level_scale() {
        let c = caps();
        assert_eq!(c.level_db(243), 0.0);
        assert_eq!(c.level_db(255), 6.0);
        assert_eq!(c.level_db(0), RTA_FLOOR_DB);
    }

    #[test]
    fn band_frame_layout() {
        let mut b = vec![0u8; 82];
        b[..6].copy_from_slice(&[3, 2, 7, 34, 20, 0]);
        b[8] = 243;
        b[45] = 255;
        let f = BandFrame::parse(&b, 37).unwrap();
        assert_eq!((f.channel, f.seq, f.n_bands, f.age_ms), (2, 7, 34, 20));
        assert_eq!((f.avg[0], f.peak[0]), (243, 255));
        assert!(BandFrame::parse(&b[..81], 37).is_none());
    }

    #[test]
    fn torn_bin_frames_are_rejected() {
        let mut b = vec![0u8; 16 + 128 + 1];
        b[..4].copy_from_slice(&[3, 0, 9, 8]);
        b[4..8].copy_from_slice(&48000u32.to_le_bytes());
        b[8..10].copy_from_slice(&128u16.to_le_bytes());
        b[144] = 9;
        let f = BinFrame::parse(&b).unwrap();
        assert_eq!((f.seq, f.bins.len(), f.sample_rate), (9, 128, 48000));
        b[144] = 8;
        assert!(BinFrame::parse(&b).is_none(), "torn");
        b[2] = 0xFF;
        b[144] = 0xFF;
        assert!(BinFrame::parse(&b).is_none(), "in progress");
    }

    #[test]
    fn status_layout() {
        let mut b = [0u8; 24];
        b[..6].copy_from_slice(&[3, 1, 1, 0, 0, 2]);
        b[6..8].copy_from_slice(&0b11u16.to_le_bytes());
        b[8..10].copy_from_slice(&90u16.to_le_bytes());
        b[16..20].copy_from_slice(&48000u32.to_le_bytes());
        let s = Status::parse(&b).unwrap();
        assert_eq!((s.state, s.live_count, s.live_mask, s.frames_per_s, s.sample_rate, s.first_band), (1, 2, 3, 90, 48000, 0));
    }

    #[test]
    fn populated_bands_follow_the_firmware_tables() {
        let c = caps();
        // 1024 points at 48 kHz: bass bank plus every FFT band up to 20 kHz
        let m = populated_bands(&c, 34, 0, 48000, 10);
        assert_eq!(m, (1u64 << 34) - 1);
        // 256 points at 44.1 kHz: band 16 (400 Hz) holds no bin
        let m = populated_bands(&c, 34, 0, 44100, 8);
        assert_eq!(m & (1 << 16), 0);
        assert_ne!(m & (1 << 13), 0, "bass bands are always populated");
        assert_eq!(populated_bands(&c, 34, 0xFF, 48000, 10), 0);
    }

    #[test]
    fn bins_average_in_power_and_ignore_repeats() {
        let c = caps();
        let t0 = Instant::now();
        let frame = |seq, v| BinFrame { channel: 0, seq, fft_order: 8, sample_rate: 48000, bins: vec![v; 128] };
        let mut a = BinAverage::default();
        a.add(&frame(1, 243), &c, 300, t0);
        assert!((a.power[5] - 1.0).abs() < 1e-9);
        a.add(&frame(1, 0), &c, 300, t0 + Duration::from_millis(100));
        assert!((a.power[5] - 1.0).abs() < 1e-9, "same seq ignored");
        a.add(&frame(2, 0), &c, 300, t0 + Duration::from_millis(100));
        assert!(a.power[5] < 1.0 && a.power[5] > 0.5, "a = 0.1 / 0.4 of the way down");
        a.add(&frame(3, 0), &c, 0, t0 + Duration::from_millis(200));
        assert!(a.power[5] < 1e-10, "averaging off takes the frame as it is");
    }

    #[test]
    fn smoothing_keeps_a_flat_spectrum_flat() {
        let power = vec![1e-3f64; 512];
        let db = smooth_bins(&power, 48000, 512);
        assert!(db.iter().all(|&d| (d + 30.0).abs() < 1e-3));
        // A lone tone spreads over the bins its window covers
        let mut tone = vec![0.0f64; 512];
        tone[400] = 1.0;
        let db = smooth_bins(&tone, 48000, 512);
        assert!(db[400] < 0.0 && db[400] > -20.0);
    }
}
