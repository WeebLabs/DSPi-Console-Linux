//! Filter text files, after the macOS Console (format 2): a header, then one
//! section per channel with its preamp (inputs), PEQ bands and crossover
//! bands. The band grammar is a superset of REW's, so REW and AutoEQ exports
//! import too (as one set of filters for the channels the user picks):
//!
//!     [Input 0: Master L]
//!     Preamp -6.5 dB
//!     Filter  3: ON  PK      Fc   100.0 Hz  Gain  +3.000 dB  Q  1.000  [Bypassed]
//!     Filter  4: ON  LT      Fc    40.0 Hz  Q  0.700  Fp    28.0 Hz  Qp  0.710
//!     Filter  5: OFF
//!     Xover   1: ON  LR4LP   Fc  2000.0 Hz
//!
//! Sections are keyed by input / output index; the Windows Console's
//! name-keyed sections ("Master L", "SPDIF 2 R", "PDM") are read as well.

use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use crate::state::DspState;
use crate::types::*;
use crate::usb::Result;
use crate::DspiCore;

pub const FORMAT_VERSION: u32 = 2;

fn uses_gain(t: u8) -> bool {
    matches!(t, 1 | 2 | 3 | 9 | 10)
}
fn uses_q(t: u8) -> bool {
    (1..=7).contains(&t)
}

/// The file token for a type (None = flat, written OFF).
fn file_code(t: u8) -> Option<String> {
    let code = match t {
        0 => return None,
        1 => "PK",
        2 => "LS",
        3 => "HS",
        4 => "LP",
        5 => "HP",
        6 => "NT",
        7 => "AP",
        8 => "AP1",
        9 => "LS1",
        10 => "HS1",
        11 => "LT",
        12 => "LP1",
        13 => "HP1",
        _ => {
            let (fam, order, hp) = crossover_meta(t)?;
            let f = match fam {
                XoverFamily::LinkwitzRiley => "LR",
                XoverFamily::Butterworth => "BW",
                XoverFamily::Bessel => "BES",
            };
            return Some(format!("{f}{order}{}", if hp { "HP" } else { "LP" }));
        }
    };
    Some(code.to_string())
}

fn crossover_type(family: &str, order: u8, hp: bool) -> Option<u8> {
    let pair = match family {
        "LR" if matches!(order, 2 | 4 | 6 | 8) => order / 2 - 1,
        "BW" if (1..=8).contains(&order) => order + 3,
        "BES" | "BESSEL" if matches!(order, 2 | 4 | 6 | 8) => order / 2 + 11,
        _ => return None,
    };
    Some(FILTER_XOVER_FIRST + pair * 2 + hp as u8)
}

/// A type from a file token, with the aliases other tools write.
fn type_for_code(code: &str) -> Option<u8> {
    let c = code.to_uppercase();
    Some(match c.as_str() {
        "PK" | "PEQ" => 1,
        "LS" | "LSC" => 2,
        "HS" | "HSC" => 3,
        "LP" | "LPQ" => 4,
        "HP" | "HPQ" => 5,
        "NT" | "NO" => 6,
        "AP" => 7,
        "AP1" => 8,
        "LS1" => 9,
        "HS1" => 10,
        "LT" => 11,
        "LP1" => 12,
        "HP1" => 13,
        _ => {
            // "LR4LP", "BW3HP", "BES2LP"
            let (fam, rest) = ["BES", "LR", "BW"].iter().find_map(|f| c.strip_prefix(f).map(|r| (*f, r)))?;
            let hp = rest.ends_with("HP");
            if !hp && !rest.ends_with("LP") {
                return None;
            }
            let order: u8 = rest[..rest.len() - 2].parse().ok()?;
            return crossover_type(fam, order, hp);
        }
    })
}

/// A number token, tolerating a glued unit and either decimal separator
/// (the last of '.' / ',' is the decimal point).
fn number(token: &str) -> Option<f32> {
    let mut t = token.trim_end_matches(|c: char| !c.is_ascii_digit() && c != '.' && c != ',').to_string();
    if t.is_empty() {
        return None;
    }
    if let (Some(d), Some(c)) = (t.rfind('.'), t.rfind(',')) {
        t = t.replace(if d > c { ',' } else { '.' }, "");
    }
    t.replace(',', ".").parse().ok()
}

