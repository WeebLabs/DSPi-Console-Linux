//! USB request constants, bulk parameter wire format, and packet encoding.
//!
//! Mirrors firmware `config.h` and `bulk_params.h` (wire format V32,
//! firmware 1.1.6). All multi-byte fields are little-endian.

use crate::state::DspState;
use crate::types::*;

// ── USB Device IDs ──────────────────────────────────────────────────

/// DSPi vendor ID. Firmware moved from 0x2E8A (Raspberry Pi's, still used by
/// the RP2040/RP2350 ROM bootloader) to 0x2E8B in May 2026.
pub const VENDOR_ID: u16 = 0x2e8b;
/// Vendor ID used by firmware before the change; still recognised so an old
/// device shows up and can be told it needs a firmware update.
pub const LEGACY_VENDOR_ID: u16 = 0x2e8a;
pub const PRODUCT_ID: u16 = 0xfeaa;

/// Vendor interface number (WinUSB / WCID interface).
pub const VENDOR_INTERFACE: u8 = 2;

// ── bmRequestType ───────────────────────────────────────────────────

/// Host→Device | Vendor | Interface
pub const REQ_TYPE_OUT: u8 = 0x41;
/// Device→Host | Vendor | Interface
pub const REQ_TYPE_IN: u8 = 0xC1;

// ── Request codes ───────────────────────────────────────────────────

// Control Surfaces aux outputs
pub const REQ_SET_CS_AUX_STATE: u8 = 0x04;
pub const REQ_GET_CS_AUX_STATE: u8 = 0x05;
pub const REQ_SET_CS_AUX_LEVEL: u8 = 0x06;
pub const REQ_GET_CS_AUX_LEVEL: u8 = 0x07;

// Spectrum analyser (RTA)
pub const REQ_RTA_SET_CONFIG: u8 = 0x08;
pub const REQ_RTA_GET_CONFIG: u8 = 0x09;
pub const REQ_RTA_GET_CAPS: u8 = 0x0A;
pub const REQ_RTA_GET_BANDS: u8 = 0x0B;
pub const REQ_RTA_GET_BINS: u8 = 0x0C;
pub const REQ_RTA_GET_STATUS: u8 = 0x0D;
pub const REQ_RTA_CONTROL: u8 = 0x0E;
pub const REQ_RTA_GET_BANDS_ALL: u8 = 0x0F;

// Subharmonic synthesizer
pub const REQ_SET_SUBHARM: u8 = 0x10;
pub const REQ_GET_SUBHARM: u8 = 0x11;
pub const REQ_SET_SUBHARM_LOW: u8 = 0x12;
pub const REQ_GET_SUBHARM_LOW: u8 = 0x13;
pub const REQ_SET_SUBHARM_HIGH: u8 = 0x14;
pub const REQ_GET_SUBHARM_HIGH: u8 = 0x15;
pub const REQ_SET_SUBHARM_BOOST: u8 = 0x16;
pub const REQ_GET_SUBHARM_BOOST: u8 = 0x17;
pub const REQ_SET_SUBHARM_MASK: u8 = 0x18;
pub const REQ_GET_SUBHARM_MASK: u8 = 0x19;
pub const REQ_GET_SUBHARM_HEADROOM: u8 = 0x1A;
pub const REQ_SET_SUBHARM_TOP: u8 = 0x1B;
pub const REQ_GET_SUBHARM_TOP: u8 = 0x1C;
pub const REQ_SET_SUBHARM_SELECT: u8 = 0x1D;
pub const REQ_GET_SUBHARM_SELECT: u8 = 0x1E;
pub const REQ_GET_SUBHARM_METER: u8 = 0x1F;
pub const REQ_SET_SUBHARM_SOLO: u8 = 0x2C;
pub const REQ_GET_SUBHARM_SOLO: u8 = 0x2D;
pub const REQ_SET_SUBHARM_LINK: u8 = 0x2E;
pub const REQ_GET_SUBHARM_LINK: u8 = 0x2F;
pub const REQ_SET_SUBHARM_DEPTH: u8 = 0xA9;
pub const REQ_GET_SUBHARM_DEPTH: u8 = 0xAA;
pub const REQ_SET_SUBHARM_HOLD: u8 = 0xAB;
pub const REQ_GET_SUBHARM_HOLD: u8 = 0xAC;
pub const REQ_SET_SUBHARM_CEILING: u8 = 0xAD;
pub const REQ_GET_SUBHARM_CEILING: u8 = 0xAE;

// Control Surfaces groups, macros, display
pub const REQ_SET_CS_GROUP: u8 = 0x20;
pub const REQ_GET_CS_GROUP: u8 = 0x21;
pub const REQ_SET_CS_MACRO: u8 = 0x22;
pub const REQ_GET_CS_MACRO: u8 = 0x23;
pub const REQ_SET_CS_MACRO_STEP: u8 = 0x24;
pub const REQ_CS_MACRO_FIRE: u8 = 0x25;
pub const REQ_GET_CS_EXT_STATUS: u8 = 0x26;
pub const REQ_SET_CS_DISPLAY_CFG: u8 = 0x27;
pub const REQ_GET_CS_DISPLAY_CFG: u8 = 0x28;
pub const REQ_SET_CS_DISPLAY_PAGE: u8 = 0x29;
pub const REQ_GET_CS_DISPLAY_PAGE: u8 = 0x2A;
pub const REQ_GET_CS_DISPLAY_STATUS: u8 = 0x2B;

// Psychoacoustic bass
pub const REQ_SET_PSYBASS: u8 = 0x30;
pub const REQ_GET_PSYBASS: u8 = 0x31;
pub const REQ_SET_PSYBASS_CUTOFF: u8 = 0x32;
pub const REQ_GET_PSYBASS_CUTOFF: u8 = 0x33;
pub const REQ_SET_PSYBASS_HARMONICS: u8 = 0x34;
pub const REQ_GET_PSYBASS_HARMONICS: u8 = 0x35;
pub const REQ_SET_PSYBASS_DRIVE: u8 = 0x36;
pub const REQ_GET_PSYBASS_DRIVE: u8 = 0x37;
pub const REQ_SET_PSYBASS_CHARACTER: u8 = 0x38;
pub const REQ_GET_PSYBASS_CHARACTER: u8 = 0x39;
pub const REQ_SET_PSYBASS_ORIGINAL: u8 = 0x3A;
pub const REQ_GET_PSYBASS_ORIGINAL: u8 = 0x3B;
pub const REQ_SET_PSYBASS_MASK: u8 = 0x3C;
pub const REQ_GET_PSYBASS_MASK: u8 = 0x3D;

