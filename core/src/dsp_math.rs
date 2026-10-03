//! Biquad coefficient calculation and frequency/phase response.
//!
//! Port of the macOS Console's DSPMath.swift (via the Windows port's
//! DspMath.cs) and the firmware's coefficient and crossover design code.
//! Uses f64 internally for accuracy at low frequencies.

use std::f64::consts::PI;

use crate::types::*;

pub const SAMPLE_RATE: f64 = 48000.0;

/// Number of magnitude curve points (log-spaced from 10 Hz to 20 kHz).
pub const MAGNITUDE_POINTS: usize = 201;

/// Biquad coefficients (normalized, a0 = 1).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BiquadCoeffs {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

impl BiquadCoeffs {
    pub const UNITY: Self = Self { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0 };
}

/// Coefficients for a PEQ filter type (0..13). Crossover types are cascades;
/// see [`sections_for`].
pub fn calculate_coefficients(p: &FilterParams) -> BiquadCoeffs {
    calculate_coefficients_at(p, SAMPLE_RATE)
}

pub fn calculate_coefficients_at(p: &FilterParams, fs: f64) -> BiquadCoeffs {
    if p.filter_type == FILTER_FLAT || !filter_is_peq(p.filter_type) {
        return BiquadCoeffs::UNITY;
    }

    // Linkwitz Transform: zeros at the driver corner (f0, Q0), poles at the
    // target (fp, Qp). fp travels in the gain field (Hz); fp <= 0 is flat.
    // Both corners are tan-prewarped, as in the firmware.
    if p.filter_type == FILTER_LINKWITZ_TRANSFORM {
        let f0 = p.freq as f64;
        let fp = p.gain as f64;
        if fp <= 0.0 || f0 <= 0.0 {
            return BiquadCoeffs::UNITY;
        }
        let q0 = (p.q as f64).max(0.1);
        let qp = (p.qp as f64).max(0.1);
        let g0 = (PI * f0 / fs).tan();
        let gp = (PI * fp / fs).tan();
        let nb0 = 1.0 + g0 / q0 + g0 * g0;
        let nb1 = 2.0 * (g0 * g0 - 1.0);
        let nb2 = 1.0 - g0 / q0 + g0 * g0;
        let na0 = 1.0 + gp / qp + gp * gp;
        let na1 = 2.0 * (gp * gp - 1.0);
        let na2 = 1.0 - gp / qp + gp * gp;
        return BiquadCoeffs { b0: nb0 / na0, b1: nb1 / na0, b2: nb2 / na0, a1: na1 / na0, a2: na2 / na0 };
    }

    let omega = 2.0 * PI * p.freq as f64 / fs;
    let sn = omega.sin();
    let cs = omega.cos();
    let alpha = sn / (2.0 * p.q as f64);
    let a = 10.0_f64.powf(p.gain as f64 / 40.0);

    let (b0, b1, b2, a0, a1, a2) = match p.filter_type {
        FILTER_LOWPASS => ((1.0 - cs) / 2.0, 1.0 - cs, (1.0 - cs) / 2.0, 1.0 + alpha, -2.0 * cs, 1.0 - alpha),
        FILTER_HIGHPASS => ((1.0 + cs) / 2.0, -(1.0 + cs), (1.0 + cs) / 2.0, 1.0 + alpha, -2.0 * cs, 1.0 - alpha),
        FILTER_PEAKING => (
            1.0 + alpha * a,
            -2.0 * cs,
            1.0 - alpha * a,
            1.0 + alpha / a,
            -2.0 * cs,
            1.0 - alpha / a,
        ),
        FILTER_LOWSHELF => {
            let sa = a.sqrt();
            (
                a * ((a + 1.0) - (a - 1.0) * cs + 2.0 * sa * alpha),
                2.0 * a * ((a - 1.0) - (a + 1.0) * cs),
                a * ((a + 1.0) - (a - 1.0) * cs - 2.0 * sa * alpha),
                (a + 1.0) + (a - 1.0) * cs + 2.0 * sa * alpha,
                -2.0 * ((a - 1.0) + (a + 1.0) * cs),
                (a + 1.0) + (a - 1.0) * cs - 2.0 * sa * alpha,
            )
        }
        FILTER_HIGHSHELF => {
            let sa = a.sqrt();
            (
                a * ((a + 1.0) + (a - 1.0) * cs + 2.0 * sa * alpha),
                -2.0 * a * ((a - 1.0) + (a + 1.0) * cs),
                a * ((a + 1.0) + (a - 1.0) * cs - 2.0 * sa * alpha),
                (a + 1.0) - (a - 1.0) * cs + 2.0 * sa * alpha,
                2.0 * ((a - 1.0) - (a + 1.0) * cs),
                (a + 1.0) - (a - 1.0) * cs - 2.0 * sa * alpha,
            )
        }
        FILTER_NOTCH => (1.0, -2.0 * cs, 1.0, 1.0 + alpha, -2.0 * cs, 1.0 - alpha),
        FILTER_ALLPASS => (1.0 - alpha, -2.0 * cs, 1.0 + alpha, 1.0 + alpha, -2.0 * cs, 1.0 - alpha),
        // First-order types: degenerate biquads (b2 = a2 = 0), matching the
        // firmware's fallback biquad forms.
        FILTER_ALLPASS1 => {
            let t = (omega / 2.0).tan();
            let ap = (t - 1.0) / (t + 1.0);
            (ap, 1.0, 0.0, 1.0, ap, 0.0)
        }
        // DC gain A², unity at Nyquist.
        FILTER_LOWSHELF1 => (a * sn + 1.0 + cs, a * sn - 1.0 - cs, 0.0, sn / a + 1.0 + cs, sn / a - 1.0 - cs, 0.0),
        // Unity at DC, gain A² at Nyquist.
        FILTER_HIGHSHELF1 => (sn + a + a * cs, sn - a - a * cs, 0.0, sn + 1.0 / a + cs / a, sn - 1.0 / a - cs / a, 0.0),
        FILTER_LOWPASS1 => (sn, sn, 0.0, sn + 1.0 + cs, sn - 1.0 - cs, 0.0),
        FILTER_HIGHPASS1 => (1.0 + cs, -1.0 - cs, 0.0, sn + 1.0 + cs, sn - 1.0 - cs, 0.0),
        _ => return BiquadCoeffs::UNITY, // reserved PEQ types
    };

    BiquadCoeffs { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 }
}

