//! DSP state model: every device parameter the core tracks.
//!
//! Channel-indexed arrays use wire channel indices (see `types.rs`);
//! output-indexed arrays use output indices 0..num_output_channels-1.

use crate::protocol::{
    BULK_PARAMS_SIZE, SUBHARM_DEFAULTS, SUBHARM_PARAM_COUNT, TUBE_DEFAULTS, TUBE_PARAM_COUNT,
    UPMIX_DEFAULTS, UPMIX_PARAM_COUNT,
};
use crate::types::*;

/// Firmware compatibility of the connected device, as judged at connect time.
pub const COMPAT_UNKNOWN: u8 = 0;
/// Wire format and firmware match this core.
pub const COMPAT_OK: u8 = 1;
/// Firmware is too old (pre-V32 wire format, or the old USB vendor ID).
pub const COMPAT_FIRMWARE_TOO_OLD: u8 = 2;
/// Firmware is newer than this core understands.
pub const COMPAT_FIRMWARE_TOO_NEW: u8 = 3;

/// Complete DSP parameter state for the connected device.
/// Owned by DspiCore; the GUI reads it through `dspi_get_state`.
#[repr(C)]
pub struct DspState {
    // ── Device / firmware ───────────────────────────────────────────
    pub platform_id: u8,
    pub num_channels: u8,
    pub num_input_channels: u8,
    pub num_output_channels: u8,
    pub format_version: u8,
    pub fw_major: u8,
    pub fw_minor: u8,
    pub fw_patch: u8,
    pub fw_beta: u8,
    /// `COMPAT_*`.
    pub compat: u8,

    // ── Global ──────────────────────────────────────────────────────
    /// Legacy global preamp (mirrors input 0's preamp on current firmware).
    pub preamp_db: f32,
    pub bypass: bool,

    // ── Per-input preamp ────────────────────────────────────────────
    pub input_preamp_db: [f32; MAX_INPUTS],

    // ── Volume ──────────────────────────────────────────────────────
    /// Device master volume: −128 = mute sentinel, −127..0 dB.
    pub master_volume_db: f32,
    /// 0 = independent of presets, 1 = saved with presets.
    pub master_volume_mode: u8,
    pub user_volume_db: f32,
    pub user_mute: bool,

    // ── Loudness ────────────────────────────────────────────────────
    pub loudness_enabled: bool,
    pub loudness_ref_spl: f32,
    pub loudness_intensity: f32,
    /// Bit k: loudness processes output k.
    pub loudness_output_mask: u16,

    // ── Crossfeed ───────────────────────────────────────────────────
    pub crossfeed_enabled: bool,
    pub crossfeed_preset: u8,
    pub crossfeed_freq: f32,
    pub crossfeed_feed: f32,
    pub crossfeed_itd: bool,
    /// Bit p: crossfeed runs on output pair p.
    pub crossfeed_output_pair_mask: u8,

    // ── Per-channel delays (wire channel index) ─────────────────────
    pub channel_delays: [f32; MAX_CHANNELS],

    // ── Matrix mixer [input][output] ────────────────────────────────
    pub matrix_routing: [[bool; MAX_OUTPUTS]; MAX_INPUTS],
    pub matrix_gain: [[f32; MAX_OUTPUTS]; MAX_INPUTS],
    pub matrix_invert: [[bool; MAX_OUTPUTS]; MAX_INPUTS],

    // ── Outputs ─────────────────────────────────────────────────────
    pub output_enabled: [bool; MAX_OUTPUTS],
    pub output_muted: [bool; MAX_OUTPUTS],
    pub output_gain_db: [f32; MAX_OUTPUTS],
    pub output_delay_ms: [f32; MAX_OUTPUTS],

    // ── Output limiter (per output) ─────────────────────────────────
    pub limiter_enabled: [bool; MAX_OUTPUTS],
    /// 0 = unlinked, 1..4 = link group.
    pub limiter_link_group: [u8; MAX_OUTPUTS],
    pub limiter_threshold_db: [f32; MAX_OUTPUTS],
    pub limiter_release_ms: [f32; MAX_OUTPUTS],

    // ── Pin configuration ───────────────────────────────────────────
    pub num_pin_outputs: u8,
    pub output_pins: [u8; MAX_PHYSICAL_OUTPUTS],
    /// 0 = output config stored independently, 1 = saved with presets.
    pub output_config_mode: u8,

    // ── EQ (wire channel index) ─────────────────────────────────────
    pub filters: [[FilterParams; BANDS_PER_CHANNEL]; MAX_CHANNELS],
    /// Crossover bands; input rows are unused (crossovers are output-only).
    pub xover: [[FilterParams; MAX_XOVER_BANDS]; MAX_CHANNELS],

    // ── Channel names (wire channel index) ──────────────────────────
    pub channel_names: [[u8; CHANNEL_NAME_LEN]; MAX_CHANNELS],