/// Psybass parameter ids for `set_psybass_param` (host-side, not wire values).
pub const PSYBASS_PARAM_CUTOFF: u8 = 0;
pub const PSYBASS_PARAM_HARMONICS: u8 = 1;
pub const PSYBASS_PARAM_DRIVE: u8 = 2;
pub const PSYBASS_PARAM_CHARACTER: u8 = 3;
pub const PSYBASS_PARAM_ORIGINAL: u8 = 4;

// Tube modeller
pub const REQ_SET_TUBE_PARAM: u8 = 0x3E;
pub const REQ_GET_TUBE_PARAM: u8 = 0x3F;

// EQ / Preamp / Bypass / Delay
pub const REQ_SET_EQ_PARAM: u8 = 0x42;
pub const REQ_GET_EQ_PARAM: u8 = 0x43;
/// Legacy: sets every input channel's preamp to the same value.
pub const REQ_SET_PREAMP: u8 = 0x44;
pub const REQ_GET_PREAMP: u8 = 0x45;
pub const REQ_SET_BYPASS: u8 = 0x46;
pub const REQ_GET_BYPASS: u8 = 0x47;
pub const REQ_SET_DELAY: u8 = 0x48;
pub const REQ_GET_DELAY: u8 = 0x49;

// Stereo upmixer
pub const REQ_UPMIX_SET_CONFIG: u8 = 0x4A;
pub const REQ_UPMIX_GET_CONFIG: u8 = 0x4B;
pub const REQ_UPMIX_SET_PARAM: u8 = 0x4C;
pub const REQ_UPMIX_GET_PARAM: u8 = 0x4D;
pub const REQ_UPMIX_GET_STATUS: u8 = 0x4E;

// Status / flash
pub const REQ_GET_STATUS: u8 = 0x50;
pub const REQ_SAVE_PARAMS: u8 = 0x51;
/// Persist the live output (IO) config in independent mode. Was the
/// deprecated REQ_LOAD_PARAMS, which is gone.
pub const REQ_SAVE_OUTPUT_CONFIG: u8 = 0x52;
pub const REQ_FACTORY_RESET: u8 = 0x53;

// Legacy channel gain/mute
pub const REQ_SET_CHANNEL_GAIN: u8 = 0x54;
pub const REQ_GET_CHANNEL_GAIN: u8 = 0x55;
pub const REQ_SET_CHANNEL_MUTE: u8 = 0x56;
pub const REQ_GET_CHANNEL_MUTE: u8 = 0x57;

// Loudness
pub const REQ_SET_LOUDNESS: u8 = 0x58;
pub const REQ_GET_LOUDNESS: u8 = 0x59;
pub const REQ_SET_LOUDNESS_REF: u8 = 0x5A;
pub const REQ_GET_LOUDNESS_REF: u8 = 0x5B;
pub const REQ_SET_LOUDNESS_INTENSITY: u8 = 0x5C;
pub const REQ_GET_LOUDNESS_INTENSITY: u8 = 0x5D;
pub const REQ_SET_LOUDNESS_MASK: u8 = 0xFA;
pub const REQ_GET_LOUDNESS_MASK: u8 = 0xFB;

// Crossfeed
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
pub const REQ_SET_CROSSFEED_OUTPUTS: u8 = 0xFC;
pub const REQ_GET_CROSSFEED_OUTPUTS: u8 = 0xFD;

// ADAT input (RP2350)
pub const REQ_SET_ADAT_INPUT_ENABLE: u8 = 0x68;
pub const REQ_GET_ADAT_INPUT_ENABLE: u8 = 0x69;
pub const REQ_SET_ADAT_INPUT_PIN: u8 = 0x6A;
pub const REQ_GET_ADAT_INPUT_PIN: u8 = 0x6B;
pub const REQ_SET_ADAT_INPUT_CLOCK_MODE: u8 = 0x6C;
pub const REQ_GET_ADAT_INPUT_CLOCK_MODE: u8 = 0x6D;
pub const REQ_GET_ADAT_INPUT_STATUS: u8 = 0x6E;

// Matrix mixer / outputs
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

// Core 1
pub const REQ_GET_CORE1_MODE: u8 = 0x7A;
pub const REQ_GET_CORE1_CONFLICT: u8 = 0x7B;

// Pins
pub const REQ_SET_OUTPUT_PIN: u8 = 0x7C;
pub const REQ_GET_OUTPUT_PIN: u8 = 0x7D;

// Identification
pub const REQ_GET_SERIAL: u8 = 0x7E;
pub const REQ_GET_PLATFORM: u8 = 0x7F;
pub const REQ_GET_BUILD_INFO: u8 = 0x80;

// Output limiter (sub-command multiplexed)
pub const REQ_LIMITER: u8 = 0x81;

/// REQ_LIMITER wValue low byte: parameter index (high byte = output).
pub const LIMITER_PARAM_ENABLED: u8 = 0;
pub const LIMITER_PARAM_THRESHOLD_DB: u8 = 1;
pub const LIMITER_PARAM_RELEASE_MS: u8 = 2;
pub const LIMITER_PARAM_LINK_GROUP: u8 = 3;
/// GET: per-output gain reduction, u16 in 0.01 dB.
pub const LIMITER_GET_METER: u8 = 0x80;
/// GET: engaged, lookahead, block, num_outputs.
pub const LIMITER_GET_STATUS: u8 = 0x81;
/// SET output byte: apply to every output.
pub const LIMITER_ALL_OUTPUTS: u8 = 0xFF;

// Clip detection
pub const REQ_CLEAR_CLIPS: u8 = 0x83;

// Control Surfaces bindings / IR
pub const REQ_SET_CS_BINDING: u8 = 0x84;
pub const REQ_GET_CS_BINDING: u8 = 0x85;
pub const REQ_GET_CS_CAPS: u8 = 0x86;
pub const REQ_GET_CS_STATUS: u8 = 0x87;
pub const REQ_SET_CS_NAME: u8 = 0x8B;
pub const REQ_GET_CS_NAME: u8 = 0x8C;
pub const REQ_SET_CS_IR_CMD: u8 = 0x8D;
pub const REQ_GET_CS_IR_CMD: u8 = 0x8E;
pub const REQ_CS_IR_LEARN: u8 = 0x8F;
pub const REQ_CS_SAVE: u8 = 0x9D;
pub const REQ_CS_REVERT: u8 = 0x9E;

