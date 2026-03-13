//! USB request constants and bulk parameter parsing.
//!
//! All constants mirror Constants.swift from the macOS app.
//! All multi-byte fields are little-endian (ARM Cortex-M).

use crate::types::*;

// ── USB Device IDs ──────────────────────────────────────────────────

pub const VENDOR_ID: u16 = 0x2e8a;
pub const PRODUCT_ID: u16 = 0xfeaa;

// ── bmRequestType ───────────────────────────────────────────────────

/// Host→Device | Vendor | Interface
pub const REQ_TYPE_OUT: u8 = 0x41;
/// Device→Host | Vendor | Interface
pub const REQ_TYPE_IN: u8 = 0xC1;

// ── EQ / Preamp / Bypass / Delay ────────────────────────────────────

pub const REQ_SET_EQ_PARAM: u8 = 0x42;
pub const REQ_GET_EQ_PARAM: u8 = 0x43;
pub const REQ_SET_PREAMP: u8 = 0x44;
pub const REQ_GET_PREAMP: u8 = 0x45;
pub const REQ_SET_BYPASS: u8 = 0x46;
pub const REQ_GET_BYPASS: u8 = 0x47;
pub const REQ_SET_DELAY: u8 = 0x48;
pub const REQ_GET_DELAY: u8 = 0x49;

// ── Status ──────────────────────────────────────────────────────────

pub const REQ_GET_STATUS: u8 = 0x50;

// ── Flash Storage ───────────────────────────────────────────────────

pub const REQ_SAVE_PARAMS: u8 = 0x51;
pub const REQ_LOAD_PARAMS: u8 = 0x52;
pub const REQ_FACTORY_RESET: u8 = 0x53;

// ── Channel Gain/Mute ───────────────────────────────────────────────

pub const REQ_SET_CHANNEL_GAIN: u8 = 0x54;
pub const REQ_GET_CHANNEL_GAIN: u8 = 0x55;
pub const REQ_SET_CHANNEL_MUTE: u8 = 0x56;
pub const REQ_GET_CHANNEL_MUTE: u8 = 0x57;

// ── Loudness ────────────────────────────────────────────────────────

pub const REQ_SET_LOUDNESS: u8 = 0x58;
pub const REQ_GET_LOUDNESS: u8 = 0x59;
pub const REQ_SET_LOUDNESS_REF: u8 = 0x5A;
pub const REQ_GET_LOUDNESS_REF: u8 = 0x5B;
pub const REQ_SET_LOUDNESS_INTENSITY: u8 = 0x5C;
pub const REQ_GET_LOUDNESS_INTENSITY: u8 = 0x5D;

// ── Crossfeed ───────────────────────────────────────────────────────

pub const REQ_SET_CROSSFEED: u8 = 0x5E;
pub const REQ_GET_CROSSFEED: u8 = 0x5F;
pub const REQ_SET_CROSSFEED_PRESET: u8 = 0x60;
pub const REQ_GET_CROSSFEED_PRESET: u8 = 0x61;
pub const REQ_SET_CROSSFEED_FREQ: u8 = 0x62;
pub const REQ_GET_CROSSFEED_FREQ: u8 = 0x63;
pub const REQ_SET_CROSSFEED_FEED: u8 = 0x64;
pub const REQ_GET_CROSSFEED_FEED: u8 = 0x65;
pub const REQ_SET_CROSSFEED_ITD: u8 = 0x66;
pub const REQ_GET_CROSSFEED_ITD: u8 = 0x67;

// ── Matrix Mixer ────────────────────────────────────────────────────

pub const REQ_SET_MATRIX_ROUTE: u8 = 0x70;
pub const REQ_GET_MATRIX_ROUTE: u8 = 0x71;
pub const REQ_SET_OUTPUT_ENABLE: u8 = 0x72;
pub const REQ_GET_OUTPUT_ENABLE: u8 = 0x73;
pub const REQ_SET_OUTPUT_GAIN: u8 = 0x74;
pub const REQ_GET_OUTPUT_GAIN: u8 = 0x75;
pub const REQ_SET_OUTPUT_MUTE: u8 = 0x76;
pub const REQ_GET_OUTPUT_MUTE: u8 = 0x77;
pub const REQ_SET_OUTPUT_DELAY: u8 = 0x78;
pub const REQ_GET_OUTPUT_DELAY: u8 = 0x79;

