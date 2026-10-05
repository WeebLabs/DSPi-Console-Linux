//! Device configuration files (`.dspipreset`): the JSON document the macOS
//! and Windows Consoles share (schema 1). It covers what a preset slot
//! covers: EQ and crossovers, delays, gains, routing, the DSP features and,
//! in its own block, the board's wiring. Values are stored raw, as the
//! firmware holds them, and every field is read leniently (a missing or
//! mistyped field takes its default), so files from either Console and from
//! older builds load.
//!
//! Channels carry the Windows Console's channel id and, additively, the
//! input / output index; the index wins when present.
//!
//! Import builds the new state and writes it in one bulk SET. Volumes and the
//! hardware I/O are applied only when the user asks; the I/O fields that
//! changed are also sent one by one, since the firmware's bulk SET leaves
//! pins and limiters alone when the output config is device-global.

use serde_json::{json, Map, Value};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::protocol::*;
use crate::state::DspState;
use crate::types::*;
use crate::usb::Result;
use crate::DspiCore;

pub const SCHEMA_VERSION: i64 = 1;

/// Windows Console channel ids: inputs 0-1 and 11-16, outputs from 2, and
/// the RP2350 PDM output at 10.
const EXTRA_INPUT_BASE: i64 = 11;
const OUTPUT_BASE: i64 = 2;
const PDM_ID_RP2350: i64 = 10;

fn platform_name(id: u8) -> &'static str {
    if id == 1 { "RP2350" } else { "RP2040" }
}

fn id_for_input(i: usize) -> i64 {
    if i < 2 { i as i64 } else { EXTRA_INPUT_BASE + (i as i64 - 2) }
}

fn id_for_output(o: usize, outputs: usize, rp2350: bool) -> i64 {
    if rp2350 && o + 1 == outputs { PDM_ID_RP2350 } else { OUTPUT_BASE + o as i64 }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ChannelRef {
    Input(usize),
    Output(usize),
}

fn ref_for_id(id: i64, outputs: usize, rp2350: bool) -> Option<ChannelRef> {
    if (0..2).contains(&id) {
        return Some(ChannelRef::Input(id as usize));
    }
    if (EXTRA_INPUT_BASE..EXTRA_INPUT_BASE + (MAX_INPUTS as i64 - 2)).contains(&id) {
        return Some(ChannelRef::Input(2 + (id - EXTRA_INPUT_BASE) as usize));
    }
    if rp2350 && id == PDM_ID_RP2350 {
        return Some(ChannelRef::Output(outputs - 1));
    }
    let o = id - OUTPUT_BASE;
    (o >= 0 && (o as usize) < outputs).then_some(ChannelRef::Output(o as usize))
}

// ── Lenient reading ──

fn num(v: &Value, key: &str, def: f64) -> f64 {
    v.get(key).and_then(Value::as_f64).unwrap_or(def)
}
fn f(v: &Value, key: &str, def: f32) -> f32 {
    num(v, key, def as f64) as f32
}
fn int(v: &Value, key: &str, def: i64) -> i64 {
    v.get(key).and_then(|x| x.as_i64().or_else(|| x.as_f64().map(|f| f as i64))).unwrap_or(def)
}
fn flag(v: &Value, key: &str, def: bool) -> bool {
    v.get(key).and_then(Value::as_bool).unwrap_or(def)
}
fn text(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(Value::as_str).map(str::to_string)
}
fn ints(v: &Value, key: &str) -> Option<Vec<i64>> {
    v.get(key).and_then(Value::as_array).map(|a| a.iter().map(|x| x.as_i64().or_else(|| x.as_f64().map(|f| f as i64)).unwrap_or(0)).collect())
}
fn floats(v: &Value, key: &str) -> Option<Vec<f32>> {
    v.get(key).and_then(Value::as_array).map(|a| a.iter().map(|x| x.as_f64().unwrap_or(0.0) as f32).collect())
}
/// A block that is an object (missing / null / wrong type = None).
fn block<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    v.get(key).filter(|b| b.is_object())
}

fn name_of(raw: &[u8]) -> String {
    let end = raw.iter().position(|&c| c == 0).unwrap_or(raw.len());
    String::from_utf8_lossy(&raw[..end]).into_owned()
}

fn set_name(dst: &mut [u8; CHANNEL_NAME_LEN], name: &str) {
    let mut n = name.len().min(CHANNEL_NAME_LEN - 1);
    while !name.is_char_boundary(n) {
        n -= 1;
    }
    dst.fill(0);
    dst[..n].copy_from_slice(&name.as_bytes()[..n]);
}

/// ISO-8601 UTC for now, without a date library.
fn utc_now() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm)
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + (m <= 2) as i64;
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", rem / 3600, rem / 60 % 60, rem % 60)
}

fn band_json(p: &FilterParams) -> Value {
    json!({ "type": p.filter_type, "freqHz": p.freq, "q": p.q, "gain": p.gain, "qp": p.qp, "bypass": p.bypass })
}

