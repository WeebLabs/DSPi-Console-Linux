//! Shared types with C-compatible representations for FFI.
//!
//! Channel indices everywhere in the core are firmware *wire* indices
//! (unified channel model, wire format V16+):
//! `[ inputs 0..num_input_channels-1 ][ outputs num_input_channels.. ]`.
//! RP2040 has 2 inputs + 5 outputs (7 channels), RP2350 8 inputs + 9 outputs
//! (17 channels). Output-relative commands (matrix, output gain/mute/delay,
//! limiter) take an output index 0..num_output_channels-1 instead.

// ── Filter types (firmware config.h `enum FilterType`) ─────────────────
//
// Value space: 0..13 PEQ types, 14..31 reserved, 32..63 crossover types
// (only valid in crossover bands), 64+ reserved.

pub const FILTER_FLAT: u8 = 0;
pub const FILTER_PEAKING: u8 = 1;
pub const FILTER_LOWSHELF: u8 = 2;
pub const FILTER_HIGHSHELF: u8 = 3;
pub const FILTER_LOWPASS: u8 = 4;
pub const FILTER_HIGHPASS: u8 = 5;
pub const FILTER_NOTCH: u8 = 6;
/// Second-order (RBJ) all-pass.
pub const FILTER_ALLPASS: u8 = 7;
/// First-order all-pass: frequency only.
pub const FILTER_ALLPASS1: u8 = 8;
/// First-order low shelf: frequency + gain, no Q.
pub const FILTER_LOWSHELF1: u8 = 9;
/// First-order high shelf: frequency + gain, no Q.
pub const FILTER_HIGHSHELF1: u8 = 10;
/// Linkwitz Transform: freq = f0, q = Q0, gain carries fp in Hz, qp = target Q.
pub const FILTER_LINKWITZ_TRANSFORM: u8 = 11;
/// First-order low pass (6 dB/oct): frequency only.
pub const FILTER_LOWPASS1: u8 = 12;
/// First-order high pass (6 dB/oct): frequency only.
pub const FILTER_HIGHPASS1: u8 = 13;

/// First crossover type (LR2 LP). Crossover types run 32..=63:
/// LR2/4/6/8 = 32..39, Butterworth 1..8 = 40..55, Bessel 2/4/6/8 = 56..63,
/// each pair LP = even, HP = odd.
pub const FILTER_XOVER_FIRST: u8 = 32;
pub const FILTER_XOVER_LAST: u8 = 63;

/// True for a PEQ filter type (anything below the crossover block).
pub fn filter_is_peq(t: u8) -> bool {
    t < FILTER_XOVER_FIRST
}

/// True for a crossover filter type (32..=63).
pub fn filter_is_crossover(t: u8) -> bool {
    (FILTER_XOVER_FIRST..=FILTER_XOVER_LAST).contains(&t)
}

/// Crossover family, matching firmware `XoverFamily`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum XoverFamily {
    LinkwitzRiley,
    Butterworth,
    Bessel,
}

/// Decode a crossover type into (family, order, is_high_pass).
pub fn crossover_meta(t: u8) -> Option<(XoverFamily, u8, bool)> {
    if !filter_is_crossover(t) {
        return None;
    }
    let rel = t - FILTER_XOVER_FIRST;
    let hp = rel & 1 == 1;
    let pair = rel / 2;
    Some(match pair {
        0..=3 => (XoverFamily::LinkwitzRiley, (pair + 1) * 2, hp),
        4..=11 => (XoverFamily::Butterworth, pair - 3, hp),
        _ => (XoverFamily::Bessel, (pair - 11) * 2, hp),
    })
}

/// Default Q (Butterworth), also the Linkwitz Transform target-Q default.
pub const DEFAULT_Q: f32 = 0.707;

/// Parameters for a single filter band (PEQ or crossover).
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct FilterParams {
    /// Firmware filter type (`FILTER_*`).
    pub filter_type: u8,
    /// User bypass: the band keeps its settings but is not processed.
    pub bypass: bool,
    pub freq: f32,
    pub q: f32,
    /// Gain in dB; for the Linkwitz Transform, the target frequency fp in Hz.
    pub gain: f32,
    /// Linkwitz Transform target Q (ignored by every other type).
    pub qp: f32,
}

