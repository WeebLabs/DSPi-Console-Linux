//! Interrupt Monitor: a log of the device's notification packets (bulk IN
//! EP 0x83), decoded into one line each in the macOS Console's format, with
//! PARAM_CHANGED named by its bulk-image offset. The notification listener
//! records every packet but the idle keep-alive, whether or not a window
//! shows the log; it keeps the last 2000.

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::protocol::*;

const LOG_LIMIT: usize = 2000;

pub struct MonitorEntry {
    pub id: u64,
    /// Host time, ms since the Unix epoch.
    pub time_ms: i64,
    pub text: String,
}

#[derive(Default)]
pub struct MonitorLog {
    inner: Mutex<(VecDeque<MonitorEntry>, u64)>,
}

impl MonitorLog {
    pub fn record(&self, packet: &[u8]) {
        let time_ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0);
        let text = decode(packet);
        let mut g = self.inner.lock().unwrap();
        g.1 += 1;
        let id = g.1;
        if g.0.len() >= LOG_LIMIT {
            g.0.pop_front();
        }
        g.0.push_back(MonitorEntry { id, time_ms, text });
    }

    pub fn clear(&self) {
        self.inner.lock().unwrap().0.clear();
    }

    /// Entries after `after_id`, oldest first, each `f`-ed; returns the last id.
    pub fn read_after(&self, after_id: u64, mut f: impl FnMut(&MonitorEntry)) -> u64 {
        let g = self.inner.lock().unwrap();
        for e in g.0.iter().filter(|e| e.id > after_id) {
            f(e);
        }
        g.1
    }
}

fn source_label(s: u8) -> String {
    match s {
        0 => "?".into(),
        1 => "HOST".into(),
        2 => "BULK".into(),
        3 => "PRESET".into(),
        4 => "FACTORY".into(),
        5 => "GPIO".into(),
        6 => "INTERNAL".into(),
        7 => "UAC1".into(),
        8 => "UART".into(),
        9 => "I2C".into(),
        _ => format!("src=0x{s:02X}"),
    }
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02X}")).collect::<Vec<_>>().join(" ")
}

fn le_f32(b: &[u8]) -> Option<f32> {
    (b.len() >= 4).then(|| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

fn le_u32(b: &[u8], at: usize) -> u32 {
    if b.len() < at + 4 { 0 } else { u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]]) }
}

/// One packet as a log line (without the timestamp).
pub fn decode(b: &[u8]) -> String {
    let Some(&first) = b.first() else { return "(empty)".into() };
    if first == 0 && b.len() <= 1 {
        return "Idle".into();
    }
    if first == 0x02 && b.len() >= 4 {
        return decode_v2(b);
    }
    // v1: byte 0 is the event
    if first == 0x01 {
        return match le_f32(&b[4.min(b.len())..]) {
            Some(db) => format!("{:<14}  {}", "v1.MasterVolume", volume(db)),
            None => format!("{:<14}  (short: {} bytes)", "v1.MasterVolume", b.len()),
        };
    }
    format!("{:<14}  {}", format!("v1?evt=0x{first:02X}"), hex(b))
}

fn volume(db: f32) -> String {
    if db <= -128.0 { "MUTE".into() } else { format!("{db:+7.2} dB") }
}