// ── Crossover design (ported from firmware crossover.c) ─────────────
//
// Each crossover band is a cascade of biquad sections built from an analog
// prototype by the bilinear transform with prewarping.

/// Biquad sections a band contributes, ignoring its bypass flag: one for a
/// PEQ type, a cascade for a crossover type, none when it is off.
pub fn sections_for(p: &FilterParams, fs: f64) -> Vec<BiquadCoeffs> {
    if p.filter_type == FILTER_FLAT {
        Vec::new()
    } else if filter_is_crossover(p.filter_type) {
        crossover_sections(p.filter_type, p.freq as f64, fs)
    } else {
        vec![calculate_coefficients_at(p, fs)]
    }
}

/// Design the biquad cascade for crossover type `t` at cutoff `fc`.
pub fn crossover_sections(t: u8, fc: f64, fs: f64) -> Vec<BiquadCoeffs> {
    let mut s = Vec::with_capacity(4);
    let Some((family, order, hp)) = crossover_meta(t) else {
        return s;
    };
    let fc = fc.clamp(10.0, fs * 0.45);
    let omega_a = 2.0 * fs * (PI * fc / fs).tan();
    let order = order as usize;
    match family {
        XoverFamily::Butterworth => design_butterworth(&mut s, order, hp, omega_a, fs),
        XoverFamily::LinkwitzRiley => {
            if order == 2 {
                // LR2: one biquad with a double real pole.
                s.push(section_2nd(1.0, 0.0, omega_a, hp, fs));
            } else {
                // LR_2N = (BW_N)²: design BW_N and duplicate every section.
                design_butterworth(&mut s, order / 2, hp, omega_a, fs);
                let copy = s.clone();
                s.extend(copy);
            }
        }
        XoverFamily::Bessel => {
            for &(sigma, omega) in bessel_poles(order) {
                s.push(section_2nd(sigma, omega, omega_a, hp, fs));
            }
        }
    }
    s
}