// I2S clock mode
pub const REQ_SET_I2S_CLOCK_MODE: u8 = 0x88;
pub const REQ_GET_I2S_CLOCK_MODE: u8 = 0x89;
pub const REQ_GET_I2S_SLAVE_STATUS: u8 = 0x8A;
pub const REQ_SET_I2S_CLOCK_PIN_MODE: u8 = 0xFE;
pub const REQ_GET_I2S_CLOCK_PIN_MODE: u8 = 0xFF;

// Presets
pub const REQ_PRESET_SAVE: u8 = 0x90;
pub const REQ_PRESET_LOAD: u8 = 0x91;
pub const REQ_PRESET_DELETE: u8 = 0x92;
pub const REQ_PRESET_GET_NAME: u8 = 0x93;
pub const REQ_PRESET_SET_NAME: u8 = 0x94;
pub const REQ_PRESET_GET_DIR: u8 = 0x95;
pub const REQ_PRESET_SET_STARTUP: u8 = 0x96;
pub const REQ_PRESET_GET_STARTUP: u8 = 0x97;
/// Replaced the old include-pins flag (same 0/1 meaning).
pub const REQ_SET_OUTPUT_CONFIG_MODE: u8 = 0x98;
pub const REQ_GET_OUTPUT_CONFIG_MODE: u8 = 0x99;
pub const REQ_PRESET_GET_ACTIVE: u8 = 0x9A;

// Channel names
pub const REQ_SET_CHANNEL_NAME: u8 = 0x9B;
pub const REQ_GET_CHANNEL_NAME: u8 = 0x9C;

// Bulk parameter transfer
pub const REQ_GET_ALL_PARAMS: u8 = 0xA0;
pub const REQ_SET_ALL_PARAMS: u8 = 0xA1;
pub const REQ_GET_ALL_PARAMS_CHUNK: u8 = 0xA2;
pub const REQ_SET_ALL_PARAMS_CHUNK: u8 = 0xA3;

// Signal generator
pub const REQ_SIGGEN_SET_CONFIG: u8 = 0xA4;
pub const REQ_SIGGEN_GET_CONFIG: u8 = 0xA5;
pub const REQ_SIGGEN_CONTROL: u8 = 0xA6;
pub const REQ_SIGGEN_GET_STATUS: u8 = 0xA7;
pub const REQ_SIGGEN_GET_CAPS: u8 = 0xA8;

// Buffer / USB statistics
pub const REQ_GET_BUFFER_STATS: u8 = 0xB0;
pub const REQ_RESET_BUFFER_STATS: u8 = 0xB1;
pub const REQ_GET_USB_ERROR_STATS: u8 = 0xB2;
pub const REQ_RESET_USB_ERROR_STATS: u8 = 0xB3;

// Volume leveller
pub const REQ_SET_LEVELLER_ENABLE: u8 = 0xB4;
pub const REQ_GET_LEVELLER_ENABLE: u8 = 0xB5;
pub const REQ_SET_LEVELLER_AMOUNT: u8 = 0xB6;
pub const REQ_GET_LEVELLER_AMOUNT: u8 = 0xB7;
pub const REQ_SET_LEVELLER_SPEED: u8 = 0xB8;
pub const REQ_GET_LEVELLER_SPEED: u8 = 0xB9;
pub const REQ_SET_LEVELLER_MAX_GAIN: u8 = 0xBA;
pub const REQ_GET_LEVELLER_MAX_GAIN: u8 = 0xBB;
pub const REQ_SET_LEVELLER_LOOKAHEAD: u8 = 0xBC;
pub const REQ_GET_LEVELLER_LOOKAHEAD: u8 = 0xBD;
pub const REQ_SET_LEVELLER_GATE: u8 = 0xBE;
pub const REQ_GET_LEVELLER_GATE: u8 = 0xBF;
pub const REQ_SET_LEVELLER_MASKS: u8 = 0xDE;
pub const REQ_GET_LEVELLER_MASKS: u8 = 0xDF;

// Output types / I2S / MCK
pub const REQ_SET_OUTPUT_TYPE: u8 = 0xC0;
pub const REQ_GET_OUTPUT_TYPE: u8 = 0xC1;
pub const REQ_SET_I2S_BCK_PIN: u8 = 0xC2;
pub const REQ_GET_I2S_BCK_PIN: u8 = 0xC3;
pub const REQ_SET_MCK_ENABLE: u8 = 0xC4;
pub const REQ_GET_MCK_ENABLE: u8 = 0xC5;
pub const REQ_SET_MCK_PIN: u8 = 0xC6;
pub const REQ_GET_MCK_PIN: u8 = 0xC7;
pub const REQ_SET_MCK_MULTIPLIER: u8 = 0xC8;
pub const REQ_GET_MCK_MULTIPLIER: u8 = 0xC9;

// ADAT output (RP2350)
pub const REQ_SET_ADAT_ENABLE: u8 = 0xCA;
pub const REQ_GET_ADAT_ENABLE: u8 = 0xCB;
pub const REQ_SET_ADAT_PIN: u8 = 0xCC;
pub const REQ_GET_ADAT_PIN: u8 = 0xCD;
pub const REQ_GET_ADAT_STATUS: u8 = 0xCE;

// Per-input preamp
pub const REQ_SET_PREAMP_CH: u8 = 0xD0;
pub const REQ_GET_PREAMP_CH: u8 = 0xD1;

// Master volume
pub const REQ_SET_MASTER_VOLUME: u8 = 0xD2;
pub const REQ_GET_MASTER_VOLUME: u8 = 0xD3;
pub const REQ_SET_MASTER_VOLUME_MODE: u8 = 0xD4;
pub const REQ_GET_MASTER_VOLUME_MODE: u8 = 0xD5;
pub const REQ_SAVE_MASTER_VOLUME: u8 = 0xD6;
pub const REQ_GET_SAVED_MASTER_VOLUME: u8 = 0xD7;

// Per-band bypass
pub const REQ_SET_BAND_BYPASS: u8 = 0xD8;
pub const REQ_GET_BAND_BYPASS: u8 = 0xD9;

// User volume / mute
pub const REQ_SET_USER_VOLUME: u8 = 0xDA;
pub const REQ_GET_USER_VOLUME: u8 = 0xDB;
pub const REQ_SET_USER_MUTE: u8 = 0xDC;
pub const REQ_GET_USER_MUTE: u8 = 0xDD;