// ── Core 1 Mode ─────────────────────────────────────────────────────

pub const REQ_GET_CORE1_MODE: u8 = 0x7A;
pub const REQ_GET_CORE1_CONFLICT: u8 = 0x7B;

// ── Pin Configuration ───────────────────────────────────────────────

pub const REQ_SET_OUTPUT_PIN: u8 = 0x7C;
pub const REQ_GET_OUTPUT_PIN: u8 = 0x7D;

// ── Device Identification ───────────────────────────────────────────

pub const REQ_GET_SERIAL: u8 = 0x7E;
pub const REQ_GET_PLATFORM: u8 = 0x7F;

// ── Clip Detection ──────────────────────────────────────────────────

pub const REQ_CLEAR_CLIPS: u8 = 0x83;

// ── Pin Config Status Codes ─────────────────────────────────────────

pub const PIN_CONFIG_SUCCESS: u8 = 0x00;
pub const PIN_CONFIG_INVALID_PIN: u8 = 0x01;
pub const PIN_CONFIG_PIN_IN_USE: u8 = 0x02;
pub const PIN_CONFIG_INVALID_OUTPUT: u8 = 0x03;
pub const PIN_CONFIG_OUTPUT_ACTIVE: u8 = 0x04;

// ── Preset Commands ─────────────────────────────────────────────────

pub const REQ_PRESET_SAVE: u8 = 0x90;
pub const REQ_PRESET_LOAD: u8 = 0x91;
pub const REQ_PRESET_DELETE: u8 = 0x92;
pub const REQ_PRESET_GET_NAME: u8 = 0x93;
pub const REQ_PRESET_SET_NAME: u8 = 0x94;
pub const REQ_PRESET_GET_DIR: u8 = 0x95;
pub const REQ_PRESET_SET_STARTUP: u8 = 0x96;
pub const REQ_PRESET_GET_STARTUP: u8 = 0x97;
pub const REQ_PRESET_SET_INCLUDE_PINS: u8 = 0x98;
pub const REQ_PRESET_GET_INCLUDE_PINS: u8 = 0x99;
pub const REQ_PRESET_GET_ACTIVE: u8 = 0x9A;

// ── Channel Names ───────────────────────────────────────────────────

pub const REQ_SET_CHANNEL_NAME: u8 = 0x9B;
pub const REQ_GET_CHANNEL_NAME: u8 = 0x9C;

// ── Bulk Parameter Transfer ─────────────────────────────────────────

pub const REQ_GET_ALL_PARAMS: u8 = 0xA0;
pub const REQ_SET_ALL_PARAMS: u8 = 0xA1;
pub const BULK_PARAMS_SIZE: u16 = 2832;

// ── Preset Status Codes ─────────────────────────────────────────────

pub const PRESET_OK: u8 = 0x00;
pub const PRESET_ERR_INVALID_SLOT: u8 = 0x01;
pub const PRESET_ERR_SLOT_EMPTY: u8 = 0x02;
pub const PRESET_ERR_CRC: u8 = 0x03;
pub const PRESET_ERR_FLASH_WRITE: u8 = 0x04;

// ── Flash Status Codes ──────────────────────────────────────────────

pub const FLASH_OK: u8 = 0;
pub const FLASH_ERR_WRITE: u8 = 1;
pub const FLASH_ERR_NO_DATA: u8 = 2;
pub const FLASH_ERR_CRC: u8 = 3;

// ── wIndex conventions ──────────────────────────────────────────────

/// wIndex for master/global commands (EQ, preamp, bypass, delay, status, loudness, crossfeed, core1).
pub const WINDEX_GLOBAL: u16 = 0;
/// wIndex for matrix/output/pin/preset/channel-name commands.
pub const WINDEX_OUTPUT: u16 = 2;

