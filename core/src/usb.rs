//! Low-level USB communication via libusb (rusb crate).

use std::time::Duration;

use rusb::{DeviceHandle, GlobalContext};

use crate::protocol::{REQ_TYPE_IN, REQ_TYPE_OUT};

/// Default USB transfer timeout.
const TIMEOUT: Duration = Duration::from_millis(1000);

/// Error type for USB operations.
#[derive(Debug, thiserror::Error)]
pub enum UsbError {
    #[error("USB transfer error: {0}")]
    Rusb(#[from] rusb::Error),
    #[error("Device not connected")]
    NotConnected,
    #[error("Short read: expected {expected}, got {actual}")]
    ShortRead { expected: usize, actual: usize },
}

pub type Result<T> = std::result::Result<T, UsbError>;

/// Wraps a rusb DeviceHandle for USB control transfers.
pub struct UsbConnection {
    handle: DeviceHandle<GlobalContext>,
}

impl UsbConnection {
    /// Create a new connection from an already-opened device handle.
    pub fn new(handle: DeviceHandle<GlobalContext>) -> Self {
        Self { handle }
    }

    /// Send a vendor control transfer (Host→Device, fire-and-forget).
    /// bmRequestType = 0x41 (vendor, interface, host-to-device).
    pub fn send_control(
        &self,
        request: u8,
        value: u16,
        index: u16,
        data: &[u8],
    ) -> Result<()> {
        self.handle
            .write_control(REQ_TYPE_OUT, request, value, index, data, TIMEOUT)?;
        Ok(())
    }

    /// Receive a vendor control transfer (Device→Host, synchronous).
    /// bmRequestType = 0xC1 (vendor, interface, device-to-host).
    /// Returns the received data.
    pub fn get_control(
        &self,
        request: u8,
        value: u16,
        index: u16,
        length: u16,
    ) -> Result<Vec<u8>> {
        let mut buf = vec![0u8; length as usize];
        let n = self
            .handle
            .read_control(REQ_TYPE_IN, request, value, index, &mut buf, TIMEOUT)?;
        buf.truncate(n);
        Ok(buf)
    }

    /// Send a control transfer and verify the response has at least `min_len` bytes.
    pub fn get_control_exact(
        &self,
        request: u8,
        value: u16,
        index: u16,
        length: u16,
        min_len: usize,
    ) -> Result<Vec<u8>> {
        let data = self.get_control(request, value, index, length)?;
        if data.len() < min_len {
            return Err(UsbError::ShortRead {
                expected: min_len,
                actual: data.len(),
            });
        }
        Ok(data)
    }
}
