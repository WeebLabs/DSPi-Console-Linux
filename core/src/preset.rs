//! Preset management — save/load/delete/names/directory/startup.

use std::thread;
use std::time::Duration;

use log::warn;

use crate::protocol::*;
use crate::types::*;
use crate::usb::Result;
use crate::DspiCore;

impl DspiCore {
    // ═══════════════════════════════════════════════════════════════
    // Preset Save / Load / Delete
    // ═══════════════════════════════════════════════════════════════

    pub fn save_preset(&mut self, slot: u8) -> Result<u8> {
        let data = self.get_exact(REQ_PRESET_SAVE, slot as u16, WINDEX_OUTPUT, 1, 1)?;
        let status = data[0];
        if status == PRESET_OK {
            self.state.active_preset_slot = slot;
            self.state.preset_occupied |= 1 << slot;
        }
        Ok(status)
    }

    pub fn load_preset(&mut self, slot: u8) -> Result<u8> {
        let data = self.get_exact(REQ_PRESET_LOAD, slot as u16, WINDEX_OUTPUT, 1, 1)?;
        let status = data[0];
        if status == PRESET_OK {
            self.state.active_preset_slot = slot;
            // Wait for firmware mute period then re-sync (matches Swift behavior)
            thread::sleep(Duration::from_millis(10));
            self.fetch_all()?;
        }
        Ok(status)
    }

    pub fn delete_preset(&mut self, slot: u8) -> Result<u8> {
        let data = self.get_exact(REQ_PRESET_DELETE, slot as u16, WINDEX_OUTPUT, 1, 1)?;
        let status = data[0];
        if status == PRESET_OK {
            self.state.preset_occupied &= !(1 << slot);
        }
        Ok(status)
    }

    // ═══════════════════════════════════════════════════════════════
    // Preset Names
    // ═══════════════════════════════════════════════════════════════

    pub fn set_preset_name(&mut self, slot: u8, name: &str) -> Result<()> {
        let buf = name_to_bytes(name);
        self.state.preset_names[slot as usize] = buf;
        // Send NUL-terminated name (not full 32 bytes, matching Swift)
        let utf8 = name.as_bytes();
        let len = utf8.len().min(CHANNEL_NAME_LEN - 1);
        let mut send_buf = Vec::with_capacity(len + 1);
        send_buf.extend_from_slice(&utf8[..len]);
        send_buf.push(0);
        self.send(REQ_PRESET_SET_NAME, slot as u16, WINDEX_OUTPUT, &send_buf)
    }

    pub fn get_preset_name(&mut self, slot: u8) -> Result<String> {
        let data = self.get_exact(REQ_PRESET_GET_NAME, slot as u16, WINDEX_OUTPUT, 32, 1)?;
        let mut buf = [0u8; CHANNEL_NAME_LEN];
        let len = data.len().min(CHANNEL_NAME_LEN);
        buf[..len].copy_from_slice(&data[..len]);
        self.state.preset_names[slot as usize] = buf;
        Ok(name_from_bytes(&buf))
    }

    // ═══════════════════════════════════════════════════════════════
    // Preset Directory
    // ═══════════════════════════════════════════════════════════════

    pub fn get_preset_directory(&mut self) -> Result<PresetDirectory> {
        let data = self.get_exact(REQ_PRESET_GET_DIR, 0, WINDEX_OUTPUT, 6, 6)?;
        let dir = PresetDirectory {
            occupied_mask: u16::from_le_bytes([data[0], data[1]]),
            startup_mode: data[2],
            default_slot: data[3],
            last_active: data[4],
            include_pins: data[5] != 0,
        };
        self.state.preset_occupied = dir.occupied_mask;
        self.state.preset_startup_mode = dir.startup_mode;
        self.state.preset_default_slot = dir.default_slot;
        self.state.active_preset_slot = dir.last_active;
        self.state.preset_include_pins = dir.include_pins;
        Ok(dir)
    }

    /// Internal version that doesn't propagate errors.
    pub(crate) fn fetch_preset_directory_internal(&mut self) {
        if let Err(e) = self.get_preset_directory() {
            warn!("Failed to fetch preset directory: {e}");
        }
    }

    /// Internal version that doesn't propagate errors.
    pub(crate) fn fetch_preset_name_internal(&mut self, slot: u8) {
        if let Err(e) = self.get_preset_name(slot) {
            warn!("Failed to fetch preset name for slot {slot}: {e}");
        }
    }

    /// Internal version that doesn't propagate errors.
    pub(crate) fn fetch_preset_active_internal(&mut self) {
        match self.get_exact(REQ_PRESET_GET_ACTIVE, 0, WINDEX_OUTPUT, 1, 1) {
            Ok(data) => self.state.active_preset_slot = data[0],
            Err(e) => warn!("Failed to fetch active preset: {e}"),
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Preset Startup / Include Pins
    // ═══════════════════════════════════════════════════════════════

    pub fn set_preset_startup(&mut self, mode: u8, default_slot: u8) -> Result<()> {
        self.state.preset_startup_mode = mode;
        self.state.preset_default_slot = default_slot;
        self.send(REQ_PRESET_SET_STARTUP, 0, WINDEX_OUTPUT, &[mode, default_slot])
    }

    pub fn get_preset_active(&mut self) -> Result<u8> {
        let data = self.get_exact(REQ_PRESET_GET_ACTIVE, 0, WINDEX_OUTPUT, 1, 1)?;
        self.state.active_preset_slot = data[0];
        Ok(data[0])
    }

    pub fn set_preset_include_pins(&mut self, include: bool) -> Result<()> {
        self.state.preset_include_pins = include;
        self.send(REQ_PRESET_SET_INCLUDE_PINS, 0, WINDEX_OUTPUT, &[include as u8])
    }

    pub fn get_preset_include_pins(&mut self) -> Result<bool> {
        let data = self.get_exact(REQ_PRESET_GET_INCLUDE_PINS, 0, WINDEX_OUTPUT, 1, 1)?;
        let val = data[0] != 0;
        self.state.preset_include_pins = val;
        Ok(val)
    }
}
