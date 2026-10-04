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

// Re-export constants that C consumers need
pub use protocol::{FLASH_ERR_WRITE, FLASH_OK, PIN_CONFIG_SUCCESS, PRESET_OK};
pub use notify::{NOTIFY_CURVES, NOTIFY_INPUT_FORMAT, NOTIFY_PRESET, NOTIFY_REFRESHED, NOTIFY_STATE};
