//! Unsaved-changes tracking, as on macOS: a copy of the state taken when it
//! last matched the active preset (connect, preset load, save to the active
//! slot, revert, factory reset), and a readable list of what differs since.
//! Master volume counts only in WITH_PRESET master volume mode, and the
//! hardware wiring only in WITH_PRESET output config mode, both judged by
//! the live mode.

use crate::protocol::*;
use crate::state::DspState;
use crate::types::*;
use crate::DspiCore;

fn db(v: f32) -> String {
    format!("{v:.1} dB")
}

/// Whole numbers without decimals, others with one
fn val(v: f32) -> String {
    if v == v.round() && v.abs() < 100000.0 { format!("{v:.0}") } else { format!("{v:.1}") }
}

fn on(b: bool) -> &'static str {
    if b { "enabled" } else { "disabled" }
}

fn channel_label(s: &DspState, wire: usize) -> String {
    let name = name_from_bytes(&s.channel_names[wire]);
    if !name.is_empty() {
        return name;
    }
    let ins = s.num_input_channels as usize;
    if wire < ins {
        return match wire { 0 => "USB L".into(), 1 => "USB R".into(), n => format!("Input {}", n + 1) };
    }
    format!("Output {}", wire - ins + 1)
}

fn same_filter(a: &FilterParams, b: &FilterParams) -> bool {
    // A Linkwitz Transform's target Q counts; for every other type it's ignored
    let qp = |f: &FilterParams| if f.filter_type == FILTER_LINKWITZ_TRANSFORM { f.qp } else { 0.0 };
    a.filter_type == b.filter_type && a.bypass == b.bypass && a.freq == b.freq && a.q == b.q
        && a.gain == b.gain && qp(a) == qp(b)
}