impl Default for FilterParams {
    fn default() -> Self {
        Self {
            filter_type: FILTER_FLAT,
            bypass: false,
            freq: 1000.0,
            q: DEFAULT_Q,
            gain: 0.0,
            qp: DEFAULT_Q,
        }
    }
}

impl PartialEq for FilterParams {
    fn eq(&self, other: &Self) -> bool {
        self.filter_type == other.filter_type
            && self.bypass == other.bypass
            && self.freq == other.freq
            && self.q == other.q
            && self.gain == other.gain
            && (self.filter_type != FILTER_LINKWITZ_TRANSFORM || self.qp == other.qp)
    }
}

impl FilterParams {
    /// Wire encoding of the LT target Q: round(qp × 512), 0 for every other type.
    pub fn qp_x512(&self) -> u16 {
        if self.filter_type == FILTER_LINKWITZ_TRANSFORM {
            (self.qp.clamp(0.1, 20.0) * 512.0).round() as u16
        } else {
            0
        }
    }

    /// Decode a wire `qp_x512`; 0 selects the 0.707 default.
    pub fn decode_qp(raw: u16) -> f32 {
        if raw == 0 {
            DEFAULT_Q
        } else {
            raw as f32 / 512.0
        }
    }
}

/// External-clock lock of the I2S input in slave mode, or of the ADAT input.
/// state: I2S 0 inactive, 1 acquiring, 2 relocking, 3 locked;
///        ADAT 0 inactive, 1 acquiring, 2 syncing, 3 locked, 4 relocking.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct InputLockStatus {
    pub state: u8,
    /// 0 = master (DSPi drives the clock), 1 = slave.
    pub clock_mode: u8,
    /// Rate locked to (Hz, 0 until locked) and the raw measurement.
    pub detected_rate: u32,
    pub measured_hz: u32,
    /// ADAT: the rate is supported (44.1/48 kHz).
    pub rate_ok: bool,
}

/// ADAT bulk output state (REQ_GET_ADAT_STATUS, RP2350).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct AdatOutStatus {
    pub enabled: bool,
    /// Streaming now (suspended above 48 kHz).
    pub active: bool,
    pub pin: u8,
    pub rate_ok: bool,
    pub resync_count: u16,
    pub slip_count: u16,
}

/// LG Sound Sync live state (REQ_GET_LG_SOUND_SYNC_STATUS).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct LgStatus {
    pub enabled: bool,
    /// An LG TV's volume signalling is being decoded.
    pub present: bool,
    /// TV volume 0..100; 0xFF until one has been decoded.
    pub volume: u8,
    pub muted: bool,
}

/// UART control interface config (REQ_GET/SET_UART_CONFIG). Device-level,
/// stored in the flash directory, not in the bulk image.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UartConfig {
    pub enabled: bool,
    pub tx_pin: u8,
    pub rx_pin: u8,
    /// Push change notifications to the controller.
    pub notify: bool,
    pub baud: u32,
}

impl Default for UartConfig {
    fn default() -> Self {
        Self { enabled: false, tx_pin: 16, rx_pin: 17, notify: false, baud: 115_200 }
    }
}

/// I2C target control interface config (REQ_GET/SET_I2C_CONFIG).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct I2cConfig {
    pub enabled: bool,
    pub sda_pin: u8,
    pub scl_pin: u8,
    /// 7-bit target address, 0x08..0x77.
    pub address: u8,
}

impl Default for I2cConfig {
    fn default() -> Self {
        Self { enabled: false, sda_pin: 18, scl_pin: 19, address: 0x42 }
    }
}

/// Control interface outcome and run state (REQ_GET_CTRL_IFACE_STATUS).
/// `*_last_status`: 0 OK, 1 invalid pin, 2 pin in use, 5 invalid parameter.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct CtrlIfaceStatus {
    pub uart_last_status: u8,
    pub uart_live: bool,
    pub i2c_last_status: u8,
    pub i2c_live: bool,
    pub protocol_version: u8,
}

/// Live upmixer state (REQ_UPMIX_GET_STATUS).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct UpmixStatus {
    /// True while the upmixer is processing audio.
    pub active: bool,
    /// Why it is idle: 0 active, 1 disabled, 2 input not stereo, 3 rate above 48 kHz.
    pub parked_reason: u8,
    /// Running L/R correlation, -1..1 (0 with a passive centre).
    pub correlation: f32,
    pub balance: f32,
    /// Current gains of the derived channels, 0..1.
    pub center_gain: f32,
    pub ls_gain: f32,
    pub rs_gain: f32,
}

