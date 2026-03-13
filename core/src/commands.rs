//! High-level command functions — mirrors Commands.swift.
//!
//! Each function combines USB transfers with state updates.

use log::warn;

use crate::dsp_math::quantize_gain;
use crate::dsp_math::quantize_delay;
use crate::protocol::*;
use crate::types::*;
use crate::usb::{Result, UsbError};
use crate::DspiCore;

impl DspiCore {
    // ═══════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════

    pub(crate) fn conn(&self) -> Result<&crate::usb::UsbConnection> {
        self.device_manager.connection().ok_or(UsbError::NotConnected)
    }

    pub(crate) fn send(&self, request: u8, value: u16, index: u16, data: &[u8]) -> Result<()> {
        self.conn()?.send_control(request, value, index, data)
    }

    pub(crate) fn get(&self, request: u8, value: u16, index: u16, length: u16) -> Result<Vec<u8>> {
        self.conn()?.get_control(request, value, index, length)
    }

    pub(crate) fn get_exact(&self, request: u8, value: u16, index: u16, length: u16, min: usize) -> Result<Vec<u8>> {
        self.conn()?.get_control_exact(request, value, index, length, min)
    }

    // ═══════════════════════════════════════════════════════════════
    // Bulk Operations
    // ═══════════════════════════════════════════════════════════════

    /// Fetch all parameters via GET_ALL_PARAMS and update state.
    pub fn fetch_all(&mut self) -> Result<()> {
        self.fetch_all_params()?;
        self.fetch_core1_mode_internal();
        self.fetch_preset_directory_internal();
        for slot in 0..MAX_PRESETS as u8 {
            self.fetch_preset_name_internal(slot);
        }
        self.fetch_preset_active_internal();
        Ok(())
    }

    /// Fetch and parse bulk parameters. Returns false on failure.
    fn fetch_all_params(&mut self) -> Result<()> {
        let data = self.get_exact(REQ_GET_ALL_PARAMS, 0, WINDEX_OUTPUT, BULK_PARAMS_SIZE, BULK_PARAMS_SIZE as usize)?;
        let bp = BulkParams::from_bytes(&data)
            .map_err(|_| UsbError::ShortRead { expected: BULK_PARAMS_SIZE as usize, actual: data.len() })?;
        self.state.apply_bulk_params(&bp);
        Ok(())
    }

    /// Fetch device status (peaks, CPU, clips).
    pub fn fetch_status(&mut self) -> Result<SystemStatus> {
        let num_ch = self.state.num_channels as usize;
        let response_size = (num_ch * 2 + 4) as u16;
        let data = self.get_exact(REQ_GET_STATUS, 9, WINDEX_GLOBAL, response_size, response_size as usize)?;
        parse_status(&data, num_ch).ok_or(UsbError::ShortRead {
            expected: response_size as usize,
            actual: data.len(),
        })
    }

    // ═══════════════════════════════════════════════════════════════
    // EQ
    // ═══════════════════════════════════════════════════════════════

    /// Set a filter band's parameters.
    pub fn set_filter(&mut self, ch: u8, band: u8, mut params: FilterParams) -> Result<()> {
        params.gain = quantize_gain(params.gain);
        self.state.filters[ch as usize][band as usize] = params;
        let packet = build_set_filter_packet(ch, band, &params);
        self.send(REQ_SET_EQ_PARAM, 0, WINDEX_GLOBAL, &packet)
    }