fn design_butterworth(s: &mut Vec<BiquadCoeffs>, order: usize, hp: bool, omega_a: f64, fs: f64) {
    if order & 1 == 1 {
        s.push(section_1st(1.0, omega_a, hp, fs)); // odd order: real pole at σ = 1
    }
    for p in 0..order / 2 {
        let theta = if order & 1 == 1 {
            PI * (p + 1) as f64 / order as f64
        } else {
            PI * (2 * p + 1) as f64 / (2.0 * order as f64)
        };
        s.push(section_2nd(theta.cos(), theta.sin(), omega_a, hp, fs));
    }
}

/// Bessel (−3 dB normalized) analog pole pairs (σ, ω), from firmware crossover.c.
fn bessel_poles(order: usize) -> &'static [(f64, f64)] {
    match order {
        2 => &[(1.10160, 0.63601)],
        4 => &[(1.37007, 0.41025), (0.99521, 1.25711)],
        6 => &[(1.57149, 0.32090), (1.38186, 0.97147), (0.93066, 1.66186)],
        8 => &[(1.75741, 0.27287), (1.63694, 0.82280), (1.37384, 1.38836), (0.89287, 1.99833)],
        _ => &[],
    }
}

/// Second-order section from an analog pole pair (σ, ω). HP uses the LP→HP
/// reciprocal (σ, ω)/(σ² + ω²): a no-op for BW/LR, required for Bessel.
fn section_2nd(mut sigma_n: f64, mut omega_n: f64, omega_a: f64, hp: bool, fs: f64) -> BiquadCoeffs {
    if hp {
        let r2 = sigma_n * sigma_n + omega_n * omega_n;
        if r2 > 0.0 {
            sigma_n /= r2;
            omega_n /= r2;
        }
    }
    let sigma = sigma_n * omega_a;
    let omega = omega_n * omega_a;
    let k = 2.0 * fs;
    let a = 2.0 * sigma;
    let b = sigma * sigma + omega * omega;
    let a0 = k * k + a * k + b;
    let a1 = 2.0 * (b - k * k);
    let a2 = k * k - a * k + b;
    let inv = 1.0 / a0;
    let (b0, b1, b2) = if hp {
        let kk = k * k * inv;
        (kk, -2.0 * kk, kk)
    } else {
        let bb = b * inv;
        (bb, 2.0 * bb, bb)
    };
    BiquadCoeffs { b0, b1, b2, a1: a1 * inv, a2: a2 * inv }
}

/// First-order real-pole section (Butterworth odd orders).
fn section_1st(mut sigma_n: f64, omega_a: f64, hp: bool, fs: f64) -> BiquadCoeffs {
    if hp && sigma_n > 0.0 {
        sigma_n = 1.0 / sigma_n;
    }
    let sigma = sigma_n * omega_a;
    let k = 2.0 * fs;
    let inv = 1.0 / (k + sigma);
    let (b0, b1) = if hp { (k * inv, -k * inv) } else { (sigma * inv, sigma * inv) };
    BiquadCoeffs { b0, b1, b2: 0.0, a1: (sigma - k) * inv, a2: 0.0 }
}

// ── Response evaluation ─────────────────────────────────────────────

