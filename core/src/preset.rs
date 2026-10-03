//! Preset management: save/load/delete, names, directory, startup.
//!
//! Save, load and delete are deferred on the device (they run in its main
//! loop, bracketed by a pipeline reset), so each one waits for the device to
//! report completion before touching state.

use std::thread;
use std::time::{Duration, Instant};

use log::warn;

use crate::protocol::*;
use crate::types::*;
use crate::usb::Result;
use crate::DspiCore;

const DEFERRED_TIMEOUT: Duration = Duration::from_millis(1500);
const POLL_INTERVAL: Duration = Duration::from_millis(20);

impl DspiCore {
    // ═══════════════════════════════════════════════════════════════
    // Preset Save / Load / Delete
    // ═══════════════════════════════════════════════════════════════

    pub fn save_preset(&mut self, slot: u8) -> Result<u8> {
        let status = self.get_exact(REQ_PRESET_SAVE, slot as u16, WINDEX_OUTPUT, 1, 1)?[0];
        if status == PRESET_OK {
            // Wait for the flash write: the slot shows up as occupied.
            let bit = 1u16 << slot;
            self.wait_for(|c| Ok(c.read_preset_directory()?.occupied_mask & bit != 0));
            self.state.active_preset_slot = slot;
            self.state.preset_occupied |= bit;
        }
        Ok(status)
    }

    pub fn load_preset(&mut self, slot: u8) -> Result<u8> {
        let status = self.get_exact(REQ_PRESET_LOAD, slot as u16, WINDEX_OUTPUT, 1, 1)?[0];
        if status == PRESET_OK {
            if !self.wait_for(|c| Ok(c.get_preset_active()? == slot)) {
                warn!("Preset {slot} load did not confirm in time");
            }
            self.state.active_preset_slot = slot;
            self.refresh_params()?;
        }
        Ok(status)
    }

    pub fn delete_preset(&mut self, slot: u8) -> Result<u8> {
        let status = self.get_exact(REQ_PRESET_DELETE, slot as u16, WINDEX_OUTPUT, 1, 1)?[0];
        if status == PRESET_OK {
            let bit = 1u16 << slot;
            self.wait_for(|c| Ok(c.read_preset_directory()?.occupied_mask & bit == 0));
            self.state.preset_occupied &= !bit;
            // Deleting the active slot applies factory defaults on the device.
            if self.state.active_preset_slot == slot {
                self.refresh_params()?;
            }
        }
        Ok(status)
    }

    /// Poll `done` until it returns true or the deferred-operation timeout passes.
    fn wait_for(&mut self, mut done: impl FnMut(&mut Self) -> Result<bool>) -> bool {
        let deadline = Instant::now() + DEFERRED_TIMEOUT;
        while Instant::now() < deadline {
            if let Ok(true) = done(self) {
                return true;
            }
            thread::sleep(POLL_INTERVAL);
        }
        false
    }

    // ═══════════════════════════════════════════════════════════════
    // Preset Names
    // ═══════════════════════════════════════════════════════════════

    pub fn set_preset_name(&mut self, slot: u8, name: &str) -> Result<()> {
        if slot as usize >= MAX_PRESETS {
            return Err(crate::usb::UsbError::InvalidArgument);
        }
        let buf = name_to_bytes(name);
        self.state.preset_names[slot as usize] = buf;
        let len = buf.iter().position(|&b| b == 0).unwrap_or(CHANNEL_NAME_LEN - 1);
        self.send(REQ_PRESET_SET_NAME, slot as u16, WINDEX_OUTPUT, &buf[..=len])
    }

    pub fn get_preset_name(&mut self, slot: u8) -> Result<String> {
        if slot as usize >= MAX_PRESETS {
            return Err(crate::usb::UsbError::InvalidArgument);
        }
        let data = self.get_exact(REQ_PRESET_GET_NAME, slot as u16, WINDEX_OUTPUT, 32, 1)?;
        let mut buf = [0u8; CHANNEL_NAME_LEN];
        let len = data.len().min(CHANNEL_NAME_LEN - 1);
        buf[..len].copy_from_slice(&data[..len]);
        self.state.preset_names[slot as usize] = buf;
        Ok(name_from_bytes(&buf))
    }

    pub(crate) fn fetch_preset_name_internal(&mut self, slot: u8) {
        // Empty slots STALL; that is not an error worth logging.
        if self.get_preset_name(slot).is_err() {
            self.state.preset_names[slot as usize] = [0u8; CHANNEL_NAME_LEN];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Preset Directory
    // ═══════════════════════════════════════════════════════════════

    fn read_preset_directory(&self) -> Result<PresetDirectory> {
        let d = self.get_exact(REQ_PRESET_GET_DIR, 0, WINDEX_OUTPUT, 7, 5)?;
        Ok(PresetDirectory {
            occupied_mask: u16::from_le_bytes([d[0], d[1]]),
            startup_mode: d[2],
            default_slot: d[3],
            last_active: d[4],
            output_config_mode: d.get(5).copied().unwrap_or(1),
            master_volume_mode: d.get(6).copied().unwrap_or(0),
        })
    }

    pub fn get_preset_directory(&mut self) -> Result<PresetDirectory> {
        let dir = self.read_preset_directory()?;
        let s = &mut self.state;
        s.preset_occupied = dir.occupied_mask;
        s.preset_startup_mode = dir.startup_mode;
        s.preset_default_slot = dir.default_slot;
        s.active_preset_slot = dir.last_active;
        s.output_config_mode = dir.output_config_mode;
        s.master_volume_mode = dir.master_volume_mode;
        Ok(dir)
    }

    pub(crate) fn fetch_preset_directory_internal(&mut self) {
        if let Err(e) = self.get_preset_directory() {
            warn!("Failed to fetch preset directory: {e}");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Startup / Active
    // ═══════════════════════════════════════════════════════════════

    /// mode 0 = load `default_slot` at boot, 1 = load the last active slot.
    pub fn set_preset_startup(&mut self, mode: u8, default_slot: u8) -> Result<()> {
        self.state.preset_startup_mode = mode;
        self.state.preset_default_slot = default_slot;
        self.send(REQ_PRESET_SET_STARTUP, 0, WINDEX_OUTPUT, &[mode, default_slot])
    }

    pub fn get_preset_active(&mut self) -> Result<u8> {
        let v = self.get_exact(REQ_PRESET_GET_ACTIVE, 0, WINDEX_OUTPUT, 1, 1)?[0];
        self.state.active_preset_slot = v;
        Ok(v)
    }
}