// Input source / S/PDIF / I2S input
pub const REQ_SET_INPUT_SOURCE: u8 = 0xE0;
pub const REQ_GET_INPUT_SOURCE: u8 = 0xE1;
pub const REQ_GET_SPDIF_RX_STATUS: u8 = 0xE2;
pub const REQ_GET_SPDIF_RX_CH_STATUS: u8 = 0xE3;
pub const REQ_SET_SPDIF_RX_PIN: u8 = 0xE4;
pub const REQ_GET_SPDIF_RX_PIN: u8 = 0xE5;
pub const REQ_SET_SPDIF_INPUT_ENABLE: u8 = 0xE9;
pub const REQ_GET_SPDIF_INPUT_CONFIG: u8 = 0xEF;
pub const REQ_SET_INPUT_RATE: u8 = 0xED;
pub const REQ_GET_INPUT_RATE: u8 = 0xEE;
pub const REQ_SET_I2S_RX_PIN: u8 = 0xF1;
pub const REQ_GET_I2S_RX_PIN: u8 = 0xF2;
pub const REQ_SET_I2S_INPUT_CHANNELS: u8 = 0xF3;
pub const REQ_GET_I2S_INPUT_CHANNELS: u8 = 0xF4;

// LG Sound Sync
pub const REQ_SET_LG_SOUND_SYNC_ENABLE: u8 = 0xE6;
pub const REQ_GET_LG_SOUND_SYNC_ENABLE: u8 = 0xE7;
pub const REQ_GET_LG_SOUND_SYNC_STATUS: u8 = 0xE8;

// DAC hardware mute
pub const REQ_SET_DAC_HW_MUTE_CONFIG: u8 = 0xEA;
pub const REQ_GET_DAC_HW_MUTE_CONFIG: u8 = 0xEB;
pub const REQ_TEST_DAC_HW_MUTE: u8 = 0xEC;

// System
pub const REQ_ENTER_BOOTLOADER: u8 = 0xF0;

// UART / I2C control interfaces
pub const REQ_SET_UART_CONFIG: u8 = 0xF5;
pub const REQ_GET_UART_CONFIG: u8 = 0xF6;
pub const REQ_SET_I2C_CONFIG: u8 = 0xF7;
pub const REQ_GET_I2C_CONFIG: u8 = 0xF8;
pub const REQ_GET_CTRL_IFACE_STATUS: u8 = 0xF9;

// ── Status codes ────────────────────────────────────────────────────

pub const PIN_CONFIG_SUCCESS: u8 = 0x00;
pub const PIN_CONFIG_INVALID_PIN: u8 = 0x01;
pub const PIN_CONFIG_PIN_IN_USE: u8 = 0x02;
pub const PIN_CONFIG_INVALID_OUTPUT: u8 = 0x03;
pub const PIN_CONFIG_OUTPUT_ACTIVE: u8 = 0x04;
pub const PIN_CONFIG_INVALID_PARAM: u8 = 0x05;
/// Sent as the pin byte of any single-pin SET to restore the platform default.
pub const PIN_RESET_TO_DEFAULT: u8 = 0xFF;

pub const PRESET_OK: u8 = 0x00;
pub const PRESET_ERR_INVALID_SLOT: u8 = 0x01;
pub const PRESET_ERR_SLOT_EMPTY: u8 = 0x02;
pub const PRESET_ERR_CRC: u8 = 0x03;
pub const PRESET_ERR_FLASH_WRITE: u8 = 0x04;

pub const FLASH_OK: u8 = 0;
pub const FLASH_ERR_WRITE: u8 = 1;
pub const FLASH_ERR_NO_DATA: u8 = 2;
pub const FLASH_ERR_CRC: u8 = 3;

// ── wIndex conventions (as used by the macOS Console) ───────────────

/// wIndex for EQ, preamp, bypass, delay, status, loudness, crossfeed, volume, core1.
pub const WINDEX_GLOBAL: u16 = 0;
/// wIndex for matrix/output/pin/preset/channel-name/bulk commands.
pub const WINDEX_OUTPUT: u16 = 2;

// ── Firmware the core is built against ──────────────────────────────

/// Wire format this core reads and writes.
pub const WIRE_FORMAT_VERSION: u8 = 32;
/// Oldest wire format with the unified channel model. Anything older is
/// incompatible (V16 broke compatibility with no migration).
pub const MIN_WIRE_FORMAT_VERSION: u8 = 16;

// ═══════════════════════════════════════════════════════════════════
// Bulk parameter wire format (WireBulkParams, V32)
// ═══════════════════════════════════════════════════════════════════

/// sizeof(WireBulkParams) at V32.
pub const BULK_PARAMS_SIZE: usize = 6136;
/// Chunk size for REQ_GET/SET_ALL_PARAMS_CHUNK. Kept well under the 4 KB
/// control-transfer limit (Linux usbfs caps a control transfer at one page).
pub const BULK_CHUNK_SIZE: usize = 2048;

pub const OFF_HEADER: usize = 0;
pub const OFF_GLOBAL: usize = 16;
pub const OFF_CROSSFEED: usize = 32;
pub const OFF_LEGACY: usize = 48;
pub const OFF_DELAYS: usize = 64;
pub const OFF_CROSSPOINTS: usize = 132;
pub const OFF_OUTPUTS: usize = 708;
pub const OFF_PINS: usize = 816;
pub const OFF_EQ: usize = 824;
pub const OFF_CHANNEL_NAMES: usize = 4088;
pub const OFF_I2S: usize = 4632;
pub const OFF_LEVELLER: usize = 4648;
pub const OFF_PREAMP: usize = 4668;
pub const OFF_MASTER_VOLUME: usize = 4700;
pub const OFF_INPUT_CONFIG: usize = 4716;
pub const OFF_LG_SOUND_SYNC: usize = 4732;
pub const OFF_USER_VOLUME: usize = 4748;
pub const OFF_DAC_HW_MUTE: usize = 4764;
pub const OFF_CROSSOVER: usize = 4780;
pub const OFF_ADAT: usize = 5868;
pub const OFF_PSYBASS: usize = 5876;
pub const OFF_UPMIX: usize = 5900;
pub const OFF_SUBHARM: usize = 5944;
pub const OFF_TUBE: usize = 5980;
pub const OFF_LIMITER: usize = 6028;

const BAND_SIZE: usize = 16;
const CROSSPOINT_SIZE: usize = 8;
const OUTPUT_SIZE: usize = 12;
const LIMITER_OUTPUT_SIZE: usize = 12;

// ── Little-endian helpers ───────────────────────────────────────────