fn decode_v2(b: &[u8]) -> String {
    let evt = b[1];
    let seq = format!("[{:3}]", b[3]);
    let short = |name: &str| format!("{seq} v2.{name} (short: {} bytes)", b.len());
    match evt {
        0x02 => {
            if b.len() < 12 {
                return short("ParamChanged");
            }
            let off = u16::from_le_bytes([b[4], b[5]]) as usize;
            let size = u16::from_le_bytes([b[6], b[7]]) as usize;
            let payload = &b[12..(12 + size).min(b.len())];
            let (name, value) = param(off, size, payload);
            format!("{seq} [{:<8}] {:<32}  {}", source_label(b[8]), name, value)
        }
        0x03 => format!("{seq} v2.BulkInvalidated            source={}", source_label(*b.get(4).unwrap_or(&0))),
        0x04 => format!("{seq} v2.PresetLoaded                slot={}", b.get(4).unwrap_or(&0)),
        0x05 => format!("{seq} v2.InputFormat                 channels={}", b.get(4).unwrap_or(&0)),
        0x07 => {
            if b.len() < 8 {
                return short("SiggenState");
            }
            let state = ["IDLE", "FADE_IN", "RUN", "GAP", "FADE_OUT"].get(b[4] as usize).map(|s| s.to_string()).unwrap_or(format!("state={}", b[4]));
            let reason = ["-", "HOST", "COMPLETED", "PRESET", "RECONFIG"].get(b[5] as usize).map(|s| s.to_string()).unwrap_or(format!("reason={}", b[5]));
            let ch = if b[7] == 0xFF { "-".to_string() } else { b[7].to_string() };
            format!("{seq} v2.SiggenState                 {state} reason={reason} type={} ch={ch}", b[6])
        }
        0x08 => {
            if b.len() < 8 {
                return short("AdatState");
            }
            format!("{seq} v2.AdatState                   enabled={} active={} pin={}", b[4], b[5], b[6])
        }
        0x09 => {
            if b.len() < 9 {
                return short("I2sSlaveState");
            }
            let state = ["INACTIVE", "ACQUIRING", "RELOCKING", "LOCKED"].get(b[4] as usize).map(|s| s.to_string()).unwrap_or(format!("state={}", b[4]));
            format!("{seq} v2.I2sSlaveState              {state} rate={}", le_u32(b, 5))
        }
        0x0A => {
            if b.len() < 12 {
                return short("IrLearn");
            }
            let proto = ["NONE", "NEC", "RC5", "RC6", "HASH"].get(b[5] as usize).copied().unwrap_or("?");
            if b[4] == 2 {
                format!("{seq} v2.IrLearn                     DONE {proto} code=0x{:08X}", le_u32(b, 8))
            } else {
                format!("{seq} v2.IrLearn                     TIMEOUT")
            }
        }
        0x0B => {
            if b.len() < 10 {
                return short("AdatInputState");
            }
            let state = ["INACTIVE", "ACQUIRING", "SYNCING", "LOCKED", "RELOCKING"].get(b[4] as usize).map(|s| s.to_string()).unwrap_or(format!("state={}", b[4]));
            let mode = if b[9] == 1 { "slave" } else { "master" };
            format!("{seq} v2.AdatInputState             {state} rate={} mode={mode}", le_u32(b, 5))
        }
        0x0C => {
            if b.len() < 9 {
                return short("CsAux");
            }
            let q8 = u16::from_le_bytes([b[6], b[7]]) as f32 / 256.0;
            format!("{seq} v2.CsAux                      slot={} state={} level={q8:.1}% src={}", b[4], b[5], source_label(b[8]))
        }
        _ => format!("{seq} v2?evt=0x{evt:02X}  {}", hex(&b[4..])),
    }
}

fn f(p: &[u8], suffix: &str) -> String {
    match le_f32(p) {
        Some(v) => format!("{v:+.3}{suffix}"),
        None => "(short)".into(),
    }
}
fn flag(p: &[u8]) -> String {
    match p.first() {
        Some(0) => "0 (false)".into(),
        Some(_) => "1 (true)".into(),
        None => "(empty)".into(),
    }
}
fn byte(p: &[u8]) -> String {
    p.first().map(|v| v.to_string()).unwrap_or("(empty)".into())
}
fn band(p: &[u8]) -> String {
    if p.len() < 16 {
        return hex(p);
    }
    let fl = |o: usize| f32::from_le_bytes([p[o], p[o + 1], p[o + 2], p[o + 3]]);
    format!("type={}  byp={}  f={:.1} Hz  Q={:.2}  g={:+.2} dB", p[0], p[1], fl(4), fl(8), fl(12))
}

