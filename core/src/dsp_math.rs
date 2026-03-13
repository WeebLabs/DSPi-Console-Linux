//! Biquad coefficient calculation and frequency response analysis.
//!
//! Direct port of DSPMath.swift. Uses f64 internally for precision,
//! matching the Swift implementation's Double precision.

use crate::types::FilterParams;
use crate::types::FilterType;

const SAMPLE_RATE: f64 = 48000.0;

/// Number of magnitude curve points (log-spaced from 10 Hz to 20 kHz).
pub const MAGNITUDE_POINTS: usize = 201;

/// Biquad coefficients (normalized, a0 = 1).
#[derive(Debug, Clone, Copy)]
pub struct BiquadCoeffs {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

/// Calculate biquad coefficients from filter parameters.
/// Uses f64 precision internally, same formulas as DSPMath.swift.
pub fn calculate_coefficients(params: &FilterParams) -> BiquadCoeffs {
    if matches!(params.filter_type, FilterType::Flat) {
        return BiquadCoeffs {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
        };
    }

    let freq = params.freq as f64;
    let q = params.q as f64;
    let gain = params.gain as f64;

    let omega = 2.0 * std::f64::consts::PI * freq / SAMPLE_RATE;
    let sn = omega.sin();
    let cs = omega.cos();
    let alpha = sn / (2.0 * q);
    let a_lin = 10.0_f64.powf(gain / 40.0); // A = 10^(gain/40)

    let (b0, b1, b2, a0, a1, a2) = match params.filter_type {
        FilterType::LowPass => (
            (1.0 - cs) / 2.0,
            1.0 - cs,
            (1.0 - cs) / 2.0,
            1.0 + alpha,
            -2.0 * cs,
            1.0 - alpha,
        ),
        FilterType::HighPass => (
            (1.0 + cs) / 2.0,
            -(1.0 + cs),
            (1.0 + cs) / 2.0,
            1.0 + alpha,
            -2.0 * cs,
            1.0 - alpha,
        ),
        FilterType::Peaking => (
            1.0 + alpha * a_lin,
            -2.0 * cs,
            1.0 - alpha * a_lin,
            1.0 + alpha / a_lin,
            -2.0 * cs,
            1.0 - alpha / a_lin,
        ),
        FilterType::LowShelf => {
            let sqrt_a = a_lin.sqrt();
            (
                a_lin * ((a_lin + 1.0) - (a_lin - 1.0) * cs + 2.0 * sqrt_a * alpha),
                2.0 * a_lin * ((a_lin - 1.0) - (a_lin + 1.0) * cs),
                a_lin * ((a_lin + 1.0) - (a_lin - 1.0) * cs - 2.0 * sqrt_a * alpha),
                (a_lin + 1.0) + (a_lin - 1.0) * cs + 2.0 * sqrt_a * alpha,
                -2.0 * ((a_lin - 1.0) + (a_lin + 1.0) * cs),
                (a_lin + 1.0) + (a_lin - 1.0) * cs - 2.0 * sqrt_a * alpha,
            )
        }
        FilterType::HighShelf => {
            let sqrt_a = a_lin.sqrt();
            (
                a_lin * ((a_lin + 1.0) + (a_lin - 1.0) * cs + 2.0 * sqrt_a * alpha),
                -2.0 * a_lin * ((a_lin - 1.0) + (a_lin + 1.0) * cs),
                a_lin * ((a_lin + 1.0) + (a_lin - 1.0) * cs - 2.0 * sqrt_a * alpha),
                (a_lin + 1.0) - (a_lin - 1.0) * cs + 2.0 * sqrt_a * alpha,
                2.0 * ((a_lin - 1.0) - (a_lin + 1.0) * cs),
                (a_lin + 1.0) - (a_lin - 1.0) * cs - 2.0 * sqrt_a * alpha,
            )
        }
        FilterType::Flat => unreachable!(),
    };

    BiquadCoeffs {
        b0: b0 / a0,
        b1: b1 / a0,
        b2: b2 / a0,
        a1: a1 / a0,
        a2: a2 / a0,
    }
}

/// Compute frequency response magnitude in dB at a single frequency
/// for a chain of filters. Matches DSPMath.responseAt() from Swift.
pub fn response_at(freq: f32, filters: &[FilterParams]) -> f32 {
    let mut mag_sq_total: f64 = 1.0;
    let freq_d = freq as f64;

    for f in filters {
        if matches!(f.filter_type, FilterType::Flat) {
            continue;
        }

        let coeffs = calculate_coefficients(f);
        let w = 2.0 * std::f64::consts::PI * freq_d / SAMPLE_RATE;

        let cos_w = w.cos();
        let cos_2w = (2.0 * w).cos();
        let sin_w = w.sin();
        let sin_2w = (2.0 * w).sin();

        // Numerator
        let num_r = coeffs.b0 + coeffs.b1 * cos_w + coeffs.b2 * cos_2w;
        let num_i = -(coeffs.b1 * sin_w + coeffs.b2 * sin_2w);

        // Denominator (a0 normalized to 1)
        let den_r = 1.0 + coeffs.a1 * cos_w + coeffs.a2 * cos_2w;
        let den_i = -(coeffs.a1 * sin_w + coeffs.a2 * sin_2w);

        let num_mag_sq = num_r * num_r + num_i * num_i;
        let den_mag_sq = den_r * den_r + den_i * den_i;

        if den_mag_sq > 1e-15 {
            mag_sq_total *= num_mag_sq / den_mag_sq;
        }
    }

    (10.0 * mag_sq_total.log10()) as f32
}

/// Compute magnitude curve over 201 log-spaced points from 10 Hz to 20 kHz.
/// Returns array of dB values (f64 precision).
pub fn compute_magnitude_curve(filters: &[FilterParams]) -> [f64; MAGNITUDE_POINTS] {
    let mut magnitudes = [0.0f64; MAGNITUDE_POINTS];
    let log_min = 10.0_f64.log10(); // log10(10) = 1.0
    let log_max = 20000.0_f64.log10(); // log10(20000) ≈ 4.301

    for i in 0..MAGNITUDE_POINTS {
        let log_freq = log_min + (i as f64 / 200.0) * (log_max - log_min);
        let freq = 10.0_f64.powf(log_freq);
        magnitudes[i] = response_at(freq as f32, filters) as f64;
    }

    magnitudes
}

/// Quantize gain to 0.1 dB resolution, handling -0.0 → 0.0.
/// Matches the Swift pattern: `(db * 10).rounded() / 10`
pub fn quantize_gain(db: f32) -> f32 {
    let val = (db * 10.0).round() / 10.0;
    if val == -0.0 { 0.0 } else { val }
}

/// Quantize delay to integer ms, handling -0.0 → 0.0.
pub fn quantize_delay(ms: f32) -> f32 {
    let val = ms.round();
    if val == -0.0 { 0.0 } else { val }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::FilterType;

    #[test]
    fn test_flat_filter_response() {
        let filters = [FilterParams {
            filter_type: FilterType::Flat,
            freq: 1000.0,
            q: 0.707,
            gain: 0.0,
        }];
        let resp = response_at(1000.0, &filters);
        assert!((resp - 0.0).abs() < 0.001, "Flat filter should be 0 dB, got {resp}");
    }

    #[test]
    fn test_peaking_filter_at_center() {
        let filters = [FilterParams {
            filter_type: FilterType::Peaking,
            freq: 1000.0,
            q: 1.0,
            gain: 6.0,
        }];
        let resp = response_at(1000.0, &filters);
        assert!(
            (resp - 6.0).abs() < 0.01,
            "Peaking at center should be ~6 dB, got {resp}"
        );
    }

    #[test]
    fn test_peaking_filter_away_from_center() {
        let filters = [FilterParams {
            filter_type: FilterType::Peaking,
            freq: 1000.0,
            q: 1.0,
            gain: 6.0,
        }];
        // Far from center frequency, response should be near 0 dB
        let resp = response_at(20.0, &filters);
        assert!(resp.abs() < 0.5, "Peaking far from center should be ~0 dB, got {resp}");
    }

    #[test]
    fn test_low_pass_filter() {
        let filters = [FilterParams {
            filter_type: FilterType::LowPass,
            freq: 1000.0,
            q: 0.707,
            gain: 0.0,
        }];
        // At DC-ish should be ~0 dB
        let resp_low = response_at(20.0, &filters);
        assert!(resp_low.abs() < 0.5, "LP at 20Hz should be ~0 dB, got {resp_low}");
        // Well above cutoff should be negative
        let resp_high = response_at(10000.0, &filters);
        assert!(resp_high < -20.0, "LP at 10kHz should be < -20 dB, got {resp_high}");
    }

    #[test]
    fn test_high_pass_filter() {
        let filters = [FilterParams {
            filter_type: FilterType::HighPass,
            freq: 1000.0,
            q: 0.707,
            gain: 0.0,
        }];
        let resp_high = response_at(10000.0, &filters);
        assert!(resp_high.abs() < 0.5, "HP at 10kHz should be ~0 dB, got {resp_high}");
        let resp_low = response_at(100.0, &filters);
        assert!(resp_low < -20.0, "HP at 100Hz should be < -20 dB, got {resp_low}");
    }

    #[test]
    fn test_magnitude_curve_length() {
        let filters = [FilterParams::default()];
        let curve = compute_magnitude_curve(&filters);
        assert_eq!(curve.len(), 201);
    }

    #[test]
    fn test_quantize_gain() {
        assert_eq!(quantize_gain(3.14), 3.1);
        assert_eq!(quantize_gain(3.15), 3.2);
        assert_eq!(quantize_gain(-0.0), 0.0);
        assert_eq!(quantize_gain(0.0), 0.0);
    }

    #[test]
    fn test_low_shelf() {
        let filters = [FilterParams {
            filter_type: FilterType::LowShelf,
            freq: 200.0,
            q: 0.707,
            gain: 6.0,
        }];
        let resp_low = response_at(20.0, &filters);
        assert!(
            (resp_low - 6.0).abs() < 1.0,
            "Low shelf at 20Hz should be ~6 dB, got {resp_low}"
        );
        let resp_high = response_at(10000.0, &filters);
        assert!(resp_high.abs() < 0.5, "Low shelf at 10kHz should be ~0 dB, got {resp_high}");
    }

    #[test]
    fn test_high_shelf() {
        let filters = [FilterParams {
            filter_type: FilterType::HighShelf,
            freq: 5000.0,
            q: 0.707,
            gain: 6.0,
        }];
        let resp_high = response_at(20000.0, &filters);
        assert!(
            (resp_high - 6.0).abs() < 1.0,
            "High shelf at 20kHz should be ~6 dB, got {resp_high}"
        );
        let resp_low = response_at(100.0, &filters);
        assert!(resp_low.abs() < 0.5, "High shelf at 100Hz should be ~0 dB, got {resp_low}");
    }
}
