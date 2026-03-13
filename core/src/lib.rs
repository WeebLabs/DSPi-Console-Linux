//! DSPi Console Unified — Shared Rust Core Library
//!
//! Cross-platform USB communication and DSP math for DSPi firmware.
//! Exposes a C ABI for FFI consumption by Swift (macOS) and Qt/C++ (Windows/Linux).

#![allow(private_interfaces)] // FfiCore is intentionally opaque via raw pointers

pub mod commands;
pub mod device;
pub mod dsp_math;
pub mod preset;
pub mod protocol;
pub mod state;
pub mod types;
pub mod usb;

use std::ffi::{c_char, c_void, CStr};
use std::sync::Mutex;

use crate::device::DeviceManager;
use crate::dsp_math::MAGNITUDE_POINTS;
use crate::state::DspState;
use crate::types::*;

// ═══════════════════════════════════════════════════════════════════
// Core Instance
// ═══════════════════════════════════════════════════════════════════

/// Main library instance. Holds device manager and DSP state.
/// All FFI functions operate on this through an opaque pointer.
pub struct DspiCore {
    pub(crate) device_manager: DeviceManager,
    pub(crate) state: DspState,
    hotplug_callback: Option<(DeviceEventCallback, *mut c_void)>,
}

// SAFETY: The FFI layer serializes all access through a Mutex.
// The raw pointer in hotplug_callback is managed by the caller.
unsafe impl Send for DspiCore {}

impl DspiCore {
    pub fn new() -> Self {
        Self {
            device_manager: DeviceManager::new(),
            state: DspState::default(),
            hotplug_callback: None,
        }
    }

    pub fn state(&self) -> &DspState {
        &self.state
    }
}