pub(crate) fn read_f32_le(data: &[u8], offset: usize) -> f32 {
    f32::from_le_bytes([data[offset], data[offset + 1], data[offset + 2], data[offset + 3]])
}

pub(crate) fn read_u16_le(data: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes([data[offset], data[offset + 1]])
}

pub(crate) fn read_u32_le(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([data[offset], data[offset + 1], data[offset + 2], data[offset + 3]])
}

pub(crate) fn write_f32_le(data: &mut [u8], offset: usize, val: f32) {
    data[offset..offset + 4].copy_from_slice(&val.to_le_bytes());
}

pub(crate) fn write_u16_le(data: &mut [u8], offset: usize, val: u16) {
    data[offset..offset + 2].copy_from_slice(&val.to_le_bytes());
}

/// Why a bulk image was rejected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BulkError {
    TooShort,
    /// Wire format older than the unified channel model, or newer than this core.
    UnsupportedVersion(u8),
}

fn parse_band(data: &[u8], off: usize) -> FilterParams {
    let filter_type = data[off];
    let qp_raw = read_u16_le(data, off + 2);
    FilterParams {
        filter_type,
        bypass: data[off + 1] == 1,
        freq: read_f32_le(data, off + 4),
        q: read_f32_le(data, off + 8),
        gain: read_f32_le(data, off + 12),
        qp: if filter_type == FILTER_LINKWITZ_TRANSFORM {
            FilterParams::decode_qp(qp_raw)
        } else {
            DEFAULT_Q
        },
    }
}

fn write_band(data: &mut [u8], off: usize, p: &FilterParams) {
    data[off] = p.filter_type;
    data[off + 1] = p.bypass as u8;
    write_u16_le(data, off + 2, p.qp_x512());
    write_f32_le(data, off + 4, p.freq);
    write_f32_le(data, off + 8, p.q);
    write_f32_le(data, off + 12, p.gain);
}

/// Decode a full V32 bulk image into `state`. The raw image is kept in
/// `state.bulk_raw` so sections the core does not model round-trip intact.
pub fn decode_bulk(data: &[u8], state: &mut DspState) -> Result<(), BulkError> {
    if data.len() < BULK_PARAMS_SIZE {
        return Err(BulkError::TooShort);
    }
    let version = data[OFF_HEADER];
    // The firmware's SET rejects anything but its own version, so a state
    // read from another version could never be written back. Only V32.
    if version != WIRE_FORMAT_VERSION {
        return Err(BulkError::UnsupportedVersion(version));
    }
    let d = data;
    let s = state;

    // Header
    s.format_version = version;
    s.platform_id = d[OFF_HEADER + 1];
    s.num_channels = d[OFF_HEADER + 2].min(MAX_CHANNELS as u8);
    s.num_output_channels = d[OFF_HEADER + 3].min(MAX_OUTPUTS as u8);
    s.num_input_channels = d[OFF_HEADER + 4].min(MAX_INPUTS as u8);

    // Global
    s.preamp_db = read_f32_le(d, OFF_GLOBAL);
    s.bypass = d[OFF_GLOBAL + 4] != 0;
    s.loudness_enabled = d[OFF_GLOBAL + 5] != 0;
    s.loudness_output_mask = read_u16_le(d, OFF_GLOBAL + 6);
    s.loudness_ref_spl = read_f32_le(d, OFF_GLOBAL + 8);
    s.loudness_intensity = read_f32_le(d, OFF_GLOBAL + 12);

    // Crossfeed
    s.crossfeed_enabled = d[OFF_CROSSFEED] != 0;
    s.crossfeed_preset = d[OFF_CROSSFEED + 1];
    s.crossfeed_itd = d[OFF_CROSSFEED + 2] != 0;
    s.crossfeed_output_pair_mask = d[OFF_CROSSFEED + 3];
    s.crossfeed_freq = read_f32_le(d, OFF_CROSSFEED + 4);
    s.crossfeed_feed = read_f32_le(d, OFF_CROSSFEED + 8);

    // Delays
    for ch in 0..MAX_CHANNELS {
        s.channel_delays[ch] = read_f32_le(d, OFF_DELAYS + ch * 4);
    }

    // Matrix crosspoints [input][output]
    for i in 0..MAX_INPUTS {
        for o in 0..MAX_OUTPUTS {
            let off = OFF_CROSSPOINTS + (i * MAX_OUTPUTS + o) * CROSSPOINT_SIZE;
            s.matrix_routing[i][o] = d[off] != 0;
            s.matrix_invert[i][o] = d[off + 1] != 0;
            s.matrix_gain[i][o] = read_f32_le(d, off + 4);
        }
    }

    // Outputs
    for o in 0..MAX_OUTPUTS {
        let off = OFF_OUTPUTS + o * OUTPUT_SIZE;
        s.output_enabled[o] = d[off] != 0;
        s.output_muted[o] = d[off + 1] != 0;
        s.output_gain_db[o] = read_f32_le(d, off + 4);
        s.output_delay_ms[o] = read_f32_le(d, off + 8);
    }

    // Pins
    s.num_pin_outputs = d[OFF_PINS].min(MAX_PHYSICAL_OUTPUTS as u8);
    s.output_pins.copy_from_slice(&d[OFF_PINS + 1..OFF_PINS + 1 + MAX_PHYSICAL_OUTPUTS]);

    // EQ bands
    for ch in 0..MAX_CHANNELS {
        for band in 0..BANDS_PER_CHANNEL {
            let off = OFF_EQ + (ch * FIRMWARE_BANDS_PER_CHANNEL + band) * BAND_SIZE;
            s.filters[ch][band] = parse_band(d, off);
        }
    }

    // Channel names
    for ch in 0..MAX_CHANNELS {
        let off = OFF_CHANNEL_NAMES + ch * CHANNEL_NAME_LEN;
        s.channel_names[ch].copy_from_slice(&d[off..off + CHANNEL_NAME_LEN]);
        s.channel_names[ch][CHANNEL_NAME_LEN - 1] = 0;
    }

    // Leveller
    s.leveller_enabled = d[OFF_LEVELLER] != 0;
    s.leveller_speed = d[OFF_LEVELLER + 1];
    s.leveller_lookahead = d[OFF_LEVELLER + 2] != 0;
    s.leveller_amount = read_f32_le(d, OFF_LEVELLER + 4);
    s.leveller_max_gain_db = read_f32_le(d, OFF_LEVELLER + 8);
    s.leveller_gate_db = read_f32_le(d, OFF_LEVELLER + 12);
    s.leveller_detector_mask = d[OFF_LEVELLER + 16];
    s.leveller_apply_mask = d[OFF_LEVELLER + 17];

    // Per-input preamp
    for i in 0..MAX_INPUTS {
        s.input_preamp_db[i] = read_f32_le(d, OFF_PREAMP + i * 4);
    }

    // Master volume
    s.master_volume_db = read_f32_le(d, OFF_MASTER_VOLUME);

    // Input config (source and which inputs are enabled; the rest
    // round-trips raw). V28 layout: spdif_rx_pin_ext[3] at +8, then the
    // +1-encoded S/PDIF 2-4 enable mask, I2S clock mode, ADAT pin, and the
    // +1-encoded ADAT enable.
    s.input_source = d[OFF_INPUT_CONFIG];
    let ext_p1 = d[OFF_INPUT_CONFIG + 11];
    s.spdif_inputs_enabled = 0x01 | if ext_p1 > 0 { (ext_p1 - 1) << 1 } else { 0 };
    s.adat_input_enabled = d[OFF_INPUT_CONFIG + 14] == 2;

    s.psybass_enabled = d[OFF_PSYBASS] != 0;
    s.psybass_output_mask = read_u16_le(d, OFF_PSYBASS + 2);
    s.psybass_cutoff_hz = read_f32_le(d, OFF_PSYBASS + 4);
    s.psybass_harmonics_db = read_f32_le(d, OFF_PSYBASS + 8);
    s.psybass_drive_db = read_f32_le(d, OFF_PSYBASS + 12);
    s.psybass_character_pct = read_f32_le(d, OFF_PSYBASS + 16);
    s.psybass_original_db = read_f32_le(d, OFF_PSYBASS + 20);

    // LG Sound Sync (only `enabled` is honored on SET)
    s.lg_sound_sync_enabled = d[OFF_LG_SOUND_SYNC] != 0;

    // User volume / mute
    s.user_volume_db = read_f32_le(d, OFF_USER_VOLUME);
    s.user_mute = d[OFF_USER_VOLUME + 4] != 0;

    // Crossover bands
    for ch in 0..MAX_CHANNELS {
        for band in 0..MAX_XOVER_BANDS {
            let off = OFF_CROSSOVER + (ch * MAX_XOVER_BANDS + band) * BAND_SIZE;
            s.xover[ch][band] = parse_band(d, off);
        }
    }

    // Output limiter
    for o in 0..MAX_OUTPUTS {
        let off = OFF_LIMITER + o * LIMITER_OUTPUT_SIZE;
        s.limiter_enabled[o] = d[off] != 0;
        s.limiter_link_group[o] = d[off + 1];
        s.limiter_threshold_db[o] = read_f32_le(d, off + 4);
        s.limiter_release_ms[o] = read_f32_le(d, off + 8);
    }

    s.bulk_raw.copy_from_slice(&d[..BULK_PARAMS_SIZE]);
    s.bulk_valid = true;
    Ok(())
}