/// What differs between the baseline `o` and the live state `n`, worded as
/// the macOS Console words it.
pub fn diff(o: &DspState, n: &DspState) -> Vec<String> {
    let mut c = Vec::new();
    let ins = n.num_input_channels as usize;
    let outs = n.num_output_channels as usize;
    let labels = ["L", "R", "FC", "LFE", "BL", "BR", "SL", "SR"];

    // Global
    for i in 0..ins.min(MAX_INPUTS) {
        if o.input_preamp_db[i] != n.input_preamp_db[i] {
            let l = labels.get(i).map(|s| s.to_string()).unwrap_or(format!("In {}", i + 1));
            c.push(format!("Preamp {l}: {} → {}", db(o.input_preamp_db[i]), db(n.input_preamp_db[i])));
        }
    }
    if n.master_volume_mode == 1 && o.master_volume_db != n.master_volume_db {
        let mv = |v: f32| if v <= -128.0 { "-∞ dB".to_string() } else { db(v) };
        c.push(format!("Master Volume: {} → {}", mv(o.master_volume_db), mv(n.master_volume_db)));
    }
    if o.bypass != n.bypass {
        c.push(format!("Master EQ bypass: {} → {}", if o.bypass { "on" } else { "off" }, if n.bypass { "on" } else { "off" }));
    }

    // Loudness
    if o.loudness_enabled != n.loudness_enabled { c.push(format!("Loudness: {}", on(n.loudness_enabled))); }
    if o.loudness_output_mask != n.loudness_output_mask {
        c.push(format!("Loudness outputs: 0x{:04X} → 0x{:04X}", o.loudness_output_mask, n.loudness_output_mask));
    }
    if o.loudness_ref_spl != n.loudness_ref_spl {
        c.push(format!("Loudness ref SPL: {} → {}", val(o.loudness_ref_spl), val(n.loudness_ref_spl)));
    }
    if o.loudness_intensity != n.loudness_intensity {
        c.push(format!("Loudness intensity: {}% → {}%", val(o.loudness_intensity), val(n.loudness_intensity)));
    }

    // Crossfeed
    if o.crossfeed_enabled != n.crossfeed_enabled { c.push(format!("Crossfeed: {}", on(n.crossfeed_enabled))); }
    if o.crossfeed_preset != n.crossfeed_preset {
        c.push(format!("Crossfeed preset: {} → {}", o.crossfeed_preset, n.crossfeed_preset));
    }
    if o.crossfeed_freq != n.crossfeed_freq {
        c.push(format!("Crossfeed frequency: {} → {} Hz", val(o.crossfeed_freq), val(n.crossfeed_freq)));
    }
    if o.crossfeed_feed != n.crossfeed_feed {
        c.push(format!("Crossfeed feed: {} → {}", val(o.crossfeed_feed), val(n.crossfeed_feed)));
    }
    if o.crossfeed_itd != n.crossfeed_itd { c.push(format!("Crossfeed ITD: {}", on(n.crossfeed_itd))); }
    if o.crossfeed_output_pair_mask != n.crossfeed_output_pair_mask {
        c.push(format!("Crossfeed output pairs: 0x{:02X} → 0x{:02X}", o.crossfeed_output_pair_mask, n.crossfeed_output_pair_mask));
    }

    // Psychoacoustic bass
    if o.psybass_enabled != n.psybass_enabled { c.push(format!("Psychoacoustic Bass: {}", on(n.psybass_enabled))); }
    if o.psybass_output_mask != n.psybass_output_mask {
        c.push(format!("Psybass outputs: 0x{:04X} → 0x{:04X}", o.psybass_output_mask, n.psybass_output_mask));
    }
    for (name, a, b, unit) in [
        ("Psybass cutoff", o.psybass_cutoff_hz, n.psybass_cutoff_hz, " Hz"),
        ("Psybass harmonics", o.psybass_harmonics_db, n.psybass_harmonics_db, " dB"),
        ("Psybass drive", o.psybass_drive_db, n.psybass_drive_db, " dB"),
        ("Psybass character", o.psybass_character_pct, n.psybass_character_pct, "%"),
        ("Psybass original bass", o.psybass_original_db, n.psybass_original_db, " dB"),
    ] {
        if a != b { c.push(format!("{name}: {}{unit} → {}{unit}", val(a), val(b))); }
    }

    // Subharmonic synthesizer
    let sh = |i: u8| (o.subharm[i as usize], n.subharm[i as usize]);
    let (a, b) = sh(SUBHARM_PARAM_ENABLED);
    if a != b { c.push(format!("Subharmonic Synthesizer: {}", on(b != 0.0))); }
    let (a, b) = sh(SUBHARM_PARAM_MASK);
    if a != b { c.push(format!("Subharm outputs: 0x{:04X} → 0x{:04X}", a as u32, b as u32)); }
    let level = |v: f32| if v <= -30.0 { "Off".to_string() } else { db(v) };
    for (name, i) in [("Subharm 24-36 Hz", SUBHARM_PARAM_LOW), ("Subharm 36-56 Hz", SUBHARM_PARAM_HIGH),
                      ("Subharm 56-80 Hz", SUBHARM_PARAM_TOP)] {
        let (a, b) = sh(i);
        if a != b { c.push(format!("{name}: {} → {}", level(a), level(b))); }
    }
    let select = |v: f32| match v as i32 { 1 => "Percussive", 2 => "Sustained", _ => "All material" };
    let (a, b) = sh(SUBHARM_PARAM_SELECT);
    if a != b { c.push(format!("Subharm selectivity: {} → {}", select(a), select(b))); }
    let (a, b) = sh(SUBHARM_PARAM_DEPTH);
    if a != b { c.push(format!("Subharm selectivity depth: {}% → {}%", val(a), val(b))); }
    let (a, b) = sh(SUBHARM_PARAM_HOLD);
    if a != b { c.push(format!("Subharm selectivity hold: {} ms → {} ms", val(a), val(b))); }
    let ceiling = |v: f32| if v >= 0.0 { "Off".to_string() } else { db(v) };
    let (a, b) = sh(SUBHARM_PARAM_CEILING);
    if a != b { c.push(format!("Subharm sub ceiling: {} → {}", ceiling(a), ceiling(b))); }
    let (a, b) = sh(SUBHARM_PARAM_LINK);
    if a != b { c.push(format!("Subharm pair link: {}", if b != 0.0 { "linked" } else { "independent" })); }
    let (a, b) = sh(SUBHARM_PARAM_BOOST);
    if a != b { c.push(format!("Subharm LF boost: {} dB → {} dB", val(a), val(b))); }
    // Solo is for listening, not part of the sound: not a preset change (as on macOS)

    // Tube modeller
    let tb = |i: u8| (o.tube[i as usize], n.tube[i as usize]);
    let (a, b) = tb(TUBE_PARAM_ENABLED);
    if a != b { c.push(format!("Tube Modeller: {}", on(b != 0.0))); }
    let (a, b) = tb(TUBE_PARAM_MASK);
    if a != b { c.push(format!("Tube outputs: 0x{:04X} → 0x{:04X}", a as u32, b as u32)); }
    let tube_names = ["Custom", "12AX7", "5751", "12AT7", "12AY7", "12AU7", "6SN7", "6SL7", "6DJ8", "EF86", "6SJ7",
                      "EL84", "EL34", "6L6", "6V6", "KT88", "300B"];
    let tube = |v: f32| tube_names.get(v as usize).copied().unwrap_or("Custom");
    let (a, b) = tb(TUBE_PARAM_TYPE);
    if a != b { c.push(format!("Tube type: {} → {}", tube(a), tube(b))); }
    for (name, i, unit) in [("Tube drive", TUBE_PARAM_DRIVE, " dB"), ("Tube bias", TUBE_PARAM_BIAS, "%"),
                            ("Tube asymmetry", TUBE_PARAM_ASYM, " dB"), ("Tube knee hardness", TUBE_PARAM_HARDNESS, "%"),
                            ("Tube sag", TUBE_PARAM_SAG, "%")] {
        let (a, b) = tb(i);
        if a != b { c.push(format!("{name}: {}{unit} → {}{unit}", val(a), val(b))); }
    }
    let rect = |v: f32| match v as i32 { 0 => "Solid state", 2 => "Tube (slow)", 3 => "Tube (heavy)", _ => "Tube" };
    let (a, b) = tb(TUBE_PARAM_RECTIFIER);
    if a != b { c.push(format!("Tube rectifier: {} → {}", rect(a), rect(b))); }
    let (a, b) = tb(TUBE_PARAM_XFMR);
    if a != b { c.push(format!("Tube output stage: {}", on(b != 0.0))); }
    for (name, i, unit) in [("Tube damping factor", TUBE_PARAM_DAMPING, ""), ("Tube speaker resonance", TUBE_PARAM_RESONANCE, " Hz"),
                            ("Tube mix", TUBE_PARAM_MIX, "%"), ("Tube output trim", TUBE_PARAM_TRIM, " dB")] {
        let (a, b) = tb(i);
        if a != b {
            let sep = if unit == "%" { "%" } else { "" };
            let unit = if unit == "%" { "" } else { unit };
            c.push(format!("{name}: {}{sep}{unit} → {}{sep}{unit}", val(a), val(b)));
        }
    }

    // Output limiters (part of the preset only with the hardware config)
    if n.output_config_mode == 1 {
        for i in 0..outs.min(MAX_OUTPUTS) {
            let name = channel_label(n, ins + i);
            if o.limiter_enabled[i] != n.limiter_enabled[i] { c.push(format!("{name} limiter: {}", on(n.limiter_enabled[i]))); }
            if o.limiter_threshold_db[i] != n.limiter_threshold_db[i] {
                c.push(format!("{name} limiter threshold: {:.1} → {:.1} dBFS", o.limiter_threshold_db[i], n.limiter_threshold_db[i]));
            }
            if o.limiter_release_ms[i] != n.limiter_release_ms[i] {
                c.push(format!("{name} limiter release: {} ms → {} ms", val(o.limiter_release_ms[i]), val(n.limiter_release_ms[i])));
            }
            if o.limiter_link_group[i] != n.limiter_link_group[i] {
                let g = |v: u8| if v == 0 { "Unlinked".to_string() } else { format!("Group {v}") };
                c.push(format!("{name} limiter link: {} → {}", g(o.limiter_link_group[i]), g(n.limiter_link_group[i])));
            }
        }
    }

    // Stereo upmixer
    let up = |i: u8| (o.upmix[i as usize], n.upmix[i as usize]);
    let (a, b) = up(UPMIX_PARAM_ENABLED);
    if a != b { c.push(format!("Stereo Upmixer: {}", on(b != 0.0))); }
    let centre = |v: f32| match v as i32 { 0 => "Sinner", 1 => "Logician", _ => "Off" };
    let surround = |v: f32| match v as i32 { 1 => "Sinner", 2 => "Logician", _ => "Off" };
    let (a, b) = up(UPMIX_PARAM_CENTER_MODE);
    if a != b { c.push(format!("Centre mode: {} → {}", centre(a), centre(b))); }
    let (a, b) = up(UPMIX_PARAM_SURROUND_MODE);
    if a != b { c.push(format!("Surround mode: {} → {}", surround(a), surround(b))); }
    for (name, i, unit) in [
        ("Centre strength", UPMIX_PARAM_STRENGTH, "%"), ("Centre width", UPMIX_PARAM_WIDTH, "%"),
        ("Correlation threshold", UPMIX_PARAM_THRESHOLD, "%"), ("Centre attack", UPMIX_PARAM_ATTACK, " ms"),
        ("Centre release", UPMIX_PARAM_RELEASE, " ms"), ("Detector HPF", UPMIX_PARAM_DETECTOR_HPF, " Hz"),
        ("Surround delay", UPMIX_PARAM_SURROUND_DELAY, " ms"), ("Surround HPF", UPMIX_PARAM_SURROUND_HPF, " Hz"),
        ("Surround LPF", UPMIX_PARAM_SURROUND_LPF, " Hz"), ("Decorrelation", UPMIX_PARAM_DECORRELATION, "%"),
        ("Centre presence", UPMIX_PARAM_PRESENCE, " dB"),
    ] {
        let (a, b) = up(i);
        if a != b { c.push(format!("{name}: {}{unit} → {}{unit}", val(a), val(b))); }
    }

    // Volume leveller
    if o.leveller_enabled != n.leveller_enabled { c.push(format!("Volume Leveller: {}", on(n.leveller_enabled))); }
    if o.leveller_amount != n.leveller_amount {
        c.push(format!("Leveller amount: {}% → {}%", val(o.leveller_amount), val(n.leveller_amount)));
    }
    if o.leveller_speed != n.leveller_speed {
        let sp = |v: u8| ["Slow", "Medium", "Fast"].get(v as usize).copied().unwrap_or("Medium");
        c.push(format!("Leveller speed: {} → {}", sp(o.leveller_speed), sp(n.leveller_speed)));
    }
    if o.leveller_max_gain_db != n.leveller_max_gain_db {
        c.push(format!("Leveller max gain: {} dB → {} dB", val(o.leveller_max_gain_db), val(n.leveller_max_gain_db)));
    }
    if o.leveller_lookahead != n.leveller_lookahead { c.push(format!("Leveller lookahead: {}", on(n.leveller_lookahead))); }
    if o.leveller_gate_db != n.leveller_gate_db {
        c.push(format!("Leveller gate: {} dB → {} dB", val(o.leveller_gate_db), val(n.leveller_gate_db)));
    }
    if o.leveller_detector_mask != n.leveller_detector_mask { c.push("Leveller detector channels changed".into()); }
    if o.leveller_apply_mask != n.leveller_apply_mask { c.push("Leveller apply channels changed".into()); }

    // Input channel delays (outputs have their own below)
    for w in 0..ins.min(MAX_CHANNELS) {
        if o.channel_delays[w] != n.channel_delays[w] {
            c.push(format!("{} delay: {} ms → {} ms", channel_label(n, w), val(o.channel_delays[w]), val(n.channel_delays[w])));
        }
    }

    // Matrix crosspoints
    let mut points = 0;
    for i in 0..ins.min(MAX_INPUTS) {
        for j in 0..outs.min(MAX_OUTPUTS) {
            if o.matrix_routing[i][j] != n.matrix_routing[i][j] || o.matrix_gain[i][j] != n.matrix_gain[i][j]
                || o.matrix_invert[i][j] != n.matrix_invert[i][j] {
                points += 1;
            }
        }
    }
    if points > 0 { c.push(format!("{points} crosspoint{} changed", if points == 1 { "" } else { "s" })); }

    // Outputs
    for i in 0..outs.min(MAX_OUTPUTS) {
        let name = channel_label(n, ins + i);
        if o.output_enabled[i] != n.output_enabled[i] { c.push(format!("{name} {}", on(n.output_enabled[i]))); }
        if o.output_muted[i] != n.output_muted[i] {
            c.push(format!("{name} {}", if n.output_muted[i] { "muted" } else { "unmuted" }));
        }
        if o.output_gain_db[i] != n.output_gain_db[i] {
            c.push(format!("{name} gain: {} → {}", db(o.output_gain_db[i]), db(n.output_gain_db[i])));
        }
        if o.output_delay_ms[i] != n.output_delay_ms[i] {
            c.push(format!("{name} delay: {} ms → {} ms", val(o.output_delay_ms[i]), val(n.output_delay_ms[i])));
        }
    }

    // EQ and crossover bands
    for w in 0..(ins + outs).min(MAX_CHANNELS) {
        let changed = (0..BANDS_PER_CHANNEL).filter(|&b| !same_filter(&o.filters[w][b], &n.filters[w][b])).count();
        if changed > 0 {
            c.push(format!("{changed} band{} changed on {}", if changed == 1 { "" } else { "s" }, channel_label(n, w)));
        }
    }
    for w in ins..(ins + outs).min(MAX_CHANNELS) {
        let changed = (0..MAX_XOVER_BANDS).filter(|&b| !same_filter(&o.xover[w][b], &n.xover[w][b])).count();
        if changed > 0 {
            c.push(format!("{changed} crossover band{} changed on {}", if changed == 1 { "" } else { "s" }, channel_label(n, w)));
        }
    }

    // Channel names. Changing an output's type makes the firmware rename its
    // channels that are still at their default: a consequence, not an edit
    let types_changed = o.output_types != n.output_types;
    for w in 0..(ins + outs).min(MAX_CHANNELS) {
        if o.channel_names[w] != n.channel_names[w] && !(types_changed && w >= ins) {
            c.push(format!("'{}' → '{}'", name_from_bytes(&o.channel_names[w]), name_from_bytes(&n.channel_names[w])));
        }
    }

    // Hardware configuration, when it travels with the preset
    if n.output_config_mode == 1 {
        let pins = (0..MAX_PHYSICAL_OUTPUTS).filter(|&i| o.output_pins[i] != n.output_pins[i]).count();
        if pins > 0 { c.push(format!("{pins} pin assignment{} changed", if pins == 1 { "" } else { "s" })); }
        let types = (0..4).filter(|&i| o.output_types[i] != n.output_types[i]).count();
        if types > 0 { c.push(format!("{types} output type{} changed", if types == 1 { "" } else { "s" })); }
        if o.i2s_bck_pin != n.i2s_bck_pin { c.push(format!("BCK pin: GPIO {} → GPIO {}", o.i2s_bck_pin, n.i2s_bck_pin)); }
        if o.mck_enabled != n.mck_enabled { c.push(format!("MCK: {}", on(n.mck_enabled))); }
        if o.mck_pin != n.mck_pin { c.push(format!("MCK pin: GPIO {} → GPIO {}", o.mck_pin, n.mck_pin)); }
        if o.mck_multiplier != n.mck_multiplier {
            c.push(format!("MCK multiplier: {}x → {}x", 128u32 << o.mck_multiplier.min(1), 128u32 << n.mck_multiplier.min(1)));
        }
        if o.spdif_rx_pins[0] != n.spdif_rx_pins[0] {
            c.push(format!("S/PDIF RX pin: GPIO {} → GPIO {}", o.spdif_rx_pins[0], n.spdif_rx_pins[0]));
        }
        for k in 1..4 {
            let (oe, ne) = (o.spdif_inputs_enabled >> k & 1 == 1, n.spdif_inputs_enabled >> k & 1 == 1);
            if oe != ne { c.push(format!("S/PDIF {} input: {}", k + 1, on(ne))); }
            if o.spdif_rx_pins[k] != n.spdif_rx_pins[k] {
                c.push(format!("S/PDIF {} RX pin: GPIO {} → GPIO {}", k + 1, o.spdif_rx_pins[k], n.spdif_rx_pins[k]));
            }
        }
        if o.i2s_input_channels != n.i2s_input_channels {
            c.push(format!("I2S input channels: {} → {}", o.i2s_input_channels, n.i2s_input_channels));
        }
        for p in 0..4 {
            if o.i2s_rx_pins[p] != n.i2s_rx_pins[p] {
                c.push(format!("I2S RX pin (pair {}): GPIO {} → GPIO {}", p + 1, o.i2s_rx_pins[p], n.i2s_rx_pins[p]));
            }
        }
        if o.i2s_input_rate != n.i2s_input_rate { c.push("I2S rate changed".into()); }
        let mode = |v: u8| if v == 1 { "Slave" } else { "Master" };
        if o.i2s_clock_mode != n.i2s_clock_mode {
            c.push(format!("I2S clock mode: {} → {}", mode(o.i2s_clock_mode), mode(n.i2s_clock_mode)));
        }
        if o.adat_out_enabled != n.adat_out_enabled { c.push(format!("ADAT output: {}", on(n.adat_out_enabled))); }
        if o.adat_out_pin != n.adat_out_pin { c.push(format!("ADAT pin: GPIO {} → GPIO {}", o.adat_out_pin, n.adat_out_pin)); }
        if o.adat_input_enabled != n.adat_input_enabled { c.push(format!("ADAT input: {}", on(n.adat_input_enabled))); }
        if o.adat_input_pin != n.adat_input_pin {
            let pin = |v: u8| if v == 0xFF { "Not set".to_string() } else { format!("GPIO {v}") };
            c.push(format!("ADAT input pin: {} → {}", pin(o.adat_input_pin), pin(n.adat_input_pin)));
        }
        if o.adat_input_clock_mode != n.adat_input_clock_mode {
            c.push(format!("ADAT input clock mode: {} → {}", mode(o.adat_input_clock_mode), mode(n.adat_input_clock_mode)));
        }
    }

    if o.input_source != n.input_source {
        let src = |v: u8| match v { 0 => "USB".to_string(), 1 => "S/PDIF".into(), 2 => "I2S".into(), 3 => "ADAT".into(),
                                    4..=6 => format!("S/PDIF {}", v - 2), _ => format!("Source {v}") };
        c.push(format!("Input source: {} → {}", src(o.input_source), src(n.input_source)));
    }
    if o.lg_sound_sync_enabled != n.lg_sound_sync_enabled {
        c.push(format!("LG Sound Sync: {}", on(n.lg_sound_sync_enabled)));
    }
    c
}

