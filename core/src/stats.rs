//! Device statistics for the System Statistics window: the general status
//! counters (REQ_GET_STATUS sub-queries), buffer fill levels with their
//! watermarks, and the S/PDIF receiver. All polled; none is in the bulk
//! image, and only the buffer watermarks can be reset.

use crate::protocol::*;
use crate::usb::{Result, UsbError};
use crate::DspiCore;

/// REQ_GET_STATUS sub-queries that return one u32 (cumulative since boot).
pub const STAT_PDM_RING_OVERRUNS: u16 = 3;
pub const STAT_PDM_RING_UNDERRUNS: u16 = 4;
pub const STAT_PDM_DMA_OVERRUNS: u16 = 5;
pub const STAT_PDM_DMA_UNDERRUNS: u16 = 6;
pub const STAT_SPDIF_OVERRUNS: u16 = 7;
pub const STAT_SPDIF_UNDERRUNS: u16 = 8;
pub const STAT_CLOCK_HZ: u16 = 13;
pub const STAT_CORE_MV: u16 = 14;
pub const STAT_SAMPLE_RATE: u16 = 15;
/// Centi-degrees C, signed (an i16 widened to u32).
pub const STAT_TEMPERATURE: u16 = 16;
/// S/PDIF DMA starvations: total, then instances 0-3 (18-21).
pub const STAT_STARVATION_TOTAL: u16 = 17;
pub const STAT_STARVATION_FIRST: u16 = 18;
pub const STAT_USB_RING_OVERRUNS: u16 = 22;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SpdifBufferStats {
    pub free: u8,
    pub prepared: u8,
    pub playing: u8,
    /// Consumer pipeline fill now, and its lowest and highest since the
    /// watermarks were reset, in %.
    pub fill_pct: u8,
    pub min_pct: u8,
    pub max_pct: u8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct PdmBufferStats {
    pub dma_fill_pct: u8,
    pub dma_min_pct: u8,
    pub dma_max_pct: u8,
    pub ring_fill_pct: u8,
    pub ring_min_pct: u8,
    pub ring_max_pct: u8,
}

/// REQ_GET_BUFFER_STATS (44 bytes).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct BufferStats {
    pub num_spdif: u8,
    pub pdm_active: bool,
    pub streaming: bool,
    pub sequence: u16,
    pub spdif: [SpdifBufferStats; 4],
    pub pdm: PdmBufferStats,
}

impl BufferStats {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < 44 {
            return None;
        }
        let mut s = Self {
            num_spdif: b[0].min(4),
            pdm_active: b[1] & 1 != 0,
            streaming: b[1] & 2 != 0,
            sequence: read_u16_le(b, 2),
            ..Default::default()
        };
        for (i, o) in s.spdif.iter_mut().enumerate() {
            let r = &b[4 + 8 * i..];
            *o = SpdifBufferStats { free: r[0], prepared: r[1], playing: r[2], fill_pct: r[3], min_pct: r[4], max_pct: r[5] };
        }
        let p = &b[36..];
        s.pdm = PdmBufferStats {
            dma_fill_pct: p[0],
            dma_min_pct: p[1],
            dma_max_pct: p[2],
            ring_fill_pct: p[3],
            ring_min_pct: p[4],
            ring_max_pct: p[5],
        };
        Some(s)
    }
}

/// REQ_GET_SPDIF_RX_STATUS (16 bytes).
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SpdifRxStatus {
    /// 0 inactive, 1 acquiring, 2 locked, 3 relocking.
    pub state: u8,
    /// InputSource: 0 USB, 1 S/PDIF, 2 I2S, 3 ADAT, 4-6 S/PDIF 2-4.
    pub input_source: u8,
    pub lock_count: u8,
    pub loss_count: u8,
    /// Hz when locked (else the receiver's raw estimate or 0).
    pub sample_rate: u32,
    pub parity_errors: u32,
    pub fifo_fill_pct: u16,
    /// Receiver library debug: 0 no signal, 1 waiting stable, 2 stable;
    /// and its stable / lost callback counts (4 bits each).
    pub lib_state: u8,
    pub stable_callbacks: u8,
    pub lost_callbacks: u8,
}