/// A bulk-image offset's field name and its value, formatted by type.
fn param(off: usize, size: usize, p: &[u8]) -> (String, String) {
    let n = |s: &str| s.to_string();
    if off < OFF_GLOBAL {
        return (format!("header+0x{off:02X}"), hex(p));
    }
    match off {
        16 => return (n("global.preamp_gain_db"), f(p, " dB")),
        20 => return (n("global.bypass"), flag(p)),
        21 => return (n("global.loudness_enabled"), flag(p)),
        22 => return (n("global.loudness_output_mask"), hex(p)),
        24 => return (n("global.loudness_ref_spl"), f(p, " dB SPL")),
        28 => return (n("global.loudness_intensity_pct"), f(p, "%")),
        32 => return (n("crossfeed.enabled"), flag(p)),
        33 => return (n("crossfeed.preset"), byte(p)),
        34 => return (n("crossfeed.itd_enabled"), flag(p)),
        36 => return (n("crossfeed.custom_fc"), f(p, " Hz")),
        40 => return (n("crossfeed.custom_feed_db"), f(p, " dB")),
        _ => {}
    }
    if (OFF_LEGACY..OFF_LEGACY + 12).contains(&off) && (off - OFF_LEGACY) % 4 == 0 && size == 4 {
        return (format!("legacy.gain_db[{}]", (off - OFF_LEGACY) / 4), f(p, " dB"));
    }
    if (OFF_LEGACY + 12..OFF_LEGACY + 15).contains(&off) && size == 1 {
        return (format!("legacy.mute[{}]", off - OFF_LEGACY - 12), flag(p));
    }
    if (OFF_DELAYS..OFF_DELAYS + 17 * 4).contains(&off) && (off - OFF_DELAYS) % 4 == 0 && size == 4 {
        return (format!("delays.delay_ms[{}]", (off - OFF_DELAYS) / 4), f(p, " ms"));
    }
    if (OFF_CROSSPOINTS..OFF_OUTPUTS).contains(&off) {
        let rel = off - OFF_CROSSPOINTS;
        let (input, output, sub) = (rel / 8 / 9, rel / 8 % 9, rel % 8);
        if sub == 0 && size == 8 && p.len() >= 8 {
            let g = f32::from_le_bytes([p[4], p[5], p[6], p[7]]);
            return (format!("crosspoints[{input}][{output}]"), format!("en={} inv={} {g:+6.2} dB", (p[0] != 0) as u8, (p[1] != 0) as u8));
        }
        return (format!("crosspoints[{input}][{output}]+0x{sub:X}"), hex(p));
    }
    if (OFF_OUTPUTS..OFF_PINS).contains(&off) {
        let rel = off - OFF_OUTPUTS;
        let (i, sub) = (rel / 12, rel % 12);
        return match sub {
            0 => (format!("outputs[{i}].enabled"), flag(p)),
            1 => (format!("outputs[{i}].mute"), flag(p)),
            4 => (format!("outputs[{i}].gain_db"), f(p, " dB")),
            8 => (format!("outputs[{i}].delay_ms"), f(p, " ms")),
            _ => (format!("outputs[{i}]+0x{sub:X}"), hex(p)),
        };
    }
    if off == OFF_PINS && size == 1 {
        return (n("pins.num_pin_outputs"), byte(p));
    }
    if (OFF_PINS + 1..OFF_PINS + 6).contains(&off) && size == 1 {
        return (format!("pins.pins[{}]", off - OFF_PINS - 1), byte(p));
    }
    if (OFF_EQ..OFF_CHANNEL_NAMES).contains(&off) {
        let rel = off - OFF_EQ;
        let (ch, b, sub) = (rel / 16 / 12, rel / 16 % 12, rel % 16);
        if sub == 0 && size == 16 {
            return (format!("eq[{ch}][{b}]"), band(p));
        }
        return (format!("eq[{ch}][{b}]+0x{sub:X}"), hex(p));
    }
    if (OFF_CHANNEL_NAMES..OFF_I2S).contains(&off) && (off - OFF_CHANNEL_NAMES) % 32 == 0 {
        let end = p.iter().position(|&c| c == 0).unwrap_or(p.len());
        return (format!("channel_names[{}]", (off - OFF_CHANNEL_NAMES) / 32), format!("\"{}\"", String::from_utf8_lossy(&p[..end])));
    }
    if (OFF_I2S..OFF_I2S + 4).contains(&off) && size == 1 {
        let v = p.first().copied().unwrap_or(0);
        return (format!("i2s_config.output_types[{}]", off - OFF_I2S), format!("{v} ({})", if v == 1 { "I2S" } else { "SPDIF" }));
    }
    match off.wrapping_sub(OFF_I2S) {
        4 => return (n("i2s_config.bck_pin"), byte(p)),
        5 => return (n("i2s_config.mck_pin"), byte(p)),
        6 => return (n("i2s_config.mck_enabled"), flag(p)),
        7 => {
            let v = p.first().copied().unwrap_or(0);
            return (n("i2s_config.mck_multiplier"), format!("{v} ({})", if v == 1 { "256x" } else { "128x" }));
        }
        _ => {}
    }
    match off.wrapping_sub(OFF_LEVELLER) {
        0 => return (n("leveller.enabled"), flag(p)),
        1 => return (n("leveller.speed"), byte(p)),
        2 => return (n("leveller.lookahead"), flag(p)),
        4 => return (n("leveller.amount"), f(p, "%")),
        8 => return (n("leveller.max_gain_db"), f(p, " dB")),
        12 => return (n("leveller.gate_threshold_db"), f(p, " dB")),
        16 => return (n("leveller.detector_mask"), hex(p)),
        17 => return (n("leveller.apply_mask"), hex(p)),
        _ => {}
    }
    if (OFF_PREAMP..OFF_PREAMP + 32).contains(&off) && (off - OFF_PREAMP) % 4 == 0 && size == 4 {
        return (format!("preamp.preamp_db[{}]", (off - OFF_PREAMP) / 4), f(p, " dB"));
    }
    if off == OFF_MASTER_VOLUME && size == 4 {
        return (n("master_volume.master_volume_db"), le_f32(p).map(volume).unwrap_or(hex(p)));
    }
    if off == OFF_INPUT_CONFIG && size == 1 {
        let v = p.first().copied().unwrap_or(0);
        let name = ["USB", "SPDIF", "I2S", "ADAT", "SPDIF2", "SPDIF3", "SPDIF4"].get(v as usize).copied().unwrap_or("?");
        return (n("input_config.input_source"), format!("{v} ({name})"));
    }
    if (OFF_INPUT_CONFIG + 1..OFF_INPUT_CONFIG + 16).contains(&off) && size == 1 {
        let k = off - OFF_INPUT_CONFIG;
        let v = p.first().copied().unwrap_or(0);
        let name = match k {
            1 => "input_config.spdif_rx_pin".to_string(),
            2 => "input_config.i2s_rx_pin".to_string(),
            3 => return (n("input_config.i2s_input_rate"), format!("{v} ({} Hz)", ["44100", "48000", "96000"].get(v as usize).copied().unwrap_or("?"))),
            4 => "input_config.i2s_input_channels".to_string(),
            5..=7 => format!("input_config.i2s_rx_pin_ext[{}]", k - 5),
            8..=10 => format!("input_config.spdif_rx_pin_ext[{}]", k - 8),
            11 => "input_config.spdif_ext_enable_p1".to_string(),
            12 => "input_config.i2s_clock_mode".to_string(),
            13 => return (n("input_config.adat_input_pin"), if v == 0 { "unset".into() } else { format!("GPIO {v}") }),
            14 => return (n("input_config.adat_input_enabled_p1"), format!("{v} ({})", match v { 0 => "absent", 2 => "enabled", _ => "disabled" })),
            _ => return (n("input_config.adat_clock_mode_p1"), format!("{v} ({})", match v { 0 => "absent", 2 => "slave", _ => "master" })),
        };
        return (name, v.to_string());
    }
    match off.wrapping_sub(OFF_LG_SOUND_SYNC) {
        0 if size == 1 => return (n("lg_sound_sync.enabled"), flag(p)),
        1 if size == 1 => return (n("lg_sound_sync.present"), flag(p)),
        2 if size == 1 => {
            let v = p.first().copied().unwrap_or(0xFF);
            return (n("lg_sound_sync.volume"), if v == 0xFF { "-".into() } else { format!("{v} / 100") });
        }
        3 if size == 1 => return (n("lg_sound_sync.muted"), flag(p)),
        _ => {}
    }
    if off == OFF_USER_VOLUME && size == 4 {
        return (n("user_volume.user_volume_db"), le_f32(p).map(volume).unwrap_or(hex(p)));
    }
    if off == OFF_USER_VOLUME + 4 && size == 1 {
        return (n("user_volume.user_mute"), flag(p));
    }
    match off.wrapping_sub(OFF_DAC_HW_MUTE) {
        0 => return (n("dac_mute.enabled"), flag(p)),
        1 => return (n("dac_mute.active_low"), flag(p)),
        2 => return (n("dac_mute.pin"), byte(p)),
        4 if p.len() >= 2 => return (n("dac_mute.hold_ms"), format!("{} ms", u16::from_le_bytes([p[0], p[1]]))),
        6 if p.len() >= 2 => return (n("dac_mute.release_ms"), format!("{} ms", u16::from_le_bytes([p[0], p[1]]))),
        _ => {}
    }
    if (OFF_CROSSOVER..OFF_ADAT).contains(&off) {
        let rel = off - OFF_CROSSOVER;
        let (ch, b, sub) = (rel / 16 / 4, rel / 16 % 4, rel % 16);
        if sub == 0 && size == 16 {
            return (format!("xover[{ch}][{b}]"), band(p));
        }
        return (format!("xover[{ch}][{b}]+0x{sub:X}"), hex(p));
    }
    if off == OFF_ADAT && size == 1 {
        return (n("adat_config.enabled"), flag(p));
    }
    if off == OFF_ADAT + 1 && size == 1 {
        let v = p.first().copied().unwrap_or(0);
        return (n("adat_config.pin"), if v == 0 { "default".into() } else { format!("GPIO {v}") });
    }
    match off.wrapping_sub(OFF_PSYBASS) {
        0 => return (n("psybass.enabled"), flag(p)),
        2 => return (n("psybass.output_mask"), hex(p)),
        4 => return (n("psybass.cutoff_hz"), f(p, " Hz")),
        8 => return (n("psybass.harmonics_db"), f(p, " dB")),
        12 => return (n("psybass.drive_db"), f(p, " dB")),
        16 => return (n("psybass.character_pct"), f(p, "%")),
        20 => return (n("psybass.original_db"), f(p, " dB")),
        _ => {}
    }
    if (OFF_UPMIX..OFF_SUBHARM).contains(&off) {
        let k = off - OFF_UPMIX;
        return match k {
            0 => (n("upmix.enabled"), flag(p)),
            1 => (n("upmix.engine"), byte(p)),
            2 => (n("upmix.mode"), byte(p)),
            3 => (n("upmix.center_trim_halfdb"), p.first().map(|&v| format!("{:+.1} dB", (v as i8) as f32 * 0.5)).unwrap_or_default()),
            _ if k >= 4 && (k - 4) % 4 == 0 => (format!("upmix.param[{}]", (k - 4) / 4 + 3), f(p, "")),
            _ => (format!("upmix+0x{k:X}"), hex(p)),
        };
    }
    match off.wrapping_sub(OFF_SUBHARM) {
        0 => return (n("subharm.enabled"), flag(p)),
        2 => return (n("subharm.output_mask"), hex(p)),
        4 => return (n("subharm.low_db"), f(p, " dB")),
        8 => return (n("subharm.high_db"), f(p, " dB")),
        12 => return (n("subharm.boost_db"), f(p, " dB")),
        16 => return (n("subharm.top_db"), f(p, " dB")),
        20 => return (n("subharm.select_depth"), f(p, "%")),
        24 => return (n("subharm.select_hold_ms"), f(p, " ms")),
        28 => return (n("subharm.ceiling_db"), f(p, " dBFS")),
        32 => return (n("subharm.select_mode"), hex(p)),
        33 => return (n("subharm.link_pairs"), flag(p)),
        _ => {}
    }
    match off.wrapping_sub(OFF_TUBE) {
        0 => return (n("tube.enabled"), flag(p)),
        1 => return (n("tube.tube_type"), byte(p)),
        2 => return (n("tube.rectifier"), byte(p)),
        3 => return (n("tube.xfmr_enabled"), flag(p)),
        4 => return (n("tube.output_mask"), hex(p)),
        8 => return (n("tube.drive_db"), f(p, " dB")),
        12 => return (n("tube.bias_pct"), f(p, "%")),
        16 => return (n("tube.asym_db"), f(p, " dB")),
        20 => return (n("tube.hardness_pct"), f(p, "%")),
        24 => return (n("tube.sag_pct"), f(p, "%")),
        28 => return (n("tube.xfmr_damping"), f(p, "")),
        32 => return (n("tube.xfmr_res_hz"), f(p, " Hz")),
        36 => return (n("tube.mix_pct"), f(p, "%")),
        40 => return (n("tube.trim_db"), f(p, " dB")),
        _ => {}
    }
    if (OFF_LIMITER..BULK_PARAMS_SIZE).contains(&off) {
        let rel = off - OFF_LIMITER;
        let o = rel / 12;
        return match rel % 12 {
            0 => (format!("limiter[{o}].enabled"), flag(p)),
            1 => (format!("limiter[{o}].link_group"), p.first().map(|&v| if v == 0 { "off".into() } else { format!("group {v}") }).unwrap_or_default()),
            4 => (format!("limiter[{o}].threshold_db"), f(p, " dBFS")),
            8 => (format!("limiter[{o}].release_ms"), f(p, " ms")),
            s => (format!("limiter[{o}]+0x{s:X}"), hex(p)),
        };
    }
    (format!("offset=0x{off:04X} size={size}"), hex(p))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn param_packet(off: u16, src: u8, payload: &[u8]) -> Vec<u8> {
        let mut b = vec![2, 2, 0, 7];
        b.extend_from_slice(&off.to_le_bytes());
        b.extend_from_slice(&(payload.len() as u16).to_le_bytes());
        b.extend_from_slice(&[src, 0, 0, 0]);
        b.extend_from_slice(payload);
        b
    }

    #[test]
    fn param_changes_are_named() {
        let line = decode(&param_packet(OFF_MASTER_VOLUME as u16, 7, &(-12.5f32).to_le_bytes()));
        assert!(line.starts_with("[  7] [UAC1    ] master_volume.master_volume_db"), "{line}");
        assert!(line.ends_with(" -12.50 dB"), "{line}");
        let gain = decode(&param_packet((OFF_OUTPUTS + 12 * 2 + 4) as u16, 1, &3.0f32.to_le_bytes()));
        assert!(gain.contains("outputs[2].gain_db") && gain.ends_with("+3.000 dB"), "{gain}");
        let mut band = [0u8; 16];
        band[0] = 1;
        band[4..8].copy_from_slice(&1000.0f32.to_le_bytes());
        band[8..12].copy_from_slice(&0.7f32.to_le_bytes());
        band[12..16].copy_from_slice(&(-3.0f32).to_le_bytes());
        let eq = decode(&param_packet((OFF_EQ + (12 * 3 + 2) * 16) as u16, 5, &band));
        assert!(eq.contains("eq[3][2]") && eq.contains("f=1000.0 Hz") && eq.contains("g=-3.00 dB"), "{eq}");
    }

    #[test]
    fn events_and_fallbacks() {
        assert_eq!(decode(&[0]), "Idle");
        assert!(decode(&[2, 7, 0, 9, 2, 0, 4, 0xFF]).contains("v2.SiggenState                 RUN reason=- type=4 ch=-"));
        assert!(decode(&[2, 4, 0, 1, 3, 0, 0, 0]).ends_with("slot=3"));
        assert!(decode(&[2, 0x0E, 0, 1, 0xAB]).contains("v2?evt=0x0E  AB"));
        let v1 = decode(&[1, 0, 0, 0, 0, 0, 0x20, 0xC1]);
        assert!(v1.starts_with("v1.MasterVolume") && v1.ends_with("-10.00 dB"), "{v1}");
    }
}