/// Encode `state` as a V32 bulk image for REQ_SET_ALL_PARAMS. Starts from the
/// last image read from the device so unmodeled sections are preserved.
pub fn encode_bulk(state: &DspState) -> Vec<u8> {
    let s = state;
    let mut d = s.bulk_raw.to_vec();

    d[OFF_HEADER] = WIRE_FORMAT_VERSION;
    write_u16_le(&mut d, OFF_HEADER + 6, BULK_PARAMS_SIZE as u16);

    // Global
    write_f32_le(&mut d, OFF_GLOBAL, s.preamp_db);
    d[OFF_GLOBAL + 4] = s.bypass as u8;
    d[OFF_GLOBAL + 5] = s.loudness_enabled as u8;
    write_u16_le(&mut d, OFF_GLOBAL + 6, s.loudness_output_mask);
    write_f32_le(&mut d, OFF_GLOBAL + 8, s.loudness_ref_spl);
    write_f32_le(&mut d, OFF_GLOBAL + 12, s.loudness_intensity);

    // Crossfeed
    d[OFF_CROSSFEED] = s.crossfeed_enabled as u8;
    d[OFF_CROSSFEED + 1] = s.crossfeed_preset;
    d[OFF_CROSSFEED + 2] = s.crossfeed_itd as u8;
    d[OFF_CROSSFEED + 3] = s.crossfeed_output_pair_mask;
    write_f32_le(&mut d, OFF_CROSSFEED + 4, s.crossfeed_freq);
    write_f32_le(&mut d, OFF_CROSSFEED + 8, s.crossfeed_feed);

    for ch in 0..MAX_CHANNELS {
        write_f32_le(&mut d, OFF_DELAYS + ch * 4, s.channel_delays[ch]);
    }

    for i in 0..MAX_INPUTS {
        for o in 0..MAX_OUTPUTS {
            let off = OFF_CROSSPOINTS + (i * MAX_OUTPUTS + o) * CROSSPOINT_SIZE;
            d[off] = s.matrix_routing[i][o] as u8;
            d[off + 1] = s.matrix_invert[i][o] as u8;
            write_f32_le(&mut d, off + 4, s.matrix_gain[i][o]);
        }
    }

    for o in 0..MAX_OUTPUTS {
        let off = OFF_OUTPUTS + o * OUTPUT_SIZE;
        d[off] = s.output_enabled[o] as u8;
        d[off + 1] = s.output_muted[o] as u8;
        write_f32_le(&mut d, off + 4, s.output_gain_db[o]);
        write_f32_le(&mut d, off + 8, s.output_delay_ms[o]);
    }

    d[OFF_PINS] = s.num_pin_outputs;
    d[OFF_PINS + 1..OFF_PINS + 1 + MAX_PHYSICAL_OUTPUTS].copy_from_slice(&s.output_pins);

    for ch in 0..MAX_CHANNELS {
        for band in 0..BANDS_PER_CHANNEL {
            let off = OFF_EQ + (ch * FIRMWARE_BANDS_PER_CHANNEL + band) * BAND_SIZE;
            write_band(&mut d, off, &s.filters[ch][band]);
        }
    }

    for ch in 0..MAX_CHANNELS {
        let off = OFF_CHANNEL_NAMES + ch * CHANNEL_NAME_LEN;
        d[off..off + CHANNEL_NAME_LEN].copy_from_slice(&s.channel_names[ch]);
    }

    d[OFF_LEVELLER] = s.leveller_enabled as u8;
    d[OFF_LEVELLER + 1] = s.leveller_speed;
    d[OFF_LEVELLER + 2] = s.leveller_lookahead as u8;
    write_f32_le(&mut d, OFF_LEVELLER + 4, s.leveller_amount);
    write_f32_le(&mut d, OFF_LEVELLER + 8, s.leveller_max_gain_db);
    write_f32_le(&mut d, OFF_LEVELLER + 12, s.leveller_gate_db);
    d[OFF_LEVELLER + 16] = s.leveller_detector_mask;
    d[OFF_LEVELLER + 17] = s.leveller_apply_mask;

    for i in 0..MAX_INPUTS {
        write_f32_le(&mut d, OFF_PREAMP + i * 4, s.input_preamp_db[i]);
    }

    write_f32_le(&mut d, OFF_MASTER_VOLUME, s.master_volume_db);
    d[OFF_INPUT_CONFIG] = s.input_source;
    d[OFF_PSYBASS] = s.psybass_enabled as u8;
    write_u16_le(&mut d, OFF_PSYBASS + 2, s.psybass_output_mask);
    write_f32_le(&mut d, OFF_PSYBASS + 4, s.psybass_cutoff_hz);
    write_f32_le(&mut d, OFF_PSYBASS + 8, s.psybass_harmonics_db);
    write_f32_le(&mut d, OFF_PSYBASS + 12, s.psybass_drive_db);
    write_f32_le(&mut d, OFF_PSYBASS + 16, s.psybass_character_pct);
    write_f32_le(&mut d, OFF_PSYBASS + 20, s.psybass_original_db);
    d[OFF_LG_SOUND_SYNC] = s.lg_sound_sync_enabled as u8;
    write_f32_le(&mut d, OFF_USER_VOLUME, s.user_volume_db);
    d[OFF_USER_VOLUME + 4] = s.user_mute as u8;

    for ch in 0..MAX_CHANNELS {
        for band in 0..MAX_XOVER_BANDS {
            let off = OFF_CROSSOVER + (ch * MAX_XOVER_BANDS + band) * BAND_SIZE;
            write_band(&mut d, off, &s.xover[ch][band]);
        }
    }

    for o in 0..MAX_OUTPUTS {
        let off = OFF_LIMITER + o * LIMITER_OUTPUT_SIZE;
        d[off] = s.limiter_enabled[o] as u8;
        d[off + 1] = s.limiter_link_group[o];
        write_f32_le(&mut d, off + 4, s.limiter_threshold_db[o]);
        write_f32_le(&mut d, off + 8, s.limiter_release_ms[o]);
    }

    d
}