// ═══════════════════════════════════════════════════════════════════
// Bulk Parameter Parsing
// ═══════════════════════════════════════════════════════════════════

/// Parsed bulk parameters from the 2832-byte USB response.
/// Mirrors the WireBulkParams structure from firmware.
#[derive(Debug, Clone)]
pub struct BulkParams {
    // Header (offset 0)
    pub platform_id: u8,
    pub num_channels: u8,
    pub num_output_channels: u8,

    // Global (offset 16)
    pub preamp_db: f32,
    pub bypass: bool,
    pub loudness_enabled: bool,
    pub loudness_ref_spl: f32,
    pub loudness_intensity: f32,

    // Crossfeed (offset 32)
    pub crossfeed_enabled: bool,
    pub crossfeed_preset: u8,
    pub crossfeed_itd: bool,
    pub crossfeed_freq: f32,
    pub crossfeed_feed: f32,

    // Delays (offset 64)
    pub delays: [f32; MAX_CHANNELS],

    // Matrix crosspoints (offset 108)
    pub matrix_routing: [[bool; MAX_OUTPUTS]; 2],
    pub matrix_gain: [[f32; MAX_OUTPUTS]; 2],
    pub matrix_invert: [[bool; MAX_OUTPUTS]; 2],

    // Matrix outputs (offset 252)
    pub output_enabled: [bool; MAX_OUTPUTS],
    pub output_muted: [bool; MAX_OUTPUTS],
    pub output_gain_db: [f32; MAX_OUTPUTS],
    pub output_delay_ms: [f32; MAX_OUTPUTS],

    // Pin config (offset 360)
    pub output_pins: [u8; MAX_PHYSICAL_OUTPUTS],

    // EQ bands (offset 368)
    pub filters: [[FilterParams; BANDS_PER_CHANNEL]; MAX_CHANNELS],

    // Channel names (offset 2480)
    pub channel_names: [[u8; CHANNEL_NAME_LEN]; MAX_CHANNELS],
}

impl Default for BulkParams {
    fn default() -> Self {
        Self {
            platform_id: 0,
            num_channels: 7,
            num_output_channels: 5,
            preamp_db: 0.0,
            bypass: false,
            loudness_enabled: false,
            loudness_ref_spl: 83.0,
            loudness_intensity: 100.0,
            crossfeed_enabled: false,
            crossfeed_preset: 0,
            crossfeed_itd: true,
            crossfeed_freq: 700.0,
            crossfeed_feed: 4.5,
            delays: [0.0; MAX_CHANNELS],
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
        }
    }
}

/// Read a little-endian f32 from a byte slice at the given offset.
fn read_f32_le(data: &[u8], offset: usize) -> f32 {
    let bytes: [u8; 4] = [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]];
    f32::from_le_bytes(bytes)
}

/// Read a little-endian u16 from a byte slice at the given offset.
fn read_u16_le(data: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes([data[offset], data[offset + 1]])
}

/// Read a little-endian u32 from a byte slice at the given offset.
fn read_u32_le(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([data[offset], data[offset + 1], data[offset + 2], data[offset + 3]])
}

/// Write a little-endian f32 into a byte slice at the given offset.
fn write_f32_le(data: &mut [u8], offset: usize, val: f32) {
    let bytes = val.to_le_bytes();
    data[offset..offset + 4].copy_from_slice(&bytes);
}

/// Write a little-endian u32 into a byte slice at the given offset.
fn write_u32_le(data: &mut [u8], offset: usize, val: u32) {
    let bytes = val.to_le_bytes();
    data[offset..offset + 4].copy_from_slice(&bytes);
}

/// Write a little-endian u16 into a byte slice at the given offset.
#[allow(dead_code)]
fn write_u16_le(data: &mut [u8], offset: usize, val: u16) {
    let bytes = val.to_le_bytes();
    data[offset..offset + 2].copy_from_slice(&bytes);
}

impl BulkParams {
    /// Parse from raw 2832-byte USB response.
    pub fn from_bytes(data: &[u8]) -> Result<Self, &'static str> {
        if data.len() < BULK_PARAMS_SIZE as usize {
            return Err("Bulk params data too short");
        }