impl Default for DspiCore {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Thread-Safe Wrapper
// ═══════════════════════════════════════════════════════════════════

/// Thread-safe wrapper around DspiCore for FFI.
struct FfiCore {
    inner: Mutex<DspiCore>,
}

/// Hot-plug event callback type.
/// event: 0 = arrived, 1 = departed.
/// serial: NUL-terminated ASCII device serial.
pub type DeviceEventCallback = extern "C" fn(event: u8, serial: *const c_char, user_data: *mut c_void);

// ── Helper: lock the mutex and run a closure ────────────────────────

fn with_core<F, R>(ptr: *mut FfiCore, f: F) -> R
where
    F: FnOnce(&mut DspiCore) -> R,
{
    assert!(!ptr.is_null(), "DspiCore pointer is null");
    let ffi = unsafe { &*ptr };
    let mut guard = ffi.inner.lock().expect("DspiCore mutex poisoned");
    f(&mut guard)
}

fn with_core_const<F, R>(ptr: *const FfiCore, f: F) -> R
where
    F: FnOnce(&DspiCore) -> R,
{
    assert!(!ptr.is_null(), "DspiCore pointer is null");
    let ffi = unsafe { &*ptr };
    let guard = ffi.inner.lock().expect("DspiCore mutex poisoned");
    f(&guard)
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Lifecycle
// ═══════════════════════════════════════════════════════════════════

/// Create a new DspiCore instance. Returns opaque handle.
/// The caller must eventually call `dspi_core_free` to release it.
#[no_mangle]
pub extern "C" fn dspi_core_new() -> *mut FfiCore {
    let _ = env_logger::try_init();
    let core = FfiCore {
        inner: Mutex::new(DspiCore::new()),
    };
    Box::into_raw(Box::new(core))
}

/// Destroy a DspiCore instance.
#[no_mangle]
pub extern "C" fn dspi_core_free(core: *mut FfiCore) {
    if !core.is_null() {
        unsafe {
            drop(Box::from_raw(core));
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Device Management
// ═══════════════════════════════════════════════════════════════════

/// Scan for connected DSPi devices. Writes up to `max_devices` DeviceInfo
/// structs to `out_devices`. Returns the number of devices found.
#[no_mangle]
pub extern "C" fn dspi_scan_devices(
    core: *mut FfiCore,
    out_devices: *mut DeviceInfo,
    max_devices: u32,
) -> u32 {
    with_core(core, |c| {
        let devices = c.device_manager.scan();
        let count = devices.len().min(max_devices as usize);
        if !out_devices.is_null() && count > 0 {
            let slice = unsafe { std::slice::from_raw_parts_mut(out_devices, count) };
            for (i, dev) in devices.iter().take(count).enumerate() {
                slice[i] = dev.clone();
            }
        }
        count as u32
    })
}

/// Select and open a device by serial number (NUL-terminated C string).
/// Returns true on success.
#[no_mangle]
pub extern "C" fn dspi_select_device(core: *mut FfiCore, serial: *const c_char) -> bool {
    if serial.is_null() {
        return false;
    }
    let serial_str = unsafe { CStr::from_ptr(serial) };
    let Ok(serial_str) = serial_str.to_str() else {
        return false;
    };
    with_core(core, |c| c.device_manager.select_device(serial_str).is_ok())
}

/// Disconnect from the current device.
#[no_mangle]
pub extern "C" fn dspi_disconnect(core: *mut FfiCore) {
    with_core(core, |c| c.device_manager.disconnect());
}

/// Check if a device is currently connected.
#[no_mangle]
pub extern "C" fn dspi_is_connected(core: *const FfiCore) -> bool {
    with_core_const(core, |c| c.device_manager.is_connected())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Bulk Operations
// ═══════════════════════════════════════════════════════════════════

/// Fetch all parameters from the device. Returns true on success.
#[no_mangle]
pub extern "C" fn dspi_fetch_all(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.fetch_all().is_ok())
}

/// Fetch device status. Writes to `out_status`. Returns true on success.
#[no_mangle]
pub extern "C" fn dspi_fetch_status(core: *mut FfiCore, out_status: *mut SystemStatus) -> bool {
    with_core(core, |c| {
        match c.fetch_status() {
            Ok(status) => {
                if !out_status.is_null() {
                    unsafe { *out_status = status; }
                }
                true
            }
            Err(_) => false,
        }
    })
}

/// Get a pointer to the current cached state. Valid until the next mutable FFI call.
#[no_mangle]
pub extern "C" fn dspi_get_state(core: *const FfiCore) -> *const DspState {
    with_core_const(core, |c| c.state() as *const DspState)
}

// ═══════════════════════════════════════════════════════════════════
// FFI — EQ
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_filter(
    core: *mut FfiCore,
    ch: u8,
    band: u8,
    params: FilterParams,
) -> bool {
    with_core(core, |c| c.set_filter(ch, band, params).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Global
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_preamp(core: *mut FfiCore, db: f32) -> bool {
    with_core(core, |c| c.set_preamp(db).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_bypass(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_bypass(enabled).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Delay
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_delay(core: *mut FfiCore, ch: u8, ms: f32) -> bool {
    with_core(core, |c| c.set_delay(ch, ms).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Loudness
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_loudness(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_loudness(enabled).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_loudness_ref(core: *mut FfiCore, spl: f32) -> bool {
    with_core(core, |c| c.set_loudness_ref(spl).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_loudness_intensity(core: *mut FfiCore, pct: f32) -> bool {
    with_core(core, |c| c.set_loudness_intensity(pct).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Crossfeed
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_crossfeed(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_crossfeed(enabled).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_crossfeed_preset(core: *mut FfiCore, preset: u8) -> bool {
    with_core(core, |c| c.set_crossfeed_preset(preset).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_crossfeed_freq(core: *mut FfiCore, freq: f32) -> bool {
    with_core(core, |c| c.set_crossfeed_freq(freq).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_crossfeed_feed(core: *mut FfiCore, feed: f32) -> bool {
    with_core(core, |c| c.set_crossfeed_feed(feed).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_crossfeed_itd(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_crossfeed_itd(enabled).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Matrix
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_matrix_route(
    core: *mut FfiCore,
    input: u8,
    output: u8,
    enabled: bool,
    gain: f32,
    invert: bool,
) -> bool {
    with_core(core, |c| {
        c.set_matrix_route(input, output, enabled, gain, invert).is_ok()
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Output
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_output_enable(core: *mut FfiCore, output: u8, enabled: bool) -> bool {
    with_core(core, |c| c.set_output_enable(output, enabled).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_output_gain(core: *mut FfiCore, output: u8, db: f32) -> bool {
    with_core(core, |c| c.set_output_gain(output, db).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_output_mute(core: *mut FfiCore, output: u8, muted: bool) -> bool {
    with_core(core, |c| c.set_output_mute(output, muted).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_output_delay(core: *mut FfiCore, output: u8, ms: f32) -> bool {
    with_core(core, |c| c.set_output_delay(output, ms).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Pin Config
// ═══════════════════════════════════════════════════════════════════

/// Returns firmware status code (0 = success). 0xFF on communication error.
#[no_mangle]
pub extern "C" fn dspi_set_output_pin(core: *mut FfiCore, output: u8, pin: u8) -> u8 {
    with_core(core, |c| c.set_output_pin(output, pin).unwrap_or(0xFF))
}

/// Returns pin number. 0xFF on error.
#[no_mangle]
pub extern "C" fn dspi_fetch_output_pin(core: *mut FfiCore, output: u8) -> u8 {
    with_core(core, |c| c.fetch_output_pin(output).unwrap_or(0xFF))
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Channel Names
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_channel_name(
    core: *mut FfiCore,
    channel: u8,
    name: *const c_char,
) -> bool {
    if name.is_null() {
        return false;
    }
    let name_str = unsafe { CStr::from_ptr(name) };
    let Ok(name_str) = name_str.to_str() else {
        return false;
    };
    with_core(core, |c| c.set_channel_name(channel, name_str).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_get_channel_name(
    core: *mut FfiCore,
    channel: u8,
    out_buf: *mut c_char,
    buf_len: u32,
) -> bool {
    if out_buf.is_null() || buf_len == 0 {
        return false;
    }
    with_core(core, |c| {
        let name: String = match c.fetch_channel_name(channel) {
            Ok(n) => n,
            Err(_) => return false,
        };
        let bytes = name.as_bytes();
        let copy_len = bytes.len().min((buf_len - 1) as usize);
        let out_slice =
            unsafe { std::slice::from_raw_parts_mut(out_buf as *mut u8, buf_len as usize) };
        out_slice[..copy_len].copy_from_slice(&bytes[..copy_len]);
        out_slice[copy_len] = 0;
        true
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Presets
// ═══════════════════════════════════════════════════════════════════

/// Returns preset status code (0 = success). 0xFF on communication error.
#[no_mangle]
pub extern "C" fn dspi_save_preset(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.save_preset(slot).unwrap_or(0xFF))
}

#[no_mangle]
pub extern "C" fn dspi_load_preset(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.load_preset(slot).unwrap_or(0xFF))
}

#[no_mangle]
pub extern "C" fn dspi_delete_preset(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.delete_preset(slot).unwrap_or(0xFF))
}

#[no_mangle]
pub extern "C" fn dspi_set_preset_name(
    core: *mut FfiCore,
    slot: u8,
    name: *const c_char,
) -> bool {
    if name.is_null() {
        return false;
    }
    let name_str = unsafe { CStr::from_ptr(name) };
    let Ok(name_str) = name_str.to_str() else {
        return false;
    };
    with_core(core, |c| c.set_preset_name(slot, name_str).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_get_preset_name(
    core: *mut FfiCore,
    slot: u8,
    out_buf: *mut c_char,
    buf_len: u32,
) -> bool {
    if out_buf.is_null() || buf_len == 0 {
        return false;
    }
    with_core(core, |c| {
        let name: String = match c.get_preset_name(slot) {
            Ok(n) => n,
            Err(_) => return false,
        };
        let bytes = name.as_bytes();
        let copy_len = bytes.len().min((buf_len - 1) as usize);
        let out_slice =
            unsafe { std::slice::from_raw_parts_mut(out_buf as *mut u8, buf_len as usize) };
        out_slice[..copy_len].copy_from_slice(&bytes[..copy_len]);
        out_slice[copy_len] = 0;
        true
    })
}

#[no_mangle]
pub extern "C" fn dspi_get_preset_directory(
    core: *mut FfiCore,
    out_dir: *mut PresetDirectory,
) -> bool {
    if out_dir.is_null() {
        return false;
    }
    with_core(core, |c| {
        match c.get_preset_directory() {
            Ok(dir) => {
                unsafe { *out_dir = dir; }
                true
            }
            Err(_) => false,
        }
    })
}

#[no_mangle]
pub extern "C" fn dspi_set_preset_startup(
    core: *mut FfiCore,
    mode: u8,
    default_slot: u8,
) -> bool {
    with_core(core, |c| c.set_preset_startup(mode, default_slot).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_preset_include_pins(core: *mut FfiCore, include: bool) -> bool {
    with_core(core, |c| c.set_preset_include_pins(include).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Flash
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_save_params(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.save_params().unwrap_or(FLASH_ERR_WRITE))
}

#[no_mangle]
pub extern "C" fn dspi_load_params(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.load_params().unwrap_or(FLASH_ERR_WRITE))
}

#[no_mangle]
pub extern "C" fn dspi_factory_reset(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.factory_reset().unwrap_or(FLASH_ERR_WRITE))
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Core1
// ═══════════════════════════════════════════════════════════════════

/// Returns core1 mode (0=IDLE, 1=PDM, 2=EQ_WORKER). -1 on error.
#[no_mangle]
pub extern "C" fn dspi_fetch_core1_mode(core: *mut FfiCore) -> i8 {
    with_core(core, |c| c.fetch_core1_mode().map(|v| v as i8).unwrap_or(-1))
}

/// Returns 1 if conflict, 0 if no conflict, -1 on error.
#[no_mangle]
pub extern "C" fn dspi_check_core1_conflict(core: *mut FfiCore, output: u8) -> i8 {
    with_core(core, |c| {
        c.check_core1_conflict(output)
            .map(|v| if v { 1 } else { 0 })
            .unwrap_or(-1)
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Clips
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_clear_clips(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.clear_clips().is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — DSP Math (stateless, no device needed)
// ═══════════════════════════════════════════════════════════════════

/// Compute frequency response magnitude in dB at a single frequency.
#[no_mangle]
pub extern "C" fn dspi_compute_response(
    filters: *const FilterParams,
    num_filters: u32,
    freq: f32,
) -> f32 {
    if filters.is_null() || num_filters == 0 {
        return 0.0;
    }
    let slice = unsafe { std::slice::from_raw_parts(filters, num_filters as usize) };
    dsp_math::response_at(freq, slice)
}

/// Compute 201-point magnitude curve (10 Hz to 20 kHz, log-spaced).
/// `out_magnitudes` must point to at least 201 f64s.
#[no_mangle]
pub extern "C" fn dspi_compute_magnitude_curve(
    filters: *const FilterParams,
    num_filters: u32,
    out_magnitudes: *mut f64,
) -> bool {
    if filters.is_null() || out_magnitudes.is_null() || num_filters == 0 {
        return false;
    }
    let slice = unsafe { std::slice::from_raw_parts(filters, num_filters as usize) };
    let curve = dsp_math::compute_magnitude_curve(slice);
    let out = unsafe { std::slice::from_raw_parts_mut(out_magnitudes, MAGNITUDE_POINTS) };
    out.copy_from_slice(&curve);
    true
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Hot-Plug
// ═══════════════════════════════════════════════════════════════════

/// Register a callback for device arrival/departure events.
#[no_mangle]
pub extern "C" fn dspi_set_hotplug_callback(
    core: *mut FfiCore,
    callback: DeviceEventCallback,
    user_data: *mut c_void,
) -> bool {
    with_core(core, |c| {
        c.hotplug_callback = Some((callback, user_data));
        true
    })
}

/// Poll for hot-plug changes. Must be called periodically (~500ms).
/// Fires the registered callback for arrivals (event=0) and departures (event=1).
/// No-op if no callback is registered.
#[no_mangle]
pub extern "C" fn dspi_poll_hotplug(core: *mut FfiCore) {
    with_core(core, |c| {
        let (arrivals, departures) = c.device_manager.poll_changes();
        if let Some((callback, user_data)) = c.hotplug_callback {
            for serial in &arrivals {
                let mut buf = Vec::with_capacity(serial.len() + 1);
                buf.extend_from_slice(serial.as_bytes());
                buf.push(0);
                callback(0, buf.as_ptr() as *const c_char, user_data);
            }
            for serial in &departures {
                let mut buf = Vec::with_capacity(serial.len() + 1);
                buf.extend_from_slice(serial.as_bytes());
                buf.push(0);
                callback(1, buf.as_ptr() as *const c_char, user_data);
            }
        }
    });
}

// Re-export constants that C consumers need
pub use protocol::FLASH_ERR_WRITE;
pub use protocol::FLASH_OK;
pub use protocol::PIN_CONFIG_SUCCESS;
pub use protocol::PRESET_OK;