// ═══════════════════════════════════════════════════════════════════
// Packets
// ═══════════════════════════════════════════════════════════════════

/// REQ_GET_EQ_PARAM wValue: (channel << 8) | (band << 3) | param.
/// The band field is 5 bits so crossover bands 20..23 are addressable.
/// param: 0 type, 1 freq, 2 Q, 3 gain, 4 bypass, 5 LT Qp (Q×512).
pub fn eq_param_wvalue(ch: u8, band: u8, param: u8) -> u16 {
    ((ch as u16) << 8) | (((band & 0x1F) as u16) << 3) | ((param & 0x07) as u16)
}

/// wValue for channel/band addressed commands (band bypass): (channel << 8) | band.
pub fn channel_band_wvalue(ch: u8, band: u8) -> u16 {
    ((ch as u16) << 8) | (band as u16)
}

/// Matrix route wValue: (input << 8) | output.
pub fn matrix_route_wvalue(input: u8, output: u8) -> u16 {
    ((input as u16) << 8) | (output as u16)
}

/// Pin config SET wValue: (new_pin << 8) | output_index.
pub fn pin_config_wvalue(pin: u8, output: u8) -> u16 {
    ((pin as u16) << 8) | (output as u16)
}

/// REQ_SET_EQ_PARAM payload: 16-byte EqParamPacket plus the 2-byte LT target
/// Qp (Q×512). `band` is a PEQ band (0..9) or crossover band (20..23).
pub fn build_set_filter_packet(ch: u8, band: u8, p: &FilterParams) -> Vec<u8> {
    let mut packet = vec![0u8; 18];
    packet[0] = ch;
    packet[1] = band;
    packet[2] = p.filter_type;
    packet[3] = p.bypass as u8;
    write_f32_le(&mut packet, 4, p.freq);
    write_f32_le(&mut packet, 8, p.q);
    write_f32_le(&mut packet, 12, p.gain);
    write_u16_le(&mut packet, 16, p.qp_x512());
    packet
}

/// REQ_SET_MATRIX_ROUTE payload (MatrixRoutePacket).
pub fn build_matrix_route_packet(input: u8, output: u8, enabled: bool, gain: f32, invert: bool) -> Vec<u8> {
    let mut packet = vec![0u8; 8];
    packet[0] = input;
    packet[1] = output;
    packet[2] = enabled as u8;
    packet[3] = invert as u8;
    write_f32_le(&mut packet, 4, gain);
    packet
}

/// Parse the combined status reply (REQ_GET_STATUS wValue 9):
/// peaks[num_channels] × u16, cpu0, cpu1, clip_flags u32, active inputs.
pub fn parse_status(data: &[u8], num_channels: usize) -> Option<SystemStatus> {
    let n = num_channels.min(MAX_CHANNELS);
    if data.len() < n * 2 + 6 {
        return None;
    }
    let mut status = SystemStatus {
        num_channels: n as u8,
        ..Default::default()
    };
    for i in 0..n {
        status.peaks[i] = read_u16_le(data, i * 2) as f32 / 32767.0;
    }
    let off = n * 2;
    status.cpu0 = data[off];
    status.cpu1 = data[off + 1];
    status.clip_flags = read_u32_le(data, off + 2);
    if data.len() > off + 6 {
        status.active_input_channels = data[off + 6];
    }
    Some(status)
}

/// Parse the REQ_GET_PLATFORM reply. Firmware before 1.1.6 sends 4 bytes with
/// minor/patch packed into nibbles; 1.1.6+ appends full-width minor, patch, beta.
pub fn parse_platform(data: &[u8]) -> Option<PlatformInfo> {
    if data.len() < 4 {
        return None;
    }
    let mut info = PlatformInfo {
        platform_id: data[0],
        fw_major: data[1],
        fw_minor: data[2] >> 4,
        fw_patch: data[2] & 0x0F,
        num_output_channels: data[3],
        fw_beta: 0,
    };
    if data.len() >= 6 {
        info.fw_minor = data[4];
        info.fw_patch = data[5];
    }
    if data.len() >= 7 {
        info.fw_beta = data[6];
    }
    Some(info)
}

