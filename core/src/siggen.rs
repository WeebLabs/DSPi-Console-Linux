//! Onboard signal generator (firmware siggen, config version 1).
//!
//! The device renders test signals after the matrix mixer, before each
//! output's crossover/PEQ (skipped with RAW), delay, trim and volume. Its
//! state is transient: never saved, stopped by a preset load or factory
//! reset, and it keeps running when the host goes away. The firmware ACKs
//! every SET_CONFIG on USB, even one it rejects, so a write is checked by
//! reading the config back. NOTIFY 0x07 reports starts and stops; fades,
//! gaps and walk steps are only visible by polling the status.

use crate::protocol::*;
use crate::usb::{Result, UsbError};
use crate::DspiCore;

pub const SIGGEN_VERSION: u8 = 1;
pub const SIGGEN_TYPE_COUNT: usize = 15;
const CONFIG_SIZE: usize = 36;
const STATUS_SIZE: usize = 16;
const CAPS_HEADER_SIZE: usize = 8;
const TYPE_DESC_SIZE: usize = 62;

pub const SIGGEN_FLAG_RAW: u8 = 0x01;
pub const SIGGEN_FLAG_DECORR: u8 = 0x02;
pub const SIGGEN_FLAG_WALK: u8 = 0x04;

/// CONTROL actions.
pub const SIGGEN_CTL_STOP: u16 = 0;
pub const SIGGEN_CTL_START: u16 = 1;
pub const SIGGEN_CTL_STOP_NOW: u16 = 2;

/// One signal's settings. `p` holds the type's parameters (see the caps).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SiggenConfig {
    pub signal_type: u8,
    /// Bit i = output i.
    pub channel_mask: u16,
    /// Polarity-inverted subset of channel_mask.
    pub invert_mask: u16,
    /// SIGGEN_FLAG_*.
    pub flags: u8,
    /// Peak level, dBFS (-120..0).
    pub level_db: f32,
    /// Continuous: play time (0 = forever), or per-output dwell when walking;
    /// sweep: one sweep. Unused by patterns.
    pub duration_ms: u32,
    /// Sweeps, pattern periods or walk passes (0 = forever).
    pub repeat: u16,
    pub gap_ms: u16,
    pub p: [f32; 4],
}

impl SiggenConfig {
    pub fn encode(&self) -> [u8; CONFIG_SIZE] {
        let mut b = [0u8; CONFIG_SIZE];
        b[0] = SIGGEN_VERSION;
        b[1] = self.signal_type;
        b[2..4].copy_from_slice(&self.channel_mask.to_le_bytes());
        b[4..6].copy_from_slice(&self.invert_mask.to_le_bytes());
        b[6] = self.flags;
        b[8..12].copy_from_slice(&self.level_db.to_le_bytes());
        b[12..16].copy_from_slice(&self.duration_ms.to_le_bytes());
        b[16..18].copy_from_slice(&self.repeat.to_le_bytes());
        b[18..20].copy_from_slice(&self.gap_ms.to_le_bytes());
        for (i, v) in self.p.iter().enumerate() {
            b[20 + 4 * i..24 + 4 * i].copy_from_slice(&v.to_le_bytes());
        }
        b
    }

    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < CONFIG_SIZE || b[0] != SIGGEN_VERSION {
            return None;
        }
        let mut p = [0f32; 4];
        for (i, v) in p.iter_mut().enumerate() {
            *v = read_f32_le(b, 20 + 4 * i);
        }
        Some(Self {
            signal_type: b[1],
            channel_mask: read_u16_le(b, 2),
            invert_mask: read_u16_le(b, 4),
            flags: b[6],
            level_db: read_f32_le(b, 8),
            duration_ms: read_u32_le(b, 12),
            repeat: read_u16_le(b, 16),
            gap_ms: read_u16_le(b, 18),
            p,
        })
    }
}