/// |H(e^jw)|² of one biquad, written in φ = sin²(w/2) (the RBJ plotting form).
/// Unlike evaluating numerator and denominator at e^jw directly, this keeps
/// the resonance of low, narrow sections (a 10 Hz, Q 20 bell).
fn mag_squared(c: &BiquadCoeffs, w: f64) -> f64 {
    let s = (w / 2.0).sin();
    let phi = s * s;
    let sb = c.b0 + c.b1 + c.b2;
    let sa = 1.0 + c.a1 + c.a2;
    let num = sb * sb - 4.0 * (c.b0 * c.b1 + c.b1 * c.b2 + 4.0 * c.b0 * c.b2) * phi + 16.0 * c.b0 * c.b2 * phi * phi;
    let den = sa * sa - 4.0 * (c.a1 + c.a1 * c.a2 + 4.0 * c.a2) * phi + 16.0 * c.a2 * phi * phi;
    if den <= 0.0 {
        1.0
    } else {
        num.max(0.0) / den
    }
}

/// Phase (radians) of one biquad at angular frequency w.
fn phase(c: &BiquadCoeffs, w: f64) -> f64 {
    let (sw, cw) = w.sin_cos();
    let (s2w, c2w) = (2.0 * w).sin_cos();
    let nr = c.b0 + c.b1 * cw + c.b2 * c2w;
    let ni = -(c.b1 * sw + c.b2 * s2w);
    let dr = 1.0 + c.a1 * cw + c.a2 * c2w;
    let di = -(c.a1 * sw + c.a2 * s2w);
    ni.atan2(nr) - di.atan2(dr)
}

fn active(f: &FilterParams) -> bool {
    f.filter_type != FILTER_FLAT && !f.bypass
}

/// Magnitude in dB at `freq` of a chain of bands (PEQ and crossover alike).
/// Bypassed and off bands are skipped.
pub fn response_at(freq: f32, filters: &[FilterParams]) -> f32 {
    let w = 2.0 * PI * freq as f64 / SAMPLE_RATE;
    let mut mag = 1.0;
    for f in filters.iter().filter(|f| active(f)) {
        for c in sections_for(f, SAMPLE_RATE) {
            mag *= mag_squared(&c, w);
        }
    }
    (10.0 * mag.max(1e-30).log10()) as f32
}

/// Phase in degrees at `freq`, wrapped to [−180, 180].
pub fn phase_at(freq: f32, filters: &[FilterParams]) -> f32 {
    let w = 2.0 * PI * freq as f64 / SAMPLE_RATE;
    let mut ph = 0.0;
    for f in filters.iter().filter(|f| active(f)) {
        for c in sections_for(f, SAMPLE_RATE) {
            ph += phase(&c, w);
        }
    }
    let mut deg = (ph * 180.0 / PI) % 360.0;
    if deg > 180.0 {
        deg -= 360.0;
    }
    if deg < -180.0 {
        deg += 360.0;
    }
    deg as f32
}

/// Frequency of curve point `i` (log-spaced, 10 Hz .. 20 kHz).
pub fn curve_freq(i: usize) -> f64 {
    let log_min = 10.0_f64.log10();
    let log_max = 20000.0_f64.log10();
    10.0_f64.powf(log_min + (i as f64 / (MAGNITUDE_POINTS - 1) as f64) * (log_max - log_min))
}

/// Magnitude curve over 201 log-spaced points from 10 Hz to 20 kHz, in dB.
/// Each band is designed once, then evaluated at every point.
pub fn compute_magnitude_curve(filters: &[FilterParams]) -> [f64; MAGNITUDE_POINTS] {
    let sections: Vec<BiquadCoeffs> =
        filters.iter().filter(|f| active(f)).flat_map(|f| sections_for(f, SAMPLE_RATE)).collect();
    let mut out = [0.0; MAGNITUDE_POINTS];
    for (i, v) in out.iter_mut().enumerate() {
        let w = 2.0 * PI * curve_freq(i) / SAMPLE_RATE;
        let mag: f64 = sections.iter().map(|c| mag_squared(c, w)).product();
        *v = 10.0 * mag.max(1e-30).log10();
    }
    out
}