fn format_band(xover: bool, index: usize, p: &FilterParams) -> String {
    let kw = if xover { "Xover " } else { "Filter" };
    let Some(code) = file_code(p.filter_type) else {
        return format!("{kw} {index:2}: OFF\n");
    };
    let mut line = format!("{kw} {index:2}: ON  {code:<8}Fc {:7.1} Hz", p.freq);
    if p.filter_type == FILTER_LINKWITZ_TRANSFORM {
        line += &format!("  Q {:6.3}  Fp {:7.1} Hz  Qp {:6.3}", p.q, p.gain, p.qp);
    } else {
        if uses_gain(p.filter_type) {
            line += &format!("  Gain {:+7.3} dB", p.gain);
        }
        if uses_q(p.filter_type) {
            line += &format!("  Q {:6.3}", p.q);
        }
    }
    if p.bypass {
        line += "  [Bypassed]";
    }
    line + "\n"
}

fn name_of(raw: &[u8]) -> String {
    let end = raw.iter().position(|&c| c == 0).unwrap_or(raw.len());
    String::from_utf8_lossy(&raw[..end]).into_owned()
}

/// Every channel's filters as a file. `inputs` = the live inputs to write.
pub fn export(s: &DspState, inputs: usize) -> String {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let mut out = format!("# DSPi Console Filter Settings\n# Exported: {now} (Unix time)\n# Format: {FORMAT_VERSION}\n\n");
    let n_in = s.num_input_channels as usize;
    for i in 0..inputs.min(n_in) {
        out += &format!("[Input {i}: {}]\n", name_of(&s.channel_names[i]));
        out += &format!("Preamp {:+.1} dB\n", s.input_preamp_db[i]);
        for (b, p) in s.filters[i].iter().enumerate() {
            out += &format_band(false, b + 1, p);
        }
        out += "\n";
    }
    for o in 0..s.num_output_channels as usize {
        let w = n_in + o;
        out += &format!("[Output {o}: {} ({})]\n", name_of(&s.channel_names[w]), if s.output_enabled[o] { "Enabled" } else { "Disabled" });
        for (b, p) in s.filters[w].iter().enumerate() {
            out += &format_band(false, b + 1, p);
        }
        for (b, p) in s.xover[w].iter().enumerate() {
            out += &format_band(true, b + 1, p);
        }
        out += "\n";
    }
    out
}

// ── Reading ──

#[derive(Debug, Clone, PartialEq)]
struct Band {
    xover: bool,
    params: FilterParams,
    enabled: bool,
}

fn parse_preamp(line: &str) -> Option<f32> {
    let l = line.trim();
    if !l.to_lowercase().starts_with("preamp") {
        return None;
    }
    l[6..].split(|c: char| c.is_whitespace() || c == ':').find_map(number)
}

fn parse_band(line: &str) -> Option<Band> {
    let l = line.trim();
    let lower = l.to_lowercase();
    let (kw, xover) = [("crossover", true), ("filter", false), ("xover", true)].into_iter().find(|(k, _)| lower.starts_with(k))?;
    let colon = l.find(':')?;
    if colon < kw.len() || l[kw.len()..colon].trim().parse::<i32>().is_err() {
        return None;
    }
    let mut tokens: Vec<&str> = l[colon + 1..].split_whitespace().collect();
    let off = Band { xover, params: FilterParams::default(), enabled: false };
    if tokens.is_empty() || !tokens.remove(0).eq_ignore_ascii_case("ON") || tokens.is_empty() {
        return Some(off);
    }
    let type_token = tokens.remove(0);
    let mut values: BTreeMap<String, f32> = BTreeMap::new();
    for w in tokens.windows(2) {
        if number(w[0]).is_none() {
            if let Some(v) = number(w[1]) {
                values.insert(w[0].to_uppercase(), v);
            }
        }
    }
    // A crossover written as family + shape + slope (the Windows spelling)
    let t = type_for_code(type_token).or_else(|| {
        let slope = *values.get("SLOPE")?;
        let shape = tokens.first()?.to_uppercase();
        let hp = match shape.as_str() { "HP" => true, "LP" => false, _ => return None };
        crossover_type(&type_token.to_uppercase(), (slope / 6.0) as u8, hp)
    });
    let Some(t) = t else { return Some(off) };
    let mut p = FilterParams { filter_type: t, ..FilterParams::default() };
    if let Some(v) = values.get("FC") { p.freq = *v; }
    if let Some(v) = values.get("GAIN") { p.gain = *v; }
    if let Some(v) = values.get("Q") { p.q = *v; }
    if let Some(v) = values.get("QP") { p.qp = *v; }
    if t == FILTER_LINKWITZ_TRANSFORM {
        if let Some(v) = values.get("FP") { p.gain = *v; }
    }
    p.bypass = l.to_uppercase().contains("[BYPASSED]") || tokens.iter().any(|t| t.eq_ignore_ascii_case("BYP"));
    Some(Band { xover, params: p, enabled: true })
}