        let mut params = BulkParams::default();

        // Header (offset 0, 16 bytes)
        params.platform_id = data[1];
        params.num_channels = data[2];
        params.num_output_channels = data[3];
        let num_ch = params.num_channels as usize;
        let num_out = params.num_output_channels as usize;

        // Global (offset 16, 16 bytes)
        params.preamp_db = read_f32_le(data, 16);
        params.bypass = data[20] != 0;
        params.loudness_enabled = data[21] != 0;
        params.loudness_ref_spl = read_f32_le(data, 24);
        params.loudness_intensity = read_f32_le(data, 28);

        // Crossfeed (offset 32, 16 bytes)
        params.crossfeed_enabled = data[32] != 0;
        params.crossfeed_preset = data[33];
        params.crossfeed_itd = data[34] != 0;
        params.crossfeed_freq = read_f32_le(data, 36);
        params.crossfeed_feed = read_f32_le(data, 40);

        // Delays (offset 64, 44 bytes)
        for i in 0..num_ch.min(MAX_CHANNELS) {
            params.delays[i] = read_f32_le(data, 64 + i * 4);
        }

        // Matrix crosspoints (offset 108, 2×9×8 = 144 bytes)
        for input in 0..2 {
            for output in 0..num_out.min(MAX_OUTPUTS) {
                let base = 108 + (input * 9 + output) * 8;
                params.matrix_routing[input][output] = data[base] != 0;
                params.matrix_invert[input][output] = data[base + 1] != 0;
                params.matrix_gain[input][output] = read_f32_le(data, base + 4);
            }
        }

        // Matrix outputs (offset 252, 9×12 = 108 bytes)
        for output in 0..num_out.min(MAX_OUTPUTS) {
            let base = 252 + output * 12;
            params.output_enabled[output] = data[base] != 0;
            params.output_muted[output] = data[base + 1] != 0;
            params.output_gain_db[output] = read_f32_le(data, base + 4);
            params.output_delay_ms[output] = read_f32_le(data, base + 8);
        }

        // Pin config (offset 360, 8 bytes)
        let num_pins = (data[360] as usize).min(MAX_PHYSICAL_OUTPUTS);
        for i in 0..num_pins {
            params.output_pins[i] = data[361 + i];
        }

        // EQ bands (offset 368, 11ch × 12bands × 16bytes = 2112 bytes)
        for ch in 0..num_ch.min(MAX_CHANNELS) {
            for band in 0..BANDS_PER_CHANNEL {
                let base = 368 + (ch * FIRMWARE_BANDS_PER_CHANNEL + band) * 16;
                let type_raw = read_u32_le(data, base);
                params.filters[ch][band] = FilterParams {
                    filter_type: FilterType::from_u32(type_raw),
                    freq: read_f32_le(data, base + 4),
                    q: read_f32_le(data, base + 8),
                    gain: read_f32_le(data, base + 12),
                };
            }
        }

        // Channel names (offset 2480, 11ch × 32bytes = 352 bytes)
        for ch in 0..num_ch.min(MAX_CHANNELS) {
            let base = 2480 + ch * CHANNEL_NAME_LEN;
            let end = base + CHANNEL_NAME_LEN;
            params.channel_names[ch][..CHANNEL_NAME_LEN].copy_from_slice(&data[base..end]);
        }