impl DspiCore {
    /// The live state now matches the active preset
    pub fn capture_baseline(&mut self) {
        self.baseline = Some(Box::new(self.state.clone()));
    }

    /// What differs from the active preset (empty before any baseline)
    pub fn preset_changes(&self) -> Vec<String> {
        match &self.baseline {
            Some(b) => diff(b, &self.state),
            None => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diff_reports_edits_and_respects_modes() {
        let mut a = DspState::default();
        a.num_input_channels = 2;
        a.num_output_channels = 4;
        let mut b = a.clone();
        assert!(diff(&a, &b).is_empty());

        b.input_preamp_db[0] = -3.0;
        b.filters[2][1].gain = 4.0;
        b.output_muted[1] = true;
        b.master_volume_db = -10.0;     // independent mode: not part of the preset
        b.output_pins[0] = 9;           // with preset mode by default? judged below
        b.output_config_mode = 0;
        let lines = diff(&a, &b);
        assert!(lines.contains(&"Preamp L: 0.0 dB → -3.0 dB".to_string()), "{lines:?}");
        assert!(lines.iter().any(|l| l == "1 band changed on Output 1"), "{lines:?}");
        assert!(lines.iter().any(|l| l == "Output 2 muted"), "{lines:?}");
        assert!(!lines.iter().any(|l| l.starts_with("Master Volume")));
        assert!(!lines.iter().any(|l| l.contains("pin assignment")));

        b.master_volume_mode = 1;
        b.output_config_mode = 1;
        let lines = diff(&a, &b);
        assert!(lines.iter().any(|l| l.starts_with("Master Volume")));
        assert!(lines.iter().any(|l| l == "1 pin assignment changed"));
    }
}