fn band_from(v: &Value, xover: bool) -> (FilterParams, bool) {
    let t = int(v, "type", 0);
    let valid = t == 0 || if xover { (FILTER_XOVER_FIRST as i64..=FILTER_XOVER_LAST as i64).contains(&t) } else { (0..=13).contains(&t) };
    let p = FilterParams {
        filter_type: if valid { t as u8 } else { FILTER_FLAT },
        bypass: flag(v, "bypass", false),
        freq: f(v, "freqHz", 1000.0),
        q: f(v, "q", 0.707),
        gain: f(v, "gain", 0.0),
        qp: f(v, "qp", 0.707),
    };
    (p, valid)
}

// ═══════════════════════════════════════════════════════════════════
// Export
// ═══════════════════════════════════════════════════════════════════

/// The device's configuration as a document. `links` is the app's input-pair
/// link mask (bit p = pair p), which the firmware doesn't hold.
pub fn export(s: &DspState, name: &str, app_version: &str, links: u8) -> String {
    let rp2350 = s.platform_id == 1;
    let n_in = s.num_input_channels as usize;
    let n_out = s.num_output_channels as usize;
    let fw = format!("{}.{}.{}", s.fw_major, s.fw_minor, s.fw_patch)
        + &if s.fw_beta > 0 { format!("-beta{}", s.fw_beta) } else { String::new() };

    let mut channels = Vec::new();
    for i in 0..n_in {
        channels.push(json!({
            "channelId": id_for_input(i), "name": name_of(&s.channel_names[i]), "isOutput": false,
            "eqChannel": i, "inputIndex": i,
            "delayMs": s.channel_delays[i], "gainDb": 0.0, "muted": false, "enabled": true,
            "eq": s.filters[i].iter().map(band_json).collect::<Vec<_>>(), "crossover": [],
        }));
    }
    for o in 0..n_out {
        let w = n_in + o;
        channels.push(json!({
            "channelId": id_for_output(o, n_out, rp2350), "name": name_of(&s.channel_names[w]), "isOutput": true,
            "eqChannel": w, "outputIndex": o,
            "delayMs": s.channel_delays[w], "gainDb": s.output_gain_db[o], "muted": s.output_muted[o],
            "enabled": s.output_enabled[o], "outputDelayMs": s.output_delay_ms[o],
            "limiter": { "enabled": s.limiter_enabled[o], "thresholdDb": s.limiter_threshold_db[o],
                         "releaseMs": s.limiter_release_ms[o], "linkGroup": s.limiter_link_group[o] },
            "eq": s.filters[w].iter().map(band_json).collect::<Vec<_>>(),
            "crossover": s.xover[w].iter().map(band_json).collect::<Vec<_>>(),
        }));
    }
    let mut matrix = Vec::new();
    for i in 0..n_in.min(MAX_INPUTS) {
        for o in 0..n_out {
            matrix.push(json!({ "input": i, "output": o, "enabled": s.matrix_routing[i][o],
                                "invert": s.matrix_invert[i][o], "gainDb": s.matrix_gain[i][o] }));
        }
    }

    let u = &s.upmix;
    let sh = &s.subharm;
    let t = &s.tube;
    let mut doc = Map::new();
    doc.insert("schemaVersion".into(), json!(SCHEMA_VERSION));
    doc.insert("meta".into(), json!({
        "name": name, "savedUtc": utc_now(), "appVersion": app_version,
        "platform": platform_name(s.platform_id), "firmwareVersion": fw,
        "wireFormatVersion": s.format_version, "inputChannelCount": n_in, "outputChannelCount": n_out,
        "masterVolumeMode": s.master_volume_mode, "outputConfigMode": s.output_config_mode,
    }));
    doc.insert("global".into(), json!({
        "inputPreampsDb": s.input_preamp_db.to_vec(), "bypass": s.bypass,
        "masterVolumeDb": s.master_volume_db, "userVolumeDb": s.user_volume_db,
        "inputSource": s.input_source, "lgSoundSyncEnabled": s.lg_sound_sync_enabled,
        "inputPairLinked": (0..4).map(|p| links >> p & 1 == 1).collect::<Vec<_>>(),
    }));
    doc.insert("loudness".into(), json!({
        "enabled": s.loudness_enabled, "refSpl": s.loudness_ref_spl,
        "intensityPct": s.loudness_intensity, "outputMask": s.loudness_output_mask,
    }));
    doc.insert("crossfeed".into(), json!({
        "enabled": s.crossfeed_enabled, "preset": s.crossfeed_preset, "freqHz": s.crossfeed_freq,
        "feedDb": s.crossfeed_feed, "itd": s.crossfeed_itd, "outputPairMask": s.crossfeed_output_pair_mask,
    }));
    doc.insert("leveller".into(), json!({
        "enabled": s.leveller_enabled, "speed": s.leveller_speed, "lookahead": s.leveller_lookahead,
        "amountPct": s.leveller_amount, "maxGainDb": s.leveller_max_gain_db, "gateDb": s.leveller_gate_db,
        "detectorMask": s.leveller_detector_mask, "applyMask": s.leveller_apply_mask,
    }));
    doc.insert("psybass".into(), json!({
        "enabled": s.psybass_enabled, "cutoffHz": s.psybass_cutoff_hz, "harmonicsDb": s.psybass_harmonics_db,
        "driveDb": s.psybass_drive_db, "characterPct": s.psybass_character_pct,
        "originalDb": s.psybass_original_db, "outputMask": s.psybass_output_mask,
    }));
    doc.insert("upmix".into(), if rp2350 {
        json!({
            "enabled": u[0] != 0.0, "centerMode": u[1] as i64, "surroundMode": u[2] as i64,
            "strengthPct": u[3], "centerWidthPct": u[4], "thresholdPct": u[5], "attackMs": u[6],
            "releaseMs": u[7], "detectorHpfHz": u[8], "surroundDelayMs": u[9], "surroundHpfHz": u[10],
            "surroundLpfHz": u[11], "decorrPct": u[12], "presenceDb": u[13],
        })
    } else {
        Value::Null
    });
    doc.insert("subharm".into(), json!({
        "enabled": sh[0] != 0.0, "outputMask": sh[1] as i64, "lowDb": sh[2], "highDb": sh[3], "topDb": sh[4],
        "boostDb": sh[5], "selectMode": sh[6] as i64, "selectDepthPct": sh[7], "selectHoldMs": sh[8],
        "ceilingDb": sh[9], "linkPairs": sh[10] != 0.0,
    }));
    doc.insert("tube".into(), json!({
        "enabled": t[0] != 0.0, "outputMask": t[1] as i64, "tubeType": t[2] as i64, "driveDb": t[3],
        "biasPct": t[4], "asymDb": t[5], "hardnessPct": t[6], "sagPct": t[7], "rectifier": t[8] as i64,
        "xfmrEnabled": t[9] != 0.0, "xfmrDamping": t[10], "xfmrResHz": t[11], "mixPct": t[12], "trimDb": t[13],
    }));
    doc.insert("channels".into(), Value::Array(channels));
    doc.insert("matrix".into(), Value::Array(matrix));
    let rate_hz = [44_100u32, 48_000, 96_000][(s.i2s_input_rate as usize).min(2)];
    let mut io = json!({
        "outputPins": s.output_pins[..(s.num_pin_outputs as usize).clamp(1, MAX_PHYSICAL_OUTPUTS)].to_vec(),
        "outputSlotTypes": s.output_types.to_vec(),
        "i2sBckPin": s.i2s_bck_pin, "mckEnabled": s.mck_enabled, "mckPin": s.mck_pin,
        "mckMultiplier": if s.mck_multiplier == 1 { 256 } else { 128 },
        "i2sClockMode": s.i2s_clock_mode, "i2sClockPinMode": s.i2s_clock_pin_mode, "i2sBckPinSlave": s.i2s_bck_pin_slave,
        "spdifRxPins": s.spdif_rx_pins[..3].to_vec(), "spdifRxPin4": s.spdif_rx_pins[3],
        "spdifEnabledExt": (s.spdif_inputs_enabled >> 1) & 0x07,
        "i2sRxPins": s.i2s_rx_pins.to_vec(), "i2sInputChannels": s.i2s_input_channels,
        "i2sInputRateHz": rate_hz,
        "adatEnabled": s.adat_out_enabled, "adatPin": s.adat_out_pin,
        "adatInputEnabled": s.adat_input_enabled, "adatInputPin": s.adat_input_pin,
        "adatInputClockMode": s.adat_input_clock_mode, "dacHwMute": Value::Null,
    });
    if s.dac_mute_supported {
        io["dacHwMute"] = json!({ "enabled": s.dac_mute_enabled, "activeLow": s.dac_mute_active_low,
                                  "pin": s.dac_mute_pin, "holdMs": s.dac_mute_hold_ms, "releaseMs": s.dac_mute_release_ms });
    }
    doc.insert("io".into(), io);
    // serde_json's map is sorted, so two exports of one state diff cleanly
    serde_json::to_string_pretty(&Value::Object(doc)).unwrap_or_default()
}