    // ── Volume leveller ─────────────────────────────────────────────
    pub leveller_enabled: bool,
    /// 0 = slow, 1 = medium, 2 = fast.
    pub leveller_speed: u8,
    pub leveller_lookahead: bool,
    pub leveller_amount: f32,
    pub leveller_max_gain_db: f32,
    pub leveller_gate_db: f32,
    /// Bit k: input k feeds the detector.
    pub leveller_detector_mask: u8,
    /// Bit k: gain applied to input k.
    pub leveller_apply_mask: u8,

    // ── Input / misc ────────────────────────────────────────────────
    /// 0 = USB, 1 = S/PDIF, 2 = I2S, ...
    pub input_source: u8,
    pub lg_sound_sync_enabled: bool,
    /// Bit k: S/PDIF input k+1 is enabled (input 1 is always on).
    pub spdif_inputs_enabled: u8,
    pub adat_input_enabled: bool,
    /// RX pin of each S/PDIF input (1-4).
    pub spdif_rx_pins: [u8; 4],
    /// Data pin of each I2S input pair; active pairs = channels / 2.
    pub i2s_rx_pins: [u8; 4],
    pub i2s_input_channels: u8,
    /// Master-mode rate shared by I2S and ADAT: 0 = 44.1k, 1 = 48k, 2 = 96k.
    pub i2s_input_rate: u8,
    /// 0 = master (DSPi drives BCK/LRCLK), 1 = slave.
    pub i2s_clock_mode: u8,
    /// ADAT input data pin, 0xFF = not set (it ships unset).
    pub adat_input_pin: u8,
    pub adat_input_clock_mode: u8,

    // ── Psychoacoustic bass ─────────────────────────────────────────
    pub psybass_enabled: bool,
    /// Bit k: psybass processes output k.
    pub psybass_output_mask: u16,
    pub psybass_cutoff_hz: f32,
    pub psybass_harmonics_db: f32,
    pub psybass_drive_db: f32,
    pub psybass_character_pct: f32,
    pub psybass_original_db: f32,

    // ── Stereo upmixer (RP2350 only) ────────────────────────────────
    /// By `UPMIX_PARAM_*` id; enable and modes as whole numbers.
    pub upmix: [f32; UPMIX_PARAM_COUNT],

    // ── Subharmonic synthesizer ─────────────────────────────────────
    /// By `SUBHARM_PARAM_*` id; flags, mask and mode as whole numbers.
    pub subharm: [f32; SUBHARM_PARAM_COUNT],
    /// Program muted on the masked outputs. Runtime only: not in the bulk
    /// image, never saved.
    pub subharm_solo: bool,

    // ── Tube modeller ───────────────────────────────────────────────
    /// By `TUBE_PARAM_*` index; flags, mask and enums as whole numbers.
    pub tube: [f32; TUBE_PARAM_COUNT],

    // ── Output types and clocks (i2s_config / adat_config sections) ─
    /// Per S/PDIF-or-I2S slot: 0 = S/PDIF, 1 = I2S.
    pub output_types: [u8; 4],
    /// I2S bit clock (LRCLK is the next GPIO); the slave pair in split mode.
    pub i2s_bck_pin: u8,
    pub i2s_bck_pin_slave: u8,
    /// 0 = master and slave share the clock pins, 1 = separate pins.
    pub i2s_clock_pin_mode: u8,
    pub mck_enabled: bool,
    pub mck_pin: u8,
    /// 0 = 128 x fs, 1 = 256 x fs.
    pub mck_multiplier: u8,
    /// ADAT optical output (RP2350).
    pub adat_out_enabled: bool,
    pub adat_out_pin: u8,

    // ── DAC hardware mute (device-level; in the bulk image) ────────
    pub dac_mute_supported: bool,
    pub dac_mute_enabled: bool,
    pub dac_mute_active_low: bool,
    /// GPIO, 0xFF = none.
    pub dac_mute_pin: u8,
    pub dac_mute_hold_ms: u16,
    pub dac_mute_release_ms: u16,

    // ── UART / I2C control interfaces (flash directory, not bulk) ──
    pub ctrl_iface_supported: bool,
    pub uart: UartConfig,
    pub i2c: I2cConfig,
    pub ctrl_status: CtrlIfaceStatus,

    // ── Core 1 mode ─────────────────────────────────────────────────
    pub core1_mode: u8,

    // ── Presets ─────────────────────────────────────────────────────
    pub preset_occupied: u16,
    pub preset_names: [[u8; CHANNEL_NAME_LEN]; MAX_PRESETS],
    pub active_preset_slot: u8,
    pub preset_startup_mode: u8,
    pub preset_default_slot: u8,

    // ── Raw bulk image ──────────────────────────────────────────────
    /// True once a bulk image has been read from the device.
    pub bulk_valid: bool,
    /// The last bulk image read, kept so unmodeled sections round-trip.
    pub bulk_raw: [u8; BULK_PARAMS_SIZE],
}