        Ok(params)
    }

    /// Serialize to 2832-byte buffer for SET_ALL_PARAMS.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut data = vec![0u8; BULK_PARAMS_SIZE as usize];
        let num_ch = self.num_channels as usize;
        let num_out = self.num_output_channels as usize;

        // Header
        data[1] = self.platform_id;
        data[2] = self.num_channels;
        data[3] = self.num_output_channels;

        // Global
        write_f32_le(&mut data, 16, self.preamp_db);
        data[20] = self.bypass as u8;
        data[21] = self.loudness_enabled as u8;
        write_f32_le(&mut data, 24, self.loudness_ref_spl);
        write_f32_le(&mut data, 28, self.loudness_intensity);

        // Crossfeed
        data[32] = self.crossfeed_enabled as u8;
        data[33] = self.crossfeed_preset;
        data[34] = self.crossfeed_itd as u8;
        write_f32_le(&mut data, 36, self.crossfeed_freq);
        write_f32_le(&mut data, 40, self.crossfeed_feed);

        // Delays
        for i in 0..num_ch.min(MAX_CHANNELS) {
            write_f32_le(&mut data, 64 + i * 4, self.delays[i]);
        }

        // Matrix crosspoints
        for input in 0..2 {
            for output in 0..num_out.min(MAX_OUTPUTS) {
                let base = 108 + (input * 9 + output) * 8;
                data[base] = self.matrix_routing[input][output] as u8;
                data[base + 1] = self.matrix_invert[input][output] as u8;
                write_f32_le(&mut data, base + 4, self.matrix_gain[input][output]);
            }
        }

        // Matrix outputs
        for output in 0..num_out.min(MAX_OUTPUTS) {
            let base = 252 + output * 12;
            data[base] = self.output_enabled[output] as u8;
            data[base + 1] = self.output_muted[output] as u8;
            write_f32_le(&mut data, base + 4, self.output_gain_db[output]);
            write_f32_le(&mut data, base + 8, self.output_delay_ms[output]);
        }

        // Pin config
        data[360] = MAX_PHYSICAL_OUTPUTS as u8;
        for i in 0..MAX_PHYSICAL_OUTPUTS {
            data[361 + i] = self.output_pins[i];
        }

        // EQ bands
        for ch in 0..num_ch.min(MAX_CHANNELS) {
            for band in 0..BANDS_PER_CHANNEL {
                let base = 368 + (ch * FIRMWARE_BANDS_PER_CHANNEL + band) * 16;
                write_u32_le(&mut data, base, self.filters[ch][band].filter_type as u32);
                write_f32_le(&mut data, base + 4, self.filters[ch][band].freq);
                write_f32_le(&mut data, base + 8, self.filters[ch][band].q);
                write_f32_le(&mut data, base + 12, self.filters[ch][band].gain);
            }
        }

        // Channel names
        for ch in 0..num_ch.min(MAX_CHANNELS) {
            let base = 2480 + ch * CHANNEL_NAME_LEN;
            data[base..base + CHANNEL_NAME_LEN].copy_from_slice(&self.channel_names[ch]);
        }

        data
    }
}

/// Encode EQ parameter wValue: (ch << 8) | (band << 4) | param
pub fn eq_param_wvalue(ch: u8, band: u8, param: u8) -> u16 {
    ((ch as u16) << 8) | ((band as u16) << 4) | (param as u16)
}

/// Encode matrix route wValue: (input << 8) | output
pub fn matrix_route_wvalue(input: u8, output: u8) -> u16 {
    ((input as u16) << 8) | (output as u16)
}

/// Encode pin config SET wValue: (new_pin << 8) | output_index
pub fn pin_config_wvalue(pin: u8, output: u8) -> u16 {
    ((pin as u16) << 8) | (output as u16)
}

/// Build a 16-byte set-filter packet (matches Commands.swift setFilter encoding).
pub fn build_set_filter_packet(ch: u8, band: u8, params: &FilterParams) -> Vec<u8> {
    let mut packet = vec![0u8; 16];
    packet[0] = ch;
    packet[1] = band;
    packet[2] = params.filter_type as u8;
    packet[3] = 0; // reserved
    write_f32_le(&mut packet, 4, params.freq);
    write_f32_le(&mut packet, 8, params.q);
    write_f32_le(&mut packet, 12, params.gain);
    packet
}

/// Build a 9-byte matrix route packet.
pub fn build_matrix_route_packet(input: u8, output: u8, enabled: bool, gain: f32, invert: bool) -> Vec<u8> {
    let mut packet = vec![0u8; 9];
    packet[0] = input;
    packet[1] = output;
    packet[2] = enabled as u8;
    packet[3] = invert as u8;
    write_f32_le(&mut packet, 4, gain);
    packet
}