// ═══════════════════════════════════════════════════════════════════
// Import
// ═══════════════════════════════════════════════════════════════════

/// Parse a document; Err is the message to show.
pub fn parse(text: &str) -> std::result::Result<Value, String> {
    let v: Value = serde_json::from_str(text).map_err(|e| format!("Not a valid configuration file: {e}."))?;
    let version = int(&v, "schemaVersion", 0);
    let has_channels = v.get("channels").and_then(Value::as_array).is_some_and(|a| !a.is_empty());
    if version <= 0 || !has_channels {
        return Err("Not a valid configuration file: no channel data found.".into());
    }
    if version > SCHEMA_VERSION {
        return Err(format!(
            "This configuration was written by a newer version of DSPi Console (format {version}, this build reads {SCHEMA_VERSION})."
        ));
    }
    Ok(v)
}

/// Where a document came from: (name, platform, firmware, saved UTC).
pub fn provenance(v: &Value) -> (String, String, String, String) {
    let m = v.get("meta").cloned().unwrap_or(Value::Null);
    (
        text(&m, "name").unwrap_or_default(),
        text(&m, "platform").unwrap_or_default(),
        text(&m, "firmwareVersion").unwrap_or_default(),
        text(&m, "savedUtc").unwrap_or_default(),
    )
}

