//! High-level command functions (mirrors the macOS Console's Commands.swift).
//!
//! Each function combines USB transfers with state updates. Channel
//! arguments are wire channel indices; output arguments are output indices.

use std::thread;
use std::time::Duration;

use log::warn;

use crate::dsp_math::{quantize_delay, quantize_gain};
use crate::protocol::*;
use crate::state::*;
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

    fn get_u8(&self, request: u8, value: u16, index: u16) -> Result<u8> {
        Ok(self.get_exact(request, value, index, 1, 1)?[0])
    }

    /// Longest delay the firmware's delay line holds (2048 samples on RP2350,
    /// 1024 on RP2040, at 48 kHz).
    pub fn max_delay_ms(&self) -> f32 {
        if self.state.platform_id == 1 {
            42.0
        } else {
            21.0
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Connect-time sync
    // ═══════════════════════════════════════════════════════════════

    /// Identify the firmware and, if it is compatible, read every parameter.
    /// Returns Ok even for incompatible firmware (check `state.compat`); an
    /// Err means the device could not be talked to at all.
    pub fn fetch_all(&mut self) -> Result<()> {
        if self.device_manager.connected_vendor_id() == Some(LEGACY_VENDOR_ID) {
            // Pre-May-2026 firmware: wire format far older than V32.
            self.fetch_platform().ok();
            self.state.compat = COMPAT_FIRMWARE_TOO_OLD;
            return Ok(());
        }

        self.fetch_platform()?;
        match self.fetch_all_params() {
            Ok(()) => self.state.compat = COMPAT_OK,
            Err(FetchError::Usb(e)) => return Err(e),
            Err(FetchError::Bulk(BulkError::UnsupportedVersion(v))) => {
                self.state.format_version = v;
                self.state.compat = if v > WIRE_FORMAT_VERSION {
                    COMPAT_FIRMWARE_TOO_NEW
                } else {
                    COMPAT_FIRMWARE_TOO_OLD
                };
                return Ok(());
            }
            Err(FetchError::Bulk(BulkError::TooShort)) => {
                self.state.compat = COMPAT_FIRMWARE_TOO_OLD;
                return Ok(());
            }
        }

        let st = &self.state;
        log::debug!(
            "Firmware {}.{}.{} on {}, input source {}, user volume {} dB",
            st.fw_major, st.fw_minor, st.fw_patch, st.platform_name(), st.input_source, st.user_volume_db
        );
        self.fetch_core1_mode_internal();
        self.fetch_subharm_solo_internal();
        let _ = self.fetch_dac_mute();
        let _ = self.fetch_ctrl_ifaces();
        self.fetch_preset_directory_internal();
        for slot in 0..MAX_PRESETS as u8 {
            self.fetch_preset_name_internal(slot);
        }
        Ok(())
    }

    /// Read platform and firmware version (REQ_GET_PLATFORM).
    pub fn fetch_platform(&mut self) -> Result<PlatformInfo> {
        let data = self.get_exact(REQ_GET_PLATFORM, 0, WINDEX_GLOBAL, 7, 4)?;
        let info = parse_platform(&data).ok_or(UsbError::ShortRead { expected: 4, actual: data.len() })?;
        let s = &mut self.state;
        s.platform_id = info.platform_id;
        s.num_output_channels = info.num_output_channels.min(MAX_OUTPUTS as u8);
        s.fw_major = info.fw_major;
        s.fw_minor = info.fw_minor;
        s.fw_patch = info.fw_patch;
        s.fw_beta = info.fw_beta;
        Ok(info)
    }

    /// Read the whole bulk image in chunks and decode it into state.
    fn fetch_all_params(&mut self) -> std::result::Result<(), FetchError> {
        let data = self.read_bulk_chunked().map_err(FetchError::Usb)?;
        decode_bulk(&data, &mut self.state).map_err(FetchError::Bulk)
    }

    /// Re-read every parameter after the device changed state on its own
    /// (preset load, factory reset).
    pub fn refresh_params(&mut self) -> Result<()> {
        match self.fetch_all_params() {
            Ok(()) => Ok(()),
            Err(FetchError::Usb(e)) => Err(e),
            Err(FetchError::Bulk(_)) => Err(UsbError::ShortRead { expected: BULK_PARAMS_SIZE, actual: 0 }),
        }
    }

    /// REQ_GET_ALL_PARAMS_CHUNK: offset 0 snapshots the struct on the device,
    /// later offsets read the snapshot out.
    fn read_bulk_chunked(&self) -> Result<Vec<u8>> {
        let bus = self.conn()?.bus();
        let _session = bus.lock().unwrap_or_else(|e| e.into_inner());
        let mut out = Vec::with_capacity(BULK_PARAMS_SIZE);
        while out.len() < BULK_PARAMS_SIZE {
            let off = out.len();
            let n = BULK_CHUNK_SIZE.min(BULK_PARAMS_SIZE - off);
            let chunk = self.get(REQ_GET_ALL_PARAMS_CHUNK, off as u16, WINDEX_OUTPUT, n as u16)?;
            if chunk.is_empty() {
                return Err(UsbError::ShortRead { expected: BULK_PARAMS_SIZE, actual: off });
            }
            out.extend_from_slice(&chunk);
        }
        Ok(out)
    }

    /// Write the whole state to the device (REQ_SET_ALL_PARAMS_CHUNK). The
    /// device applies it in its main loop once the last byte lands.
    pub fn apply_all_params(&mut self) -> Result<()> {
        if !self.state.bulk_valid {
            return Err(UsbError::NotConnected);
        }
        let data = encode_bulk(&self.state);
        let bus = self.conn()?.bus();
        let _session = bus.lock().unwrap_or_else(|e| e.into_inner());
        for (i, chunk) in data.chunks(BULK_CHUNK_SIZE).enumerate() {
            self.send(REQ_SET_ALL_PARAMS_CHUNK, (i * BULK_CHUNK_SIZE) as u16, WINDEX_OUTPUT, chunk)?;
        }
        Ok(())
    }

    /// Fetch device status (peaks, CPU, clips).
    pub fn fetch_status(&mut self) -> Result<SystemStatus> {
        let num_ch = self.state.num_channels as usize;
        let len = (num_ch * 2 + 7) as u16;
        let data = self.get_exact(REQ_GET_STATUS, 9, WINDEX_GLOBAL, len, num_ch * 2 + 6)?;
        parse_status(&data, num_ch).ok_or(UsbError::ShortRead { expected: len as usize, actual: data.len() })
    }

    // ═══════════════════════════════════════════════════════════════
    // EQ
    // ═══════════════════════════════════════════════════════════════

    /// Set a PEQ band (band 0..9) of wire channel `ch`.
    pub fn set_filter(&mut self, ch: u8, band: u8, mut params: FilterParams) -> Result<()> {
        if ch as usize >= MAX_CHANNELS || band as usize >= BANDS_PER_CHANNEL {
            return Err(UsbError::InvalidArgument);
        }
        if params.filter_type != FILTER_LINKWITZ_TRANSFORM {
            params.gain = quantize_gain(params.gain);
        }
        self.state.filters[ch as usize][band as usize] = params;
        self.send(REQ_SET_EQ_PARAM, 0, WINDEX_GLOBAL, &build_set_filter_packet(ch, band, &params))
    }

    /// Set crossover band `xband` (0..3) of an output's wire channel `ch`.
    pub fn set_crossover(&mut self, ch: u8, xband: u8, params: FilterParams) -> Result<()> {
        if self.state.output_of_channel(ch).is_none() || xband as usize >= MAX_XOVER_BANDS {
            return Err(UsbError::InvalidArgument);
        }
        if params.filter_type != FILTER_FLAT && !filter_is_crossover(params.filter_type) {
            return Err(UsbError::InvalidArgument);
        }
        self.state.xover[ch as usize][xband as usize] = params;
        let packet = build_set_filter_packet(ch, XOVER_BAND_BASE + xband, &params);
        self.send(REQ_SET_EQ_PARAM, 0, WINDEX_GLOBAL, &packet)
    }

    /// Bypass or re-enable one band, keeping its settings. `band` is a PEQ
    /// band (0..9) or a crossover band (20..23).
    pub fn set_band_bypass(&mut self, ch: u8, band: u8, bypass: bool) -> Result<()> {
        let c = ch as usize;
        if c >= MAX_CHANNELS {
            return Err(UsbError::InvalidArgument);
        }
        if (band as usize) < BANDS_PER_CHANNEL {
            self.state.filters[c][band as usize].bypass = bypass;
        } else if (XOVER_BAND_BASE..XOVER_BAND_BASE + MAX_XOVER_BANDS as u8).contains(&band) {
            self.state.xover[c][(band - XOVER_BAND_BASE) as usize].bypass = bypass;
        } else {
            return Err(UsbError::InvalidArgument);
        }
        self.send(REQ_SET_BAND_BYPASS, channel_band_wvalue(ch, band), WINDEX_GLOBAL, &[bypass as u8])
    }

    /// Read one band back from the device. `band` is a PEQ band or 20..23.
    pub fn fetch_filter(&mut self, ch: u8, band: u8) -> Result<FilterParams> {
        let get = |param: u8| -> Result<[u8; 4]> {
            let d = self.get_exact(REQ_GET_EQ_PARAM, eq_param_wvalue(ch, band, param), WINDEX_GLOBAL, 4, 4)?;
            Ok([d[0], d[1], d[2], d[3]])
        };
        let filter_type = u32::from_le_bytes(get(0)?) as u8;
        let mut params = FilterParams {
            filter_type,
            freq: f32::from_le_bytes(get(1)?),
            q: f32::from_le_bytes(get(2)?),
            gain: f32::from_le_bytes(get(3)?),
            bypass: u32::from_le_bytes(get(4)?) == 1,
            qp: DEFAULT_Q,
        };
        if filter_type == FILTER_LINKWITZ_TRANSFORM {
            params.qp = FilterParams::decode_qp(u32::from_le_bytes(get(5)?) as u16);
        }
        let c = ch as usize;
        if (band as usize) < BANDS_PER_CHANNEL && c < MAX_CHANNELS {
            self.state.filters[c][band as usize] = params;
        } else if band >= XOVER_BAND_BASE && c < MAX_CHANNELS {
            if let Some(slot) = self.state.xover[c].get_mut((band - XOVER_BAND_BASE) as usize) {
                *slot = params;
            }
        }
        Ok(params)
    }

    // ═══════════════════════════════════════════════════════════════
    // Preamp / Bypass
    // ═══════════════════════════════════════════════════════════════

    /// Legacy preamp: sets every input channel to the same value.
    pub fn set_preamp(&mut self, db: f32) -> Result<()> {
        let (lo, hi) = self.state.preamp_range();
        let val = quantize_gain(db.clamp(lo, hi));
        self.state.preamp_db = val;
        self.state.input_preamp_db = [val; MAX_INPUTS];
        self.send(REQ_SET_PREAMP, 0, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    /// Per-input preamp (input index 0..num_input_channels-1).
    pub fn set_input_preamp(&mut self, input: u8, db: f32) -> Result<()> {
        if input as usize >= MAX_INPUTS {
            return Err(UsbError::InvalidArgument);
        }
        let (lo, hi) = self.state.preamp_range();
        let val = quantize_gain(db.clamp(lo, hi));
        self.state.input_preamp_db[input as usize] = val;
        if input == 0 {
            self.state.preamp_db = val;
        }
        self.send(REQ_SET_PREAMP_CH, input as u16, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    pub fn set_bypass(&mut self, enabled: bool) -> Result<()> {
        self.state.bypass = enabled;
        self.send(REQ_SET_BYPASS, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    // ═══════════════════════════════════════════════════════════════
    // Volume
    // ═══════════════════════════════════════════════════════════════

    /// Device master volume: −128 mutes, otherwise −127..0 dB in 0.5 dB steps.
    pub fn set_master_volume(&mut self, db: f32) -> Result<()> {
        let val = if db <= MASTER_VOL_MUTE_DB {
            MASTER_VOL_MUTE_DB
        } else {
            ((db * 2.0).round() / 2.0).clamp(-127.0, 0.0)
        };
        self.state.master_volume_db = val;
        self.send(REQ_SET_MASTER_VOLUME, 0, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    /// 0 = master volume independent of presets, 1 = saved with presets.
    pub fn set_master_volume_mode(&mut self, mode: u8) -> Result<()> {
        self.state.master_volume_mode = mode;
        self.send(REQ_SET_MASTER_VOLUME_MODE, 0, WINDEX_GLOBAL, &[mode])
    }

    /// Persist the live master volume for independent mode.
    pub fn save_master_volume(&mut self) -> Result<u8> {
        self.get_u8(REQ_SAVE_MASTER_VOLUME, 0, WINDEX_GLOBAL)
    }

    /// User volume (the value the host's volume slider drives), −60..0 dB.
    pub fn set_user_volume(&mut self, db: f32) -> Result<()> {
        let val = db.clamp(-60.0, 0.0);
        self.state.user_volume_db = val;
        self.send(REQ_SET_USER_VOLUME, 0, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    pub fn set_user_mute(&mut self, muted: bool) -> Result<()> {
        self.state.user_mute = muted;
        self.send(REQ_SET_USER_MUTE, 0, WINDEX_GLOBAL, &[muted as u8])
    }

    // ═══════════════════════════════════════════════════════════════
    // Delay
    // ═══════════════════════════════════════════════════════════════

    /// Channel delay by wire channel. For an output channel this is the same
    /// value as its output delay, so it goes through the output command.
    pub fn set_delay(&mut self, ch: u8, ms: f32) -> Result<()> {
        if let Some(out) = self.state.output_of_channel(ch) {
            return self.set_output_delay(out, ms);
        }
        if ch as usize >= MAX_CHANNELS {
            return Err(UsbError::InvalidArgument);
        }
        let val = quantize_delay(ms).clamp(0.0, self.max_delay_ms());
        self.state.channel_delays[ch as usize] = val;
        self.send(REQ_SET_DELAY, ch as u16, WINDEX_GLOBAL, &val.to_le_bytes())
    }

    // ═══════════════════════════════════════════════════════════════
    // Loudness
    // ═══════════════════════════════════════════════════════════════

    pub fn set_loudness(&mut self, enabled: bool) -> Result<()> {
        self.state.loudness_enabled = enabled;
        self.send(REQ_SET_LOUDNESS, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn set_loudness_ref(&mut self, spl: f32) -> Result<()> {
        self.state.loudness_ref_spl = spl;
        self.send(REQ_SET_LOUDNESS_REF, 0, WINDEX_GLOBAL, &spl.to_le_bytes())
    }

    pub fn set_loudness_intensity(&mut self, pct: f32) -> Result<()> {
        self.state.loudness_intensity = pct;
        self.send(REQ_SET_LOUDNESS_INTENSITY, 0, WINDEX_GLOBAL, &pct.to_le_bytes())
    }

    /// Bit k: loudness compensates output k.
    pub fn set_loudness_mask(&mut self, mask: u16) -> Result<()> {
        self.state.loudness_output_mask = mask;
        self.send(REQ_SET_LOUDNESS_MASK, 0, WINDEX_GLOBAL, &mask.to_le_bytes())
    }

    // ═══════════════════════════════════════════════════════════════
    // Crossfeed
    // ═══════════════════════════════════════════════════════════════

    pub fn set_crossfeed(&mut self, enabled: bool) -> Result<()> {
        self.state.crossfeed_enabled = enabled;
        self.send(REQ_SET_CROSSFEED, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn set_crossfeed_preset(&mut self, preset: u8) -> Result<()> {
        self.state.crossfeed_preset = preset;
        self.send(REQ_SET_CROSSFEED_PRESET, 0, WINDEX_GLOBAL, &[preset])?;
        // Known preset values, applied locally (matches the macOS Console).
        const PRESET_VALUES: [(f32, f32); 3] = [(700.0, 4.5), (700.0, 6.0), (650.0, 9.5)];
        if let Some(&(freq, feed)) = PRESET_VALUES.get(preset as usize) {
            self.state.crossfeed_freq = freq;
            self.state.crossfeed_feed = feed;
        }
        Ok(())
    }

    pub fn set_crossfeed_freq(&mut self, freq: f32) -> Result<()> {
        self.state.crossfeed_freq = freq;
        self.send(REQ_SET_CROSSFEED_FREQ, 0, WINDEX_GLOBAL, &freq.to_le_bytes())
    }

    pub fn set_crossfeed_feed(&mut self, feed: f32) -> Result<()> {
        self.state.crossfeed_feed = feed;
        self.send(REQ_SET_CROSSFEED_FEED, 0, WINDEX_GLOBAL, &feed.to_le_bytes())
    }

    pub fn set_crossfeed_itd(&mut self, enabled: bool) -> Result<()> {
        self.state.crossfeed_itd = enabled;
        self.send(REQ_SET_CROSSFEED_ITD, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    /// Bit p: crossfeed runs on output pair p.
    pub fn set_crossfeed_outputs(&mut self, pair_mask: u8) -> Result<()> {
        self.state.crossfeed_output_pair_mask = pair_mask;
        self.send(REQ_SET_CROSSFEED_OUTPUTS, 0, WINDEX_GLOBAL, &[pair_mask])
    }

    // ═══════════════════════════════════════════════════════════════
    // Volume Leveller
    // ═══════════════════════════════════════════════════════════════

    pub fn set_leveller_enabled(&mut self, enabled: bool) -> Result<()> {
        self.state.leveller_enabled = enabled;
        self.send(REQ_SET_LEVELLER_ENABLE, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn set_leveller_amount(&mut self, pct: f32) -> Result<()> {
        self.state.leveller_amount = pct;
        self.send(REQ_SET_LEVELLER_AMOUNT, 0, WINDEX_GLOBAL, &pct.to_le_bytes())
    }

    pub fn set_leveller_speed(&mut self, speed: u8) -> Result<()> {
        self.state.leveller_speed = speed;
        self.send(REQ_SET_LEVELLER_SPEED, 0, WINDEX_GLOBAL, &[speed])
    }

    pub fn set_leveller_max_gain(&mut self, db: f32) -> Result<()> {
        self.state.leveller_max_gain_db = db;
        self.send(REQ_SET_LEVELLER_MAX_GAIN, 0, WINDEX_GLOBAL, &db.to_le_bytes())
    }

    pub fn set_leveller_lookahead(&mut self, enabled: bool) -> Result<()> {
        self.state.leveller_lookahead = enabled;
        self.send(REQ_SET_LEVELLER_LOOKAHEAD, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn set_leveller_gate(&mut self, db: f32) -> Result<()> {
        self.state.leveller_gate_db = db;
        self.send(REQ_SET_LEVELLER_GATE, 0, WINDEX_GLOBAL, &db.to_le_bytes())
    }

    pub fn set_leveller_masks(&mut self, detector: u8, apply: u8) -> Result<()> {
        self.state.leveller_detector_mask = detector;
        self.state.leveller_apply_mask = apply;
        self.send(REQ_SET_LEVELLER_MASKS, 0, WINDEX_GLOBAL, &[detector, apply])
    }

    // ═══════════════════════════════════════════════════════════════
    // Input source / Psychoacoustic bass
    // ═══════════════════════════════════════════════════════════════

    /// 0 = USB, 1 = S/PDIF, 2 = I2S, ... (firmware InputSource).
    pub fn set_input_source(&mut self, source: u8) -> Result<()> {
        self.send(REQ_SET_INPUT_SOURCE, 0, WINDEX_GLOBAL, &[source])?;
        self.state.input_source = source;
        Ok(())
    }

    pub fn set_psybass_enabled(&mut self, enabled: bool) -> Result<()> {
        self.state.psybass_enabled = enabled;
        self.send(REQ_SET_PSYBASS, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    /// Set one psybass parameter (`PSYBASS_PARAM_*`), clamped to its range.
    pub fn set_psybass_param(&mut self, param: u8, value: f32) -> Result<()> {
        let (req, v) = match param {
            PSYBASS_PARAM_CUTOFF => (REQ_SET_PSYBASS_CUTOFF, value.clamp(30.0, 300.0)),
            PSYBASS_PARAM_HARMONICS => (REQ_SET_PSYBASS_HARMONICS, value.clamp(-24.0, 12.0)),
            PSYBASS_PARAM_DRIVE => (REQ_SET_PSYBASS_DRIVE, value.clamp(0.0, 18.0)),
            PSYBASS_PARAM_CHARACTER => (REQ_SET_PSYBASS_CHARACTER, value.clamp(0.0, 100.0)),
            PSYBASS_PARAM_ORIGINAL => (REQ_SET_PSYBASS_ORIGINAL, value.clamp(-60.0, 0.0)),
            _ => return Err(UsbError::InvalidArgument),
        };
        let s = &mut self.state;
        match param {
            PSYBASS_PARAM_CUTOFF => s.psybass_cutoff_hz = v,
            PSYBASS_PARAM_HARMONICS => s.psybass_harmonics_db = v,
            PSYBASS_PARAM_DRIVE => s.psybass_drive_db = v,
            PSYBASS_PARAM_CHARACTER => s.psybass_character_pct = v,
            _ => s.psybass_original_db = v,
        }
        self.send(req, 0, WINDEX_GLOBAL, &v.to_le_bytes())
    }

    // ═══════════════════════════════════════════════════════════════
    // Stereo upmixer, subharmonic synth, tube modeller
    // ═══════════════════════════════════════════════════════════════

    /// Set upmixer parameter `id` (`UPMIX_PARAM_*`). The firmware stores the
    /// raw value, so it is clamped here.
    pub fn set_upmix_param(&mut self, id: u8, value: f32) -> Result<()> {
        let i = id as usize;
        if i >= UPMIX_PARAM_COUNT {
            return Err(UsbError::InvalidArgument);
        }
        let (lo, hi) = UPMIX_LIMITS[i];
        let mut v = value.clamp(lo, hi);
        if id <= UPMIX_PARAM_SURROUND_MODE {
            v = v.round();
        } else if id == UPMIX_PARAM_PRESENCE {
            v = (v * 2.0).round() / 2.0; // stored in half-dB steps
        }
        self.state.upmix[i] = v;
        self.send(REQ_UPMIX_SET_PARAM, id as u16, WINDEX_GLOBAL, &v.to_le_bytes())
    }

    pub fn fetch_upmix_status(&self) -> Result<UpmixStatus> {
        let d = self.get_exact(REQ_UPMIX_GET_STATUS, 0, WINDEX_GLOBAL, 16, 12)?;
        let q14 = |o: usize| i16::from_le_bytes([d[o], d[o + 1]]) as f32 / 16384.0;
        let q15 = |o: usize| u16::from_le_bytes([d[o], d[o + 1]]) as f32 / 32767.0;
        Ok(UpmixStatus {
            active: d[0] != 0,
            parked_reason: d[1],
            correlation: q14(2),
            balance: q14(4),
            center_gain: q15(6),
            ls_gain: q15(8),
            rs_gain: q15(10),
        })
    }

    /// Set subharmonic synth parameter `id` (`SUBHARM_PARAM_*`), clamped.
    pub fn set_subharm_param(&mut self, id: u8, value: f32) -> Result<()> {
        let i = id as usize;
        if i >= SUBHARM_PARAM_COUNT {
            return Err(UsbError::InvalidArgument);
        }
        let (lo, hi) = SUBHARM_LIMITS[i];
        let whole = matches!(id, SUBHARM_PARAM_ENABLED | SUBHARM_PARAM_MASK | SUBHARM_PARAM_SELECT | SUBHARM_PARAM_LINK);
        let v = if whole { value.round().clamp(lo, hi) } else { value.clamp(lo, hi) };
        self.state.subharm[i] = v;
        let req = SUBHARM_SET_REQUESTS[i];
        match id {
            SUBHARM_PARAM_MASK => self.send(req, 0, WINDEX_GLOBAL, &(v as u16).to_le_bytes()),
            _ if whole => self.send(req, 0, WINDEX_GLOBAL, &[v as u8]),
            _ => self.send(req, 0, WINDEX_GLOBAL, &v.to_le_bytes()),
        }
    }

    /// Mute the program on the subharm outputs so the sub is heard alone.
    pub fn set_subharm_solo(&mut self, solo: bool) -> Result<()> {
        self.state.subharm_solo = solo;
        self.send(REQ_SET_SUBHARM_SOLO, 0, WINDEX_GLOBAL, &[solo as u8])
    }

    pub(crate) fn fetch_subharm_solo_internal(&mut self) {
        if let Ok(v) = self.get_u8(REQ_GET_SUBHARM_SOLO, 0, WINDEX_GLOBAL) {
            self.state.subharm_solo = v != 0;
        }
    }

    /// How far the current settings can push the signal above its input, dB.
    pub fn fetch_subharm_headroom(&self) -> Result<f32> {
        let d = self.get_exact(REQ_GET_SUBHARM_HEADROOM, 0, WINDEX_GLOBAL, 4, 4)?;
        Ok(read_f32_le(&d, 0))
    }

    /// Decaying peak of the synthesized sub on each output, 0..1.
    pub fn fetch_subharm_meter(&self) -> Result<[f32; MAX_OUTPUTS]> {
        let n = self.state.num_output_channels as usize;
        let d = self.get_exact(REQ_GET_SUBHARM_METER, 0, WINDEX_GLOBAL, (n * 2) as u16, n * 2)?;
        let mut out = [0.0f32; MAX_OUTPUTS];
        for (o, v) in out.iter_mut().enumerate().take(n) {
            *v = read_u16_le(&d, o * 2) as f32 / 32767.0;
        }
        Ok(out)
    }

    /// Set tube parameter `idx` (`TUBE_PARAM_*`), clamped. Mirrors the
    /// firmware: choosing a tube type copies its character row, and editing a
    /// character value makes the type Custom (our own writes are not echoed).
    pub fn set_tube_param(&mut self, idx: u8, value: f32) -> Result<()> {
        let i = idx as usize;
        if i >= TUBE_PARAM_COUNT {
            return Err(UsbError::InvalidArgument);
        }
        let (lo, hi) = TUBE_LIMITS[i];
        let whole = matches!(
            idx,
            TUBE_PARAM_ENABLED | TUBE_PARAM_MASK | TUBE_PARAM_TYPE | TUBE_PARAM_RECTIFIER | TUBE_PARAM_XFMR
        );
        let v = if whole { value.round().clamp(lo, hi) } else { value.clamp(lo, hi) };
        let t = &mut self.state.tube;
        let character = TUBE_PARAM_BIAS as usize..=TUBE_PARAM_SAG as usize;
        if idx == TUBE_PARAM_TYPE && v >= 1.0 {
            t[character].copy_from_slice(&TUBE_ROWS[v as usize - 1]);
        } else if character.contains(&i) && t[i] != v {
            t[TUBE_PARAM_TYPE as usize] = 0.0;
        }
        t[i] = v;
        self.send(REQ_SET_TUBE_PARAM, idx as u16, WINDEX_GLOBAL, &v.to_le_bytes())
    }

    // ═══════════════════════════════════════════════════════════════
    // DAC hardware mute, LG Sound Sync, UART / I2C control
    // ═══════════════════════════════════════════════════════════════

    /// Send a DAC mute config. The device validates and applies it later in
    /// its main loop and drops it silently if invalid, so read it back with
    /// `fetch_dac_mute` about 150 ms afterwards.
    pub fn set_dac_mute(&mut self, enabled: bool, active_low: bool, pin: u8, hold_ms: u16, release_ms: u16) -> Result<()> {
        let mut d = [0u8; 16];
        d[0] = enabled as u8;
        d[1] = active_low as u8;
        d[2] = pin;
        d[4..6].copy_from_slice(&hold_ms.to_le_bytes());
        d[6..8].copy_from_slice(&release_ms.to_le_bytes());
        self.send(REQ_SET_DAC_HW_MUTE_CONFIG, 0, WINDEX_GLOBAL, &d)
    }

    /// Read the DAC mute config the device is using (also the support probe).
    pub fn fetch_dac_mute(&mut self) -> Result<()> {
        let d = self.get_exact(REQ_GET_DAC_HW_MUTE_CONFIG, 0, WINDEX_GLOBAL, 16, 8)?;
        let s = &mut self.state;
        s.dac_mute_supported = true;
        s.dac_mute_enabled = d[0] != 0;
        s.dac_mute_active_low = d[1] != 0;
        s.dac_mute_pin = d[2];
        s.dac_mute_hold_ms = read_u16_le(&d, 4);
        s.dac_mute_release_ms = read_u16_le(&d, 6);
        // Keep the raw image in step: a later bulk SET would re-apply it
        if s.bulk_valid {
            s.bulk_raw[OFF_DAC_HW_MUTE..OFF_DAC_HW_MUTE + 8].copy_from_slice(&d[..8]);
        }
        Ok(())
    }

    /// Pulse the mute output for about a second. 0 = started, 3 = disabled.
    pub fn test_dac_mute(&self) -> Result<u8> {
        self.get_u8(REQ_TEST_DAC_HW_MUTE, 0, WINDEX_GLOBAL)
    }

    /// LG Sound Sync on or off (live; saved with the preset).
    pub fn set_lg_sound_sync(&mut self, enabled: bool) -> Result<()> {
        self.state.lg_sound_sync_enabled = enabled;
        self.send(REQ_SET_LG_SOUND_SYNC_ENABLE, 0, WINDEX_GLOBAL, &[enabled as u8])
    }

    pub fn fetch_lg_status(&self) -> Result<LgStatus> {
        let d = self.get_exact(REQ_GET_LG_SOUND_SYNC_STATUS, 0, WINDEX_GLOBAL, 16, 4)?;
        Ok(LgStatus { enabled: d[0] != 0, present: d[1] != 0, volume: d[2], muted: d[3] != 0 })
    }

    /// Read both control interface configs and their status. A device that
    /// does not answer the status request has no control interfaces.
    pub fn fetch_ctrl_ifaces(&mut self) -> Result<()> {
        let st = match self.get_exact(REQ_GET_CTRL_IFACE_STATUS, 0, WINDEX_GLOBAL, 8, 5) {
            Ok(d) => d,
            Err(e) => {
                self.state.ctrl_iface_supported = false;
                return Err(e);
            }
        };
        let u = self.get_exact(REQ_GET_UART_CONFIG, 0, WINDEX_GLOBAL, 8, 8)?;
        let i = self.get_exact(REQ_GET_I2C_CONFIG, 0, WINDEX_GLOBAL, 8, 4)?;
        let s = &mut self.state;
        s.ctrl_iface_supported = true;
        s.ctrl_status = CtrlIfaceStatus {
            uart_last_status: st[0],
            uart_live: st[1] != 0,
            i2c_last_status: st[2],
            i2c_live: st[3] != 0,
            protocol_version: st[4],
        };
        s.uart = UartConfig {
            enabled: u[0] != 0,
            tx_pin: u[1],
            rx_pin: u[2],
            notify: u[3] != 0,
            baud: u32::from_le_bytes([u[4], u[5], u[6], u[7]]),
        };
        s.i2c = I2cConfig { enabled: i[0] != 0, sda_pin: i[1], scl_pin: i[2], address: i[3] };
        Ok(())
    }

    /// Send a UART config; the device applies it later (read the outcome
    /// with `fetch_ctrl_ifaces` about 250 ms afterwards).
    pub fn set_uart(&mut self, c: UartConfig) -> Result<()> {
        let mut d = [0u8; 8];
        d[0] = c.enabled as u8;
        d[1] = c.tx_pin;
        d[2] = c.rx_pin;
        d[3] = c.notify as u8;
        d[4..8].copy_from_slice(&c.baud.to_le_bytes());
        self.send(REQ_SET_UART_CONFIG, 0, WINDEX_GLOBAL, &d)
    }

    pub fn set_i2c(&mut self, c: I2cConfig) -> Result<()> {
        let d = [c.enabled as u8, c.sda_pin, c.scl_pin, c.address, 0, 0, 0, 0];
        self.send(REQ_SET_I2C_CONFIG, 0, WINDEX_GLOBAL, &d)
    }

    /// Bit k: psybass processes output k.
    pub fn set_psybass_mask(&mut self, mask: u16) -> Result<()> {
        self.state.psybass_output_mask = mask;
        self.send(REQ_SET_PSYBASS_MASK, 0, WINDEX_GLOBAL, &mask.to_le_bytes())
    }

    // ═══════════════════════════════════════════════════════════════
    // Matrix Mixer
    // ═══════════════════════════════════════════════════════════════

    pub fn set_matrix_route(&mut self, input: u8, output: u8, enabled: bool, gain: f32, invert: bool) -> Result<()> {
        let (i, o) = (input as usize, output as usize);
        if i >= MAX_INPUTS || o >= MAX_OUTPUTS {
            return Err(UsbError::InvalidArgument);
        }
        let gain = quantize_gain(gain);
        self.state.matrix_routing[i][o] = enabled;
        self.state.matrix_gain[i][o] = gain;
        self.state.matrix_invert[i][o] = invert;
        let packet = build_matrix_route_packet(input, output, enabled, gain, invert);
        self.send(REQ_SET_MATRIX_ROUTE, 0, WINDEX_OUTPUT, &packet)
    }

    // ═══════════════════════════════════════════════════════════════
    // Outputs
    // ═══════════════════════════════════════════════════════════════

    /// Enable/disable an output. The firmware refuses to enable PDM while a
    /// Core 1 EQ-worker output is on (and vice versa), so the result is read
    /// back rather than assumed.
    pub fn set_output_enable(&mut self, output: u8, enabled: bool) -> Result<bool> {
        if output as usize >= MAX_OUTPUTS {
            return Err(UsbError::InvalidArgument);
        }
        self.send(REQ_SET_OUTPUT_ENABLE, output as u16, WINDEX_OUTPUT, &[enabled as u8])?;
        let actual = match self.get_u8(REQ_GET_OUTPUT_ENABLE, output as u16, WINDEX_OUTPUT) {
            Ok(v) => v != 0,
            Err(_) => enabled,
        };
        self.state.output_enabled[output as usize] = actual;
        self.fetch_core1_mode_internal();
        Ok(actual)
    }

    pub fn set_output_gain(&mut self, output: u8, db: f32) -> Result<()> {
        if output as usize >= MAX_OUTPUTS {
            return Err(UsbError::InvalidArgument);
        }
        let val = quantize_gain(db);
        self.state.output_gain_db[output as usize] = val;
        self.send(REQ_SET_OUTPUT_GAIN, output as u16, WINDEX_OUTPUT, &val.to_le_bytes())
    }

    pub fn set_output_mute(&mut self, output: u8, muted: bool) -> Result<()> {
        if output as usize >= MAX_OUTPUTS {
            return Err(UsbError::InvalidArgument);
        }
        self.state.output_muted[output as usize] = muted;
        self.send(REQ_SET_OUTPUT_MUTE, output as u16, WINDEX_OUTPUT, &[muted as u8])
    }

    pub fn set_output_delay(&mut self, output: u8, ms: f32) -> Result<()> {
        if output as usize >= MAX_OUTPUTS {
            return Err(UsbError::InvalidArgument);
        }
        let val = quantize_delay(ms).clamp(0.0, self.max_delay_ms());
        self.state.output_delay_ms[output as usize] = val;
        let ch = self.state.output_channel(output) as usize;
        if ch < MAX_CHANNELS {
            self.state.channel_delays[ch] = val;
        }
        self.send(REQ_SET_OUTPUT_DELAY, output as u16, WINDEX_OUTPUT, &val.to_le_bytes())
    }

    // ═══════════════════════════════════════════════════════════════
    // Output Limiter
    // ═══════════════════════════════════════════════════════════════

    /// Set one limiter parameter (`LIMITER_PARAM_*`) of `output`, or of every
    /// output when `output` is `LIMITER_ALL_OUTPUTS`. Values are clamped the
    /// way the firmware clamps them.
    pub fn set_limiter_param(&mut self, output: u8, param: u8, value: f32) -> Result<()> {
        let value = match param {
            LIMITER_PARAM_ENABLED => (value != 0.0) as u8 as f32,
            LIMITER_PARAM_THRESHOLD_DB => value.clamp(-30.0, 0.0),
            LIMITER_PARAM_RELEASE_MS => value.clamp(10.0, 1000.0),
            LIMITER_PARAM_LINK_GROUP => value.round().clamp(0.0, 4.0),
            _ => return Err(UsbError::InvalidArgument),
        };
        let outputs: Vec<usize> = if output == LIMITER_ALL_OUTPUTS {
            (0..self.state.num_output_channels as usize).collect()
        } else if (output as usize) < MAX_OUTPUTS {
            vec![output as usize]
        } else {
            return Err(UsbError::InvalidArgument);
        };
        for o in outputs {
            match param {
                LIMITER_PARAM_ENABLED => self.state.limiter_enabled[o] = value != 0.0,
                LIMITER_PARAM_THRESHOLD_DB => self.state.limiter_threshold_db[o] = value,
                LIMITER_PARAM_RELEASE_MS => self.state.limiter_release_ms[o] = value,
                _ => self.state.limiter_link_group[o] = value as u8,
            }
        }
        let wvalue = ((output as u16) << 8) | param as u16;
        self.send(REQ_LIMITER, wvalue, WINDEX_GLOBAL, &value.to_le_bytes())
    }

    /// Current gain reduction per output in dB (positive = reducing).
    pub fn fetch_limiter_meter(&mut self) -> Result<[f32; MAX_OUTPUTS]> {
        let n = self.state.num_output_channels as usize;
        let data = self.get_exact(REQ_LIMITER, LIMITER_GET_METER as u16, WINDEX_GLOBAL, (n * 2) as u16, n * 2)?;
        let mut gr = [0.0f32; MAX_OUTPUTS];
        for (k, v) in gr.iter_mut().enumerate().take(n) {
            *v = u16::from_le_bytes([data[2 * k], data[2 * k + 1]]) as f32 / 100.0;
        }
        Ok(gr)
    }

    // ═══════════════════════════════════════════════════════════════
    // Core 1 Mode
    // ═══════════════════════════════════════════════════════════════

    pub fn fetch_core1_mode(&mut self) -> Result<u8> {
        let v = self.get_u8(REQ_GET_CORE1_MODE, 0, WINDEX_GLOBAL)?;
        self.state.core1_mode = v;
        Ok(v)
    }

    pub(crate) fn fetch_core1_mode_internal(&mut self) {
        if let Err(e) = self.fetch_core1_mode() {
            warn!("Failed to fetch core1 mode: {e}");
        }
    }

    pub fn check_core1_conflict(&mut self, output: u8) -> Result<bool> {
        Ok(self.get_u8(REQ_GET_CORE1_CONFLICT, output as u16, WINDEX_GLOBAL)? != 0)
    }

    // ═══════════════════════════════════════════════════════════════
    // Pins
    // ═══════════════════════════════════════════════════════════════

    /// Set the GPIO of a physical output slot. Returns the firmware status
    /// code. SET is an IN transfer: wValue = (new_pin << 8) | slot.
    pub fn set_output_pin(&mut self, slot: u8, pin: u8) -> Result<u8> {
        let status = self.get_u8(REQ_SET_OUTPUT_PIN, pin_config_wvalue(pin, slot), WINDEX_OUTPUT)?;
        if status == PIN_CONFIG_SUCCESS {
            if pin == PIN_RESET_TO_DEFAULT {
                // Reset to the platform default: read back which pin that is
                self.fetch_output_pin(slot)?;
            } else if let Some(p) = self.state.output_pins.get_mut(slot as usize) {
                *p = pin;
            }
        }
        Ok(status)
    }

    pub fn fetch_output_pin(&mut self, slot: u8) -> Result<u8> {
        let v = self.get_u8(REQ_GET_OUTPUT_PIN, slot as u16, WINDEX_OUTPUT)?;
        if let Some(p) = self.state.output_pins.get_mut(slot as usize) {
            *p = v;
        }
        Ok(v)
    }

    // Write-as-read setters: an IN transfer with the parameters in wValue,
    // replying a PIN_CONFIG_* status. The state follows only on success.

    /// Slot type: 0 = S/PDIF, 1 = I2S.
    pub fn set_output_type(&mut self, slot: u8, kind: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_OUTPUT_TYPE, ((kind as u16) << 8) | slot as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            if let Some(t) = self.state.output_types.get_mut(slot as usize) {
                *t = kind;
            }
        }
        Ok(st)
    }

    /// I2S bit clock pin (LRCLK = pin + 1). role 0 = master / shared pair,
    /// 1 = the slave pair used in split mode.
    pub fn set_i2s_bck_pin(&mut self, role: u8, pin: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_I2S_BCK_PIN, ((role as u16) << 8) | pin as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            if role == 0 { self.state.i2s_bck_pin = pin } else { self.state.i2s_bck_pin_slave = pin }
        }
        Ok(st)
    }

    /// 0 = master and slave share the clock pins, 1 = separate pins.
    pub fn set_i2s_clock_pin_mode(&mut self, mode: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_I2S_CLOCK_PIN_MODE, mode as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.i2s_clock_pin_mode = mode;
        }
        Ok(st)
    }

    pub fn set_mck_enabled(&mut self, enabled: bool) -> Result<u8> {
        let st = self.get_u8(REQ_SET_MCK_ENABLE, enabled as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.mck_enabled = enabled;
        }
        Ok(st)
    }

    pub fn set_mck_pin(&mut self, pin: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_MCK_PIN, pin as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.mck_pin = pin;
        }
        Ok(st)
    }

    /// 0 = 128 x fs, 1 = 256 x fs.
    pub fn set_mck_multiplier(&mut self, mult: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_MCK_MULTIPLIER, mult as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.mck_multiplier = mult;
        }
        Ok(st)
    }

    /// ADAT optical output (RP2350; INVALID_OUTPUT on RP2040).
    pub fn set_adat_out_enabled(&mut self, enabled: bool) -> Result<u8> {
        let st = self.get_u8(REQ_SET_ADAT_ENABLE, enabled as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.adat_out_enabled = enabled;
        }
        Ok(st)
    }

    pub fn set_adat_out_pin(&mut self, pin: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_ADAT_PIN, pin as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.adat_out_pin = pin;
        }
        Ok(st)
    }

    pub fn fetch_adat_out_status(&self) -> Result<AdatOutStatus> {
        let d = self.get_exact(REQ_GET_ADAT_STATUS, 0, WINDEX_OUTPUT, 8, 8)?;
        Ok(AdatOutStatus {
            enabled: d[0] != 0,
            active: d[1] != 0,
            pin: d[2],
            rate_ok: d[3] != 0,
            resync_count: read_u16_le(&d, 4),
            slip_count: read_u16_le(&d, 6),
        })
    }

    // ── Inputs (write-as-read unless noted; saved with the preset, or
    //    with the output config in independent mode) ──

    /// S/PDIF input `index` (0-3) RX pin. PIN_RESET_TO_DEFAULT resets it.
    pub fn set_spdif_rx_pin(&mut self, index: u8, pin: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_SPDIF_RX_PIN, ((index as u16) << 8) | pin as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS && (index as usize) < 4 {
            self.state.spdif_rx_pins[index as usize] =
                if pin == PIN_RESET_TO_DEFAULT { self.get_u8(REQ_GET_SPDIF_RX_PIN, index as u16, WINDEX_OUTPUT)? } else { pin };
        }
        Ok(st)
    }

    /// Enable S/PDIF input `index` (1-3; input 0 is always on).
    pub fn set_spdif_input_enabled(&mut self, index: u8, enabled: bool) -> Result<u8> {
        let st = self.get_u8(REQ_SET_SPDIF_INPUT_ENABLE, ((index as u16) << 8) | enabled as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS && index < 4 {
            let bit = 1u8 << index;
            if enabled { self.state.spdif_inputs_enabled |= bit } else { self.state.spdif_inputs_enabled &= !bit }
        }
        Ok(st)
    }

    /// Master-mode rate for I2S and ADAT: 0 = 44.1k, 1 = 48k, 2 = 96k (OUT).
    pub fn set_input_rate(&mut self, index: u8) -> Result<()> {
        let index = if index > 2 { 1 } else { index };
        let hz: u32 = match index { 0 => 44_100, 2 => 96_000, _ => 48_000 };
        self.state.i2s_input_rate = index;
        self.send(REQ_SET_INPUT_RATE, 0, WINDEX_OUTPUT, &hz.to_le_bytes())
    }

    /// The rate the pipeline runs at now, Hz.
    pub fn fetch_input_rate(&self) -> Result<u32> {
        let d = self.get_exact(REQ_GET_INPUT_RATE, 0, WINDEX_OUTPUT, 8, 4)?;
        Ok(u32::from_le_bytes([d[0], d[1], d[2], d[3]]))
    }

    /// I2S input data pin of `pair` (0-3).
    pub fn set_i2s_rx_pin(&mut self, pair: u8, pin: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_I2S_RX_PIN, ((pair as u16) << 8) | pin as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS && (pair as usize) < 4 {
            self.state.i2s_rx_pins[pair as usize] =
                if pin == PIN_RESET_TO_DEFAULT { self.get_u8(REQ_GET_I2S_RX_PIN, pair as u16, WINDEX_OUTPUT)? } else { pin };
        }
        Ok(st)
    }

    /// I2S input channels: 2, 4, 6 or 8.
    pub fn set_i2s_input_channels(&mut self, channels: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_I2S_INPUT_CHANNELS, channels as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.i2s_input_channels = channels;
        }
        Ok(st)
    }

    /// 0 = master, 1 = slave (OUT; applied later in the main loop).
    pub fn set_i2s_clock_mode(&mut self, mode: u8) -> Result<()> {
        self.state.i2s_clock_mode = mode.min(1);
        self.send(REQ_SET_I2S_CLOCK_MODE, 0, WINDEX_OUTPUT, &[mode.min(1)])
    }

    pub fn fetch_i2s_slave_status(&self) -> Result<InputLockStatus> {
        let d = self.get_exact(REQ_GET_I2S_SLAVE_STATUS, 0, WINDEX_OUTPUT, 16, 12)?;
        Ok(InputLockStatus {
            state: d[0],
            clock_mode: d[1],
            detected_rate: read_u32_le(&d, 4),
            measured_hz: read_u32_le(&d, 8),
            rate_ok: true,
            lock_count: d[2],
            loss_count: d[3],
        })
    }

    /// ADAT input (RP2350): needs a data pin before it can be enabled.
    pub fn set_adat_input_enabled(&mut self, enabled: bool) -> Result<u8> {
        let st = self.get_u8(REQ_SET_ADAT_INPUT_ENABLE, enabled as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.adat_input_enabled = enabled;
        }
        Ok(st)
    }

    /// ADAT input data pin; 0xFF clears it (only while disabled).
    pub fn set_adat_input_pin(&mut self, pin: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_ADAT_INPUT_PIN, pin as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.adat_input_pin = pin;
        }
        Ok(st)
    }

    /// 0 = master, 1 = slave (applied later in the main loop).
    pub fn set_adat_input_clock_mode(&mut self, mode: u8) -> Result<u8> {
        let st = self.get_u8(REQ_SET_ADAT_INPUT_CLOCK_MODE, mode as u16, WINDEX_OUTPUT)?;
        if st == PIN_CONFIG_SUCCESS {
            self.state.adat_input_clock_mode = mode;
        }
        Ok(st)
    }

    pub fn fetch_adat_input_status(&self) -> Result<InputLockStatus> {
        let d = self.get_exact(REQ_GET_ADAT_INPUT_STATUS, 0, WINDEX_OUTPUT, 20, 20)?;
        Ok(InputLockStatus {
            state: d[0],
            clock_mode: d[1],
            detected_rate: read_u32_le(&d, 12),
            measured_hz: read_u32_le(&d, 16),
            rate_ok: d[4] != 0,
            lock_count: d[5],
            loss_count: d[6],
        })
    }

    /// 0 = output config stored independently, 1 = saved with presets.
    pub fn set_output_config_mode(&mut self, mode: u8) -> Result<()> {
        self.state.output_config_mode = mode;
        self.send(REQ_SET_OUTPUT_CONFIG_MODE, 0, WINDEX_OUTPUT, &[mode])
    }

    /// Persist the live output config (independent mode).
    pub fn save_output_config(&mut self) -> Result<u8> {
        self.get_u8(REQ_SAVE_OUTPUT_CONFIG, 0, WINDEX_GLOBAL)
    }

    // ═══════════════════════════════════════════════════════════════
    // Channel Names
    // ═══════════════════════════════════════════════════════════════

    pub fn set_channel_name(&mut self, ch: u8, name: &str) -> Result<()> {
        if ch as usize >= MAX_CHANNELS {
            return Err(UsbError::InvalidArgument);
        }
        let buf = name_to_bytes(name);
        self.state.channel_names[ch as usize] = buf;
        self.send(REQ_SET_CHANNEL_NAME, ch as u16, WINDEX_OUTPUT, &buf)
    }

    pub fn fetch_channel_name(&mut self, ch: u8) -> Result<String> {
        if ch as usize >= MAX_CHANNELS {
            return Err(UsbError::InvalidArgument);
        }
        let data = self.get_exact(REQ_GET_CHANNEL_NAME, ch as u16, WINDEX_OUTPUT, 32, 1)?;
        let mut buf = [0u8; CHANNEL_NAME_LEN];
        let len = data.len().min(CHANNEL_NAME_LEN - 1);
        buf[..len].copy_from_slice(&data[..len]);
        self.state.channel_names[ch as usize] = buf;
        Ok(name_from_bytes(&buf))
    }

    // ═══════════════════════════════════════════════════════════════
    // Flash / System
    // ═══════════════════════════════════════════════════════════════

    /// Legacy "save params" (saves to the active preset slot; deferred).
    pub fn save_params(&mut self) -> Result<u8> {
        self.get_u8(REQ_SAVE_PARAMS, 0, WINDEX_GLOBAL)
    }

    /// Revert to saved: reload the active preset through the deferred,
    /// S/PDIF-safe preset load. Returns a FLASH_* code.
    pub fn load_params(&mut self) -> Result<u8> {
        let slot = self.state.active_preset_slot;
        Ok(match self.load_preset(slot)? {
            PRESET_OK => FLASH_OK,
            PRESET_ERR_CRC => FLASH_ERR_CRC,
            _ => FLASH_ERR_WRITE,
        })
    }

    /// Factory reset (deferred on the device), then re-read everything.
    pub fn factory_reset(&mut self) -> Result<u8> {
        let status = self.get_u8(REQ_FACTORY_RESET, 0, WINDEX_GLOBAL)?;
        if status == FLASH_OK {
            thread::sleep(Duration::from_millis(250));
            self.fetch_all()?;
        }
        Ok(status)
    }

    /// Restart the device into its USB bootloader (for firmware updates).
    /// The device drops off the bus, so the transfer may report an error.
    pub fn enter_bootloader(&mut self) -> Result<()> {
        let _ = self.get(REQ_ENTER_BOOTLOADER, 0, WINDEX_GLOBAL, 1);
        Ok(())
    }

    /// Read-then-clear the device's sticky clip flags. Returns the flags.
    pub fn clear_clips(&mut self) -> Result<u32> {
        let data = self.get(REQ_CLEAR_CLIPS, 0, WINDEX_GLOBAL, 4)?;
        let mut b = [0u8; 4];
        b[..data.len().min(4)].copy_from_slice(&data[..data.len().min(4)]);
        Ok(u32::from_le_bytes(b))
    }
}

/// Failure while reading the bulk image.
enum FetchError {
    Usb(UsbError),
    Bulk(BulkError),
}

#[cfg(test)]
mod tests {
    use super::*;

    // Not connected: the state still changes, the send fails.
    #[test]
    fn tube_type_and_character_follow_the_firmware_rules() {
        let mut c = DspiCore::new();
        let _ = c.set_tube_param(TUBE_PARAM_TYPE, 16.0);
        assert_eq!(&c.state.tube[4..8], &TUBE_ROWS[15]);
        let _ = c.set_tube_param(TUBE_PARAM_BIAS, 12.0); // same value: type stays
        assert_eq!(c.state.tube[TUBE_PARAM_TYPE as usize], 16.0);
        let _ = c.set_tube_param(TUBE_PARAM_SAG, 40.0);
        assert_eq!(c.state.tube[TUBE_PARAM_TYPE as usize], 0.0);
        let _ = c.set_tube_param(TUBE_PARAM_TYPE, 0.0); // Custom keeps the values
        assert_eq!(c.state.tube[TUBE_PARAM_SAG as usize], 40.0);
    }

    #[test]
    fn tool_params_are_clamped_and_rounded() {
        let mut c = DspiCore::new();
        let _ = c.set_upmix_param(UPMIX_PARAM_PRESENCE, 3.3);
        assert_eq!(c.state.upmix[UPMIX_PARAM_PRESENCE as usize], 3.5);
        let _ = c.set_upmix_param(UPMIX_PARAM_CENTER_MODE, 7.0);
        assert_eq!(c.state.upmix[UPMIX_PARAM_CENTER_MODE as usize], 2.0);
        let _ = c.set_subharm_param(SUBHARM_PARAM_HOLD, 10.0);
        assert_eq!(c.state.subharm[SUBHARM_PARAM_HOLD as usize], 50.0);
        let _ = c.set_tube_param(TUBE_PARAM_RECTIFIER, 2.6);
        assert_eq!(c.state.tube[TUBE_PARAM_RECTIFIER as usize], 3.0);
    }
}