/// Phase curve in degrees over the same 201 points; unwrapped when `unwrap`
/// is set (continuous across ±180°), otherwise wrapped to [−180, 180].
pub fn compute_phase_curve(filters: &[FilterParams], unwrap: bool) -> [f64; MAGNITUDE_POINTS] {
    let mut out = [0.0; MAGNITUDE_POINTS];
    for (i, v) in out.iter_mut().enumerate() {
        *v = phase_at(curve_freq(i) as f32, filters) as f64;
    }
    if unwrap {
        for i in 1..MAGNITUDE_POINTS {
            let mut d = out[i] - out[i - 1];
            while d > 180.0 {
                d -= 360.0;
            }
            while d <= -180.0 {
                d += 360.0;
            }
            out[i] = out[i - 1] + d;
        }
    }
    out
}

/// Quantize gain to 0.1 dB, mapping −0.0 to 0.0.
pub fn quantize_gain(db: f32) -> f32 {
    let val = (db * 10.0).round() / 10.0;
    if val == 0.0 {
        0.0
    } else {
        val
    }
}

/// Quantize delay to whole milliseconds, mapping −0.0 to 0.0.
pub fn quantize_delay(ms: f32) -> f32 {
    let val = ms.round();
    if val == 0.0 {
        0.0
    } else {
        val
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn band(t: u8, freq: f32, q: f32, gain: f32) -> FilterParams {
        FilterParams { filter_type: t, freq, q, gain, ..Default::default() }
    }

    #[test]
    fn flat_is_zero_db() {
        assert!(response_at(1000.0, &[band(FILTER_FLAT, 1000.0, 0.707, 0.0)]).abs() < 0.001);
    }

    #[test]
    fn peaking_hits_gain_at_center_only() {
        let f = [band(FILTER_PEAKING, 1000.0, 1.0, 6.0)];
        assert!((response_at(1000.0, &f) - 6.0).abs() < 0.01);
        assert!(response_at(20.0, &f).abs() < 0.5);
    }

    #[test]
    fn bypassed_band_is_ignored() {
        let mut f = band(FILTER_PEAKING, 1000.0, 1.0, 6.0);
        f.bypass = true;
        assert!(response_at(1000.0, &[f]).abs() < 0.001);
    }

    #[test]
    fn low_and_high_pass() {
        let lp = [band(FILTER_LOWPASS, 1000.0, 0.707, 0.0)];
        assert!(response_at(20.0, &lp).abs() < 0.5);
        assert!(response_at(10000.0, &lp) < -20.0);
        let hp = [band(FILTER_HIGHPASS, 1000.0, 0.707, 0.0)];
        assert!(response_at(10000.0, &hp).abs() < 0.5);
        assert!(response_at(100.0, &hp) < -20.0);
    }

    #[test]
    fn shelves() {
        let ls = [band(FILTER_LOWSHELF, 200.0, 0.707, 6.0)];
        assert!((response_at(20.0, &ls) - 6.0).abs() < 1.0);
        assert!(response_at(10000.0, &ls).abs() < 0.5);
        let hs = [band(FILTER_HIGHSHELF, 5000.0, 0.707, 6.0)];
        assert!((response_at(20000.0, &hs) - 6.0).abs() < 1.0);
        assert!(response_at(100.0, &hs).abs() < 0.5);
    }

    #[test]
    fn first_order_types() {
        let lp1 = [band(FILTER_LOWPASS1, 1000.0, 0.707, 0.0)];
        assert!((response_at(1000.0, &lp1) + 3.01).abs() < 0.1);
        // 6 dB/oct: one decade above the corner is about −20 dB.
        assert!((response_at(10000.0, &lp1) + 20.0).abs() < 1.5);
        let ap1 = [band(FILTER_ALLPASS1, 1000.0, 0.707, 0.0)];
        assert!(response_at(300.0, &ap1).abs() < 0.001);
        assert!((phase_at(1000.0, &ap1) + 90.0).abs() < 0.5);
        let ls1 = [band(FILTER_LOWSHELF1, 100.0, 0.707, 6.0)];
        assert!((response_at(10.0, &ls1) - 6.0).abs() < 0.5);
    }

    #[test]
    fn notch_and_allpass() {
        assert!(response_at(1000.0, &[band(FILTER_NOTCH, 1000.0, 2.0, 0.0)]) < -40.0);
        let ap = [band(FILTER_ALLPASS, 1000.0, 0.707, 0.0)];
        assert!(response_at(400.0, &ap).abs() < 0.001);
        assert!((phase_at(1000.0, &ap).abs() - 180.0).abs() < 0.5);
    }

    #[test]
    fn linkwitz_transform_shifts_the_corner() {
        // f0 = 50 Hz Q0 = 1.0 → fp = 25 Hz Qp = 0.707: big boost around 25-40 Hz,
        // flat well above both corners.
        let mut lt = band(FILTER_LINKWITZ_TRANSFORM, 50.0, 1.0, 25.0);
        lt.qp = 0.707;
        assert!(response_at(20.0, &[lt]) > 6.0);
        assert!(response_at(2000.0, &[lt]).abs() < 0.1);
    }

    #[test]
    fn crossovers_are_minus_3_or_6_db_at_fc() {
        // Butterworth: −3 dB at fc; Linkwitz-Riley: −6 dB at fc.
        for (t, want) in [(46u8, -3.01), (47, -3.01), (34, -6.02), (35, -6.02), (38, -6.02), (44, -3.01)] {
            let r = response_at(1000.0, &[band(t, 1000.0, 0.707, 0.0)]);
            assert!((r - want as f32).abs() < 0.1, "type {t}: {r} dB at fc");
        }
        // LR4 LP: 24 dB/oct, so about −48 dB two octaves up... at least −40.
        assert!(response_at(4000.0, &[band(34, 1000.0, 0.707, 0.0)]) < -40.0);
        // Bessel 4 LP passes DC and rolls off.
        let bes = [band(58, 1000.0, 0.707, 0.0)];
        assert!(response_at(20.0, &bes).abs() < 0.1);
        assert!(response_at(10000.0, &bes) < -30.0);
    }

    #[test]
    fn crossover_section_counts() {
        assert_eq!(crossover_sections(32, 1000.0, SAMPLE_RATE).len(), 1); // LR2
        assert_eq!(crossover_sections(38, 1000.0, SAMPLE_RATE).len(), 4); // LR8
        assert_eq!(crossover_sections(44, 1000.0, SAMPLE_RATE).len(), 2); // BW3
        assert_eq!(crossover_sections(62, 1000.0, SAMPLE_RATE).len(), 4); // Bessel 8
    }

    #[test]
    fn curve_shapes() {
        let f = [band(FILTER_PEAKING, 1000.0, 1.0, 6.0)];
        let m = compute_magnitude_curve(&f);
        assert_eq!(m.len(), 201);
        assert!((curve_freq(0) - 10.0).abs() < 1e-9);
        assert!((curve_freq(200) - 20000.0).abs() < 1e-6);
        // The curve and the point evaluation agree.
        assert!((m[120] - response_at(curve_freq(120) as f32, &f) as f64).abs() < 0.01);
        let p = compute_phase_curve(&[band(38, 1000.0, 0.707, 0.0)], true);
        assert!(p[200] < -500.0, "LR8 unwrapped phase should pass −540°, got {}", p[200]);
    }

    #[test]
    fn quantize() {
        assert_eq!(quantize_gain(3.14), 3.1);
        assert_eq!(quantize_gain(3.15), 3.2);
        assert_eq!(quantize_gain(-0.0).to_bits(), 0.0f32.to_bits());
        assert_eq!(quantize_delay(-0.2).to_bits(), 0.0f32.to_bits());
    }
}