    /// Fetch a single filter band's parameters.
    pub fn fetch_filter(&mut self, ch: u8, band: u8) -> Result<FilterParams> {
        // Param 0 = type (u32), 1 = freq (f32), 2 = q (f32), 3 = gain (f32)
        let get_f32 = |param: u8| -> Result<f32> {
            let wval = eq_param_wvalue(ch, band, param);
            let data = self.get_exact(REQ_GET_EQ_PARAM, wval, WINDEX_GLOBAL, 4, 4)?;
            Ok(f32::from_le_bytes([data[0], data[1], data[2], data[3]]))
        };

        let type_wval = eq_param_wvalue(ch, band, 0);
        let type_data = self.get_exact(REQ_GET_EQ_PARAM, type_wval, WINDEX_GLOBAL, 4, 4)?;
        let type_raw = u32::from_le_bytes([type_data[0], type_data[1], type_data[2], type_data[3]]);

        let params = FilterParams {
            filter_type: FilterType::from_u32(type_raw),
            freq: get_f32(1)?,
            q: get_f32(2)?,
            gain: get_f32(3)?,
        };

        self.state.filters[ch as usize][band as usize] = params;
        Ok(params)
    }

    // ═══════════════════════════════════════════════════════════════
    // Global (Preamp / Bypass)
    // ═══════════════════════════════════════════════════════════════