impl Default for DspState {
    fn default() -> Self {
        Self {
            platform_id: 0,
            num_channels: 7,
            num_input_channels: 2,
            num_output_channels: 5,
            format_version: 0,
            fw_major: 0,
            fw_minor: 0,
            fw_patch: 0,
            fw_beta: 0,
            compat: COMPAT_UNKNOWN,
            preamp_db: 0.0,
            bypass: false,
            input_preamp_db: [0.0; MAX_INPUTS],
            master_volume_db: -20.0,
            master_volume_mode: 0,
            user_volume_db: 0.0,
            user_mute: false,
            loudness_enabled: false,
            loudness_ref_spl: 83.0,
            loudness_intensity: 100.0,
            loudness_output_mask: 0,
            crossfeed_enabled: false,
            crossfeed_preset: 0,
            crossfeed_freq: 700.0,
            crossfeed_feed: 4.5,
            crossfeed_itd: true,
            crossfeed_output_pair_mask: 0,
            channel_delays: [0.0; MAX_CHANNELS],
            matrix_routing: [[false; MAX_OUTPUTS]; MAX_INPUTS],
            matrix_gain: [[0.0; MAX_OUTPUTS]; MAX_INPUTS],
            matrix_invert: [[false; MAX_OUTPUTS]; MAX_INPUTS],
            output_enabled: [false; MAX_OUTPUTS],
            output_muted: [false; MAX_OUTPUTS],
            output_gain_db: [0.0; MAX_OUTPUTS],
            output_delay_ms: [0.0; MAX_OUTPUTS],
            limiter_enabled: [false; MAX_OUTPUTS],
            limiter_link_group: [0; MAX_OUTPUTS],
            limiter_threshold_db: [0.0; MAX_OUTPUTS],
            limiter_release_ms: [100.0; MAX_OUTPUTS],
            num_pin_outputs: 3,
            output_pins: [6, 7, 10, 0, 0],
            output_config_mode: 1,
            filters: [[FilterParams::default(); BANDS_PER_CHANNEL]; MAX_CHANNELS],
            xover: [[FilterParams::default(); MAX_XOVER_BANDS]; MAX_CHANNELS],
            channel_names: [[0u8; CHANNEL_NAME_LEN]; MAX_CHANNELS],
            leveller_enabled: false,
            leveller_speed: 1,
            leveller_lookahead: false,
            leveller_amount: 50.0,
            leveller_max_gain_db: 12.0,
            leveller_gate_db: -60.0,
            leveller_detector_mask: 0x03,
            leveller_apply_mask: 0x03,
            input_source: 0,
            lg_sound_sync_enabled: false,
            spdif_inputs_enabled: 0x01,
            adat_input_enabled: false,
            spdif_rx_pins: [5, 20, 21, 22],
            i2s_rx_pins: [1, 2, 3, 4],
            i2s_input_channels: 2,
            i2s_input_rate: 1,
            i2s_clock_mode: 0,
            adat_input_pin: 0xFF,
            adat_input_clock_mode: 0,
            psybass_enabled: false,
            psybass_output_mask: 0,
            psybass_cutoff_hz: 80.0,
            psybass_harmonics_db: 0.0,
            psybass_drive_db: 6.0,
            psybass_character_pct: 50.0,
            psybass_original_db: 0.0,
            upmix: UPMIX_DEFAULTS,
            subharm: SUBHARM_DEFAULTS,
            subharm_solo: false,
            tube: TUBE_DEFAULTS,
            output_types: [0; 4],
            i2s_bck_pin: 14,
            i2s_bck_pin_slave: 26,
            i2s_clock_pin_mode: 0,
            mck_enabled: false,
            mck_pin: 13,
            mck_multiplier: 0,
            adat_out_enabled: false,
            adat_out_pin: 12,
            dac_mute_supported: false,
            dac_mute_enabled: false,
            dac_mute_active_low: true,
            dac_mute_pin: 11,
            dac_mute_hold_ms: 5,
            dac_mute_release_ms: 0,
            ctrl_iface_supported: false,
            uart: UartConfig::default(),
            i2c: I2cConfig::default(),
            ctrl_status: CtrlIfaceStatus::default(),
            core1_mode: 0,
            preset_occupied: 0,
            preset_names: [[0u8; CHANNEL_NAME_LEN]; MAX_PRESETS],
            active_preset_slot: 0,
            preset_startup_mode: 0,
            preset_default_slot: 0,
            bulk_valid: false,
            bulk_raw: [0u8; BULK_PARAMS_SIZE],
        }
    }
}

impl DspState {
    /// Platform name string.
    pub fn platform_name(&self) -> &str {
        if self.platform_id == 1 {
            "RP2350"
        } else {
            "RP2040"
        }
    }

    /// Wire channel index of output `output` (0-based).
    pub fn output_channel(&self, output: u8) -> u8 {
        self.num_input_channels + output
    }

    /// Output index of wire channel `ch`, if it is an output.
    pub fn output_of_channel(&self, ch: u8) -> Option<u8> {
        if ch >= self.num_input_channels && ch < self.num_channels {
            Some(ch - self.num_input_channels)
        } else {
            None
        }
    }

    /// PDM output index (the last output).
    pub fn pdm_output_index(&self) -> u8 {
        self.num_output_channels.saturating_sub(1)
    }
}
