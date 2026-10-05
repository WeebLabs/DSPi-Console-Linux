//! Control Surfaces: GPIO buttons, switches, pots, encoders, LEDs, an IR
//! remote receiver, an I2C display and auxiliary outputs, each bound to a
//! device function (a "noun") through an action; plus channel groups and
//! macros. The configuration lives on the device (not in presets): every
//! SET applies live and marks it dirty, Save writes it to flash and Revert
//! reloads the saved one.
//!
//! SETs are applied in the device's main loop: the result is read from the
//! status packet, whose `last_slot` names the record (slot n, IR 0x80|n,
//! group 0x40|n, macro 0x60|n, display 0x50|n, save / revert 0xFF). The
//! firmware ACKs every OUT transfer, so that poll is the only way to know.
//!
//! The GUI talks to this module in JSON: `snapshot()` describes everything,
//! `apply(op)` performs one operation and re-reads what it changed.

use std::thread;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::protocol::*;
use crate::usb::{Result, UsbError};
use crate::DspiCore;

pub const CS_MAX_BINDINGS: usize = 16;
pub const CS_MAX_IR: usize = 16;
pub const CS_MAX_GROUPS: usize = 8;
pub const CS_MAX_MACROS: usize = 8;
pub const CS_MAX_STEPS: usize = 8;
pub const CS_MAX_PAGES: usize = 16;
const NAME_LEN: usize = 32;

const ST_PENDING: u8 = 0x16;
const TAG_SAVE: u8 = 0xFF;

// Requests (firmware config.h)
const REQ_SET_BINDING: u8 = 0x84;
const REQ_GET_BINDING: u8 = 0x85;
const REQ_GET_CAPS: u8 = 0x86;
const REQ_GET_STATUS_CS: u8 = 0x87;
const REQ_SET_NAME: u8 = 0x8B;
const REQ_GET_NAME: u8 = 0x8C;
const REQ_SET_IR: u8 = 0x8D;
const REQ_GET_IR: u8 = 0x8E;
const REQ_IR_LEARN: u8 = 0x8F;
const REQ_SAVE: u8 = 0x9D;
const REQ_REVERT: u8 = 0x9E;
const REQ_SET_GROUP: u8 = 0x20;
const REQ_GET_GROUP: u8 = 0x21;
const REQ_SET_MACRO: u8 = 0x22;
const REQ_GET_MACRO: u8 = 0x23;
const REQ_SET_MACRO_STEP: u8 = 0x24;
const REQ_MACRO_FIRE: u8 = 0x25;
const REQ_GET_EXT_STATUS: u8 = 0x26;
const REQ_SET_DISPLAY_CFG: u8 = 0x27;
const REQ_GET_DISPLAY_CFG: u8 = 0x28;
const REQ_SET_DISPLAY_PAGE: u8 = 0x29;
const REQ_GET_DISPLAY_PAGE: u8 = 0x2A;
const REQ_GET_DISPLAY_STATUS: u8 = 0x2B;
const REQ_SET_AUX_STATE: u8 = 0x04;
const REQ_GET_AUX_STATE: u8 = 0x05;
const REQ_SET_AUX_LEVEL: u8 = 0x06;

fn i16_at(b: &[u8], o: usize) -> i16 {
    i16::from_le_bytes([b[o], b[o + 1]])
}
fn u16_at(b: &[u8], o: usize) -> u16 {
    u16::from_le_bytes([b[o], b[o + 1]])
}
fn u32_at(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]])
}
fn name_from(b: &[u8]) -> String {
    let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    String::from_utf8_lossy(&b[..end]).into_owned()
}
fn name_bytes(s: &str) -> [u8; NAME_LEN] {
    let mut out = [0u8; NAME_LEN];
    let mut n = s.len().min(NAME_LEN - 1);
    while !s.is_char_boundary(n) {
        n -= 1;
    }
    out[..n].copy_from_slice(&s.as_bytes()[..n]);
    out
}
fn jn(v: &Value, k: &str) -> i64 {
    v.get(k).and_then(|x| x.as_i64().or_else(|| x.as_f64().map(|f| f.round() as i64)).or_else(|| x.as_bool().map(|b| b as i64))).unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════
// Records
// ═══════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Binding {
    pub kind: u8,
    pub noun: u8,
    pub action: u8,
    pub flags: u8,
    pub gpio: [u8; 2],
    pub event: u8,
    pub target: u8,
    pub index: u8,
    pub base_bright: u8,
    pub value: i16,
    pub step: i16,
    pub range_min: i16,
    pub range_max: i16,
    pub on_delay: u16,
    pub off_delay: u16,
    pub extras: u8,
}