    pub fn set_preamp(&mut self, db: f32) -> Result<()> {
        let val = quantize_gain(db);
        self.state.preamp_db = val;
        self.send(REQ_SET_PREAMP, 0, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    pub fn fetch_preamp(&mut self) -> Result<f32> {
        let data = self.get_exact(REQ_GET_PREAMP, 0, WINDEX_GLOBAL, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.preamp_db = val;
        Ok(val)
    }

    pub fn set_bypass(&mut self, enabled: bool) -> Result<()> {
        self.state.bypass = enabled;
        self.send(REQ_SET_BYPASS, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn fetch_bypass(&mut self) -> Result<bool> {
        let data = self.get_exact(REQ_GET_BYPASS, 0, WINDEX_GLOBAL, 1, 1)?;
        let val = data[0] != 0;
        self.state.bypass = val;
        Ok(val)
    }

    // ═══════════════════════════════════════════════════════════════
    // Delay
    // ═══════════════════════════════════════════════════════════════

    pub fn set_delay(&mut self, ch: u8, ms: f32) -> Result<()> {
        let val = quantize_delay(ms);
        self.state.channel_delays[ch as usize] = val;
        self.send(REQ_SET_DELAY, ch as u16, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    pub fn fetch_delay(&mut self, ch: u8) -> Result<f32> {
        let data = self.get_exact(REQ_GET_DELAY, ch as u16, WINDEX_GLOBAL, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.channel_delays[ch as usize] = val;
        Ok(val)
    }

    // ═══════════════════════════════════════════════════════════════
    // Loudness
    // ═══════════════════════════════════════════════════════════════

    pub fn set_loudness(&mut self, enabled: bool) -> Result<()> {
        self.state.loudness_enabled = enabled;
        self.send(REQ_SET_LOUDNESS, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn fetch_loudness(&mut self) -> Result<bool> {
        let data = self.get_exact(REQ_GET_LOUDNESS, 0, WINDEX_GLOBAL, 1, 1)?;
        let val = data[0] != 0;
        self.state.loudness_enabled = val;
        Ok(val)
    }

    pub fn set_loudness_ref(&mut self, spl: f32) -> Result<()> {
        self.state.loudness_ref_spl = spl;
        self.send(REQ_SET_LOUDNESS_REF, 0, WINDEX_GLOBAL, &spl.to_le_bytes())
    }

    pub fn fetch_loudness_ref(&mut self) -> Result<f32> {
        let data = self.get_exact(REQ_GET_LOUDNESS_REF, 0, WINDEX_GLOBAL, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.loudness_ref_spl = val;
        Ok(val)
    }

    pub fn set_loudness_intensity(&mut self, pct: f32) -> Result<()> {
        self.state.loudness_intensity = pct;
        self.send(REQ_SET_LOUDNESS_INTENSITY, 0, WINDEX_GLOBAL, &pct.to_le_bytes())
    }

    pub fn fetch_loudness_intensity(&mut self) -> Result<f32> {
        let data = self.get_exact(REQ_GET_LOUDNESS_INTENSITY, 0, WINDEX_GLOBAL, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.loudness_intensity = val;
        Ok(val)
    }

    // ═══════════════════════════════════════════════════════════════
    // Crossfeed
    // ═══════════════════════════════════════════════════════════════

    pub fn set_crossfeed(&mut self, enabled: bool) -> Result<()> {
        self.state.crossfeed_enabled = enabled;
        self.send(REQ_SET_CROSSFEED, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn fetch_crossfeed(&mut self) -> Result<bool> {
        let data = self.get_exact(REQ_GET_CROSSFEED, 0, WINDEX_GLOBAL, 1, 1)?;
        let val = data[0] != 0;
        self.state.crossfeed_enabled = val;
        Ok(val)
    }

    pub fn set_crossfeed_preset(&mut self, preset: u8) -> Result<()> {
        self.state.crossfeed_preset = preset;
        self.send(REQ_SET_CROSSFEED_PRESET, 0, WINDEX_GLOBAL, &[preset])?;
        // Apply known preset values locally (matches Swift behavior)
        static PRESET_VALUES: [(f32, f32); 3] = [
            (700.0, 4.5),   // Default
            (700.0, 6.0),   // Chu Moy
            (650.0, 9.5),   // Jan Meier
        ];
        if (preset as usize) < PRESET_VALUES.len() {
            self.state.crossfeed_freq = PRESET_VALUES[preset as usize].0;
            self.state.crossfeed_feed = PRESET_VALUES[preset as usize].1;
        }
        Ok(())
    }

    pub fn fetch_crossfeed_preset(&mut self) -> Result<u8> {
        let data = self.get_exact(REQ_GET_CROSSFEED_PRESET, 0, WINDEX_GLOBAL, 1, 1)?;
        self.state.crossfeed_preset = data[0];
        Ok(data[0])
    }

    pub fn set_crossfeed_freq(&mut self, freq: f32) -> Result<()> {
        self.state.crossfeed_freq = freq;
        self.send(REQ_SET_CROSSFEED_FREQ, 0, WINDEX_GLOBAL, &freq.to_le_bytes())
    }

    pub fn fetch_crossfeed_freq(&mut self) -> Result<f32> {
        let data = self.get_exact(REQ_GET_CROSSFEED_FREQ, 0, WINDEX_GLOBAL, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.crossfeed_freq = val;
        Ok(val)
    }

    pub fn set_crossfeed_feed(&mut self, feed: f32) -> Result<()> {
        self.state.crossfeed_feed = feed;
        self.send(REQ_SET_CROSSFEED_FEED, 0, WINDEX_GLOBAL, &feed.to_le_bytes())
    }

    pub fn fetch_crossfeed_feed(&mut self) -> Result<f32> {
        let data = self.get_exact(REQ_GET_CROSSFEED_FEED, 0, WINDEX_GLOBAL, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.crossfeed_feed = val;
        Ok(val)
    }

    pub fn set_crossfeed_itd(&mut self, enabled: bool) -> Result<()> {
        self.state.crossfeed_itd = enabled;
        self.send(REQ_SET_CROSSFEED_ITD, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn fetch_crossfeed_itd(&mut self) -> Result<bool> {
        let data = self.get_exact(REQ_GET_CROSSFEED_ITD, 0, WINDEX_GLOBAL, 1, 1)?;
        let val = data[0] != 0;
        self.state.crossfeed_itd = val;
        Ok(val)
    }

    // ═══════════════════════════════════════════════════════════════
    // Matrix Mixer
    // ═══════════════════════════════════════════════════════════════

    pub fn set_matrix_route(
        &mut self,
        input: u8,
        output: u8,
        enabled: bool,
        gain: f32,
        invert: bool,
    ) -> Result<()> {
        self.state.matrix_routing[input as usize][output as usize] = enabled;
        self.state.matrix_gain[input as usize][output as usize] = gain;
        self.state.matrix_invert[input as usize][output as usize] = invert;
        let packet = build_matrix_route_packet(input, output, enabled, gain, invert);
        self.send(REQ_SET_MATRIX_ROUTE, 0, WINDEX_OUTPUT, &packet)
    }

    pub fn fetch_matrix_route(&mut self, input: u8, output: u8) -> Result<(bool, f32, bool)> {
        let wval = matrix_route_wvalue(input, output);
        let data = self.get_exact(REQ_GET_MATRIX_ROUTE, wval, WINDEX_OUTPUT, 9, 9)?;
        let enabled = data[2] != 0;
        let invert = data[3] != 0;
        let gain = f32::from_le_bytes([data[4], data[5], data[6], data[7]]);
        self.state.matrix_routing[input as usize][output as usize] = enabled;
        self.state.matrix_gain[input as usize][output as usize] = gain;
        self.state.matrix_invert[input as usize][output as usize] = invert;
        Ok((enabled, gain, invert))
    }

    // ═══════════════════════════════════════════════════════════════
    // Output Controls
    // ═══════════════════════════════════════════════════════════════

    pub fn set_output_enable(&mut self, output: u8, enabled: bool) -> Result<()> {
        self.state.output_enabled[output as usize] = enabled;
        self.send(REQ_SET_OUTPUT_ENABLE, output as u16, WINDEX_OUTPUT, &[enabled as u8])
    }

    pub fn fetch_output_enable(&mut self, output: u8) -> Result<bool> {
        let data = self.get_exact(REQ_GET_OUTPUT_ENABLE, output as u16, WINDEX_OUTPUT, 1, 1)?;
        let val = data[0] != 0;
        self.state.output_enabled[output as usize] = val;
        Ok(val)
    }

    pub fn set_output_gain(&mut self, output: u8, db: f32) -> Result<()> {
        let val = quantize_gain(db);
        self.state.output_gain_db[output as usize] = val;
        self.send(REQ_SET_OUTPUT_GAIN, output as u16, WINDEX_OUTPUT, &val.to_le_bytes())
    }

    pub fn fetch_output_gain(&mut self, output: u8) -> Result<f32> {
        let data = self.get_exact(REQ_GET_OUTPUT_GAIN, output as u16, WINDEX_OUTPUT, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.output_gain_db[output as usize] = val;
        Ok(val)
    }

    pub fn set_output_mute(&mut self, output: u8, muted: bool) -> Result<()> {
        self.state.output_muted[output as usize] = muted;
        self.send(REQ_SET_OUTPUT_MUTE, output as u16, WINDEX_OUTPUT, &[muted as u8])
    }

    pub fn fetch_output_mute(&mut self, output: u8) -> Result<bool> {
        let data = self.get_exact(REQ_GET_OUTPUT_MUTE, output as u16, WINDEX_OUTPUT, 1, 1)?;
        let val = data[0] != 0;
        self.state.output_muted[output as usize] = val;
        Ok(val)
    }

    pub fn set_output_delay(&mut self, output: u8, ms: f32) -> Result<()> {
        let val = quantize_delay(ms);
        self.state.output_delay_ms[output as usize] = val;
        self.send(REQ_SET_OUTPUT_DELAY, output as u16, WINDEX_OUTPUT, &val.to_le_bytes())
    }

    pub fn fetch_output_delay(&mut self, output: u8) -> Result<f32> {
        let data = self.get_exact(REQ_GET_OUTPUT_DELAY, output as u16, WINDEX_OUTPUT, 4, 4)?;
        let val = f32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        self.state.output_delay_ms[output as usize] = val;
        Ok(val)
    }

    // ═══════════════════════════════════════════════════════════════
    // Core 1 Mode
    // ═══════════════════════════════════════════════════════════════

    pub fn fetch_core1_mode(&mut self) -> Result<u8> {
        let data = self.get_exact(REQ_GET_CORE1_MODE, 0, WINDEX_GLOBAL, 1, 1)?;
        self.state.core1_mode = data[0];
        Ok(data[0])
    }

    /// Internal version that doesn't propagate errors.
    fn fetch_core1_mode_internal(&mut self) {
        if let Err(e) = self.fetch_core1_mode() {
            warn!("Failed to fetch core1 mode: {e}");
        }
    }

    pub fn check_core1_conflict(&mut self, output: u8) -> Result<bool> {
        let data = self.get_exact(REQ_GET_CORE1_CONFLICT, output as u16, WINDEX_GLOBAL, 1, 1)?;
        Ok(data[0] != 0)
    }

    // ═══════════════════════════════════════════════════════════════
    // Pin Configuration
    // ═══════════════════════════════════════════════════════════════

    /// Set GPIO pin for a physical output. Returns firmware status code.
    /// SET is an IN transfer: wValue = (new_pin << 8) | output_index
    pub fn set_output_pin(&mut self, output: u8, pin: u8) -> Result<u8> {
        let wval = pin_config_wvalue(pin, output);
        let data = self.get_exact(REQ_SET_OUTPUT_PIN, wval, WINDEX_OUTPUT, 1, 1)?;
        let status = data[0];
        if status == PIN_CONFIG_SUCCESS {
            self.state.output_pins[output as usize] = pin;
        }
        Ok(status)
    }

    pub fn fetch_output_pin(&mut self, output: u8) -> Result<u8> {
        let data = self.get_exact(REQ_GET_OUTPUT_PIN, output as u16, WINDEX_OUTPUT, 1, 1)?;
        self.state.output_pins[output as usize] = data[0];
        Ok(data[0])
    }

    // ═══════════════════════════════════════════════════════════════
    // Channel Names
    // ═══════════════════════════════════════════════════════════════

    pub fn set_channel_name(&mut self, channel: u8, name: &str) -> Result<()> {
        let buf = name_to_bytes(name);
        self.state.channel_names[channel as usize] = buf;
        self.send(REQ_SET_CHANNEL_NAME, channel as u16, WINDEX_OUTPUT, &buf)
    }

    pub fn fetch_channel_name(&mut self, channel: u8) -> Result<String> {
        let data = self.get_exact(REQ_GET_CHANNEL_NAME, channel as u16, WINDEX_OUTPUT, 32, 1)?;
        let mut buf = [0u8; CHANNEL_NAME_LEN];
        let len = data.len().min(CHANNEL_NAME_LEN);
        buf[..len].copy_from_slice(&data[..len]);
        self.state.channel_names[channel as usize] = buf;
        Ok(name_from_bytes(&buf))
    }

    // ═══════════════════════════════════════════════════════════════
    // Flash Storage
    // ═══════════════════════════════════════════════════════════════

    pub fn save_params(&mut self) -> Result<u8> {
        let data = self.get_exact(REQ_SAVE_PARAMS, 0, WINDEX_GLOBAL, 1, 1)?;
        Ok(data[0])
    }

    pub fn load_params(&mut self) -> Result<u8> {
        let data = self.get_exact(REQ_LOAD_PARAMS, 0, WINDEX_GLOBAL, 1, 1)?;
        let status = data[0];
        if status == FLASH_OK {
            self.fetch_all()?;
        }
        Ok(status)
    }

    pub fn factory_reset(&mut self) -> Result<u8> {
        let data = self.get_exact(REQ_FACTORY_RESET, 0, WINDEX_GLOBAL, 1, 1)?;
        let status = data[0];
        if status == FLASH_OK {
            self.fetch_all()?;
        }
        Ok(status)
    }

    // ═══════════════════════════════════════════════════════════════
    // Clip Detection
    // ═══════════════════════════════════════════════════════════════

    pub fn clear_clips(&mut self) -> Result<()> {
        let _ = self.get(REQ_CLEAR_CLIPS, 0, WINDEX_GLOBAL, 2)?;
        Ok(())
    }
}