/// What the generator is doing.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SiggenStatus {
    /// 0 idle, 1 fading in, 2 running, 3 gap, 4 fading out.
    pub state: u8,
    pub signal_type: u8,
    /// Output being played when walking, else 0xFF.
    pub active_channel: u8,
    pub elapsed_ms: u32,
    pub cycles_done: u16,
    /// Of the last stop: 0 none, 1 host, 2 completed, 3 preset load, 4 reconfigured.
    pub stop_reason: u8,
    /// Sweep frequency now, else 0.
    pub current_freq: f32,
}

impl SiggenStatus {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < STATUS_SIZE || b[0] != SIGGEN_VERSION {
            return None;
        }
        Some(Self {
            state: b[1],
            signal_type: b[2],
            active_channel: b[3],
            elapsed_ms: read_u32_le(b, 4),
            cycles_done: read_u16_le(b, 8),
            stop_reason: b[10],
            current_freq: read_f32_le(b, 12),
        })
    }
}

/// One parameter of a signal type.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SiggenParam {
    /// 0 unused, 1 Hz, 2 ms, 3 cycles, 4 count, 5 ratio, 6 pattern.
    pub semantic: u8,
    pub min: f32,
    pub max: f32,
    pub def: f32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SiggenTypeInfo {
    pub id: u8,
    /// Short firmware name, NUL-terminated.
    pub name: [u8; 9],
    /// 0 continuous, 1 sweep, 2 pattern.
    pub timing: u8,
    pub params: [SiggenParam; 4],
}

impl SiggenTypeInfo {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < TYPE_DESC_SIZE {
            return None;
        }
        let mut name = [0u8; 9];
        name[..8].copy_from_slice(&b[1..9]);
        let mut params = [SiggenParam::default(); 4];
        for (k, p) in params.iter_mut().enumerate() {
            // 13-byte records: the floats are unaligned
            let o = 10 + 13 * k;
            *p = SiggenParam {
                semantic: b[o],
                min: read_f32_le(b, o + 1),
                max: read_f32_le(b, o + 5),
                def: read_f32_le(b, o + 9),
            };
        }
        Some(Self { id: b[0], name, timing: b[9], params })
    }
}

/// The generator on this device. `supported` false without one.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SiggenCaps {
    pub supported: bool,
    pub type_count: u8,
    pub output_channels: u8,
    pub multitone_max: u8,
    pub valid_mask: u16,
    pub types: [SiggenTypeInfo; SIGGEN_TYPE_COUNT],
}

impl DspiCore {
    /// Read the caps header and every type's descriptor. Ok with
    /// `supported` false when the firmware has no generator.
    pub fn fetch_siggen_caps(&self) -> Result<SiggenCaps> {
        let mut caps = SiggenCaps::default();
        let header = match self.get(REQ_SIGGEN_GET_CAPS, 0xFFFF, WINDEX_OUTPUT, CAPS_HEADER_SIZE as u16) {
            Ok(b) if b.len() >= CAPS_HEADER_SIZE && b[0] == SIGGEN_VERSION => b,
            Ok(_) | Err(UsbError::Rusb(rusb::Error::Pipe)) => return Ok(caps),
            Err(e) => return Err(e),
        };
        caps.type_count = header[1].min(SIGGEN_TYPE_COUNT as u8);
        caps.output_channels = header[2];
        caps.multitone_max = header[3];
        caps.valid_mask = read_u16_le(&header, 4);
        for t in 0..caps.type_count {
            // A descriptor that can't be read is marked (id 0xFF), and the
            // host uses its own table for that type
            caps.types[t as usize].id = 0xFF;
            let read = self.get_exact(REQ_SIGGEN_GET_CAPS, t as u16, WINDEX_OUTPUT, TYPE_DESC_SIZE as u16, TYPE_DESC_SIZE);
            if let Some(info) = read.ok().and_then(|b| SiggenTypeInfo::parse(&b)) {
                caps.types[t as usize] = info;
            }
        }
        caps.supported = true;
        Ok(caps)
    }

    /// The config the generator runs (or last ran).
    pub fn fetch_siggen_config(&self) -> Result<SiggenConfig> {
        let b = self.get_exact(REQ_SIGGEN_GET_CONFIG, 0, WINDEX_OUTPUT, CONFIG_SIZE as u16, CONFIG_SIZE)?;
        SiggenConfig::parse(&b).ok_or(UsbError::InvalidArgument)
    }

