//! DSP state model — holds all device parameters.
//!
//! Mirrors the @Published properties from DSPViewModel.swift.

use crate::protocol::BulkParams;
use crate::types::*;

/// Complete DSP parameter state for the connected device.
/// Owned by DspiCore; the GUI reads via FFI.
#[repr(C)]
pub struct DspState {
    // ── Global ──────────────────────────────────────────────────────
    pub preamp_db: f32,
    pub bypass: bool,

    // ── Loudness ────────────────────────────────────────────────────
    pub loudness_enabled: bool,
    pub loudness_ref_spl: f32,
    pub loudness_intensity: f32,

    // ── Crossfeed ───────────────────────────────────────────────────
    pub crossfeed_enabled: bool,
    pub crossfeed_preset: u8,
    pub crossfeed_freq: f32,
    pub crossfeed_feed: f32,
    pub crossfeed_itd: bool,

    // ── Per-channel delays ──────────────────────────────────────────
    pub channel_delays: [f32; MAX_CHANNELS],

    // ── Matrix mixer (2 inputs × 9 outputs) ────────────────────────
    pub matrix_routing: [[bool; MAX_OUTPUTS]; 2],
    pub matrix_gain: [[f32; MAX_OUTPUTS]; 2],
    pub matrix_invert: [[bool; MAX_OUTPUTS]; 2],

    // ── Output settings ─────────────────────────────────────────────
    pub output_enabled: [bool; MAX_OUTPUTS],
    pub output_muted: [bool; MAX_OUTPUTS],
    pub output_gain_db: [f32; MAX_OUTPUTS],
    pub output_delay_ms: [f32; MAX_OUTPUTS],

    // ── Pin configuration ───────────────────────────────────────────
    pub output_pins: [u8; MAX_PHYSICAL_OUTPUTS],

    // ── EQ bands ────────────────────────────────────────────────────
    pub filters: [[FilterParams; BANDS_PER_CHANNEL]; MAX_CHANNELS],

    // ── Channel names ───────────────────────────────────────────────
    pub channel_names: [[u8; CHANNEL_NAME_LEN]; MAX_CHANNELS],

    // ── Platform info ───────────────────────────────────────────────
    pub platform_id: u8,
    pub num_channels: u8,
    pub num_output_channels: u8,

    // ── Core 1 mode ─────────────────────────────────────────────────
    pub core1_mode: u8,

    // ── Preset state ────────────────────────────────────────────────
    pub preset_occupied: u16,
    pub preset_names: [[u8; CHANNEL_NAME_LEN]; MAX_PRESETS],
    pub active_preset_slot: u8,
    pub preset_startup_mode: u8,
    pub preset_default_slot: u8,
    pub preset_include_pins: bool,
}

impl Default for DspState {
    fn default() -> Self {
        Self {
            preamp_db: 0.0,
            bypass: false,
            loudness_enabled: false,
            loudness_ref_spl: 83.0,
            loudness_intensity: 100.0,
            crossfeed_enabled: false,
            crossfeed_preset: 0,
            crossfeed_freq: 700.0,
            crossfeed_feed: 4.5,
            crossfeed_itd: true,
            channel_delays: [0.0; MAX_CHANNELS],
            matrix_routing: [[false; MAX_OUTPUTS]; 2],
            matrix_gain: [[0.0; MAX_OUTPUTS]; 2],
            matrix_invert: [[false; MAX_OUTPUTS]; 2],
            output_enabled: [false; MAX_OUTPUTS],
            output_muted: [false; MAX_OUTPUTS],
            output_gain_db: [0.0; MAX_OUTPUTS],
            output_delay_ms: [0.0; MAX_OUTPUTS],
            output_pins: [6, 7, 8, 9, 10],
            filters: [[FilterParams::default(); BANDS_PER_CHANNEL]; MAX_CHANNELS],
            channel_names: [[0u8; CHANNEL_NAME_LEN]; MAX_CHANNELS],
            platform_id: 0,
            num_channels: 7,
            num_output_channels: 5,
            core1_mode: 0,
            preset_occupied: 0,
            preset_names: [[0u8; CHANNEL_NAME_LEN]; MAX_PRESETS],
            active_preset_slot: 0,
            preset_startup_mode: 0,
            preset_default_slot: 0,
            preset_include_pins: false,
        }
    }
}

impl DspState {
    /// Apply bulk params to state (after fetchAllParams).
    pub fn apply_bulk_params(&mut self, bp: &BulkParams) {
        self.platform_id = bp.platform_id;
        self.num_channels = bp.num_channels;
        self.num_output_channels = bp.num_output_channels;

        self.preamp_db = bp.preamp_db;
        self.bypass = bp.bypass;
        self.loudness_enabled = bp.loudness_enabled;
        self.loudness_ref_spl = bp.loudness_ref_spl;
        self.loudness_intensity = bp.loudness_intensity;

        self.crossfeed_enabled = bp.crossfeed_enabled;
        self.crossfeed_preset = bp.crossfeed_preset;
        self.crossfeed_itd = bp.crossfeed_itd;
        self.crossfeed_freq = bp.crossfeed_freq;
        self.crossfeed_feed = bp.crossfeed_feed;

        self.channel_delays = bp.delays;

        self.matrix_routing = bp.matrix_routing;
        self.matrix_gain = bp.matrix_gain;
        self.matrix_invert = bp.matrix_invert;

        self.output_enabled = bp.output_enabled;
        self.output_muted = bp.output_muted;
        self.output_gain_db = bp.output_gain_db;
        self.output_delay_ms = bp.output_delay_ms;

        self.output_pins = bp.output_pins;
        self.filters = bp.filters;
        self.channel_names = bp.channel_names;
    }

    /// Platform name string.
    pub fn platform_name(&self) -> &str {
        if self.platform_id == 1 {
            "RP2350"
        } else {
            "RP2040"
        }
    }

    /// PDM output index for this platform.
    pub fn pdm_output_index(&self) -> u8 {
        if self.platform_id == 1 { 8 } else { 4 }
    }
}