/// A channel at an input or output index.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Chan {
    Input(usize),
    Output(usize),
}

#[derive(Debug, Default, Clone)]
struct Section {
    filters: Vec<FilterParams>,
    xover: Vec<FilterParams>,
    preamp: Option<f32>,
    enable: Option<bool>,
}

enum Parsed {
    /// A DSPi Console file: per-channel sections.
    Native { channels: BTreeMap<Chan, Section>, version: u32 },
    /// A REW / AutoEQ list: one set of filters.
    Rew { filters: Vec<FilterParams>, preamp: Option<f32>, dropped: usize },
}

/// The Windows Console's default channel names as section headers.
fn windows_header(name: &str, pdm: usize) -> Option<Chan> {
    let n = name.trim().to_uppercase();
    match n.as_str() {
        "MASTER L" | "USB L" => return Some(Chan::Input(0)),
        "MASTER R" | "USB R" => return Some(Chan::Input(1)),
        "PDM" | "SUB" => return Some(Chan::Output(pdm)),
        "OUT L" => return Some(Chan::Output(0)),
        "OUT R" => return Some(Chan::Output(1)),
        _ => {}
    }
    if let Some(i) = n.strip_prefix("INPUT ").and_then(|x| x.parse::<usize>().ok()) {
        return (3..=8).contains(&i).then_some(Chan::Input(i - 1));
    }
    let rest = n.strip_prefix("SPDIF ")?;
    let mut parts = rest.split_whitespace();
    let pair: usize = parts.next()?.parse().ok()?;
    let side = parts.next()?;
    (pair >= 1).then_some(())?;
    match side {
        "L" => Some(Chan::Output((pair - 1) * 2)),
        "R" => Some(Chan::Output((pair - 1) * 2 + 1)),
        _ => None,
    }
}

fn parse(text: &str, pdm: usize) -> Parsed {
    if !text.trim_start().starts_with("# DSPi Console") {
        let mut filters = Vec::new();
        let mut preamp = None;
        let mut dropped = 0;
        for line in text.lines() {
            if let Some(p) = parse_preamp(line) {
                preamp = Some(p);
            } else if let Some(b) = parse_band(line) {
                if b.enabled && !b.xover { filters.push(b.params) } else { dropped += 1 }
            }
        }
        return Parsed::Rew { filters, preamp, dropped };
    }
    let mut channels: BTreeMap<Chan, Section> = BTreeMap::new();
    let mut version = 1;
    let mut current: Option<Chan> = None;
    for line in text.lines() {
        let l = line.trim();
        if l.to_lowercase().starts_with("# format") {
            version = l.split(|c: char| c.is_whitespace() || c == ':').find_map(|t| t.parse().ok()).unwrap_or(1);
            continue;
        }
        if l.starts_with('[') && l.ends_with(']') {
            let h = &l[1..l.len() - 1];
            current = None;
            let idx = |prefix: &str| h.strip_prefix(prefix).and_then(|r| r.split(':').next()).and_then(|n| n.trim().parse::<usize>().ok());
            let (chan, enable) = if let Some(i) = idx("Input ") {
                (Some(Chan::Input(i)), None)
            } else if let Some(o) = idx("Output ") {
                let e = if h.ends_with("(Enabled)") { Some(true) } else if h.ends_with("(Disabled)") { Some(false) } else { None };
                (Some(Chan::Output(o)), e)
            } else {
                (windows_header(h, pdm), None)
            };
            if let Some(c) = chan {
                channels.insert(c, Section { enable, ..Default::default() });
                current = Some(c);
            }
            continue;
        }
        let Some(c) = current else { continue };
        let sec = channels.get_mut(&c).unwrap();
        if let Some(p) = parse_preamp(l) {
            sec.preamp = Some(p);
        } else if let Some(b) = parse_band(l) {
            // OFF / unknown keeps its slot (flat) so indices stay aligned
            let p = if b.enabled { b.params } else { FilterParams::default() };
            if b.xover { sec.xover.push(p) } else { sec.filters.push(p) }
        }
    }
    Parsed::Native { channels, version }
}

