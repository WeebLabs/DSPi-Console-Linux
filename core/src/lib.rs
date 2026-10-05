//! DSPi Console — Shared Rust Core Library
//!
//! USB communication, state model and DSP math for DSPi firmware 1.1.6
//! (wire format V32). Exposes a C ABI for the Qt front end.
//!
//! Channel arguments are firmware wire channel indices
//! (`[ inputs ][ outputs ]`, see `types.rs`); output arguments are output
//! indices 0..num_output_channels-1.

#![allow(private_interfaces)] // FfiCore is intentionally opaque via raw pointers

pub mod commands;
pub mod device;
pub mod dsp_math;
pub mod notify;
pub mod preset;
pub mod protocol;
pub mod rta;
pub mod siggen;
pub mod stats;
pub mod monitor;
pub mod presetfile;
pub mod filterfile;
pub mod cs;
pub mod presetdiff;
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
pub struct DspiCore {
    pub(crate) device_manager: DeviceManager,
    pub(crate) state: DspState,
    pub(crate) cs: cs::CsState,
    /// The state when it last matched the active preset (unsaved changes)
    pub(crate) baseline: Option<Box<DspState>>,
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
            cs: cs::CsState::default(),
            baseline: None,
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

/// Borrow a NUL-terminated UTF-8 C string.
fn c_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

/// Copy `s` into a caller buffer as a NUL-terminated string.
fn copy_out(s: &str, out_buf: *mut c_char, buf_len: u32) -> bool {
    if out_buf.is_null() || buf_len == 0 {
        return false;
    }
    let bytes = s.as_bytes();
    let n = bytes.len().min((buf_len - 1) as usize);
    let out = unsafe { std::slice::from_raw_parts_mut(out_buf as *mut u8, buf_len as usize) };
    out[..n].copy_from_slice(&bytes[..n]);
    out[n] = 0;
    true
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Lifecycle
// ═══════════════════════════════════════════════════════════════════

/// Create a new DspiCore instance. Free it with `dspi_core_free`.
#[no_mangle]
pub extern "C" fn dspi_core_new() -> *mut FfiCore {
    let _ = env_logger::try_init();
    Box::into_raw(Box::new(FfiCore { inner: Mutex::new(DspiCore::new()) }))
}

/// Destroy a DspiCore instance.
#[no_mangle]
pub extern "C" fn dspi_core_free(core: *mut FfiCore) {
    if !core.is_null() {
        unsafe { drop(Box::from_raw(core)) };
    }
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Device Management
// ═══════════════════════════════════════════════════════════════════

/// Scan for connected DSPi devices. Writes up to `max_devices` entries to
/// `out_devices` and returns the number found.
#[no_mangle]
pub extern "C" fn dspi_scan_devices(core: *mut FfiCore, out_devices: *mut DeviceInfo, max_devices: u32) -> u32 {
    with_core(core, |c| {
        let devices = c.device_manager.scan();
        let count = devices.len().min(max_devices as usize);
        if !out_devices.is_null() && count > 0 {
            let slice = unsafe { std::slice::from_raw_parts_mut(out_devices, count) };
            slice.clone_from_slice(&devices[..count]);
        }
        count as u32
    })
}

/// Select and open a device by serial number. Returns true on success.
#[no_mangle]
pub extern "C" fn dspi_select_device(core: *mut FfiCore, serial: *const c_char) -> bool {
    let Some(serial) = c_str(serial) else { return false };
    with_core(core, |c| {
        let ok = c.device_manager.select_device(serial).is_ok();
        if ok {
            c.state = DspState::default();
            c.cs = cs::CsState::default();
            c.baseline = None;
        }
        ok
    })
}

#[no_mangle]
pub extern "C" fn dspi_disconnect(core: *mut FfiCore) {
    with_core(core, |c| c.device_manager.disconnect());
}

#[no_mangle]
pub extern "C" fn dspi_is_connected(core: *const FfiCore) -> bool {
    with_core_const(core, |c| c.device_manager.is_connected())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Sync / Status
// ═══════════════════════════════════════════════════════════════════

/// Identify the firmware and read all parameters. Returns false only when the
/// device could not be talked to; check `DspState.compat` for compatibility.
#[no_mangle]
pub extern "C" fn dspi_fetch_all(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.fetch_all().is_ok())
}

/// Re-read the bulk parameter image only.
#[no_mangle]
pub extern "C" fn dspi_refresh_params(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.refresh_params().is_ok())
}

/// Write the whole cached state to the device in one bulk transfer.
#[no_mangle]
pub extern "C" fn dspi_apply_all_params(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.apply_all_params().is_ok())
}

/// Fetch device status into `out_status`. Returns true on success.
#[no_mangle]
pub extern "C" fn dspi_fetch_status(core: *mut FfiCore, out_status: *mut SystemStatus) -> bool {
    with_core(core, |c| match c.fetch_status() {
        Ok(status) => {
            if !out_status.is_null() {
                unsafe { *out_status = status };
            }
            true
        }
        Err(_) => false,
    })
}

/// Pointer to the cached state. Valid until the next mutating FFI call.
#[no_mangle]
pub extern "C" fn dspi_get_state(core: *const FfiCore) -> *const DspState {
    with_core_const(core, |c| c.state() as *const DspState)
}

/// Longest channel/output delay the connected platform supports, in ms.
#[no_mangle]
pub extern "C" fn dspi_max_delay_ms(core: *const FfiCore) -> f32 {
    with_core_const(core, |c| c.max_delay_ms())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — EQ
// ═══════════════════════════════════════════════════════════════════

/// Set PEQ band `band` (0..9) of wire channel `ch`.
#[no_mangle]
pub extern "C" fn dspi_set_filter(core: *mut FfiCore, ch: u8, band: u8, params: FilterParams) -> bool {
    with_core(core, |c| c.set_filter(ch, band, params).is_ok())
}

/// Set crossover band `xband` (0..3) of an output's wire channel `ch`.
#[no_mangle]
pub extern "C" fn dspi_set_crossover(core: *mut FfiCore, ch: u8, xband: u8, params: FilterParams) -> bool {
    with_core(core, |c| c.set_crossover(ch, xband, params).is_ok())
}

/// Bypass one band. `band` is a PEQ band (0..9) or crossover band (20..23).
#[no_mangle]
pub extern "C" fn dspi_set_band_bypass(core: *mut FfiCore, ch: u8, band: u8, bypass: bool) -> bool {
    with_core(core, |c| c.set_band_bypass(ch, band, bypass).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Preamp / Bypass / Volume
// ═══════════════════════════════════════════════════════════════════

/// Legacy preamp: sets every input to the same value.
#[no_mangle]
pub extern "C" fn dspi_set_preamp(core: *mut FfiCore, db: f32) -> bool {
    with_core(core, |c| c.set_preamp(db).is_ok())
}

/// Preamp of one input (input index).
#[no_mangle]
pub extern "C" fn dspi_set_input_preamp(core: *mut FfiCore, input: u8, db: f32) -> bool {
    with_core(core, |c| c.set_input_preamp(input, db).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_bypass(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_bypass(enabled).is_ok())
}

/// Master volume in dB (−128 = mute, otherwise −127..0).
#[no_mangle]
pub extern "C" fn dspi_set_master_volume(core: *mut FfiCore, db: f32) -> bool {
    with_core(core, |c| c.set_master_volume(db).is_ok())
}

/// 0 = master volume independent of presets, 1 = saved with presets.
#[no_mangle]
pub extern "C" fn dspi_set_master_volume_mode(core: *mut FfiCore, mode: u8) -> bool {
    with_core(core, |c| c.set_master_volume_mode(mode).is_ok())
}

/// Persist the live master volume (independent mode). Returns a PRESET_* code, 0xFF on error.
#[no_mangle]
pub extern "C" fn dspi_save_master_volume(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.save_master_volume().unwrap_or(0xFF))
}

#[no_mangle]
pub extern "C" fn dspi_set_user_volume(core: *mut FfiCore, db: f32) -> bool {
    with_core(core, |c| c.set_user_volume(db).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_user_mute(core: *mut FfiCore, muted: bool) -> bool {
    with_core(core, |c| c.set_user_mute(muted).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Delay
// ═══════════════════════════════════════════════════════════════════

/// Delay of wire channel `ch` (an output channel's delay is its output delay).
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

/// Bit k: loudness compensates output k.
#[no_mangle]
pub extern "C" fn dspi_set_loudness_mask(core: *mut FfiCore, mask: u16) -> bool {
    with_core(core, |c| c.set_loudness_mask(mask).is_ok())
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

/// Bit p: crossfeed runs on output pair p.
#[no_mangle]
pub extern "C" fn dspi_set_crossfeed_outputs(core: *mut FfiCore, pair_mask: u8) -> bool {
    with_core(core, |c| c.set_crossfeed_outputs(pair_mask).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Volume Leveller
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_leveller_enabled(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_leveller_enabled(enabled).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_leveller_amount(core: *mut FfiCore, pct: f32) -> bool {
    with_core(core, |c| c.set_leveller_amount(pct).is_ok())
}

/// 0 = slow, 1 = medium, 2 = fast.
#[no_mangle]
pub extern "C" fn dspi_set_leveller_speed(core: *mut FfiCore, speed: u8) -> bool {
    with_core(core, |c| c.set_leveller_speed(speed).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_leveller_max_gain(core: *mut FfiCore, db: f32) -> bool {
    with_core(core, |c| c.set_leveller_max_gain(db).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_leveller_lookahead(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_leveller_lookahead(enabled).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_leveller_gate(core: *mut FfiCore, db: f32) -> bool {
    with_core(core, |c| c.set_leveller_gate(db).is_ok())
}

/// Bit k of each mask = input k.
#[no_mangle]
pub extern "C" fn dspi_set_leveller_masks(core: *mut FfiCore, detector: u8, apply: u8) -> bool {
    with_core(core, |c| c.set_leveller_masks(detector, apply).is_ok())
}

/// Select the audio input source (firmware InputSource enum).
#[no_mangle]
pub extern "C" fn dspi_set_input_source(core: *mut FfiCore, source: u8) -> bool {
    with_core(core, |c| c.set_input_source(source).is_ok())
}

/// Set psybass parameter `param` (PSYBASS_PARAM_*).
#[no_mangle]
pub extern "C" fn dspi_set_psybass_param(core: *mut FfiCore, param: u8, value: f32) -> bool {
    with_core(core, |c| c.set_psybass_param(param, value).is_ok())
}

/// Bit k: psybass processes output k.
#[no_mangle]
pub extern "C" fn dspi_set_psybass_mask(core: *mut FfiCore, mask: u16) -> bool {
    with_core(core, |c| c.set_psybass_mask(mask).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_psybass_enabled(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_psybass_enabled(enabled).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Matrix / Outputs
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
    with_core(core, |c| c.set_matrix_route(input, output, enabled, gain, invert).is_ok())
}

/// Enable/disable an output. Returns the resulting state (1 on, 0 off; the
/// firmware may refuse a PDM / Core 1 conflict), or −1 on error.
#[no_mangle]
pub extern "C" fn dspi_set_output_enable(core: *mut FfiCore, output: u8, enabled: bool) -> i8 {
    with_core(core, |c| match c.set_output_enable(output, enabled) {
        Ok(v) => v as i8,
        Err(_) => -1,
    })
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

/// Set limiter parameter `param` (LIMITER_PARAM_*) of `output`
/// (LIMITER_ALL_OUTPUTS = every output).
#[no_mangle]
pub extern "C" fn dspi_set_limiter_param(core: *mut FfiCore, output: u8, param: u8, value: f32) -> bool {
    with_core(core, |c| c.set_limiter_param(output, param, value).is_ok())
}

/// Read gain reduction (dB, positive = reducing) for every output into
/// `out_gr`, which must hold MAX_OUTPUTS floats.
#[no_mangle]
pub extern "C" fn dspi_fetch_limiter_meter(core: *mut FfiCore, out_gr: *mut f32) -> bool {
    if out_gr.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_limiter_meter() {
        Ok(gr) => {
            unsafe { std::slice::from_raw_parts_mut(out_gr, MAX_OUTPUTS) }.copy_from_slice(&gr);
            true
        }
        Err(_) => false,
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Pins / Output config
// ═══════════════════════════════════════════════════════════════════

/// Returns a PIN_CONFIG_* status (0 = success), 0xFF on communication error.
#[no_mangle]
pub extern "C" fn dspi_set_output_pin(core: *mut FfiCore, slot: u8, pin: u8) -> u8 {
    with_core(core, |c| c.set_output_pin(slot, pin).unwrap_or(0xFF))
}

/// Returns the pin number, 0xFF on error.
#[no_mangle]
pub extern "C" fn dspi_fetch_output_pin(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.fetch_output_pin(slot).unwrap_or(0xFF))
}

/// 0 = output config stored independently, 1 = saved with presets.
#[no_mangle]
pub extern "C" fn dspi_set_output_config_mode(core: *mut FfiCore, mode: u8) -> bool {
    with_core(core, |c| c.set_output_config_mode(mode).is_ok())
}

/// Persist the live output config (independent mode). PRESET_* code, 0xFF on error.
#[no_mangle]
pub extern "C" fn dspi_save_output_config(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.save_output_config().unwrap_or(0xFF))
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Channel Names
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_set_channel_name(core: *mut FfiCore, ch: u8, name: *const c_char) -> bool {
    let Some(name) = c_str(name) else { return false };
    with_core(core, |c| c.set_channel_name(ch, name).is_ok())
}

/// Read a channel name from the device into `out_buf`.
#[no_mangle]
pub extern "C" fn dspi_get_channel_name(core: *mut FfiCore, ch: u8, out_buf: *mut c_char, buf_len: u32) -> bool {
    with_core(core, |c| match c.fetch_channel_name(ch) {
        Ok(name) => copy_out(&name, out_buf, buf_len),
        Err(_) => false,
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Presets
// ═══════════════════════════════════════════════════════════════════

/// PRESET_* status (0 = success), 0xFF on communication error. Waits for the
/// device to finish the (deferred) save.
#[no_mangle]
pub extern "C" fn dspi_save_preset(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.save_preset(slot).unwrap_or(0xFF))
}

/// Load a preset and re-read every parameter.
#[no_mangle]
pub extern "C" fn dspi_load_preset(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.load_preset(slot).unwrap_or(0xFF))
}

/// Copy the live state to `dest` and re-save it to `source` (which stays
/// active). PRESET_* status of the first failing save, 0xFF on timeout.
#[no_mangle]
pub extern "C" fn dspi_copy_preset(core: *mut FfiCore, source: u8, dest: u8) -> u8 {
    with_core(core, |c| c.copy_preset(source, dest).unwrap_or(0xFF))
}

#[no_mangle]
pub extern "C" fn dspi_delete_preset(core: *mut FfiCore, slot: u8) -> u8 {
    with_core(core, |c| c.delete_preset(slot).unwrap_or(0xFF))
}

#[no_mangle]
pub extern "C" fn dspi_set_preset_name(core: *mut FfiCore, slot: u8, name: *const c_char) -> bool {
    let Some(name) = c_str(name) else { return false };
    with_core(core, |c| c.set_preset_name(slot, name).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_get_preset_name(core: *mut FfiCore, slot: u8, out_buf: *mut c_char, buf_len: u32) -> bool {
    with_core(core, |c| match c.get_preset_name(slot) {
        Ok(name) => copy_out(&name, out_buf, buf_len),
        Err(_) => false,
    })
}

#[no_mangle]
pub extern "C" fn dspi_get_preset_directory(core: *mut FfiCore, out_dir: *mut PresetDirectory) -> bool {
    if out_dir.is_null() {
        return false;
    }
    with_core(core, |c| match c.get_preset_directory() {
        Ok(dir) => {
            unsafe { *out_dir = dir };
            true
        }
        Err(_) => false,
    })
}

/// mode 0 = load `default_slot` at boot, 1 = load the last active slot.
#[no_mangle]
pub extern "C" fn dspi_set_preset_startup(core: *mut FfiCore, mode: u8, default_slot: u8) -> bool {
    with_core(core, |c| c.set_preset_startup(mode, default_slot).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Flash / System
// ═══════════════════════════════════════════════════════════════════

#[no_mangle]
pub extern "C" fn dspi_save_params(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.save_params().unwrap_or(FLASH_ERR_WRITE))
}

/// Revert to saved (reloads the active preset).
#[no_mangle]
pub extern "C" fn dspi_load_params(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.load_params().unwrap_or(FLASH_ERR_WRITE))
}

#[no_mangle]
pub extern "C" fn dspi_factory_reset(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.factory_reset().unwrap_or(FLASH_ERR_WRITE))
}

/// Restart the device into its USB bootloader.
#[no_mangle]
pub extern "C" fn dspi_enter_bootloader(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.enter_bootloader().is_ok())
}

/// Core 1 mode (0 = idle, 1 = PDM, 2 = EQ worker), −1 on error.
#[no_mangle]
pub extern "C" fn dspi_fetch_core1_mode(core: *mut FfiCore) -> i8 {
    with_core(core, |c| c.fetch_core1_mode().map(|v| v as i8).unwrap_or(-1))
}

/// 1 if enabling `output` would conflict with Core 1's mode, 0 if not, −1 on error.
#[no_mangle]
pub extern "C" fn dspi_check_core1_conflict(core: *mut FfiCore, output: u8) -> i8 {
    with_core(core, |c| c.check_core1_conflict(output).map(|v| v as i8).unwrap_or(-1))
}

#[no_mangle]
pub extern "C" fn dspi_clear_clips(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.clear_clips().is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — DSP Math (stateless, no device needed)
// ═══════════════════════════════════════════════════════════════════

/// Magnitude in dB at one frequency for a chain of bands.
#[no_mangle]
pub extern "C" fn dspi_compute_response(filters: *const FilterParams, num_filters: u32, freq: f32) -> f32 {
    if filters.is_null() || num_filters == 0 {
        return 0.0;
    }
    let slice = unsafe { std::slice::from_raw_parts(filters, num_filters as usize) };
    dsp_math::response_at(freq, slice)
}

/// 201-point magnitude curve (dB, 10 Hz..20 kHz log-spaced).
/// `out_magnitudes` must hold 201 doubles.
#[no_mangle]
pub extern "C" fn dspi_compute_magnitude_curve(
    filters: *const FilterParams,
    num_filters: u32,
    out_magnitudes: *mut f64,
) -> bool {
    if out_magnitudes.is_null() {
        return false;
    }
    let slice = if filters.is_null() || num_filters == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(filters, num_filters as usize) }
    };
    let curve = dsp_math::compute_magnitude_curve(slice);
    unsafe { std::slice::from_raw_parts_mut(out_magnitudes, MAGNITUDE_POINTS) }.copy_from_slice(&curve);
    true
}

/// 201-point phase curve in degrees over the same grid; continuous when
/// `unwrap` is set, otherwise wrapped to ±180°.
#[no_mangle]
pub extern "C" fn dspi_compute_phase_curve(
    filters: *const FilterParams,
    num_filters: u32,
    unwrap: bool,
    out_phases: *mut f64,
) -> bool {
    if out_phases.is_null() {
        return false;
    }
    let slice = if filters.is_null() || num_filters == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(filters, num_filters as usize) }
    };
    let curve = dsp_math::compute_phase_curve(slice, unwrap);
    unsafe { std::slice::from_raw_parts_mut(out_phases, MAGNITUDE_POINTS) }.copy_from_slice(&curve);
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

/// Poll for hot-plug changes (~every 500 ms). Fires the registered callback
/// for arrivals (event 0) and departures (event 1).
#[no_mangle]
pub extern "C" fn dspi_poll_hotplug(core: *mut FfiCore) {
    with_core(core, |c| {
        let (arrivals, departures) = c.device_manager.poll_changes();
        if let Some((callback, user_data)) = c.hotplug_callback {
            for (event, serials) in [(0u8, &arrivals), (1u8, &departures)] {
                for serial in serials {
                    let mut buf = serial.as_bytes().to_vec();
                    buf.push(0);
                    callback(event, buf.as_ptr() as *const c_char, user_data);
                }
            }
        }
    });
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Upmixer, subharmonic synth, tube modeller
// ═══════════════════════════════════════════════════════════════════

/// Set upmixer parameter `id` (UPMIX_PARAM_*). RP2350 only.
#[no_mangle]
pub extern "C" fn dspi_set_upmix_param(core: *mut FfiCore, id: u8, value: f32) -> bool {
    with_core(core, |c| c.set_upmix_param(id, value).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_fetch_upmix_status(core: *mut FfiCore, out: *mut UpmixStatus) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_upmix_status() {
        Ok(st) => {
            unsafe { *out = st };
            true
        }
        Err(_) => false,
    })
}

/// Set subharmonic synth parameter `id` (SUBHARM_PARAM_*).
#[no_mangle]
pub extern "C" fn dspi_set_subharm_param(core: *mut FfiCore, id: u8, value: f32) -> bool {
    with_core(core, |c| c.set_subharm_param(id, value).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_subharm_solo(core: *mut FfiCore, solo: bool) -> bool {
    with_core(core, |c| c.set_subharm_solo(solo).is_ok())
}

/// Headroom the subharm settings cost, dB (0 = none).
#[no_mangle]
pub extern "C" fn dspi_fetch_subharm_headroom(core: *mut FfiCore, out_db: *mut f32) -> bool {
    if out_db.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_subharm_headroom() {
        Ok(db) => {
            unsafe { *out_db = db };
            true
        }
        Err(_) => false,
    })
}

/// Synthesized sub peak per output, 0..1. `out` must hold MAX_OUTPUTS floats.
#[no_mangle]
pub extern "C" fn dspi_fetch_subharm_meter(core: *mut FfiCore, out: *mut f32) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_subharm_meter() {
        Ok(m) => {
            unsafe { std::slice::from_raw_parts_mut(out, MAX_OUTPUTS) }.copy_from_slice(&m);
            true
        }
        Err(_) => false,
    })
}

/// Set tube parameter `idx` (TUBE_PARAM_*).
#[no_mangle]
pub extern "C" fn dspi_set_tube_param(core: *mut FfiCore, idx: u8, value: f32) -> bool {
    with_core(core, |c| c.set_tube_param(idx, value).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Hardware IO (outputs, clocks, inputs). Status-returning calls
// give the PIN_CONFIG_* code, or 255 when the device did not answer.
// ═══════════════════════════════════════════════════════════════════

/// Slot type: 0 = S/PDIF, 1 = I2S.
#[no_mangle]
pub extern "C" fn dspi_set_output_type(core: *mut FfiCore, slot: u8, kind: u8) -> u8 {
    with_core(core, |c| c.set_output_type(slot, kind).unwrap_or(255))
}

/// I2S BCK pin (LRCLK = +1); role 0 = master/shared, 1 = slave pair.
#[no_mangle]
pub extern "C" fn dspi_set_i2s_bck_pin(core: *mut FfiCore, role: u8, pin: u8) -> u8 {
    with_core(core, |c| c.set_i2s_bck_pin(role, pin).unwrap_or(255))
}

/// 0 = shared clock pins, 1 = separate slave pins.
#[no_mangle]
pub extern "C" fn dspi_set_i2s_clock_pin_mode(core: *mut FfiCore, mode: u8) -> u8 {
    with_core(core, |c| c.set_i2s_clock_pin_mode(mode).unwrap_or(255))
}

/// Master clock output on/off.
#[no_mangle]
pub extern "C" fn dspi_set_mck_enabled(core: *mut FfiCore, enabled: bool) -> u8 {
    with_core(core, |c| c.set_mck_enabled(enabled).unwrap_or(255))
}

/// Master clock pin (MCK off first).
#[no_mangle]
pub extern "C" fn dspi_set_mck_pin(core: *mut FfiCore, pin: u8) -> u8 {
    with_core(core, |c| c.set_mck_pin(pin).unwrap_or(255))
}

/// 0 = 128 x fs, 1 = 256 x fs.
#[no_mangle]
pub extern "C" fn dspi_set_mck_multiplier(core: *mut FfiCore, mult: u8) -> u8 {
    with_core(core, |c| c.set_mck_multiplier(mult).unwrap_or(255))
}

/// ADAT optical output (RP2350).
#[no_mangle]
pub extern "C" fn dspi_set_adat_out_enabled(core: *mut FfiCore, enabled: bool) -> u8 {
    with_core(core, |c| c.set_adat_out_enabled(enabled).unwrap_or(255))
}

/// ADAT output data pin.
#[no_mangle]
pub extern "C" fn dspi_set_adat_out_pin(core: *mut FfiCore, pin: u8) -> u8 {
    with_core(core, |c| c.set_adat_out_pin(pin).unwrap_or(255))
}

/// S/PDIF input RX pin (index 0-3).
#[no_mangle]
pub extern "C" fn dspi_set_spdif_rx_pin(core: *mut FfiCore, index: u8, pin: u8) -> u8 {
    with_core(core, |c| c.set_spdif_rx_pin(index, pin).unwrap_or(255))
}

/// Enable S/PDIF input 2-4 (index 1-3).
#[no_mangle]
pub extern "C" fn dspi_set_spdif_input_enabled(core: *mut FfiCore, index: u8, enabled: bool) -> u8 {
    with_core(core, |c| c.set_spdif_input_enabled(index, enabled).unwrap_or(255))
}

/// I2S input data pin of a pair (0-3).
#[no_mangle]
pub extern "C" fn dspi_set_i2s_rx_pin(core: *mut FfiCore, pair: u8, pin: u8) -> u8 {
    with_core(core, |c| c.set_i2s_rx_pin(pair, pin).unwrap_or(255))
}

/// I2S input channels: 2, 4, 6 or 8.
#[no_mangle]
pub extern "C" fn dspi_set_i2s_input_channels(core: *mut FfiCore, channels: u8) -> u8 {
    with_core(core, |c| c.set_i2s_input_channels(channels).unwrap_or(255))
}

/// ADAT input on/off (needs a pin).
#[no_mangle]
pub extern "C" fn dspi_set_adat_input_enabled(core: *mut FfiCore, enabled: bool) -> u8 {
    with_core(core, |c| c.set_adat_input_enabled(enabled).unwrap_or(255))
}

/// ADAT input data pin; 0xFF clears it.
#[no_mangle]
pub extern "C" fn dspi_set_adat_input_pin(core: *mut FfiCore, pin: u8) -> u8 {
    with_core(core, |c| c.set_adat_input_pin(pin).unwrap_or(255))
}

/// ADAT input clock: 0 = master, 1 = slave.
#[no_mangle]
pub extern "C" fn dspi_set_adat_input_clock_mode(core: *mut FfiCore, mode: u8) -> u8 {
    with_core(core, |c| c.set_adat_input_clock_mode(mode).unwrap_or(255))
}

/// Master-mode input rate for I2S and ADAT: 0 = 44.1k, 1 = 48k, 2 = 96k.
#[no_mangle]
pub extern "C" fn dspi_set_input_rate(core: *mut FfiCore, index: u8) -> bool {
    with_core(core, |c| c.set_input_rate(index).is_ok())
}

/// The rate the pipeline runs at now, Hz (0 if unknown).
#[no_mangle]
pub extern "C" fn dspi_fetch_input_rate(core: *mut FfiCore) -> u32 {
    with_core(core, |c| c.fetch_input_rate().unwrap_or(0))
}

/// I2S input clock: 0 = master, 1 = slave (applied by the device later).
#[no_mangle]
pub extern "C" fn dspi_set_i2s_clock_mode(core: *mut FfiCore, mode: u8) -> bool {
    with_core(core, |c| c.set_i2s_clock_mode(mode).is_ok())
}

/// `which`: 0 = I2S slave lock, 1 = ADAT input lock.
#[no_mangle]
pub extern "C" fn dspi_fetch_input_lock(core: *mut FfiCore, which: u8, out: *mut InputLockStatus) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| {
        let r = if which == 0 { c.fetch_i2s_slave_status() } else { c.fetch_adat_input_status() };
        match r {
            Ok(st) => {
                unsafe { *out = st };
                true
            }
            Err(_) => false,
        }
    })
}

#[no_mangle]
pub extern "C" fn dspi_fetch_adat_out_status(core: *mut FfiCore, out: *mut AdatOutStatus) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_adat_out_status() {
        Ok(st) => {
            unsafe { *out = st };
            true
        }
        Err(_) => false,
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — DAC hardware mute, LG Sound Sync, UART / I2C control
// ═══════════════════════════════════════════════════════════════════

/// Send a DAC mute config; read it back with `dspi_fetch_dac_mute` ~150 ms later.
#[no_mangle]
pub extern "C" fn dspi_set_dac_mute(core: *mut FfiCore, enabled: bool, active_low: bool, pin: u8, hold_ms: u16, release_ms: u16) -> bool {
    with_core(core, |c| c.set_dac_mute(enabled, active_low, pin, hold_ms, release_ms).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_fetch_dac_mute(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.fetch_dac_mute().is_ok())
}

/// Pulse the DAC mute output for ~1 s. Returns 0 when started, 3 when the
/// feature is disabled, 255 if the device did not answer.
#[no_mangle]
pub extern "C" fn dspi_test_dac_mute(core: *mut FfiCore) -> u8 {
    with_core(core, |c| c.test_dac_mute().unwrap_or(255))
}

#[no_mangle]
pub extern "C" fn dspi_set_lg_sound_sync(core: *mut FfiCore, enabled: bool) -> bool {
    with_core(core, |c| c.set_lg_sound_sync(enabled).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_fetch_lg_status(core: *mut FfiCore, out: *mut LgStatus) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_lg_status() {
        Ok(st) => {
            unsafe { *out = st };
            true
        }
        Err(_) => false,
    })
}

/// Re-read both control interface configs and their status into the state.
#[no_mangle]
pub extern "C" fn dspi_fetch_ctrl_ifaces(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.fetch_ctrl_ifaces().is_ok())
}

/// Send a UART config; read the outcome with `dspi_fetch_ctrl_ifaces` ~250 ms later.
#[no_mangle]
pub extern "C" fn dspi_set_uart(core: *mut FfiCore, config: UartConfig) -> bool {
    with_core(core, |c| c.set_uart(config).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_set_i2c(core: *mut FfiCore, config: I2cConfig) -> bool {
    with_core(core, |c| c.set_i2c(config).is_ok())
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Device notifications
// ═══════════════════════════════════════════════════════════════════

/// Register the callback the notification listener thread calls when
/// packets are waiting. It runs on that thread: it must only schedule
/// `dspi_process_notifications` on the GUI thread.
#[no_mangle]
pub extern "C" fn dspi_set_notify_callback(
    core: *mut FfiCore,
    callback: notify::NotifyCallback,
    user_data: *mut c_void,
) {
    with_core(core, |c| c.device_manager.notify_hub().set_waker(callback, user_data));
}

/// Apply the queued device notifications to the state. `out` receives what
/// changed (`NOTIFY_*` flags and the wire channels whose filters changed).
#[no_mangle]
pub extern "C" fn dspi_process_notifications(core: *mut FfiCore, out: *mut notify::NotifyResult) {
    let r = with_core(core, |c| c.process_notifications());
    if !out.is_null() {
        unsafe { *out = r };
    }
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Spectrum analyser
// ═══════════════════════════════════════════════════════════════════

/// Register the callback the analyser worker calls (on its own thread) when
/// the caps or the snapshot changed. It must only schedule work on the GUI
/// thread. NULL stops the calls; once this returns, no call is in progress.
#[no_mangle]
pub extern "C" fn dspi_rta_set_callback(core: *mut FfiCore, callback: Option<extern "C" fn(user_data: *mut c_void)>, user_data: *mut c_void) {
    with_core(core, |c| c.device_manager.rta_hub().set_waker(callback, user_data));
}

/// Probe and start polling the connected device's analyser (compatible
/// firmware only). Stops by itself on disconnect.
#[no_mangle]
pub extern "C" fn dspi_rta_start(core: *mut FfiCore) {
    with_core(core, |c| c.device_manager.start_rta());
}

/// What to analyse. A zero mask releases the analyser.
#[no_mangle]
pub extern "C" fn dspi_rta_set_request(core: *mut FfiCore, request: *const rta::RtaRequest) {
    if request.is_null() {
        return;
    }
    let r = unsafe { *request };
    with_core(core, |c| c.device_manager.rta_hub().set_request(r));
}

/// The analyser's capabilities (`supported` false until probed or without one).
#[no_mangle]
pub extern "C" fn dspi_rta_get_caps(core: *mut FfiCore, out: *mut rta::RtaCapsInfo) {
    if out.is_null() {
        return;
    }
    let caps = with_core(core, |c| c.device_manager.rta_hub().caps());
    unsafe { *out = caps };
}

/// Copy the latest snapshot into `out`.
#[no_mangle]
pub extern "C" fn dspi_rta_get_snapshot(core: *mut FfiCore, out: *mut rta::RtaSnapshot) {
    if out.is_null() {
        return;
    }
    let hub = with_core(core, |c| c.device_manager.rta_hub());
    unsafe { *out = hub.snapshot() };
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Signal generator
// ═══════════════════════════════════════════════════════════════════

/// The generator's caps and signal types. False on a USB error; true with
/// `supported` false when the firmware has no generator.
#[no_mangle]
pub extern "C" fn dspi_siggen_fetch_caps(core: *mut FfiCore, out: *mut siggen::SiggenCaps) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_siggen_caps() {
        Ok(caps) => {
            unsafe { *out = caps };
            true
        }
        Err(_) => false,
    })
}

/// The config the generator runs (as the device sanitised it).
#[no_mangle]
pub extern "C" fn dspi_siggen_get_config(core: *mut FfiCore, out: *mut siggen::SiggenConfig) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_siggen_config() {
        Ok(cfg) => {
            unsafe { *out = cfg };
            true
        }
        Err(_) => false,
    })
}

/// Stage a config; a running generator restarts with it. The device ACKs
/// even a config it refuses: read it back to check.
#[no_mangle]
pub extern "C" fn dspi_siggen_set_config(core: *mut FfiCore, cfg: *const siggen::SiggenConfig) -> bool {
    if cfg.is_null() {
        return false;
    }
    let cfg = unsafe { *cfg };
    with_core(core, |c| c.set_siggen_config(&cfg).is_ok())
}

/// SIGGEN_CTL_START / STOP (fade) / STOP_NOW. False if refused.
#[no_mangle]
pub extern "C" fn dspi_siggen_control(core: *mut FfiCore, action: u16) -> bool {
    with_core(core, |c| c.siggen_control(action).is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_siggen_get_status(core: *mut FfiCore, out: *mut siggen::SiggenStatus) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_siggen_status() {
        Ok(s) => {
            unsafe { *out = s };
            true
        }
        Err(_) => false,
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Statistics
// ═══════════════════════════════════════════════════════════════════

/// One REQ_GET_STATUS u32 counter (STAT_*).
#[no_mangle]
pub extern "C" fn dspi_fetch_stat(core: *mut FfiCore, which: u16, out: *mut u32) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_stat(which) {
        Ok(v) => {
            unsafe { *out = v };
            true
        }
        Err(_) => false,
    })
}

#[no_mangle]
pub extern "C" fn dspi_fetch_buffer_stats(core: *mut FfiCore, out: *mut stats::BufferStats) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_buffer_stats() {
        Ok(s) => {
            unsafe { *out = s };
            true
        }
        Err(_) => false,
    })
}

/// Restart the buffer watermarks.
#[no_mangle]
pub extern "C" fn dspi_reset_buffer_stats(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.reset_buffer_stats().is_ok())
}

#[no_mangle]
pub extern "C" fn dspi_fetch_spdif_rx_status(core: *mut FfiCore, out: *mut stats::SpdifRxStatus) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_spdif_rx_status() {
        Ok(s) => {
            unsafe { *out = s };
            true
        }
        Err(_) => false,
    })
}

/// `out` receives 24 bytes of IEC 60958 channel status.
#[no_mangle]
pub extern "C" fn dspi_fetch_spdif_rx_channel_status(core: *mut FfiCore, out: *mut u8) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_spdif_rx_channel_status() {
        Ok(b) => {
            unsafe { std::slice::from_raw_parts_mut(out, 24) }.copy_from_slice(&b);
            true
        }
        Err(_) => false,
    })
}

/// GPIO of S/PDIF receiver `index`; false if it has none.
#[no_mangle]
pub extern "C" fn dspi_fetch_spdif_rx_pin(core: *mut FfiCore, index: u8, out: *mut u8) -> bool {
    if out.is_null() {
        return false;
    }
    with_core(core, |c| match c.fetch_spdif_rx_pin(index) {
        Ok(p) => {
            unsafe { *out = p };
            true
        }
        Err(_) => false,
    })
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Interrupt Monitor
// ═══════════════════════════════════════════════════════════════════

/// Copy the notification log lines after `after_id` into `buf` as
/// "time_ms<TAB>text<LF>" (ms since the Unix epoch), stopping before `buf`
/// would overflow. Returns the id of the last line written (`after_id` if
/// none); call again from there to get the rest.
#[no_mangle]
pub extern "C" fn dspi_monitor_read(core: *mut FfiCore, after_id: u64, buf: *mut c_char, buf_len: u32) -> u64 {
    if buf.is_null() || buf_len == 0 {
        return after_id;
    }
    let hub = with_core(core, |c| c.device_manager.notify_hub());
    let mut text = String::new();
    let mut last = after_id;
    let limit = buf_len as usize - 1;
    let mut full = false;
    hub.monitor.read_after(after_id, |e| {
        if full {
            return;
        }
        let line = format!("{}\t{}\n", e.time_ms, e.text);
        if text.len() + line.len() > limit {
            full = true;
            return;
        }
        text.push_str(&line);
        last = e.id;
    });
    copy_out(&text, buf, buf_len);
    last
}

/// Empty the notification log.
#[no_mangle]
pub extern "C" fn dspi_monitor_clear(core: *mut FfiCore) {
    with_core(core, |c| c.device_manager.notify_hub().monitor.clear());
}

// ═══════════════════════════════════════════════════════════════════
// FFI — Configuration and filter files
// ═══════════════════════════════════════════════════════════════════

/// Copy `s` into `buf` (NUL-terminated); returns the bytes needed including
/// the NUL, so a caller with too small a buffer can retry.
fn copy_text(s: &str, buf: *mut c_char, len: u32) -> u32 {
    let needed = s.len() as u32 + 1;
    if !buf.is_null() && len >= needed {
        copy_out(s, buf, len);
    }
    needed
}

/// The device's configuration as a `.dspipreset` document. `links` = the
/// app's input-pair link mask. Returns the length needed (see copy_text).
#[no_mangle]
pub extern "C" fn dspi_config_export(core: *mut FfiCore, name: *const c_char, app_version: *const c_char,
                                     links: u8, buf: *mut c_char, len: u32) -> u32 {
    let text = with_core(core, |c| presetfile::export(&c.state, c_str(name).unwrap_or(""), c_str(app_version).unwrap_or(""), links));
    copy_text(&text, buf, len)
}

/// Check a document and describe it, as JSON {ok, error, name, platform,
/// firmware, savedUtc}. Returns the length needed.
#[no_mangle]
pub extern "C" fn dspi_config_inspect(text: *const c_char, buf: *mut c_char, len: u32) -> u32 {
    let out = match presetfile::parse(c_str(text).unwrap_or("")) {
        Ok(v) => {
            let (name, platform, firmware, saved) = presetfile::provenance(&v);
            serde_json::json!({ "ok": true, "name": name, "platform": platform, "firmware": firmware, "savedUtc": saved })
        }
        Err(e) => serde_json::json!({ "ok": false, "error": e }),
    };
    copy_text(&out.to_string(), buf, len)
}

/// Apply a document (`options`: 1 = volumes, 2 = hardware I/O). Writes JSON
/// {ok, error, lines, clean, links (or null), hardwareWritten}. Returns the
/// length needed.
#[no_mangle]
pub extern "C" fn dspi_config_import(core: *mut FfiCore, text: *const c_char, options: u32, buf: *mut c_char, len: u32) -> u32 {
    let out = match presetfile::parse(c_str(text).unwrap_or("")) {
        Err(e) => serde_json::json!({ "ok": false, "error": e }),
        Ok(v) => match with_core(core, |c| c.import_preset(&v, options)) {
            Ok(r) => serde_json::json!({ "ok": true, "lines": r.lines, "clean": r.clean, "links": r.links,
                                         "hardwareWritten": r.hardware_written }),
            Err(e) => serde_json::json!({ "ok": false, "error": format!("The device could not be written: {e}.") }),
        },
    };
    copy_text(&out.to_string(), buf, len)
}

/// Every channel's filters as a text file (`inputs` = live inputs to write).
#[no_mangle]
pub extern "C" fn dspi_filters_export(core: *mut FfiCore, inputs: u8, buf: *mut c_char, len: u32) -> u32 {
    let text = with_core(core, |c| filterfile::export(&c.state, inputs as usize));
    copy_text(&text, buf, len)
}

/// What a filter file holds, for the channel picker (JSON).
#[no_mangle]
pub extern "C" fn dspi_filters_inspect(core: *mut FfiCore, text: *const c_char, inputs: u8, buf: *mut c_char, len: u32) -> u32 {
    let out = with_core(core, |c| filterfile::inspect(&c.state, c_str(text).unwrap_or(""), inputs as usize));
    copy_text(&out.to_string(), buf, len)
}

/// Apply a filter file to the channels in `wires` (wire indices). Writes
/// JSON {ok, error, lines}.
#[no_mangle]
pub extern "C" fn dspi_filters_import(core: *mut FfiCore, text: *const c_char, wires: *const u8, count: u32,
                                      buf: *mut c_char, len: u32) -> u32 {
    let chosen: Vec<usize> = if wires.is_null() { vec![] } else {
        unsafe { std::slice::from_raw_parts(wires, count as usize) }.iter().map(|&w| w as usize).collect()
    };
    let out = match with_core(core, |c| c.import_filters(c_str(text).unwrap_or(""), &chosen)) {
        Ok(lines) => serde_json::json!({ "ok": true, "lines": lines }),
        Err(e) => serde_json::json!({ "ok": false, "error": format!("The device could not be written: {e}.") }),
    };
    copy_text(&out.to_string(), buf, len)
}

/// Read the whole control surfaces configuration from the device (bindings,
/// IR commands, groups, macros, display, aux). Returns false on a transfer
/// error; firmware without control surfaces reads as unsupported.
#[no_mangle]
pub extern "C" fn dspi_cs_fetch(core: *mut FfiCore) -> bool {
    with_core(core, |c| c.cs_fetch_all().is_ok())
}

/// The control surfaces configuration as JSON (see cs::cs_snapshot).
#[no_mangle]
pub extern "C" fn dspi_cs_snapshot(core: *mut FfiCore, buf: *mut c_char, len: u32) -> u32 {
    let out = with_core(core, |c| c.cs_snapshot());
    copy_text(&out.to_string(), buf, len)
}

/// Perform one control surfaces operation, given as JSON {op, index, ...}.
/// Writes JSON {ok, status, error, ...}.
#[no_mangle]
pub extern "C" fn dspi_cs_apply(core: *mut FfiCore, op: *const c_char, buf: *mut c_char, len: u32) -> u32 {
    let out = match serde_json::from_str::<serde_json::Value>(c_str(op).unwrap_or("")) {
        Ok(v) => match with_core(core, |c| c.cs_apply(&v)) {
            Ok(r) => r,
            Err(e) => serde_json::json!({ "ok": false, "error": format!("{e}") }),
        },
        Err(e) => serde_json::json!({ "ok": false, "error": format!("{e}") }),
    };
    copy_text(&out.to_string(), buf, len)
}

/// GPIOs held by live control surface bindings: fills `pins` and `slots`
/// (up to `max` each) and returns how many there are.
#[no_mangle]
pub extern "C" fn dspi_cs_pin_uses(core: *mut FfiCore, pins: *mut u8, slots: *mut u8, max: u32) -> u32 {
    let uses = with_core(core, |c| c.cs_pin_uses());
    if !pins.is_null() && !slots.is_null() {
        for (i, (p, s)) in uses.iter().take(max as usize).enumerate() {
            unsafe {
                *pins.add(i) = *p;
                *slots.add(i) = *s;
            }
        }
    }
    uses.len() as u32
}

/// Boards in BOOTSEL (Raspberry Pi's ROM loader, not DSPi) on the USB bus:
/// fills the RP2040 and RP2350 counts.
#[no_mangle]
pub extern "C" fn dspi_bootloader_counts(rp2040: *mut u32, rp2350: *mut u32) {
    let (mut a, mut b) = (0u32, 0u32);
    if let Ok(list) = rusb::devices() {
        for d in list.iter() {
            if let Ok(desc) = d.device_descriptor() {
                if desc.vendor_id() == 0x2E8A {
                    match desc.product_id() {
                        0x0003 => a += 1,
                        0x000F => b += 1,
                        _ => {}
                    }
                }
            }
        }
    }
    unsafe {
        if !rp2040.is_null() { *rp2040 = a; }
        if !rp2350.is_null() { *rp2350 = b; }
    }
}

/// The live state now matches the active preset (after connecting, loading
/// a preset, saving to the active slot, reverting or a factory reset).
#[no_mangle]
pub extern "C" fn dspi_capture_baseline(core: *mut FfiCore) {
    with_core(core, |c| c.capture_baseline());
}

/// Whether the live state differs from the active preset.
#[no_mangle]
pub extern "C" fn dspi_preset_dirty(core: *mut FfiCore) -> bool {
    with_core(core, |c| !c.preset_changes().is_empty())
}

/// What differs from the active preset, as a JSON array of sentences.
#[no_mangle]
pub extern "C" fn dspi_preset_changes(core: *mut FfiCore, buf: *mut c_char, len: u32) -> u32 {
    let lines = with_core(core, |c| c.preset_changes());
    copy_text(&serde_json::Value::from(lines).to_string(), buf, len)
}

// Re-export constants that C consumers need
pub use protocol::{FLASH_ERR_WRITE, FLASH_OK, FW_BETA_EARLY, PIN_CONFIG_SUCCESS, PRESET_OK};
pub use notify::{
    NOTIFY_CS_AUX, NOTIFY_CURVES, NOTIFY_INPUT_FORMAT, NOTIFY_IR_LEARN, NOTIFY_PRESET, NOTIFY_REFRESHED, NOTIFY_SIGGEN,
    NOTIFY_STATE,
};
pub use stats::{
    STAT_CLOCK_HZ, STAT_CORE_MV, STAT_PDM_DMA_OVERRUNS, STAT_PDM_DMA_UNDERRUNS, STAT_PDM_RING_OVERRUNS,
    STAT_PDM_RING_UNDERRUNS, STAT_SAMPLE_RATE, STAT_SPDIF_OVERRUNS, STAT_SPDIF_UNDERRUNS, STAT_STARVATION_FIRST,
    STAT_STARVATION_TOTAL, STAT_TEMPERATURE, STAT_USB_RING_OVERRUNS,
};
pub use siggen::{SIGGEN_CTL_START, SIGGEN_CTL_STOP, SIGGEN_CTL_STOP_NOW, SIGGEN_FLAG_DECORR, SIGGEN_FLAG_RAW, SIGGEN_FLAG_WALK, SIGGEN_TYPE_COUNT};
pub use rta::{RTA_FLOOR_DB, RTA_MAX_BANDS, RTA_MAX_BINS, RTA_MAX_CHANNELS, RTA_TAP_INPUT, RTA_TAP_OUTPUT};
