//! Device enumeration, selection, and hot-plug detection.

use std::collections::HashMap;

use log::{info, warn};
use rusb::{Device, GlobalContext};

use crate::protocol::{PRODUCT_ID, VENDOR_ID};
use crate::types::DeviceInfo;
use crate::usb::{UsbConnection, UsbError};

/// Manages DSPi device discovery and connection lifecycle.
pub struct DeviceManager {
    /// All currently known devices, keyed by serial number.
    devices: HashMap<String, DeviceInfo>,
    /// Serial of the selected/active device.
    selected_serial: Option<String>,
    /// Active USB connection.
    connection: Option<UsbConnection>,
}

impl DeviceManager {
    pub fn new() -> Self {
        Self {
            devices: HashMap::new(),
            selected_serial: None,
            connection: None,
        }
    }

    /// Scan for all connected DSPi devices (VID/PID match).
    /// Returns the list of discovered devices.
    pub fn scan(&mut self) -> Vec<DeviceInfo> {
        self.devices.clear();

        let Ok(device_list) = rusb::DeviceList::new() else {
            warn!("Failed to enumerate USB devices");
            return Vec::new();
        };

        for device in device_list.iter() {
            if let Some(info) = Self::probe_device(&device) {
                self.devices.insert(info.serial_str().to_owned(), info);
            }
        }

        self.devices.values().cloned().collect()
    }

    /// Probe a single USB device to check if it's a DSPi device.
    fn probe_device(device: &Device<GlobalContext>) -> Option<DeviceInfo> {
        let desc = device.device_descriptor().ok()?;
        if desc.vendor_id() != VENDOR_ID || desc.product_id() != PRODUCT_ID {
            return None;
        }

        let handle = device.open().ok()?;
        let serial = handle
            .read_serial_number_string_ascii(&desc)
            .unwrap_or_default();

        if serial.is_empty() {
            return None;
        }

        let mut info = DeviceInfo {
            serial: [0u8; 64],
            serial_len: serial.len().min(63) as u32,
            location_id: device.address() as u32
                | ((device.bus_number() as u32) << 8),
        };
        let len = info.serial_len as usize;
        info.serial[..len].copy_from_slice(&serial.as_bytes()[..len]);

        Some(info)
    }

    /// Select and open a specific device by serial number.
    pub fn select_device(&mut self, serial: &str) -> Result<(), UsbError> {
        // Close existing connection
        self.disconnect();

        let device_list = rusb::DeviceList::new().map_err(UsbError::Rusb)?;
        for device in device_list.iter() {
            let desc = match device.device_descriptor() {
                Ok(d) => d,
                Err(_) => continue,
            };
            if desc.vendor_id() != VENDOR_ID || desc.product_id() != PRODUCT_ID {
                continue;
            }
            let handle = match device.open() {
                Ok(h) => h,
                Err(_) => continue,
            };
            let dev_serial = match handle.read_serial_number_string_ascii(&desc) {
                Ok(s) => s,
                Err(_) => continue,
            };
            if dev_serial == serial {
                // On Linux, detach kernel driver if needed
                #[cfg(target_os = "linux")]
                {
                    let _ = handle.set_auto_detach_kernel_driver(true);
                }

                let _ = handle.claim_interface(0);
                self.connection = Some(UsbConnection::new(handle));
                self.selected_serial = Some(serial.to_owned());
                info!("Connected to DSPi device: {serial}");
                return Ok(());
            }
        }

        Err(UsbError::NotConnected)
    }

    /// Close current device connection.
    pub fn disconnect(&mut self) {
        if let Some(serial) = &self.selected_serial {
            info!("Disconnected from DSPi device: {serial}");
        }
        self.connection = None;
        // Retain selected_serial for auto-reconnect
    }

    /// Check if currently connected to a device.
    pub fn is_connected(&self) -> bool {
        self.connection.is_some()
    }

    /// Get a reference to the active USB connection.
    pub fn connection(&self) -> Option<&UsbConnection> {
        self.connection.as_ref()
    }

    /// Get the selected serial number (retained even after disconnect for auto-reconnect).
    pub fn selected_serial(&self) -> Option<&str> {
        self.selected_serial.as_deref()
    }

    /// Get the list of known devices.
    pub fn known_devices(&self) -> Vec<DeviceInfo> {
        self.devices.values().cloned().collect()
    }

    /// Poll for device changes (for platforms without native hotplug).
    /// Returns (arrivals, departures) as serial number lists.
    pub fn poll_changes(&mut self) -> (Vec<String>, Vec<String>) {
        let Ok(device_list) = rusb::DeviceList::new() else {
            return (Vec::new(), Vec::new());
        };

        let mut current_serials: HashMap<String, DeviceInfo> = HashMap::new();
        for device in device_list.iter() {
            if let Some(info) = Self::probe_device(&device) {
                current_serials.insert(info.serial_str().to_owned(), info);
            }
        }

        // Find arrivals (in current but not in previous)
        let arrivals: Vec<String> = current_serials
            .keys()
            .filter(|s| !self.devices.contains_key(*s))
            .cloned()
            .collect();

        // Find departures (in previous but not in current)
        let departures: Vec<String> = self
            .devices
            .keys()
            .filter(|s| !current_serials.contains_key(*s))
            .cloned()
            .collect();

        // Handle auto-reconnect on arrival
        let should_reconnect = match &self.selected_serial {
            Some(sel) => self.connection.is_none() && arrivals.contains(sel),
            None => false,
        };
        if should_reconnect {
            let serial = self.selected_serial.clone().unwrap();
            info!("Auto-reconnecting to {serial}");
            let _ = self.select_device(&serial);
        }

        // Handle disconnect on departure
        for dep in &departures {
            if Some(dep.as_str()) == self.selected_serial.as_deref() && self.connection.is_some() {
                info!("Selected device departed: {dep}");
                self.connection = None;
            }
        }

        self.devices = current_serials;
        (arrivals, departures)
    }
}

impl Default for DeviceManager {
    fn default() -> Self {
        Self::new()
    }
}