/// What a file holds, for the channel picker (JSON): a DSPi file lists its
/// channels (wire index, label, band count, all ticked); a REW file its
/// filter count and preamp, with every channel offered (inputs ticked).
pub fn inspect(s: &DspState, text: &str, inputs: usize) -> Value {
    let n_in = s.num_input_channels as usize;
    let n_out = s.num_output_channels as usize;
    let label = |w: usize| {
        let name = name_of(&s.channel_names[w]);
        if w < n_in { format!("Input {}: {name}", w + 1) } else { format!("Output {}: {name}", w - n_in + 1) }
    };
    match parse(text, n_out.saturating_sub(1)) {
        Parsed::Native { channels, version } => {
            let list: Vec<Value> = channels.iter().filter_map(|(c, sec)| {
                let w = match *c {
                    Chan::Input(i) if i < n_in => i,
                    Chan::Output(o) if o < n_out => n_in + o,
                    _ => return None,
                };
                let bands = sec.filters.iter().filter(|p| p.filter_type != FILTER_FLAT).count()
                    + sec.xover.iter().filter(|p| p.filter_type != FILTER_FLAT).count();
                Some(json!({ "wire": w, "label": label(w), "bands": bands, "checked": true }))
            }).collect();
            json!({ "kind": "native", "channels": list, "newer": version > FORMAT_VERSION })
        }
        Parsed::Rew { filters, preamp, .. } => {
            let mut list = Vec::new();
            for w in 0..inputs.min(n_in) {
                list.push(json!({ "wire": w, "label": label(w), "bands": filters.len(), "checked": true }));
            }
            for o in 0..n_out {
                list.push(json!({ "wire": n_in + o, "label": label(n_in + o), "bands": filters.len(), "checked": false }));
            }
            json!({ "kind": "rew", "channels": list, "filters": filters.len(), "preamp": preamp })
        }
    }
}