/// System status from the device (REQ_GET_STATUS wValue = 9).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SystemStatus {
    /// Peak level per wire channel, 0.0..1.0.
    pub peaks: [f32; MAX_CHANNELS],
    pub cpu0: u8,
    pub cpu1: u8,
    /// Sticky clip flags, one bit per wire channel.
    pub clip_flags: u32,
    /// Live active input channel count (source-aware).
    pub active_input_channels: u8,
    pub num_channels: u8,
}

impl Default for SystemStatus {
    fn default() -> Self {
        Self {
            peaks: [0.0; MAX_CHANNELS],
            cpu0: 0,
            cpu1: 0,
            clip_flags: 0,
            active_input_channels: 0,
            num_channels: 0,
        }
    }
}

/// Information about a discovered DSPi device.
#[repr(C)]
#[derive(Debug, Clone)]
pub struct DeviceInfo {
    /// NUL-terminated ASCII serial number.
    pub serial: [u8; 64],
    pub serial_len: u32,
    pub location_id: u32,
}

impl DeviceInfo {
    pub fn serial_str(&self) -> &str {
        let len = self.serial_len as usize;
        std::str::from_utf8(&self.serial[..len]).unwrap_or("")
    }
}

/// Platform and firmware identification (REQ_GET_PLATFORM, 7-byte reply).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PlatformInfo {
    /// 0 = RP2040, 1 = RP2350.
    pub platform_id: u8,
    pub num_output_channels: u8,
    pub fw_major: u8,
    pub fw_minor: u8,
    pub fw_patch: u8,
    /// Pre-release ordinal: 0 = final release, N = beta N.
    pub fw_beta: u8,
}

/// Preset directory (REQ_PRESET_GET_DIR, 7-byte reply).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct PresetDirectory {
    /// Bitmask of occupied preset slots (10 slots).
    pub occupied_mask: u16,
    /// 0 = load the specified default slot, 1 = load the last active slot.
    pub startup_mode: u8,
    pub default_slot: u8,
    pub last_active: u8,
    /// 0 = output config is stored independently, 1 = it travels with presets.
    pub output_config_mode: u8,
    /// 0 = master volume is stored independently, 1 = it travels with presets.
    pub master_volume_mode: u8,
}

/// Maximum channels in the wire format (inputs + outputs, RP2350).
pub const MAX_CHANNELS: usize = 17;
/// Maximum input channels (RP2350).
pub const MAX_INPUTS: usize = 8;
/// Maximum output channels (RP2350).
pub const MAX_OUTPUTS: usize = 9;
/// PEQ bands per channel that the firmware processes.
pub const BANDS_PER_CHANNEL: usize = 10;
/// PEQ band storage per channel in the wire layout.
pub const FIRMWARE_BANDS_PER_CHANNEL: usize = 12;
/// Crossover bands per output channel.
pub const MAX_XOVER_BANDS: usize = 4;
/// Wire band index of crossover band 0 (crossover bands are 20..23).
pub const XOVER_BAND_BASE: u8 = 20;
/// Maximum preset slots.
pub const MAX_PRESETS: usize = 10;
/// Channel / preset name buffer size.
pub const CHANNEL_NAME_LEN: usize = 32;
/// Physical output pin slots (4 S/PDIF + 1 PDM on RP2350).
pub const MAX_PHYSICAL_OUTPUTS: usize = 5;

/// Master volume mute sentinel (true −∞).
pub const MASTER_VOL_MUTE_DB: f32 = -128.0;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crossover_meta_decodes_table() {
        assert_eq!(crossover_meta(32), Some((XoverFamily::LinkwitzRiley, 2, false)));
        assert_eq!(crossover_meta(39), Some((XoverFamily::LinkwitzRiley, 8, true)));
        assert_eq!(crossover_meta(40), Some((XoverFamily::Butterworth, 1, false)));
        assert_eq!(crossover_meta(55), Some((XoverFamily::Butterworth, 8, true)));
        assert_eq!(crossover_meta(56), Some((XoverFamily::Bessel, 2, false)));
        assert_eq!(crossover_meta(63), Some((XoverFamily::Bessel, 8, true)));
        assert_eq!(crossover_meta(13), None);
        assert_eq!(crossover_meta(64), None);
    }
}