impl SpdifRxStatus {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < 16 {
            return None;
        }
        Some(Self {
            state: b[0],
            input_source: b[1],
            lock_count: b[2],
            loss_count: b[3],
            sample_rate: read_u32_le(b, 4),
            parity_errors: read_u32_le(b, 8),
            fifo_fill_pct: read_u16_le(b, 12),
            lib_state: b[14],
            stable_callbacks: b[15] >> 4,
            lost_callbacks: b[15] & 0x0F,
        })
    }
}

impl DspiCore {
    /// One REQ_GET_STATUS u32 counter (STAT_*).
    pub fn fetch_stat(&self, which: u16) -> Result<u32> {
        let b = self.get_exact(REQ_GET_STATUS, which, WINDEX_OUTPUT, 4, 4)?;
        Ok(read_u32_le(&b, 0))
    }

    pub fn fetch_buffer_stats(&self) -> Result<BufferStats> {
        let b = self.get_exact(REQ_GET_BUFFER_STATS, 0, WINDEX_OUTPUT, 44, 44)?;
        BufferStats::parse(&b).ok_or(UsbError::InvalidArgument)
    }

    /// Start the buffer watermarks again from now.
    pub fn reset_buffer_stats(&self) -> Result<()> {
        self.get_exact(REQ_RESET_BUFFER_STATS, 1, WINDEX_OUTPUT, 1, 1).map(|_| ())
    }

    pub fn fetch_spdif_rx_status(&self) -> Result<SpdifRxStatus> {
        let b = self.get_exact(REQ_GET_SPDIF_RX_STATUS, 0, WINDEX_OUTPUT, 16, 16)?;
        SpdifRxStatus::parse(&b).ok_or(UsbError::InvalidArgument)
    }

    /// The 24 bytes of IEC 60958 channel status of the locked S/PDIF input.
    pub fn fetch_spdif_rx_channel_status(&self) -> Result<[u8; 24]> {
        let b = self.get_exact(REQ_GET_SPDIF_RX_CH_STATUS, 0, WINDEX_OUTPUT, 24, 24)?;
        let mut out = [0u8; 24];
        out.copy_from_slice(&b[..24]);
        Ok(out)
    }

    /// GPIO of S/PDIF receiver `index` (0-3).
    pub fn fetch_spdif_rx_pin(&self, index: u8) -> Result<u8> {
        Ok(self.get_exact(REQ_GET_SPDIF_RX_PIN, index as u16, WINDEX_OUTPUT, 1, 1)?[0])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buffer_stats_layout() {
        let mut b = [0u8; 44];
        b[..4].copy_from_slice(&[4, 3, 0x34, 0x12]);
        b[4..10].copy_from_slice(&[10, 4, 1, 37, 25, 50]);
        b[36..42].copy_from_slice(&[12, 5, 30, 7, 2, 20]);
        let s = BufferStats::parse(&b).unwrap();
        assert_eq!((s.num_spdif, s.pdm_active, s.streaming, s.sequence), (4, true, true, 0x1234));
        assert_eq!(s.spdif[0], SpdifBufferStats { free: 10, prepared: 4, playing: 1, fill_pct: 37, min_pct: 25, max_pct: 50 });
        assert_eq!((s.pdm.dma_fill_pct, s.pdm.ring_max_pct), (12, 20));
        assert!(BufferStats::parse(&b[..43]).is_none());
    }

    #[test]
    fn spdif_rx_status_unpacks_debug_bytes() {
        let mut b = [0u8; 16];
        b[..4].copy_from_slice(&[2, 1, 3, 1]);
        b[4..8].copy_from_slice(&48000u32.to_le_bytes());
        b[8..12].copy_from_slice(&7u32.to_le_bytes());
        b[12..14].copy_from_slice(&52u16.to_le_bytes());
        b[14] = 2;
        b[15] = 0x31;
        let s = SpdifRxStatus::parse(&b).unwrap();
        assert_eq!((s.state, s.sample_rate, s.parity_errors, s.fifo_fill_pct), (2, 48000, 7, 52));
        assert_eq!((s.lib_state, s.stable_callbacks, s.lost_callbacks), (2, 3, 1));
    }
}