impl Binding {
    pub fn parse(b: &[u8]) -> Option<Self> {
        (b.len() >= 24).then(|| Self {
            kind: b[0], noun: b[1], action: b[2], flags: b[3], gpio: [b[4], b[5]], event: b[6],
            target: b[7], index: b[8], base_bright: b[9], value: i16_at(b, 10), step: i16_at(b, 12),
            range_min: i16_at(b, 14), range_max: i16_at(b, 16), on_delay: u16_at(b, 18),
            off_delay: u16_at(b, 20), extras: b[22],
        })
    }
    pub fn encode(&self) -> [u8; 24] {
        let mut b = [0u8; 24];
        b[..10].copy_from_slice(&[self.kind, self.noun, self.action, self.flags, self.gpio[0], self.gpio[1],
                                  self.event, self.target, self.index, self.base_bright]);
        b[10..12].copy_from_slice(&self.value.to_le_bytes());
        b[12..14].copy_from_slice(&self.step.to_le_bytes());
        b[14..16].copy_from_slice(&self.range_min.to_le_bytes());
        b[16..18].copy_from_slice(&self.range_max.to_le_bytes());
        b[18..20].copy_from_slice(&self.on_delay.to_le_bytes());
        b[20..22].copy_from_slice(&self.off_delay.to_le_bytes());
        b[22] = self.extras;
        b
    }
    fn json(&self) -> Value {
        json!({ "type": self.kind, "noun": self.noun, "action": self.action, "flags": self.flags,
                "gpio0": self.gpio[0], "gpio1": self.gpio[1], "event": self.event, "target": self.target,
                "index": self.index, "baseBright": self.base_bright, "value": self.value, "step": self.step,
                "rangeMin": self.range_min, "rangeMax": self.range_max, "onDelay": self.on_delay,
                "offDelay": self.off_delay, "extras": self.extras })
    }
    fn from_json(v: &Value) -> Self {
        Self {
            kind: jn(v, "type") as u8, noun: jn(v, "noun") as u8, action: jn(v, "action") as u8,
            flags: jn(v, "flags") as u8,
            gpio: [jn(v, "gpio0") as u8, v.get("gpio1").map(|_| jn(v, "gpio1") as u8).unwrap_or(0xFF)],
            event: jn(v, "event") as u8, target: jn(v, "target") as u8, index: jn(v, "index") as u8,
            base_bright: jn(v, "baseBright") as u8, value: jn(v, "value") as i16, step: jn(v, "step") as i16,
            range_min: jn(v, "rangeMin") as i16, range_max: jn(v, "rangeMax") as i16,
            on_delay: jn(v, "onDelay") as u16, off_delay: jn(v, "offDelay") as u16, extras: jn(v, "extras") as u8,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct IrCommand {
    pub noun: u8,
    pub action: u8,
    pub flags: u8,
    pub target: u8,
    pub index: u8,
    pub protocol: u8,
    pub value: i16,
    pub step: i16,
    pub code: u32,
}

impl IrCommand {
    pub fn parse(b: &[u8]) -> Option<Self> {
        (b.len() >= 16).then(|| Self {
            noun: b[0], action: b[1], flags: b[2], target: b[3], index: b[4], protocol: b[5],
            value: i16_at(b, 6), step: i16_at(b, 8), code: u32_at(b, 12),
        })
    }
    pub fn encode(&self) -> [u8; 16] {
        let mut b = [0u8; 16];
        b[..6].copy_from_slice(&[self.noun, self.action, self.flags, self.target, self.index, self.protocol]);
        b[6..8].copy_from_slice(&self.value.to_le_bytes());
        b[8..10].copy_from_slice(&self.step.to_le_bytes());
        b[12..16].copy_from_slice(&self.code.to_le_bytes());
        b
    }
    fn json(&self) -> Value {
        json!({ "noun": self.noun, "action": self.action, "flags": self.flags, "target": self.target,
                "index": self.index, "protocol": self.protocol, "value": self.value, "step": self.step, "code": self.code })
    }
    fn from_json(v: &Value) -> Self {
        Self {
            noun: jn(v, "noun") as u8, action: jn(v, "action") as u8, flags: jn(v, "flags") as u8,
            target: jn(v, "target") as u8, index: jn(v, "index") as u8, protocol: jn(v, "protocol") as u8,
            value: jn(v, "value") as i16, step: jn(v, "step") as i16, code: jn(v, "code") as u32,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Group {
    pub target_kind: u8,
    pub member_mask: u32,
    pub name: String,
}

impl Group {
    pub fn parse(b: &[u8]) -> Option<Self> {
        (b.len() >= 40).then(|| Self { target_kind: b[0], member_mask: u32_at(b, 4), name: name_from(&b[8..40]) })
    }
    pub fn encode(&self) -> [u8; 40] {
        let mut b = [0u8; 40];
        b[0] = self.target_kind;
        b[4..8].copy_from_slice(&self.member_mask.to_le_bytes());
        b[8..40].copy_from_slice(&name_bytes(&self.name));
        b
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct MacroStep {
    pub noun: u8,
    pub action: u8,
    pub flags: u8,
    pub target: u8,
    pub index: u8,
    pub value: i16,
    pub step: i16,
    pub pre_delay: u16,
}

impl MacroStep {
    fn parse(b: &[u8]) -> Self {
        Self { noun: b[0], action: b[1], flags: b[2], target: b[3], index: b[4], value: i16_at(b, 6),
               step: i16_at(b, 8), pre_delay: u16_at(b, 10) }
    }
    fn encode(&self) -> [u8; 12] {
        let mut b = [0u8; 12];
        b[..5].copy_from_slice(&[self.noun, self.action, self.flags, self.target, self.index]);
        b[6..8].copy_from_slice(&self.value.to_le_bytes());
        b[8..10].copy_from_slice(&self.step.to_le_bytes());
        b[10..12].copy_from_slice(&self.pre_delay.to_le_bytes());
        b
    }
    fn json(&self) -> Value {
        json!({ "noun": self.noun, "action": self.action, "flags": self.flags, "target": self.target,
                "index": self.index, "value": self.value, "step": self.step, "preDelay": self.pre_delay })
    }
    fn from_json(v: &Value) -> Self {
        Self { noun: jn(v, "noun") as u8, action: jn(v, "action") as u8, flags: jn(v, "flags") as u8,
               target: jn(v, "target") as u8, index: jn(v, "index") as u8, value: jn(v, "value") as i16,
               step: jn(v, "step") as i16, pre_delay: jn(v, "preDelay") as u16 }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Macro {
    pub name: String,
    pub steps: Vec<MacroStep>,
}

impl Macro {
    pub fn parse(b: &[u8]) -> Option<Self> {
        if b.len() < 132 {
            return None;
        }
        let count = (b[32] as usize).min(CS_MAX_STEPS);
        Some(Self { name: name_from(&b[..32]), steps: (0..count).map(|i| MacroStep::parse(&b[36 + 12 * i..])).collect() })
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct DisplayConfig {
    pub mode: u8,
    pub home_page: u8,
    pub dwell: u16,
    pub overlay_hold: u16,
    pub brightness: u8,
    pub flags: u8,
    pub edit_timeout: u16,
}

impl DisplayConfig {
    fn parse(b: &[u8]) -> Self {
        Self { mode: b[0], home_page: b[1], dwell: u16_at(b, 2), overlay_hold: u16_at(b, 4), brightness: b[6],
               flags: b[7], edit_timeout: u16_at(b, 8) }
    }
    fn encode(&self) -> [u8; 12] {
        let mut b = [0u8; 12];
        b[0] = self.mode;
        b[1] = self.home_page;
        b[2..4].copy_from_slice(&self.dwell.to_le_bytes());
        b[4..6].copy_from_slice(&self.overlay_hold.to_le_bytes());
        b[6] = self.brightness;
        b[7] = self.flags;
        b[8..10].copy_from_slice(&self.edit_timeout.to_le_bytes());
        b
    }
    fn json(&self) -> Value {
        json!({ "mode": self.mode, "homePage": self.home_page, "dwell": self.dwell, "overlayHold": self.overlay_hold,
                "brightness": self.brightness, "flags": self.flags, "editTimeout": self.edit_timeout })
    }
    fn from_json(v: &Value) -> Self {
        Self { mode: jn(v, "mode") as u8, home_page: jn(v, "homePage") as u8, dwell: jn(v, "dwell") as u16,
               overlay_hold: jn(v, "overlayHold") as u16, brightness: jn(v, "brightness") as u8,
               flags: jn(v, "flags") as u8, edit_timeout: jn(v, "editTimeout") as u16 }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct NounDesc {
    pub kind: u8,
    pub enum_count: u8,
    pub actions: u16,
    pub min: i16,
    pub max: i16,
    pub unit: u8,
    pub target_kind: u8,
    pub target_count: u8,
    pub dflags: u8,
}

/// Everything read from the device, kept between operations.
#[derive(Debug, Clone, Default)]
pub struct CsState {
    pub supported: bool,
    pub caps_version: u8,
    pub max_bindings: u8,
    pub types: Vec<(u16, u8, u8)>, // actions, pin count, pin class
    pub nouns: Vec<NounDesc>,
    pub max_ir: u8,
    pub max_groups: u8,
    pub max_macros: u8,
    pub max_steps: u8,
    pub status: Vec<u8>,
    pub bindings: [Binding; CS_MAX_BINDINGS],
    pub names: Vec<String>,
    pub ir: [IrCommand; CS_MAX_IR],
    pub groups: Vec<Group>,
    pub macros: Vec<Macro>,
    pub ext: Vec<u8>,
    pub display_limits: (u8, u8),
    pub display: DisplayConfig,
    pub pages: [[u8; 4]; CS_MAX_PAGES],
    pub display_status: Vec<u8>,
    pub aux_state: [u8; 16],
    pub aux_level: [u16; 16],
    /// The last IR learn result from a notification: state, protocol, code.
    pub learn: Option<(u8, u8, u32)>,
    /// The configuration as last saved (or loaded clean), to tell a real
    /// unsaved edit from changes that were undone.
    pub clean: Option<String>,
}

impl CsState {
    fn config_key(&self) -> String {
        format!("{:?}{:?}{:?}{:?}{:?}{:?}{:?}", self.bindings, self.names, self.ir, self.groups, self.macros,
                self.display, self.pages)
    }
    fn dirty(&self) -> bool {
        self.status.get(3).copied().unwrap_or(0) != 0
    }
    /// Unsaved edits: the device says dirty and the configuration differs
    /// from the clean one.
    pub fn unsaved(&self) -> bool {
        self.dirty() && self.clean.as_deref().map_or(true, |c| c != self.config_key())
    }
    fn mark_clean(&mut self) {
        self.clean = Some(self.config_key());
    }
}

// ═══════════════════════════════════════════════════════════════════
// Device access
// ═══════════════════════════════════════════════════════════════════

impl DspiCore {
    fn cs_get(&self, req: u8, value: u16, len: u16) -> Result<Vec<u8>> {
        self.get(req, value, WINDEX_OUTPUT, len)
    }

    /// Wait for the main loop to apply the SET tagged `tag`: its status code
    /// (0 = done), or PENDING if it hasn't finished in 600 ms.
    fn cs_wait(&mut self, tag: u8) -> u8 {
        let start = Instant::now();
        loop {
            if let Ok(s) = self.cs_get(REQ_GET_STATUS_CS, 0, 41) {
                if s.len() >= 2 && s[1] == tag && s[0] != ST_PENDING {
                    self.cs.status = s.clone();
                    return s[0];
                }
            }
            if start.elapsed() > Duration::from_millis(600) {
                return ST_PENDING;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }

    fn cs_set(&mut self, req: u8, value: u16, data: &[u8], tag: u8) -> Result<u8> {
        self.send(req, value, WINDEX_OUTPUT, data)?;
        Ok(self.cs_wait(tag))
    }

    fn cs_read_status(&mut self) {
        if let Ok(s) = self.cs_get(REQ_GET_STATUS_CS, 0, 41) {
            self.cs.status = s;
        }
        if self.cs.max_groups > 0 || self.cs.max_macros > 0 {
            if let Ok(e) = self.cs_get(REQ_GET_EXT_STATUS, 0, 24) {
                self.cs.ext = e;
            }
        }
    }

    fn cs_read_binding(&mut self, slot: usize) {
        if let Some(b) = self.cs_get(REQ_GET_BINDING, slot as u16, 24).ok().and_then(|b| Binding::parse(&b)) {
            self.cs.bindings[slot] = b;
        }
        if let Ok(n) = self.cs_get(REQ_GET_NAME, slot as u16, 32) {
            self.cs.names[slot] = name_from(&n);
        }
    }

    fn cs_read_display(&mut self) {
        if self.cs.types.len() <= 8 {
            return;
        }
        if let Ok(b) = self.cs_get(REQ_GET_DISPLAY_CFG, 0, 16) {
            if b.len() >= 16 {
                self.cs.display_limits = (b[0], b[1]);
                self.cs.display = DisplayConfig::parse(&b[4..]);
            }
        }
        for p in 0..CS_MAX_PAGES {
            if let Ok(b) = self.cs_get(REQ_GET_DISPLAY_PAGE, p as u16, 4) {
                if b.len() >= 4 {
                    self.cs.pages[p].copy_from_slice(&b[..4]);
                }
            }
        }
        if let Ok(b) = self.cs_get(REQ_GET_DISPLAY_STATUS, 0, 8) {
            self.cs.display_status = b;
        }
    }

    fn cs_read_aux(&mut self) {
        if self.cs.types.len() <= 10 {
            return;
        }
        if let Ok(b) = self.cs_get(REQ_GET_AUX_STATE, 0xFFFF, 48) {
            if b.len() >= 48 {
                self.cs.aux_state.copy_from_slice(&b[..16]);
                for i in 0..16 {
                    self.cs.aux_level[i] = u16_at(&b, 16 + 2 * i);
                }
            }
        }
    }

    /// Read the whole configuration. Ok with `supported` false on firmware
    /// without control surfaces.
    pub fn cs_fetch_all(&mut self) -> Result<()> {
        let clean = self.cs.clean.take();
        self.cs = CsState { learn: self.cs.learn, ..CsState::default() };
        let h = match self.cs_get(REQ_GET_CAPS, 0xFFFF, 64) {
            Ok(h) if h.len() >= 4 => h,
            Ok(_) | Err(UsbError::Rusb(rusb::Error::Pipe)) => return Ok(()),
            Err(e) => return Err(e),
        };
        let type_count = h[2] as usize;
        let noun_count = h[3] as usize;
        let tail = 4 + 4 * type_count;
        self.cs.caps_version = h[0];
        self.cs.max_bindings = (h[1] as usize).min(CS_MAX_BINDINGS) as u8;
        for t in 0..type_count {
            let o = 4 + 4 * t;
            if o + 4 <= h.len() {
                self.cs.types.push((u16_at(&h, o), h[o + 2], h[o + 3]));
            }
        }
        if h.len() >= tail + 4 {
            self.cs.max_ir = h[tail].min(CS_MAX_IR as u8);
            self.cs.max_groups = h[tail + 1].min(CS_MAX_GROUPS as u8);
            self.cs.max_macros = h[tail + 2].min(CS_MAX_MACROS as u8);
            self.cs.max_steps = h[tail + 3].min(CS_MAX_STEPS as u8);
        }
        // A noun that can't be read stays a hole (no actions), so the list
        // remains indexed by noun
        for n in 0..noun_count {
            let d = self.cs_get(REQ_GET_CAPS, n as u16, 12).ok().filter(|b| b.len() >= 12).map(|b| NounDesc {
                kind: b[0], enum_count: b[1], actions: u16_at(&b, 2), min: i16_at(&b, 4), max: i16_at(&b, 6),
                unit: b[8], target_kind: b[9], target_count: b[10], dflags: b[11],
            });
            self.cs.nouns.push(d.unwrap_or_default());
        }
        self.cs.names = vec![String::new(); CS_MAX_BINDINGS];
        for slot in 0..self.cs.max_bindings as usize {
            self.cs_read_binding(slot);
        }
        for sub in 0..self.cs.max_ir as usize {
            if let Some(c) = self.cs_get(REQ_GET_IR, sub as u16, 16).ok().and_then(|b| IrCommand::parse(&b)) {
                self.cs.ir[sub] = c;
            }
        }
        for g in 0..self.cs.max_groups as usize {
            self.cs.groups.push(self.cs_get(REQ_GET_GROUP, g as u16, 40).ok().and_then(|b| Group::parse(&b)).unwrap_or_default());
        }
        for m in 0..self.cs.max_macros as usize {
            self.cs.macros.push(self.cs_get(REQ_GET_MACRO, m as u16, 132).ok().and_then(|b| Macro::parse(&b)).unwrap_or_default());
        }
        self.cs_read_display();
        self.cs_read_aux();
        self.cs_read_status();
        self.cs.supported = true;
        // A device that isn't dirty is the baseline; a dirty one keeps the
        // known baseline (none at first read: its edits count as unsaved)
        self.cs.clean = clean;
        if !self.cs.dirty() {
            self.cs.mark_clean();
        }
        Ok(())
    }

    /// The configuration as JSON for the GUI.
    pub fn cs_snapshot(&self) -> Value {
        let c = &self.cs;
        if !c.supported {
            return json!({ "supported": false });
        }
        let s = &c.status;
        let byte = |o: usize| s.get(o).copied().unwrap_or(0);
        let status = json!({
            "lastStatus": byte(0), "lastSlot": byte(1), "dirty": c.unsaved(),
            "activeMask": if s.len() >= 6 { u16_at(s, 4) } else { 0 },
            "slotStatus": (0..16).map(|i| byte(6 + i)).collect::<Vec<_>>(),
            "irActiveMask": if s.len() >= 24 { u16_at(s, 22) } else { 0 },
            "learnState": byte(24),
            "irStatus": (0..16).map(|i| byte(25 + i)).collect::<Vec<_>>(),
        });
        let e = &c.ext;
        let eb = |o: usize| e.get(o).copied().unwrap_or(0);
        let ds = &c.display_status;
        let db = |o: usize| ds.get(o).copied().unwrap_or(0);
        json!({
            "supported": true,
            "capsVersion": c.caps_version,
            "maxBindings": c.max_bindings,
            "types": c.types.iter().map(|t| json!({ "actions": t.0, "pins": t.1, "pinClass": t.2 })).collect::<Vec<_>>(),
            "nouns": c.nouns.iter().map(|n| json!({ "kind": n.kind, "enumCount": n.enum_count, "actions": n.actions,
                "min": n.min, "max": n.max, "unit": n.unit, "targetKind": n.target_kind, "targetCount": n.target_count,
                "deferred": n.dflags & 1 != 0 })).collect::<Vec<_>>(),
            "maxIr": c.max_ir, "maxGroups": c.max_groups, "maxMacros": c.max_macros, "maxSteps": c.max_steps,
            "status": status,
            "bindings": c.bindings[..c.max_bindings as usize].iter().map(Binding::json).collect::<Vec<_>>(),
            "names": c.names,
            "ir": c.ir[..c.max_ir as usize].iter().map(IrCommand::json).collect::<Vec<_>>(),
            "groups": c.groups.iter().map(|g| json!({ "targetKind": g.target_kind, "memberMask": g.member_mask, "name": g.name })).collect::<Vec<_>>(),
            "macros": c.macros.iter().map(|m| json!({ "name": m.name, "steps": m.steps.iter().map(MacroStep::json).collect::<Vec<_>>() })).collect::<Vec<_>>(),
            "ext": { "macroRunning": if e.len() > 3 { eb(3) as i64 } else { 0xFF }, "macroStep": eb(4),
                     "groupStatus": (0..8).map(|i| eb(8 + i)).collect::<Vec<_>>(),
                     "macroStatus": (0..8).map(|i| eb(16 + i)).collect::<Vec<_>>() },
            "display": { "maxPages": c.display_limits.0, "modelCount": c.display_limits.1, "config": c.display.json(),
                         "pages": c.pages.iter().map(|p| json!({ "noun": p[0], "target": p[1], "index": p[2], "flags": p[3] })).collect::<Vec<_>>(),
                         "status": { "init": db(0), "page": db(1), "flags": db(2), "model": db(3),
                                     "naks": if ds.len() >= 6 { u16_at(ds, 4) } else { 0 } } },
            "auxState": c.aux_state.to_vec(),
            "auxLevel": c.aux_level.to_vec(),
            "learn": c.learn.map(|(state, protocol, code)| json!({ "state": state, "protocol": protocol, "code": code })),
        })
    }

    /// One operation from the GUI. Returns {ok, status} (status: the
    /// device's result code; 0x16 = still pending) plus op-specific fields.
    pub fn cs_apply(&mut self, op: &Value) -> Result<Value> {
        let kind = op.get("op").and_then(Value::as_str).unwrap_or("");
        let idx = jn(op, "index").clamp(0, 255) as usize;
        let done = |st: u8| json!({ "ok": st == 0, "status": st });
        Ok(match kind {
            "refresh" => {
                self.cs_fetch_all()?;
                json!({ "ok": true })
            }
            "refreshStatus" => {
                self.cs_read_status();
                json!({ "ok": true })
            }
            "binding" if idx < CS_MAX_BINDINGS => {
                let b = Binding::from_json(op.get("binding").unwrap_or(&Value::Null));
                let st = self.cs_set(REQ_SET_BINDING, idx as u16, &b.encode(), idx as u8)?;
                self.cs_read_binding(idx);
                self.cs_read_status();
                if b.kind > 8 || self.cs.bindings[idx].kind > 8 {
                    self.cs_read_aux();
                }
                if b.kind == 8 {
                    self.cs_read_display();
                }
                done(st)
            }
            "name" if idx < CS_MAX_BINDINGS => {
                // One NUL clears: an empty OUT never reaches the firmware
                let text = op.get("name").and_then(Value::as_str).unwrap_or("");
                let data: Vec<u8> = if text.is_empty() { vec![0] } else { name_bytes(text)[..text.len().min(31)].to_vec() };
                let st = self.cs_set(REQ_SET_NAME, idx as u16, &data, idx as u8)?;
                self.cs_read_binding(idx);
                done(st)
            }
            "ir" if idx < CS_MAX_IR => {
                let c = IrCommand::from_json(op.get("command").unwrap_or(&Value::Null));
                let st = self.cs_set(REQ_SET_IR, idx as u16, &c.encode(), 0x80 | idx as u8)?;
                if let Some(c) = self.cs_get(REQ_GET_IR, idx as u16, 16).ok().and_then(|b| IrCommand::parse(&b)) {
                    self.cs.ir[idx] = c;
                }
                self.cs_read_status();
                done(st)
            }
            "group" if idx < CS_MAX_GROUPS => {
                let g = op.get("group").unwrap_or(&Value::Null);
                let g = Group { target_kind: jn(g, "targetKind") as u8, member_mask: jn(g, "memberMask") as u32,
                                name: g.get("name").and_then(Value::as_str).unwrap_or("").to_string() };
                let st = self.cs_set(REQ_SET_GROUP, idx as u16, &g.encode(), 0x40 | idx as u8)?;
                if let Some(g) = self.cs_get(REQ_GET_GROUP, idx as u16, 40).ok().and_then(|b| Group::parse(&b)) {
                    if idx < self.cs.groups.len() { self.cs.groups[idx] = g; }
                }
                // Bindings using the group may have changed state
                for slot in 0..self.cs.max_bindings as usize {
                    self.cs_read_binding(slot);
                }
                self.cs_read_status();
                done(st)
            }
            "macro" if idx < CS_MAX_MACROS => {
                // Steps first, then the header with the step count
                let m = op.get("macro").unwrap_or(&Value::Null);
                let steps: Vec<MacroStep> = m.get("steps").and_then(Value::as_array).into_iter().flatten()
                    .take(CS_MAX_STEPS).map(MacroStep::from_json).collect();
                // Every step (an all-zero step clears it), then the header;
                // the first failure is the result
                let mut worst = 0;
                for s in 0..self.cs.max_steps.max(1) as usize {
                    let step = steps.get(s).copied().unwrap_or_default();
                    let st = self.cs_set(REQ_SET_MACRO_STEP, ((s as u16) << 8) | idx as u16, &step.encode(), 0x60 | idx as u8)?;
                    if worst == 0 { worst = st; }
                }
                let mut header = [0u8; 36];
                header[..32].copy_from_slice(&name_bytes(m.get("name").and_then(Value::as_str).unwrap_or("")));
                header[32] = steps.len() as u8;
                let st = self.cs_set(REQ_SET_MACRO, idx as u16, &header, 0x60 | idx as u8)?;
                if worst == 0 { worst = st; }
                let st = worst;
                if let Some(mc) = self.cs_get(REQ_GET_MACRO, idx as u16, 132).ok().and_then(|b| Macro::parse(&b)) {
                    if idx < self.cs.macros.len() { self.cs.macros[idx] = mc; }
                }
                self.cs_read_status();
                done(st)
            }
            "displayConfig" => {
                let d = DisplayConfig::from_json(op.get("config").unwrap_or(&Value::Null));
                let st = self.cs_set(REQ_SET_DISPLAY_CFG, 0, &d.encode(), 0x50)?;
                self.cs_read_display();
                done(st)
            }
            "displayPage" if idx < CS_MAX_PAGES => {
                let p = op.get("page").unwrap_or(&Value::Null);
                let data = [jn(p, "noun") as u8, jn(p, "target") as u8, jn(p, "index") as u8, jn(p, "flags") as u8];
                let st = self.cs_set(REQ_SET_DISPLAY_PAGE, idx as u16, &data, 0x50 | idx as u8)?;
                self.cs_read_display();
                done(st)
            }
            "displayStatus" => {
                if let Ok(b) = self.cs_get(REQ_GET_DISPLAY_STATUS, 0, 8) {
                    self.cs.display_status = b;
                }
                json!({ "ok": true })
            }
            "save" | "revert" => {
                let req = if kind == "save" { REQ_SAVE } else { REQ_REVERT };
                // A stall means busy: the reason is in the status
                let st = match self.cs_get(req, 0, 1) {
                    Ok(_) => self.cs_wait(TAG_SAVE),
                    Err(UsbError::Rusb(rusb::Error::Pipe)) => {
                        self.cs_read_status();
                        self.cs.status.first().copied().unwrap_or(ST_PENDING)
                    }
                    Err(e) => return Err(e),
                };
                // Saving folds live aux values into their power-on fields;
                // reverting reloads everything
                self.cs_fetch_all()?;
                if st == 0 {
                    self.cs.mark_clean();
                }
                done(st)
            }
            "learnArm" => {
                self.cs.learn = None;
                match self.cs_get(REQ_IR_LEARN, 1, 1) {
                    Ok(b) if b.first() == Some(&1) => json!({ "ok": true }),
                    Err(UsbError::Rusb(rusb::Error::Pipe)) | Ok(_) => json!({ "ok": false, "status": 0x1E }),
                    Err(e) => return Err(e),
                }
            }
            "learnCancel" => {
                let _ = self.cs_get(REQ_IR_LEARN, 0, 1);
                json!({ "ok": true })
            }
            "learnRead" => {
                let b = self.cs_get(REQ_IR_LEARN, 2, 8)?;
                if b.len() < 8 {
                    return Ok(json!({ "ok": false }));
                }
                json!({ "ok": true, "state": b[0], "protocol": b[1], "code": u32_at(&b, 4) })
            }
            "macroFire" => {
                // A refusal stalls and leaves the reason in the status
                let ok = self.cs_get(REQ_MACRO_FIRE, idx as u16, 1).is_ok();
                self.cs_read_status();
                let st = if ok { 0 } else { self.cs.status.first().copied().unwrap_or(0x1B) };
                json!({ "ok": ok, "status": st })
            }
            "macroCancel" => {
                let ok = self.cs_get(REQ_MACRO_FIRE, 0xFFFF, 1).is_ok();
                self.cs_read_status();
                json!({ "ok": ok })
            }
            "auxState" if idx < 16 => {
                let on = (jn(op, "on") != 0) as u8;
                self.send(REQ_SET_AUX_STATE, idx as u16, WINDEX_OUTPUT, &[on])?;
                self.cs.aux_state[idx] = on;
                json!({ "ok": true })
            }
            "auxLevel" if idx < 16 => {
                let q8 = (op.get("percent").and_then(Value::as_f64).unwrap_or(0.0).clamp(0.0, 100.0) * 256.0).round() as u16;
                self.send(REQ_SET_AUX_LEVEL, idx as u16, WINDEX_OUTPUT, &q8.to_le_bytes())?;
                self.cs.aux_level[idx] = q8.min(25600);
                json!({ "ok": true })
            }
            "auxRead" => {
                self.cs_read_aux();
                json!({ "ok": true })
            }
            _ => json!({ "ok": false, "error": format!("unknown operation {kind}") }),
        })
    }

    /// GPIOs held by live bindings, as (pin, slot): a binding reserves its
    /// pins only while its active bit is set.
    pub fn cs_pin_uses(&self) -> Vec<(u8, u8)> {
        let s = &self.cs.status;
        let active = if s.len() >= 6 { u16_at(s, 4) } else { 0 };
        let mut out = Vec::new();
        for (slot, b) in self.cs.bindings[..self.cs.max_bindings as usize].iter().enumerate() {
            if b.kind == 0 || active & (1 << slot) == 0 {
                continue;
            }
            out.push((b.gpio[0], slot as u8));
            if b.gpio[1] != 0xFF {
                out.push((b.gpio[1], slot as u8));
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binding_round_trip() {
        let b = Binding { kind: 4, noun: 0, action: 1, flags: 0x0A, gpio: [3, 4], event: 0, target: 0, index: 0,
                          base_bright: 0, value: -256, step: 128, range_min: -15360, range_max: 0,
                          on_delay: 50, off_delay: 0, extras: 0 };
        let e = b.encode();
        assert_eq!(&e[..6], &[4, 0, 1, 0x0A, 3, 4]);
        assert_eq!(&e[10..12], &(-256i16).to_le_bytes());
        assert_eq!(Binding::parse(&e), Some(b));
        assert_eq!(Binding::from_json(&b.json()), b);
    }

    #[test]
    fn ir_group_macro_layouts() {
        let c = IrCommand { noun: 0, action: 2, flags: 0x10, target: 0, index: 0, protocol: 1, value: 0, step: 256, code: 0x20DF10EF };
        let e = c.encode();
        assert_eq!(&e[12..16], &0x20DF10EFu32.to_le_bytes());
        assert_eq!(IrCommand::parse(&e), Some(c));
        let g = Group { target_kind: 2, member_mask: 0b11, name: "Fronts".into() };
        assert_eq!(Group::parse(&g.encode()), Some(g));
        let mut m = [0u8; 132];
        m[..4].copy_from_slice(b"Film");
        m[32] = 2;
        m[36] = 7;
        m[36 + 10..36 + 12].copy_from_slice(&150u16.to_le_bytes());
        m[48] = 0;
        let mac = Macro::parse(&m).unwrap();
        assert_eq!((mac.name.as_str(), mac.steps.len(), mac.steps[0].noun, mac.steps[0].pre_delay), ("Film", 2, 7, 150));
        let s = MacroStep { noun: 6, action: 5, flags: 0, target: 0, index: 0, value: 2, step: 0, pre_delay: 30 };
        assert_eq!(MacroStep::parse(&s.encode()), s);
    }

    #[test]
    fn display_config_round_trip() {
        let d = DisplayConfig { mode: 1, home_page: 2, dwell: 50, overlay_hold: 20, brightness: 200, flags: 0x05, edit_timeout: 100 };
        assert_eq!(DisplayConfig::parse(&d.encode()), d);
        assert_eq!(DisplayConfig::from_json(&d.json()), d);
    }
}