    /// Stage a config (a running generator restarts with it, fading).
    pub fn set_siggen_config(&self, cfg: &SiggenConfig) -> Result<()> {
        self.send(REQ_SIGGEN_SET_CONFIG, 0, WINDEX_OUTPUT, &cfg.encode())
    }

    /// SIGGEN_CTL_*: STOP fades out, STOP_NOW cuts, START plays the staged
    /// config. Err on a refusal (START without a valid config).
    pub fn siggen_control(&self, action: u16) -> Result<()> {
        let b = self.get_exact(REQ_SIGGEN_CONTROL, action, WINDEX_OUTPUT, 1, 1)?;
        if b[0] == 1 { Ok(()) } else { Err(UsbError::InvalidArgument) }
    }

    pub fn fetch_siggen_status(&self) -> Result<SiggenStatus> {
        let b = self.get_exact(REQ_SIGGEN_GET_STATUS, 0, WINDEX_OUTPUT, STATUS_SIZE as u16, STATUS_SIZE)?;
        SiggenStatus::parse(&b).ok_or(UsbError::InvalidArgument)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_round_trip() {
        let c = SiggenConfig {
            signal_type: 6,
            channel_mask: 0x0003,
            invert_mask: 0x0002,
            flags: SIGGEN_FLAG_RAW | SIGGEN_FLAG_WALK,
            level_db: -20.0,
            duration_ms: 5000,
            repeat: 2,
            gap_ms: 250,
            p: [20.0, 20000.0, 3.0, 250.0],
        };
        let b = c.encode();
        assert_eq!(b[0], 1);
        assert_eq!(&b[2..8], &[3, 0, 2, 0, 5, 0]);
        assert_eq!(&b[8..12], &(-20.0f32).to_le_bytes());
        assert_eq!(&b[32..36], &250.0f32.to_le_bytes());
        assert_eq!(SiggenConfig::parse(&b), Some(c));
        let mut v2 = b;
        v2[0] = 2;
        assert_eq!(SiggenConfig::parse(&v2), None);
    }

    #[test]
    fn status_layout() {
        let mut b = [0u8; 16];
        b[..4].copy_from_slice(&[1, 2, 4, 0xFF]);
        b[4..8].copy_from_slice(&1500u32.to_le_bytes());
        b[8..10].copy_from_slice(&3u16.to_le_bytes());
        b[10] = 2;
        b[12..16].copy_from_slice(&440.0f32.to_le_bytes());
        let s = SiggenStatus::parse(&b).unwrap();
        assert_eq!((s.state, s.signal_type, s.active_channel, s.elapsed_ms, s.cycles_done, s.stop_reason), (2, 4, 0xFF, 1500, 3, 2));
        assert_eq!(s.current_freq, 440.0);
    }

    #[test]
    fn type_descriptor_has_unaligned_floats() {
        let mut b = [0u8; 62];
        b[0] = 10;
        b[1..6].copy_from_slice(b"burst");
        b[9] = 2;
        for (k, (sem, min, max, def)) in [(1u8, 10.0f32, 40000.0f32, 1000.0f32), (3, 1.0, 1000.0, 8.0)].iter().enumerate() {
            let o = 10 + 13 * k;
            b[o] = *sem;
            b[o + 1..o + 5].copy_from_slice(&min.to_le_bytes());
            b[o + 5..o + 9].copy_from_slice(&max.to_le_bytes());
            b[o + 9..o + 13].copy_from_slice(&def.to_le_bytes());
        }
        let t = SiggenTypeInfo::parse(&b).unwrap();
        assert_eq!((t.id, t.timing, &t.name[..6]), (10, 2, &b"burst\0"[..]));
        assert_eq!(t.params[0], SiggenParam { semantic: 1, min: 10.0, max: 40000.0, def: 1000.0 });
        assert_eq!(t.params[1].def, 8.0);
        assert_eq!(t.params[2].semantic, 0);
    }
}