pub const IMPORT_VOLUMES: u32 = 1;
pub const IMPORT_HARDWARE: u32 = 2;

/// What an import did, as lines for the user, and the input-pair links to
/// restore (app state, not the device's).
pub struct ImportReport {
    pub lines: Vec<String>,
    pub clean: bool,
    pub links: Option<u8>,
    /// Hardware I/O was written outside a preset (save it as the output config).
    pub hardware_written: bool,
}

impl DspiCore {
    pub fn import_preset(&mut self, v: &Value, options: u32) -> Result<ImportReport> {
        let old = self.state.clone();
        let mut ns = self.state.clone();
        let rp2350 = ns.platform_id == 1;
        let n_in = ns.num_input_channels as usize;
        let n_out = ns.num_output_channels as usize;
        let max_delay = self.max_delay_ms();
        let mut missing: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();
        let mut skip = |s: String| {
            if !skipped.contains(&s) {
                skipped.push(s);
            }
        };

        // Global
        let g = v.get("global").cloned().unwrap_or(Value::Null);
        if let Some(pre) = floats(&g, "inputPreampsDb") {
            for (i, db) in pre.iter().enumerate().take(MAX_INPUTS) {
                ns.input_preamp_db[i] = db.clamp(-24.0, 24.0);
            }
            ns.preamp_db = ns.input_preamp_db[0];
        }
        ns.bypass = flag(&g, "bypass", ns.bypass);
        ns.input_source = int(&g, "inputSource", ns.input_source as i64).clamp(0, 6) as u8;
        ns.lg_sound_sync_enabled = flag(&g, "lgSoundSyncEnabled", ns.lg_sound_sync_enabled);
        if options & IMPORT_VOLUMES != 0 {
            ns.master_volume_db = f(&g, "masterVolumeDb", ns.master_volume_db).clamp(-128.0, 0.0);
            ns.user_volume_db = f(&g, "userVolumeDb", ns.user_volume_db).clamp(-128.0, 0.0);
        }
        let links = g.get("inputPairLinked").and_then(Value::as_array).map(|a| {
            a.iter().take(4).enumerate().fold(0u8, |m, (p, x)| if x.as_bool() == Some(true) { m | 1 << p } else { m })
        });

        // Features
        if let Some(b) = block(v, "loudness") {
            ns.loudness_enabled = flag(b, "enabled", false);
            ns.loudness_ref_spl = f(b, "refSpl", 83.0);
            ns.loudness_intensity = f(b, "intensityPct", 100.0);
            ns.loudness_output_mask = int(b, "outputMask", ns.loudness_output_mask as i64) as u16;
        }
        if let Some(b) = block(v, "crossfeed") {
            ns.crossfeed_enabled = flag(b, "enabled", false);
            ns.crossfeed_preset = int(b, "preset", 0).clamp(0, 3) as u8;
            ns.crossfeed_freq = f(b, "freqHz", 700.0);
            ns.crossfeed_feed = f(b, "feedDb", 4.5);
            ns.crossfeed_itd = flag(b, "itd", true);
            ns.crossfeed_output_pair_mask = int(b, "outputPairMask", ns.crossfeed_output_pair_mask as i64) as u8;
        }
        if let Some(b) = block(v, "leveller") {
            ns.leveller_enabled = flag(b, "enabled", false);
            ns.leveller_speed = int(b, "speed", 0).clamp(0, 2) as u8;
            ns.leveller_lookahead = flag(b, "lookahead", true);
            ns.leveller_amount = f(b, "amountPct", 50.0);
            ns.leveller_max_gain_db = f(b, "maxGainDb", 15.0);
            ns.leveller_gate_db = f(b, "gateDb", -96.0);
            ns.leveller_detector_mask = int(b, "detectorMask", 0xFF) as u8;
            ns.leveller_apply_mask = int(b, "applyMask", 0xFF) as u8;
        }
        if let Some(b) = block(v, "psybass") {
            ns.psybass_enabled = flag(b, "enabled", false);
            ns.psybass_cutoff_hz = f(b, "cutoffHz", 80.0);
            ns.psybass_harmonics_db = f(b, "harmonicsDb", 0.0);
            ns.psybass_drive_db = f(b, "driveDb", 6.0);
            ns.psybass_character_pct = f(b, "characterPct", 50.0);
            ns.psybass_original_db = f(b, "originalDb", 0.0);
            ns.psybass_output_mask = int(b, "outputMask", ns.psybass_output_mask as i64) as u16;
        }
        if let Some(b) = block(v, "upmix") {
            if rp2350 {
                let u = &mut ns.upmix;
                u[0] = flag(b, "enabled", false) as u8 as f32;
                u[1] = int(b, "centerMode", u[1] as i64) as f32;
                u[2] = int(b, "surroundMode", u[2] as i64) as f32;
                for (k, key) in [(3, "strengthPct"), (4, "centerWidthPct"), (5, "thresholdPct"), (6, "attackMs"),
                                 (7, "releaseMs"), (8, "detectorHpfHz"), (9, "surroundDelayMs"), (10, "surroundHpfHz"),
                                 (11, "surroundLpfHz"), (12, "decorrPct"), (13, "presenceDb")] {
                    u[k] = f(b, key, u[k]);
                }
            } else if flag(b, "enabled", false) {
                skip("the stereo upmixer (not on RP2040)".into());
            }
        }
        if let Some(b) = block(v, "subharm") {
            let s = &mut ns.subharm;
            s[0] = flag(b, "enabled", false) as u8 as f32;
            s[1] = int(b, "outputMask", s[1] as i64) as f32;
            for (k, key) in [(2, "lowDb"), (3, "highDb"), (4, "topDb"), (5, "boostDb"), (7, "selectDepthPct"),
                             (8, "selectHoldMs"), (9, "ceilingDb")] {
                s[k] = f(b, key, s[k]);
            }
            s[6] = int(b, "selectMode", s[6] as i64) as f32;
            s[10] = flag(b, "linkPairs", true) as u8 as f32;
        }
        if let Some(b) = block(v, "tube") {
            let t = &mut ns.tube;
            t[0] = flag(b, "enabled", false) as u8 as f32;
            t[1] = int(b, "outputMask", t[1] as i64) as f32;
            t[2] = int(b, "tubeType", t[2] as i64).clamp(0, 16) as f32;
            t[8] = int(b, "rectifier", t[8] as i64).clamp(0, 3) as f32;
            t[9] = flag(b, "xfmrEnabled", t[9] != 0.0) as u8 as f32;
            for (k, key) in [(3, "driveDb"), (4, "biasPct"), (5, "asymDb"), (6, "hardnessPct"), (7, "sagPct"),
                             (10, "xfmrDamping"), (11, "xfmrResHz"), (12, "mixPct"), (13, "trimDb")] {
                t[k] = f(b, key, t[k]);
            }
        }

        // Channels
        let (mut n_channels, mut n_bands, mut n_xover) = (0, 0, 0);
        let hardware = options & IMPORT_HARDWARE != 0;
        for c in v.get("channels").and_then(Value::as_array).into_iter().flatten() {
            let is_output = flag(c, "isOutput", false);
            let r = match (is_output, c.get("outputIndex").and_then(Value::as_i64), c.get("inputIndex").and_then(Value::as_i64)) {
                (true, Some(o), _) => Some(ChannelRef::Output(o.max(0) as usize)),
                (false, _, Some(i)) => Some(ChannelRef::Input(i.max(0) as usize)),
                _ => ref_for_id(int(c, "channelId", -1), n_out, rp2350),
            };
            let label = text(c, "name").filter(|s| !s.is_empty()).unwrap_or_else(|| format!("channel {}", int(c, "channelId", -1)));
            let w = match r {
                Some(ChannelRef::Input(i)) if i < n_in => i,
                Some(ChannelRef::Output(o)) if o < n_out => n_in + o,
                _ => {
                    missing.push(label);
                    continue;
                }
            };
            n_channels += 1;
            if let Some(name) = text(c, "name") {
                set_name(&mut ns.channel_names[w], &name);
            }
            ns.channel_delays[w] = f(c, "delayMs", 0.0).clamp(0.0, max_delay);
            let bands = c.get("eq").and_then(Value::as_array).cloned().unwrap_or_default();
            if bands.len() > BANDS_PER_CHANNEL {
                skip(format!("EQ bands beyond {BANDS_PER_CHANNEL} per channel"));
            }
            for b in 0..BANDS_PER_CHANNEL {
                let (p, ok) = bands.get(b).map(|x| band_from(x, false)).unwrap_or((FilterParams::default(), true));
                if !ok {
                    skip("filter types this firmware doesn't have (set to Off)".into());
                }
                if p.filter_type == FILTER_LINKWITZ_TRANSFORM && w < n_in {
                    skip("Linkwitz Transforms on inputs (set to Off)".into());
                    ns.filters[w][b] = FilterParams::default();
                    continue;
                }
                n_bands += (p.filter_type != FILTER_FLAT) as usize;
                ns.filters[w][b] = p;
            }
            if let Some(ChannelRef::Output(o)) = r.filter(|_| w >= n_in) {
                ns.output_gain_db[o] = f(c, "gainDb", 0.0).clamp(-60.0, 12.0);
                ns.output_muted[o] = flag(c, "muted", false);
                ns.output_enabled[o] = flag(c, "enabled", true);
                if c.get("outputDelayMs").is_some() {
                    ns.output_delay_ms[o] = f(c, "outputDelayMs", 0.0).clamp(0.0, max_delay);
                }
                let xs = c.get("crossover").and_then(Value::as_array).cloned().unwrap_or_default();
                for b in 0..MAX_XOVER_BANDS {
                    let (p, ok) = xs.get(b).map(|x| band_from(x, true)).unwrap_or((FilterParams::default(), true));
                    if !ok {
                        skip("crossover types this firmware doesn't have (set to Off)".into());
                    }
                    n_xover += (p.filter_type != FILTER_FLAT) as usize;
                    ns.xover[w][b] = p;
                }
                if hardware {
                    if let Some(l) = block(c, "limiter") {
                        ns.limiter_enabled[o] = flag(l, "enabled", false);
                        ns.limiter_threshold_db[o] = f(l, "thresholdDb", ns.limiter_threshold_db[o]).clamp(-30.0, 0.0);
                        ns.limiter_release_ms[o] = f(l, "releaseMs", ns.limiter_release_ms[o]).clamp(10.0, 1000.0);
                        ns.limiter_link_group[o] = int(l, "linkGroup", 0).clamp(0, 4) as u8;
                    }
                }
            }
        }

        // Matrix: every crosspoint the document has
        let mut n_points = 0;
        for x in v.get("matrix").and_then(Value::as_array).into_iter().flatten() {
            let (i, o) = (int(x, "input", -1), int(x, "output", -1));
            if i < 0 || o < 0 || i as usize >= n_in.min(MAX_INPUTS) || o as usize >= n_out {
                continue;
            }
            let (i, o) = (i as usize, o as usize);
            ns.matrix_routing[i][o] = flag(x, "enabled", false);
            ns.matrix_invert[i][o] = flag(x, "invert", false);
            ns.matrix_gain[i][o] = f(x, "gainDb", 0.0);
            n_points += ns.matrix_routing[i][o] as usize;
        }

        // Hardware I/O, when asked for
        if hardware {
            if let Some(io) = block(v, "io") {
                if let Some(pins) = ints(io, "outputPins") {
                    for (k, p) in pins.iter().enumerate().take(MAX_PHYSICAL_OUTPUTS) {
                        ns.output_pins[k] = *p as u8;
                    }
                }
                if let Some(types) = ints(io, "outputSlotTypes") {
                    for (k, t) in types.iter().enumerate().take(4) {
                        ns.output_types[k] = (*t).clamp(0, 1) as u8;
                    }
                }
                ns.i2s_bck_pin = int(io, "i2sBckPin", ns.i2s_bck_pin as i64) as u8;
                ns.mck_enabled = flag(io, "mckEnabled", ns.mck_enabled);
                ns.mck_pin = int(io, "mckPin", ns.mck_pin as i64) as u8;
                ns.mck_multiplier = (int(io, "mckMultiplier", 128) == 256) as u8;
                ns.i2s_clock_mode = int(io, "i2sClockMode", ns.i2s_clock_mode as i64).clamp(0, 1) as u8;
                ns.i2s_clock_pin_mode = int(io, "i2sClockPinMode", ns.i2s_clock_pin_mode as i64).clamp(0, 1) as u8;
                ns.i2s_bck_pin_slave = int(io, "i2sBckPinSlave", ns.i2s_bck_pin_slave as i64) as u8;
                if let Some(rx) = ints(io, "spdifRxPins") {
                    for (k, p) in rx.iter().enumerate().take(3) {
                        ns.spdif_rx_pins[k] = *p as u8;
                    }
                }
                ns.spdif_rx_pins[3] = int(io, "spdifRxPin4", ns.spdif_rx_pins[3] as i64) as u8;
                ns.spdif_inputs_enabled = 0x01 | ((int(io, "spdifEnabledExt", 0) as u8 & 0x07) << 1);
                if let Some(rx) = ints(io, "i2sRxPins") {
                    for (k, p) in rx.iter().enumerate().take(4) {
                        ns.i2s_rx_pins[k] = *p as u8;
                    }
                }
                ns.i2s_input_channels = int(io, "i2sInputChannels", ns.i2s_input_channels as i64) as u8;
                ns.i2s_input_rate = match int(io, "i2sInputRateHz", 48_000) { 44_100 => 0, 96_000 => 2, _ => 1 };
                if rp2350 {
                    ns.adat_out_enabled = flag(io, "adatEnabled", ns.adat_out_enabled);
                    ns.adat_out_pin = int(io, "adatPin", ns.adat_out_pin as i64) as u8;
                    ns.adat_input_enabled = flag(io, "adatInputEnabled", ns.adat_input_enabled);
                    ns.adat_input_pin = int(io, "adatInputPin", ns.adat_input_pin as i64) as u8;
                    ns.adat_input_clock_mode = int(io, "adatInputClockMode", ns.adat_input_clock_mode as i64).clamp(0, 1) as u8;
                }
                if let (Some(d), true) = (block(io, "dacHwMute"), ns.dac_mute_supported) {
                    ns.dac_mute_enabled = flag(d, "enabled", false);
                    ns.dac_mute_active_low = flag(d, "activeLow", true);
                    ns.dac_mute_pin = int(d, "pin", ns.dac_mute_pin as i64) as u8;
                    ns.dac_mute_hold_ms = int(d, "holdMs", 0) as u16;
                    ns.dac_mute_release_ms = int(d, "releaseMs", 0) as u16;
                }
            }
        }

        // One bulk write of the whole state; the device announces it with
        // BULK_INVALIDATED, which re-reads everything
        self.state = ns;
        if let Err(e) = self.apply_all_params() {
            self.state = old;
            return Err(e);
        }

        // The I/O that changed, one setting at a time
        let mut hardware_written = false;
        if hardware {
            let mut io_fail = |what: &str, st: Result<u8>| {
                if !matches!(st, Ok(PIN_CONFIG_SUCCESS)) {
                    skip(format!("{what} (refused by the device)"));
                }
            };
            let s = self.state.clone();
            for k in 0..4 {
                if s.output_types[k] != old.output_types[k] {
                    let r = self.set_output_type(k as u8, s.output_types[k]);
                    io_fail(&format!("output {} type", k + 1), r);
                }
            }
            for k in 0..(s.num_pin_outputs as usize).min(MAX_PHYSICAL_OUTPUTS) {
                if s.output_pins[k] != old.output_pins[k] {
                    let r = self.set_output_pin(k as u8, s.output_pins[k]);
                    io_fail(&format!("output pin {}", k + 1), r);
                }
            }
            if s.i2s_clock_pin_mode != old.i2s_clock_pin_mode {
                let r = self.set_i2s_clock_pin_mode(s.i2s_clock_pin_mode);
                io_fail("I2S clock pin mode", r);
            }
            if s.i2s_bck_pin != old.i2s_bck_pin {
                let r = self.set_i2s_bck_pin(0, s.i2s_bck_pin);
                io_fail("I2S BCK pin", r);
            }
            if s.i2s_bck_pin_slave != old.i2s_bck_pin_slave {
                let r = self.set_i2s_bck_pin(1, s.i2s_bck_pin_slave);
                io_fail("I2S slave BCK pin", r);
            }
            if s.mck_pin != old.mck_pin {
                let r = self.set_mck_pin(s.mck_pin);
                io_fail("MCK pin", r);
            }
            if s.mck_multiplier != old.mck_multiplier {
                let r = self.set_mck_multiplier(s.mck_multiplier);
                io_fail("MCK multiplier", r);
            }
            if s.mck_enabled != old.mck_enabled {
                let r = self.set_mck_enabled(s.mck_enabled);
                io_fail("MCK output", r);
            }
            if rp2350 && s.adat_out_pin != old.adat_out_pin {
                let r = self.set_adat_out_pin(s.adat_out_pin);
                io_fail("ADAT output pin", r);
            }
            if rp2350 && s.adat_out_enabled != old.adat_out_enabled {
                let r = self.set_adat_out_enabled(s.adat_out_enabled);
                io_fail("ADAT output", r);
            }
            for o in 0..n_out {
                if s.limiter_enabled[o] != old.limiter_enabled[o] { let _ = self.set_limiter_param(o as u8, LIMITER_PARAM_ENABLED, s.limiter_enabled[o] as u8 as f32); }
                if s.limiter_threshold_db[o] != old.limiter_threshold_db[o] { let _ = self.set_limiter_param(o as u8, LIMITER_PARAM_THRESHOLD_DB, s.limiter_threshold_db[o]); }
                if s.limiter_release_ms[o] != old.limiter_release_ms[o] { let _ = self.set_limiter_param(o as u8, LIMITER_PARAM_RELEASE_MS, s.limiter_release_ms[o]); }
                if s.limiter_link_group[o] != old.limiter_link_group[o] { let _ = self.set_limiter_param(o as u8, LIMITER_PARAM_LINK_GROUP, s.limiter_link_group[o] as f32); }
            }
            hardware_written = old.output_config_mode == 0;
        }

        let mut lines = vec![format!(
            "Applied {n_channels} channel{}, {n_bands} EQ band{}, {n_xover} crossover band{} and {n_points} crosspoint{}.",
            if n_channels == 1 { "" } else { "s" }, if n_bands == 1 { "" } else { "s" },
            if n_xover == 1 { "" } else { "s" }, if n_points == 1 { "" } else { "s" }
        )];
        if !missing.is_empty() {
            lines.push(format!("Not present on this device: {}.", missing.join(", ")));
        }
        if !skipped.is_empty() {
            lines.push(format!("Skipped: {}.", skipped.join("; ")));
        }
        let clean = missing.is_empty() && skipped.is_empty();
        lines.push("These changes are live but not yet stored on the device. Save them to a preset slot to keep them.".into());
        Ok(ImportReport { lines, clean, links, hardware_written })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_ids_match_the_shared_schema() {
        assert_eq!(id_for_input(0), 0);
        assert_eq!(id_for_input(2), 11);
        assert_eq!(id_for_output(0, 9, true), 2);
        assert_eq!(id_for_output(8, 9, true), 10);
        assert_eq!(id_for_output(4, 5, false), 6);
        assert_eq!(ref_for_id(11, 9, true), Some(ChannelRef::Input(2)));
        assert_eq!(ref_for_id(10, 9, true), Some(ChannelRef::Output(8)));
        assert_eq!(ref_for_id(6, 5, false), Some(ChannelRef::Output(4)));
        assert_eq!(ref_for_id(9, 5, false), None);
    }

    #[test]
    fn reads_the_windows_fixture() {
        // A file written by the macOS Console (from the Windows interop tests)
        let text = r#"{"schemaVersion": 1, "meta": {"name": "Desk", "platform": "RP2350", "firmwareVersion": "1.1.5",
            "savedUtc": "2026-07-14T09:31:07.4821563+00:00"},
          "global": {"inputPreampsDb": [-3, -3, 0, 0, 0, 0, 0, 0], "bypass": false, "inputSource": 1,
                     "inputPairLinked": [true, false, false, false]},
          "psybass": null, "upmix": null,
          "channels": [{"channelId": 0, "name": "Master L", "isOutput": false, "delayMs": 0,
              "eq": [{"type": 1, "freqHz": 100, "q": 1, "gain": 3, "qp": 0.707, "bypass": false}], "crossover": []},
            {"channelId": 10, "name": "PDM", "isOutput": true, "delayMs": 2, "gainDb": -4,
              "crossover": [{"type": 34, "freqHz": 80, "q": 0.707, "gain": 0, "qp": 0.707, "bypass": false}]}],
          "matrix": [{"input": 0, "output": 8, "enabled": true, "invert": false, "gainDb": -3}]}"#;
        let v = parse(text).unwrap();
        assert_eq!(provenance(&v).0, "Desk");
        assert!(block(&v, "psybass").is_none(), "null block is absent");
        let ch = &v["channels"][1];
        assert_eq!(ref_for_id(int(ch, "channelId", -1), 9, true), Some(ChannelRef::Output(8)));
        let (band, ok) = band_from(&ch["crossover"][0], true);
        assert!(ok && band.filter_type == 34 && band.freq == 80.0);
        assert_eq!(f(&v["global"], "inputPreampsDb", 0.0), 0.0, "wrong type takes the default");
    }

    #[test]
    fn rejects_empty_and_future_files() {
        assert!(parse("{}").unwrap_err().contains("no channel data"));
        assert!(parse(r#"{"schemaVersion": 2, "channels": [{}]}"#).unwrap_err().contains("format 2"));
        assert!(parse("not json").unwrap_err().starts_with("Not a valid configuration file"));
    }

    #[test]
    fn export_round_trips_the_fields_it_writes() {
        let mut s = DspState::default();
        s.platform_id = 1;
        s.num_input_channels = 8;
        s.num_output_channels = 9;
        s.num_pin_outputs = 5;
        s.filters[9][0] = FilterParams { filter_type: 1, bypass: false, freq: 250.0, q: 1.4, gain: -2.5, qp: 0.707 };
        set_name(&mut s.channel_names[8], "Left Woofer");
        s.matrix_routing[1][3] = true;
        let text = export(&s, "Test", "0.1", 0b0001);
        let v = parse(&text).unwrap();
        let out1 = v["channels"].as_array().unwrap().iter().find(|c| c["outputIndex"] == 1).unwrap();
        assert_eq!(out1["channelId"], 3);
        assert_eq!(out1["eq"][0]["freqHz"], 250.0);
        let out0 = v["channels"].as_array().unwrap().iter().find(|c| c["outputIndex"] == 0).unwrap();
        assert_eq!(out0["name"], "Left Woofer");
        assert_eq!(v["global"]["inputPairLinked"][0], true);
        assert!(v["matrix"].as_array().unwrap().iter().any(|x| x["input"] == 1 && x["output"] == 3 && x["enabled"] == true));
        assert!(text.find("\"channels\"").unwrap() < text.find("\"crossfeed\"").unwrap(), "keys sorted");
    }
}