/// Parse status response bytes into SystemStatus.
pub fn parse_status(data: &[u8], num_channels: usize) -> Option<SystemStatus> {
    let expected_len = num_channels * 2 + 4;
    if data.len() < expected_len {
        return None;
    }

    let mut status = SystemStatus::default();
    status.num_channels = num_channels as u8;

    for i in 0..num_channels {
        let raw = read_u16_le(data, i * 2);
        status.peaks[i] = raw as f32 / 32767.0;
    }

    status.cpu0 = data[num_channels * 2];
    status.cpu1 = data[num_channels * 2 + 1];
    status.clip_flags = read_u16_le(data, num_channels * 2 + 2);

    Some(status)
}

/// Extract a NUL-terminated ASCII string from a fixed-size buffer.
pub fn name_from_bytes(buf: &[u8; CHANNEL_NAME_LEN]) -> String {
    if let Some(nul_pos) = buf.iter().position(|&b| b == 0) {
        String::from_utf8_lossy(&buf[..nul_pos]).into_owned()
    } else {
        String::from_utf8_lossy(buf).into_owned()
    }
}

/// Write a string into a fixed-size NUL-terminated buffer. Truncates at 31 chars.
pub fn name_to_bytes(name: &str) -> [u8; CHANNEL_NAME_LEN] {
    let mut buf = [0u8; CHANNEL_NAME_LEN];
    let bytes = name.as_bytes();
    let len = bytes.len().min(CHANNEL_NAME_LEN - 1);
    buf[..len].copy_from_slice(&bytes[..len]);
    buf
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_eq_param_wvalue() {
        // ch=2, band=3, param=1(freq) => (2<<8)|(3<<4)|1 = 0x0231
        assert_eq!(eq_param_wvalue(2, 3, 1), 0x0231);
    }

    #[test]
    fn test_bulk_params_round_trip() {
        let mut params = BulkParams::default();
        params.preamp_db = -3.5;
        params.bypass = true;
        params.crossfeed_freq = 650.0;
        params.filters[0][0] = FilterParams {
            filter_type: FilterType::Peaking,
            freq: 100.0,
            q: 1.41,
            gain: 6.0,
        };
        params.channel_names[0] = name_to_bytes("Master L");

        let bytes = params.to_bytes();
        let parsed = BulkParams::from_bytes(&bytes).unwrap();

        assert_eq!(parsed.preamp_db, -3.5);
        assert!(parsed.bypass);
        assert_eq!(parsed.crossfeed_freq, 650.0);
        assert_eq!(parsed.filters[0][0].filter_type, FilterType::Peaking);
        assert_eq!(parsed.filters[0][0].freq, 100.0);
        assert_eq!(parsed.filters[0][0].q, 1.41);
        assert_eq!(parsed.filters[0][0].gain, 6.0);
        assert_eq!(name_from_bytes(&parsed.channel_names[0]), "Master L");
    }

    #[test]
    fn test_name_to_bytes_truncation() {
        let long_name = "This is a very long channel name that exceeds 31 characters";
        let buf = name_to_bytes(long_name);
        assert_eq!(buf[31], 0); // NUL terminator
        let recovered = name_from_bytes(&buf);
        assert_eq!(recovered.len(), 31);
    }

    #[test]
    fn test_parse_status() {
        // 7 channels: 14 bytes peaks + 4 bytes = 18 bytes
        let mut data = vec![0u8; 18];
        // Peak channel 0: 16384 => 16384/32767 ≈ 0.5
        data[0] = 0x00;
        data[1] = 0x40; // 0x4000 = 16384
        // CPU
        data[14] = 42;
        data[15] = 15;
        // Clip flags
        data[16] = 0x03;
        data[17] = 0x00;

        let status = parse_status(&data, 7).unwrap();
        assert!((status.peaks[0] - 0.5).abs() < 0.001);
        assert_eq!(status.cpu0, 42);
        assert_eq!(status.cpu1, 15);
        assert_eq!(status.clip_flags, 3);
    }
}
