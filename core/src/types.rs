//! Shared types with C-compatible representations for FFI.

/// Filter type matching the firmware's enum values.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterType {
    Flat = 0,
    Peaking = 1,
    LowShelf = 2,
    HighShelf = 3,
    LowPass = 4,
    HighPass = 5,
}

impl FilterType {
    pub fn from_u32(v: u32) -> Self {
        match v {
            1 => Self::Peaking,
            2 => Self::LowShelf,
            3 => Self::HighShelf,
            4 => Self::LowPass,
            5 => Self::HighPass,
            _ => Self::Flat,
        }
    }
}

/// Parameters for a single biquad filter band.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct FilterParams {
    pub filter_type: FilterType,
    pub freq: f32,
    pub q: f32,
    pub gain: f32,
}

impl Default for FilterParams {
    fn default() -> Self {
        Self {
            filter_type: FilterType::Flat,
            freq: 1000.0,
            q: 0.707,
            gain: 0.0,
        }
    }
}

impl PartialEq for FilterParams {
    fn eq(&self, other: &Self) -> bool {
        self.filter_type == other.filter_type
            && self.freq == other.freq
            && self.q == other.q
            && self.gain == other.gain
    }
}

/// System status from the device (peaks, CPU, clips).
#[repr(C)]
#[derive(Debug, Clone)]
pub struct SystemStatus {
    pub peaks: [f32; 11],
    pub cpu0: u8,
    pub cpu1: u8,
    pub clip_flags: u16,
    pub num_channels: u8,
}

impl Default for SystemStatus {
    fn default() -> Self {
        Self {
            peaks: [0.0; 11],
            cpu0: 0,
            cpu1: 0,
            clip_flags: 0,
            num_channels: 7,
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

/// Platform identification from the device.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PlatformInfo {
    /// 0 = RP2040, 1 = RP2350
    pub platform_id: u8,
    /// Total channels (7 or 11)
    pub num_channels: u8,
    /// Output channels (5 or 9)
    pub num_output_channels: u8,
    /// Firmware version byte
    pub firmware_version: u8,
}

impl Default for PlatformInfo {
    fn default() -> Self {
        Self {
            platform_id: 0,
            num_channels: 7,
            num_output_channels: 5,
            firmware_version: 0,
        }
    }
}

/// Preset directory information from the device.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PresetDirectory {
    /// Bitmask of occupied preset slots (10 slots).
    pub occupied_mask: u16,
    /// 0 = specified default, 1 = last active.
    pub startup_mode: u8,
    /// Default preset slot index.
    pub default_slot: u8,
    /// Last active preset slot.
    pub last_active: u8,
    /// Whether pin config is included in presets.
    pub include_pins: bool,
}

impl Default for PresetDirectory {
    fn default() -> Self {
        Self {
            occupied_mask: 0,
            startup_mode: 0,
            default_slot: 0,
            last_active: 0,
            include_pins: false,
        }
    }
}

/// Maximum channels supported by the protocol.
pub const MAX_CHANNELS: usize = 11;
/// Maximum output channels.
pub const MAX_OUTPUTS: usize = 9;
/// Number of EQ bands per channel used by the app.
pub const BANDS_PER_CHANNEL: usize = 10;
/// Number of EQ bands per channel in firmware layout.
pub const FIRMWARE_BANDS_PER_CHANNEL: usize = 12;
/// Maximum preset slots.
pub const MAX_PRESETS: usize = 10;
/// Channel name buffer size.
pub const CHANNEL_NAME_LEN: usize = 32;
/// Physical output count for pin config.
pub const MAX_PHYSICAL_OUTPUTS: usize = 5;
/// SPDIF/I2S-capable output slots (physical outputs minus PDM).
pub const MAX_SPDIF_SLOTS: usize = 4;

// ═══════════════════════════════════════════════════════════════════
// Test Signal Generator (firmware ≥ 1.1.5)
// ═══════════════════════════════════════════════════════════════════

/// Test-signal generator configuration. Mirrors the firmware's packed
/// 36-byte wire struct field-for-field (see test_signals_spec.md §3.1);
/// serialization happens in protocol::siggen_config_to_bytes.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct SiggenConfig {
    pub signal_type: u8,
    /// Output-channel select, bit i = output i.
    pub channel_mask: u16,
    /// Polarity-inverted subset of channel_mask.
    pub invert_mask: u16,
    /// SIGGEN_FLAG_* bitmask.
    pub flags: u8,
    /// Peak level in dBFS, -120..0.
    pub level_db: f32,
    pub duration_ms: u32,
    pub repeat: u16,
    pub gap_ms: u16,
    pub p1: f32,
    pub p2: f32,
    pub p3: f32,
    pub p4: f32,
}

impl Default for SiggenConfig {
    fn default() -> Self {
        Self {
            signal_type: 0, // sine
            channel_mask: 0,
            invert_mask: 0,
            flags: 0,
            level_db: -20.0,
            duration_ms: 0,
            repeat: 0,
            gap_ms: 0,
            p1: 0.0,
            p2: 0.0,
            p3: 0.0,
            p4: 0.0,
        }
    }
}

/// Test-signal generator live status (wire struct §3.2).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct SiggenStatus {
    /// SiggenState: 0 idle, 1 fade-in, 2 run, 3 gap, 4 fade-out.
    pub state: u8,
    pub signal_type: u8,
    /// Walk: current output channel; 0xFF when not walking.
    pub active_channel: u8,
    pub elapsed_ms: u32,
    pub cycles_done: u16,
    pub stop_reason: u8,
    /// Instantaneous sweep frequency in Hz; 0 when not sweeping.
    pub current_freq: f32,
}