impl DspiCore {
    /// Apply a filter file to the chosen channels (wire indices). Returns the
    /// report lines.
    pub fn import_filters(&mut self, text: &str, chosen: &[usize]) -> Result<Vec<String>> {
        let n_in = self.state.num_input_channels as usize;
        let n_out = self.state.num_output_channels as usize;
        let mut notes: Vec<String> = Vec::new();
        let mut applied = 0;
        let write = |core: &mut DspiCore, w: usize, filters: &[FilterParams], xover: Option<&[FilterParams]>,
                         preamp: Option<f32>, enable: Option<bool>| -> Result<()> {
            let wire = w as u8;
            for b in 0..BANDS_PER_CHANNEL {
                let mut p = filters.get(b).copied().unwrap_or_default();
                if p.filter_type >= FILTER_XOVER_FIRST || (p.filter_type == FILTER_LINKWITZ_TRANSFORM && w < n_in) {
                    p = FilterParams::default();
                }
                core.set_filter(wire, b as u8, p)?;
            }
            if let (Some(x), true) = (xover, w >= n_in) {
                for b in 0..MAX_XOVER_BANDS {
                    let mut p = x.get(b).copied().unwrap_or_default();
                    if p.filter_type != FILTER_FLAT && !filter_is_crossover(p.filter_type) {
                        p = FilterParams::default();
                    }
                    core.set_crossover(wire, b as u8, p)?;
                }
            }
            if let (Some(db), true) = (preamp, w < n_in) {
                core.set_input_preamp(wire, db.clamp(-24.0, 24.0))?;
            }
            if let (Some(on), true) = (enable, w >= n_in) {
                core.set_output_enable((w - n_in) as u8, on)?;
            }
            Ok(())
        };
        match parse(text, n_out.saturating_sub(1)) {
            Parsed::Native { channels, version } => {
                if version > FORMAT_VERSION {
                    notes.push(format!("The file is format {version}; this build reads format {FORMAT_VERSION}, so newer sections were skipped."));
                }
                for (c, sec) in &channels {
                    let w = match *c {
                        Chan::Input(i) if i < n_in => i,
                        Chan::Output(o) if o < n_out => n_in + o,
                        _ => continue,
                    };
                    if !chosen.contains(&w) {
                        continue;
                    }
                    if sec.filters.len() > BANDS_PER_CHANNEL {
                        notes.push(format!("Only the first {BANDS_PER_CHANNEL} bands of a channel were used."));
                    }
                    write(self, w, &sec.filters, Some(&sec.xover), sec.preamp, sec.enable)?;
                    applied += 1;
                }
            }
            Parsed::Rew { filters, preamp, dropped } => {
                if filters.len() > BANDS_PER_CHANNEL {
                    notes.push(format!("The file has {} filters; only the first {BANDS_PER_CHANNEL} were used.", filters.len()));
                }
                if dropped > 0 {
                    notes.push(format!("{dropped} filter line{} that were off or of an unknown type were left out.", if dropped == 1 { "" } else { "s" }));
                }
                if preamp.is_some() && chosen.iter().all(|&w| w >= n_in) {
                    notes.push("The preamp applies to inputs only, so it was not used.".into());
                }
                for &w in chosen {
                    if w < n_in + n_out {
                        write(self, w, &filters, None, preamp, None)?;
                        applied += 1;
                    }
                }
            }
        }
        notes.dedup();
        let mut lines = vec![format!("Applied filters to {applied} channel{}.", if applied == 1 { "" } else { "s" })];
        lines.extend(notes);
        lines.push("These changes are live but not yet stored on the device. Save them to a preset slot to keep them.".into());
        Ok(lines)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_round_trip() {
        for t in (1..=13).chain(32..=63) {
            let code = file_code(t).unwrap();
            assert_eq!(type_for_code(&code), Some(t), "{code}");
        }
        assert_eq!(type_for_code("PEQ"), Some(1));
        assert_eq!(type_for_code("None"), None);
    }

    #[test]
    fn band_lines_round_trip() {
        let p = FilterParams { filter_type: 1, bypass: true, freq: 100.0, q: 1.0, gain: 3.0, qp: 0.707 };
        let line = format_band(false, 3, &p);
        assert_eq!(line, "Filter  3: ON  PK      Fc   100.0 Hz  Gain  +3.000 dB  Q  1.000  [Bypassed]\n");
        assert_eq!(parse_band(&line).unwrap().params, p);
        let lt = FilterParams { filter_type: 11, bypass: false, freq: 40.0, q: 0.7, gain: 28.0, qp: 0.71 };
        assert_eq!(parse_band(&format_band(false, 4, &lt)).unwrap().params, lt);
        let x = parse_band("Xover   1: ON  LR4LP   Fc  2000.0 Hz").unwrap();
        assert!(x.xover && x.params.filter_type == 34 && x.params.freq == 2000.0);
        assert!(!parse_band("Filter  5: OFF").unwrap().enabled);
        assert!(parse_band("Filters: 5").is_none());
    }

    #[test]
    fn reads_rew_and_other_spellings() {
        let rew = "Filter Settings file\nPreamp: -6,5 dB\nFilter 1: ON PK Fc 100 Hz Gain -3.5 dB Q 2.00\nFilter 2: ON None\nFilter 3: ON LSC Fc 105Hz Gain 4 dB Q 0.71\n";
        match parse(rew, 8) {
            Parsed::Rew { filters, preamp, dropped } => {
                assert_eq!(filters.len(), 2);
                assert_eq!(preamp, Some(-6.5));
                assert_eq!(dropped, 1);
                assert_eq!((filters[1].filter_type, filters[1].freq), (2, 105.0));
            }
            _ => panic!("not read as REW"),
        }
        let win = parse_band("Crossover 1: ON BW HP Fc 80 Hz Slope 24 dB/oct").unwrap();
        assert_eq!(win.params.filter_type, crossover_type("BW", 4, true).unwrap());
        assert_eq!(windows_header("SPDIF 2 R", 8), Some(Chan::Output(3)));
        assert_eq!(windows_header("Input 5", 8), Some(Chan::Input(4)));
    }

    #[test]
    fn native_sections_keep_their_slots() {
        let text = "# DSPi Console Filter Settings\n# Format: 2\n\n[Input 1: Master R]\nPreamp -2.0 dB\nFilter  1: OFF\nFilter  2: ON  PK  Fc 500.0 Hz  Gain -1.000 dB  Q 1.000\n\n[Output 3: Tweeter (Disabled)]\nXover  1: ON  LR4HP  Fc 2000.0 Hz\n";
        match parse(text, 8) {
            Parsed::Native { channels, version } => {
                assert_eq!(version, 2);
                let i1 = &channels[&Chan::Input(1)];
                assert_eq!((i1.preamp, i1.filters.len(), i1.filters[1].freq), (Some(-2.0), 2, 500.0));
                let o3 = &channels[&Chan::Output(3)];
                assert_eq!((o3.enable, o3.xover[0].filter_type), (Some(false), 35));
            }
            _ => panic!("not read as native"),
        }
    }
}