/// Extract a NUL-terminated string from a fixed-size buffer.
pub fn name_from_bytes(buf: &[u8; CHANNEL_NAME_LEN]) -> String {
    let end = buf.iter().position(|&b| b == 0).unwrap_or(CHANNEL_NAME_LEN);
    String::from_utf8_lossy(&buf[..end]).into_owned()
}

/// Write a string into a fixed-size NUL-terminated buffer, truncating to 31
/// bytes on a UTF-8 character boundary.
pub fn name_to_bytes(name: &str) -> [u8; CHANNEL_NAME_LEN] {
    let mut buf = [0u8; CHANNEL_NAME_LEN];
    let mut len = name.len().min(CHANNEL_NAME_LEN - 1);
    while !name.is_char_boundary(len) {
        len -= 1;
    }
    buf[..len].copy_from_slice(&name.as_bytes()[..len]);
    buf
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v32_image() -> Vec<u8> {
        let mut d = vec![0u8; BULK_PARAMS_SIZE];
        d[0] = WIRE_FORMAT_VERSION;
        d[1] = 1; // RP2350
        d[2] = 17;
        d[3] = 9;
        d[4] = 8;
        d[5] = 12;
        write_u16_le(&mut d, 6, BULK_PARAMS_SIZE as u16);
        d
    }

    #[test]
    fn section_offsets_match_firmware_struct() {
        // Each offset = previous offset + previous section size (bulk_params.h).
        assert_eq!(OFF_CROSSPOINTS, OFF_DELAYS + 17 * 4);
        assert_eq!(OFF_OUTPUTS, OFF_CROSSPOINTS + 8 * 9 * 8);
        assert_eq!(OFF_EQ, OFF_PINS + 8);
        assert_eq!(OFF_CHANNEL_NAMES, OFF_EQ + 17 * 12 * 16);
        assert_eq!(OFF_CROSSOVER, OFF_DAC_HW_MUTE + 16);
        assert_eq!(OFF_ADAT, OFF_CROSSOVER + 17 * 4 * 16);
        assert_eq!(OFF_LIMITER + 9 * 12, BULK_PARAMS_SIZE);
    }

    #[test]
    fn eq_param_wvalue_uses_five_bit_band() {
        // ch=9, crossover band 22, param 1 (freq)
        assert_eq!(eq_param_wvalue(9, 22, 1), (9 << 8) | (22 << 3) | 1);
        assert_eq!(eq_param_wvalue(2, 3, 1), 0x0219);
    }

    #[test]
    fn bulk_round_trip_preserves_modeled_and_raw_sections() {
        let mut img = v32_image();
        // An unmodeled byte (tube section) must survive a round trip.
        img[OFF_TUBE + 1] = 3;
        let mut s = DspState::default();
        decode_bulk(&img, &mut s).unwrap();
        assert_eq!(s.num_input_channels, 8);

        s.preamp_db = -3.5;
        s.bypass = true;
        s.input_preamp_db[5] = -2.0;
        s.filters[9][0] = FilterParams {
            filter_type: FILTER_LINKWITZ_TRANSFORM,
            bypass: true,
            freq: 40.0,
            q: 1.2,
            gain: 25.0,
            qp: 0.5,
        };
        s.xover[10][2] = FilterParams { filter_type: 35, freq: 80.0, ..Default::default() };
        s.matrix_routing[7][8] = true;
        s.matrix_gain[7][8] = -6.0;
        s.limiter_threshold_db[4] = -1.5;
        s.channel_names[0] = name_to_bytes("USB L");

        let bytes = encode_bulk(&s);
        assert_eq!(bytes.len(), BULK_PARAMS_SIZE);
        assert_eq!(bytes[OFF_TUBE + 1], 3);

        let mut t = DspState::default();
        decode_bulk(&bytes, &mut t).unwrap();
        assert_eq!(t.preamp_db, -3.5);
        assert!(t.bypass);
        assert_eq!(t.input_preamp_db[5], -2.0);
        assert_eq!(t.filters[9][0], s.filters[9][0]);
        assert_eq!(t.filters[9][0].qp, 0.5);
        assert_eq!(t.xover[10][2].filter_type, 35);
        assert!(t.matrix_routing[7][8]);
        assert_eq!(t.matrix_gain[7][8], -6.0);
        assert_eq!(t.limiter_threshold_db[4], -1.5);
        assert_eq!(name_from_bytes(&t.channel_names[0]), "USB L");
    }

    #[test]
    fn old_wire_formats_are_rejected() {
        let mut img = v32_image();
        img[0] = 28;
        let mut s = DspState::default();
        assert_eq!(decode_bulk(&img, &mut s), Err(BulkError::UnsupportedVersion(28)));
        assert_eq!(decode_bulk(&img[..5944], &mut s), Err(BulkError::TooShort));
    }

    #[test]
    fn name_to_bytes_truncates_on_char_boundary() {
        let buf = name_to_bytes("This is a very long channel name that exceeds 31 characters");
        assert_eq!(buf[31], 0);
        assert_eq!(name_from_bytes(&buf).len(), 31);
        // 'é' is 2 bytes; 16 of them = 32 bytes, must cut to 30.
        let buf = name_to_bytes(&"é".repeat(16));
        assert_eq!(name_from_bytes(&buf), "é".repeat(15));
    }

    #[test]
    fn parse_status_rp2350() {
        let mut data = vec![0u8; 41];
        data[1] = 0x40; // ch0 peak 0x4000
        data[34] = 42;
        data[35] = 15;
        data[36] = 0x03;
        data[39] = 0x80; // bit 31
        data[40] = 6;
        let s = parse_status(&data, 17).unwrap();
        assert!((s.peaks[0] - 0.5).abs() < 0.001);
        assert_eq!((s.cpu0, s.cpu1), (42, 15));
        assert_eq!(s.clip_flags, 0x8000_0003);
        assert_eq!(s.active_input_channels, 6);
    }

    #[test]
    fn parse_platform_full_and_legacy() {
        let p = parse_platform(&[1, 1, 0x16, 9, 1, 6, 4]).unwrap();
        assert_eq!((p.platform_id, p.fw_major, p.fw_minor, p.fw_patch, p.fw_beta), (1, 1, 1, 6, 4));
        let p = parse_platform(&[0, 1, 0x15, 5]).unwrap();
        assert_eq!((p.fw_minor, p.fw_patch, p.num_output_channels), (1, 5, 5));
    }
}
