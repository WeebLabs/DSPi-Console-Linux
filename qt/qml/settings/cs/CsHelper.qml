import QtQuick 2.15

// Control Surfaces model helpers shared by the Control pages: the device's
// capability tables (`controlSurfaces.model`), the macOS Console's names and
// phrases, the wire encodings, and the rules for new and edited records.
// Records are plain objects with the core's field names (see core/src/cs.rs).
QtObject {
    id: cs

    readonly property var m: controlSurfaces.model
    // Changes only on connect / disconnect (bridge.connected notifies on
    // every status poll)
    readonly property bool connected: bridge.connected

    // ── Enums (firmware control_surfaces.h) ──
    readonly property int typeNone: 0
    readonly property int typeButton: 1
    readonly property int typeSwitch: 2
    readonly property int typePot: 3
    readonly property int typeEncoder: 4
    readonly property int typeLed: 5
    readonly property int typeLedPwm: 6
    readonly property int typeIr: 7
    readonly property int typeDisplay: 8
    readonly property int typeAuxOut: 9
    readonly property int typeAuxPwm: 10

    readonly property int actAdjust: 0
    readonly property int actStep: 1
    readonly property int actInc: 2
    readonly property int actDec: 3
    readonly property int actToggle: 4
    readonly property int actSet: 5
    readonly property int actFollow: 6
    readonly property int actTrigger: 7
    readonly property int actIndEquals: 8
    readonly property int actMomentary: 9
    readonly property int actIndAbove: 10
    readonly property int actIndLevel: 11

    readonly property int flagInvert: 0x01
    readonly property int flagReverse: 0x02
    readonly property int flagWrap: 0x04
    readonly property int flagAccel: 0x08
    readonly property int flagRepeat: 0x10
    readonly property int flagGroup: 0x20
    readonly property int flagLinkAbs: 0x40
    readonly property int flagGroupAll: 0x80

    readonly property int kindContinuous: 0
    readonly property int kindBool: 1
    readonly property int kindEnum: 2

    readonly property int unitNone: 0
    readonly property int unitDb: 1
    readonly property int unitHz: 2
    readonly property int unitQ: 3
    readonly property int unitPercent: 4
    readonly property int unitMs: 5
    readonly property int unitMsLog: 6

    readonly property int targetNone: 0
    readonly property int targetInput: 1
    readonly property int targetOutput: 2
    readonly property int targetDsp: 3
    readonly property int targetBand: 4
    readonly property int targetAux: 5

    readonly property int eventPress: 0
    readonly property int eventLong: 1
    readonly property int eventDouble: 2

    readonly property int auxBootOn: 0x01
    readonly property int auxBootSaved: 0x02
    readonly property int auxLinear: 0x04

    readonly property int dmodeFixed: 0
    readonly property int dmodeCycleSelected: 1
    readonly property int dmodeCycleAll: 2
    readonly property int dcfgOverlayAny: 0x01
    readonly property int dcfgEditGated: 0x02
    readonly property int dpageActive: 0x01
    readonly property int dpageGroup: 0x02
    readonly property int dpageLarge: 0x04
    readonly property int dpageBar: 0x08

    // Nouns used by name in the rules below
    readonly property int nounUserVolume: 0
    readonly property int nounMasterVolume: 1
    readonly property int nounUserMute: 2
    readonly property int nounPreset: 6
    readonly property int nounInputSource: 7
    readonly property int nounClip: 8
    readonly property int nounFilterFreq: 20
    readonly property int nounFilterBypass: 24
    readonly property int nounDacMuteTest: 26
    readonly property int nounClipCh: 27
    readonly property int nounPresetReload: 48
    readonly property int nounMacro: 52
    readonly property int nounDisplayPage: 54
    readonly property int nounDisplayEdit: 55
    readonly property int nounPageValue: 56
    readonly property int nounAux: 68
    readonly property int nounAuxLevel: 69

    readonly property var adcPins: [26, 27, 28]
    readonly property var macroStepActions: [actSet, actToggle, actInc, actDec, actTrigger]
    readonly property int ledBrightMax: 100
    readonly property int delayMaxSeconds: 6553       // the 0.1 s field, in whole seconds
    readonly property int displayMinDwell: 10         // 0.1 s units, cycle modes

    // ── Device tables ──
    readonly property bool supported: m.supported === true
    readonly property int slotCount: supported ? Math.min(16, m.maxBindings) : 0
    readonly property int irCount: supported ? Math.min(16, m.maxIr) : 0
    readonly property int groupCount: supported ? Math.min(8, m.maxGroups) : 0
    readonly property int macroCount: supported ? Math.min(8, m.maxMacros) : 0
    readonly property int stepCount: supported ? Math.min(8, m.maxSteps) : 0
    readonly property int pageCount: supported && m.display ? Math.min(16, m.display.maxPages) : 0
    readonly property int modelCount: supported && m.display ? m.display.modelCount : 0
    readonly property var types: supported ? m.types : []
    readonly property var nouns: supported ? m.nouns : []
    readonly property var bindings: supported ? m.bindings : []
    readonly property var names: supported ? m.names : []
    readonly property var irCommands: supported ? m.ir : []
    readonly property var groups: supported ? m.groups : []
    readonly property var macros: supported ? m.macros : []
    readonly property var status: supported ? m.status : ({})
    readonly property var ext: supported ? m.ext : ({})
    readonly property var display: supported ? m.display : ({})
    readonly property bool auxSupported: types.length > typeAuxPwm
    readonly property bool displaySupported: types.length > typeDisplay

    function typeDesc(t) { return t >= 0 && t < types.length ? types[t] : null }
    function nounDesc(n) { return n >= 0 && n < nouns.length ? nouns[n] : null }
    function isTargeted(nd) { return !!nd && nd.targetKind !== targetNone && nd.targetCount > 0 }
    function hasBand(nd) { return !!nd && nd.targetKind === targetBand }
    function isSlotActive(slot) { return !!status.activeMask && ((status.activeMask >> slot) & 1) === 1 }
    function slotHealth(slot) { return status.slotStatus ? status.slotStatus[slot] : 0 }
    function isConfigured(b) { return !!b && b.type !== typeNone }
    function irConfigured(c) { return !!c && c.protocol !== 0 }
    function groupConfigured(g) { return !!g && g.targetKind !== targetNone && g.memberMask !== 0 }
    function isAuxType(t) { return t === typeAuxOut || t === typeAuxPwm }
    function isIndicatorType(t) { return t === typeLed || t === typeLedPwm }
    function actBit(a) { return 1 << a }

    // ── Records ──
    readonly property var bindingKeys: ["type", "noun", "action", "flags", "gpio0", "gpio1", "event", "target",
        "index", "baseBright", "value", "step", "rangeMin", "rangeMax", "onDelay", "offDelay", "extras"]
    readonly property var irKeys: ["noun", "action", "flags", "target", "index", "protocol", "value", "step", "code"]
    readonly property var stepKeys: ["noun", "action", "flags", "target", "index", "value", "step", "preDelay"]

    function blank(keys) {
        var o = {}
        for (var i = 0; i < keys.length; i++) o[keys[i]] = 0
        return o
    }
    function emptyBinding() { var b = blank(bindingKeys); b.gpio1 = 0xFF; return b }
    function emptyIr() { return blank(irKeys) }
    function emptyStep() { return blank(stepKeys) }
    function copy(o) { return JSON.parse(JSON.stringify(o)) }
    function same(a, b, keys) {
        if (!a || !b) return a === b
        for (var i = 0; i < keys.length; i++) if (a[keys[i]] !== b[keys[i]]) return false
        return true
    }
    function sameBinding(a, b) { return same(a, b, bindingKeys) }
    function sameIr(a, b) { return same(a, b, irKeys) }
    function sameGroup(a, b) {
        return !!a && !!b && a.targetKind === b.targetKind && a.memberMask === b.memberMask && a.name === b.name
    }
    function sameMacro(a, b) {
        if (!a || !b || a.name !== b.name || a.steps.length !== b.steps.length) return false
        for (var i = 0; i < a.steps.length; i++) if (!same(a.steps[i], b.steps[i], stepKeys)) return false
        return true
    }
    function stepConfigured(s) { return !same(s, emptyStep(), stepKeys) }
    function macroConfigured(mc) { return !!mc && (mc.steps.length > 0 || mc.name !== "") }

    // ── Names ──
    function typeName(t) {
        switch (t) {
        case typeNone: return "None"
        case typeButton: return "Push Button"
        case typeSwitch: return "Toggle Switch"
        case typePot: return "Potentiometer / Fader"
        case typeEncoder: return "Rotary Encoder"
        case typeLed: return "Indicator LED"
        case typeLedPwm: return "Dimmable LED"
        case typeIr: return "IR Remote"
        case typeDisplay: return "Display"
        case typeAuxOut: return "On/Off Output"
        case typeAuxPwm: return "Dimmable Output"
        default: return "Type " + t
        }
    }
    function typeIcon(t) {
        switch (t) {
        case typeButton: return "cs-button"
        case typeSwitch: return "cs-switch"
        case typePot: return "cs-pot"
        case typeEncoder: return "cs-encoder"
        case typeLed: return "cs-led"
        case typeLedPwm: return "sun"
        case typeIr: return "cs-ir"
        case typeDisplay: return "cs-display"
        case typeAuxOut: return "power"
        case typeAuxPwm: return "sun"
        default: return "cs-pot"
        }
    }
    // Cool hues for inputs, warm for the LEDs (they are lights)
    function typeTint(t) {
        switch (t) {
        case typeButton: return Qt.rgba(0.20, 0.62, 0.74, 1)
        case typeSwitch: return Qt.rgba(0.15, 0.49, 0.62, 1)
        case typePot: return Qt.rgba(0.21, 0.49, 0.82, 1)
        case typeEncoder: return Qt.rgba(0.34, 0.37, 0.80, 1)
        case typeLed: return Qt.rgba(0.93, 0.63, 0.18, 1)
        case typeLedPwm: return Qt.rgba(0.90, 0.45, 0.20, 1)
        case typeIr: return Qt.rgba(0.55, 0.35, 0.72, 1)
        case typeDisplay: return Qt.rgba(0.016, 0.522, 0.435, 1)
        case typeAuxOut: return Qt.rgba(0.478, 0.353, 0.675, 1)
        case typeAuxPwm: return Qt.rgba(0.62, 0.40, 0.62, 1)
        default: return Qt.rgba(0.46, 0.53, 0.62, 1)
        }
    }

    readonly property var nounNames: ({
        0: "Volume", 1: "Master Volume", 2: "Mute", 3: "Loudness", 4: "Crossfeed", 5: "Volume Leveller",
        6: "Preset", 7: "Input Source", 8: "Clipping", 9: "EQ Bypass", 10: "LG Sound Sync",
        11: "Crossfeed Preset", 12: "Crossfeed ITD", 13: "Leveller Amount", 14: "Leveller Speed",
        15: "Leveller Lookahead", 16: "Input Preamp", 17: "Output Gain", 18: "Output Mute", 19: "Output Enable",
        20: "Filter Frequency", 21: "Filter Gain", 22: "Filter Q", 23: "Filter Type", 24: "Filter Bypass",
        25: "Signal Generator", 26: "DAC Mute Test", 27: "Channel Clipping", 28: "Channel Level",
        29: "S/PDIF Lock", 30: "Sample Rate", 31: "USB Streaming", 32: "ADAT Active", 33: "LG Source Present",
        34: "LG Muted", 35: "Upmixer", 36: "Upmixer Centre Mode", 37: "Upmixer Surround Mode",
        38: "Upmixer Strength", 39: "Upmixer Width", 40: "Upmixer Presence", 41: "Psychoacoustic Bass",
        42: "Psych Bass Cutoff Frequency", 43: "Psych Bass Harmonics", 44: "Psych Bass Drive",
        45: "Psych Bass Character", 46: "Psych Bass Original Level", 47: "Output Delay", 48: "Preset Reload",
        49: "Loudness Reference SPL", 50: "Loudness Intensity", 51: "Input Signal Level", 52: "Macro",
        53: "CPU Load", 54: "Show Page", 55: "Allow Editing", 56: "Browse/Adjust",
        57: "Subharmonic Synthesizer", 58: "Subharm 24-36 Hz Level", 59: "Subharm 36-56 Hz Level",
        60: "Subharm LF Boost", 61: "Subharm 56-80 Hz Level", 62: "Subharm Selectivity",
        63: "Subharm Selectivity Depth", 64: "Subharm Selectivity Hold", 65: "Subharm Sub Ceiling",
        66: "Subharm Pair Link", 67: "Subharm Solo", 68: "Aux Switch", 69: "Aux Level",
        70: "Tube Modeller", 71: "Tube Drive", 72: "Tube Type", 73: "Tube Mix",
        74: "Output Limiter", 75: "Limiter Threshold", 76: "Limiter Release", 77: "Limiter Link Group",
        78: "Limiter Gain Reduction"
    })
    // A few read differently on a control than on an LED: a button clears
    // clipping, an LED shows it
    function nounName(n, type) {
        if (!isIndicatorType(type)) {
            if (n === nounClip) return "Clear Clipping"
            if (n === nounDacMuteTest) return "Test DAC Mute"
            if (n === nounPresetReload) return "Reload Preset"
        }
        if (n === nounMacro) return isIndicatorType(type) ? "Running Macro" : "Macro"
        return nounNames[n] !== undefined ? nounNames[n] : "Parameter " + n
    }

    // The function menu's families (macOS order; the output limiter as on
    // Windows). `strip` drops a prefix the family title already says; the
    // family's on/off noun reads Enable/Disable inside it.
    readonly property var nounCategories: [
        { name: "Volume & Mute", nouns: [0, 1, 2] },
        { name: "Loudness", nouns: [3, 49, 50], strip: ["Loudness"], enable: 3 },
        { name: "Crossfeed", nouns: [4, 11, 12], strip: ["Crossfeed"], enable: 4 },
        { name: "Volume Leveller", nouns: [5, 13, 14, 15], strip: ["Leveller"], enable: 5 },
        { name: "Psychoacoustic Bass", nouns: [41, 42, 43, 44, 45, 46], strip: ["Psych Bass"], enable: 41 },
        { name: "Subharmonic Synth", nouns: [57, 58, 59, 61, 60, 62, 63, 64, 65, 66, 67], strip: ["Subharm"], enable: 57 },
        { name: "Tube Modeller", nouns: [70, 72, 71, 73], strip: ["Tube"], enable: 70 },
        { name: "Output Limiter", nouns: [74, 75, 76, 77, 78], strip: ["Limiter"], enable: 74 },
        { name: "Upmixer", nouns: [35, 36, 37, 38, 39, 40], strip: ["Upmixer"], enable: 35 },
        { name: "Input & Presets", nouns: [6, 48, 7, 10] },
        { name: "Channels", nouns: [16, 17, 18, 19, 47] },
        { name: "Filters", nouns: [9, 20, 21, 22, 23, 24], strip: ["Filter"] },
        { name: "Tools", nouns: [52, 25, 26, 8] },
        { name: "Display", nouns: [54, 56, 55], strip: ["Display"] },
        { name: "Auxiliary Outputs", nouns: [68, 69], strip: ["Aux"], enable: 68 },
        { name: "Status", nouns: [53, 27, 28, 51, 29, 30, 31, 32, 33, 34] }
    ]

    function nounMenuLabel(n, type, cat) {
        var full = nounName(n, type)
        if (!cat) return full
        if (cat.enable === n) return isIndicatorType(type) ? "Enabled" : "Enable/Disable"
        var strip = cat.strip || []
        for (var i = 0; i < strip.length; i++)
            if (full.indexOf(strip[i] + " ") === 0) return full.substring(strip[i].length + 1)
        return full
    }

    function actionName(a, noun) {
        var nd = nounDesc(noun)
        var isEnum = !!nd && nd.kind === kindEnum
        if (noun === nounPageValue) {
            if (a === actInc) return "Up"
            if (a === actDec) return "Down"
        }
        switch (a) {
        case actAdjust: return "Adjust"
        case actStep: return "Step"
        case actInc: return isEnum ? "Next" : "Increase"
        case actDec: return isEnum ? "Previous" : "Decrease"
        case actToggle: return "Toggle"
        case actSet: return "Set value"
        case actFollow: return "Follow position"
        case actTrigger: return "Trigger"
        case actIndEquals: return "Indicate"
        case actMomentary: return "Hold"
        case actIndAbove: return "Indicate above"
        case actIndLevel: return "Show level"
        default: return "Action " + a
        }
    }

    function boolLabel(noun, on) {
        switch (noun) {
        case 8: case 27: return on ? "Clipping" : "Not clipping"
        case 2: case 18: case 34: return on ? "Muted" : "Unmuted"
        case 29: return on ? "Locked" : "Unlocked"
        case 31: case 32: case 25: return on ? "Active" : "Idle"
        case 33: return on ? "Present" : "Absent"
        default: return on ? "On" : "Off"
        }
    }

    readonly property var tubeNames: ["Custom", "12AX7 / ECC83", "5751", "12AT7 / ECC81", "12AY7",
        "12AU7 / ECC82", "6SN7", "6SL7", "6DJ8 / ECC88 / 6922", "EF86 / 6267", "6SJ7",
        "EL84 / 6BQ5", "EL34", "6L6 / 5881", "6V6", "KT88 / 6550", "300B / 2A3"]

    function inputSourceName(v) {
        var extra = false
        var list = bridge.inputSources
        for (var i = 0; i < list.length; i++) if (list[i].id >= 4) extra = true
        switch (v) {
        case 0: return "USB"
        case 1: return extra ? "S/PDIF 1" : "S/PDIF"
        case 2: return "I2S"
        case 3: return "ADAT"
        case 4: case 5: case 6: return "S/PDIF " + (v - 2)
        default: return "Source " + v
        }
    }

    function enumValueLabel(noun, v) {
        function pick(names, fallback) { return v >= 0 && v < names.length ? names[v] : fallback + " " + v }
        switch (noun) {
        case nounMacro: return macroName(v)
        case nounPreset: {
            var name = bridge.presetName(v)
            return name ? "Preset " + (v + 1) + " - " + name : "Preset " + (v + 1)
        }
        case nounInputSource: return inputSourceName(v)
        case 30: return pick(["44.1 kHz", "48 kHz", "96 kHz"], "Rate")
        case 14: return pick(["Slow", "Medium", "Fast"], "Speed")
        case 11: return pick(["Default", "Chu Moy", "Meier", "Custom"], "Preset")
        case 36: return pick(["Sinner", "Logician", "Off"], "Mode")
        case 37: return pick(["Off", "Sinner", "Logician"], "Mode")
        case 62: return pick(["All material", "Percussive", "Sustained"], "Mode")
        case 72: return pick(tubeNames, "Type")
        case 77: return v === 0 ? "Unlinked" : "Group " + v
        case 23: return pick(["Flat", "Peaking", "Low Shelf", "High Shelf", "High Cut", "Low Cut", "Notch",
                              "All Pass", "All Pass (1st)", "Low Shelf (1st)", "High Shelf (1st)"], "Type")
        case nounDisplayPage: return "Page " + (v + 1)
        default: return "" + v
        }
    }

    function groupName(g) {
        var grp = groups[g]
        return grp && grp.name !== "" ? grp.name : "Group " + (g + 1)
    }
    function macroName(i) {
        var mc = macros[i]
        return mc && mc.name !== "" ? mc.name : "Macro " + (i + 1)
    }
    function auxName(slot) {
        return names[slot] ? names[slot] : "Aux " + (slot + 1)
    }

    // ── Channels and targets ──
    function channelName(appId) {
        var n = appId >= 0 ? bridge.channelName(appId) : ""
        return n !== "" ? n : "Channel " + (appId + 1)
    }
    // DSP channels are numbered inputs first, then outputs
    function dspName(w) {
        var ins = bridge.numInputChannels
        return w < ins ? channelName(bridge.inputAppId(w)) : channelName(2 + (w - ins))
    }
    function targetName(nd, t) {
        switch (nd.targetKind) {
        case targetInput: return channelName(bridge.inputAppId(t))
        case targetOutput: return channelName(2 + t)
        case targetAux: return auxName(t)
        default: return dspName(t)
        }
    }
    function targetNoun(nd) { return nd.targetKind === targetAux ? "Auxiliary Output" : "Channel" }
    function targetNounPlural(nd) { return nd.targetKind === targetAux ? "Auxiliary Outputs" : "Channels" }
    function bandName(b) { return b >= 20 && b <= 23 ? "Crossover " + (b - 19) : "Band " + (b + 1) }

    // Channels a target picker offers; an aux noun offers the slots holding
    // an aux output on the device (a dimmable one for the level noun)
    function targetChoices(nd, noun) {
        var list = []
        if (nd.targetKind !== targetAux) {
            for (var t = 0; t < nd.targetCount; t++) list.push(t)
            return list
        }
        for (var s = 0; s < Math.min(nd.targetCount, slotCount); s++) {
            var ty = bindings[s].type
            if (noun === nounAuxLevel ? ty === typeAuxPwm : isAuxType(ty)) list.push(s)
        }
        return list
    }

    // Groups whose channel space matches what the noun targets
    function compatibleGroups(noun) {
        var nd = nounDesc(noun)
        if (!isTargeted(nd)) return []
        var wanted = nd.targetKind === targetBand ? targetDsp : nd.targetKind
        var list = []
        for (var g = 0; g < groupCount; g++)
            if (groupConfigured(groups[g]) && groups[g].targetKind === wanted) list.push(g)
        return list
    }
    function memberList(mask) {
        var list = []
        for (var i = 0; i < 32; i++) if ((mask >>> i) & 1) list.push(i)
        return list
    }
    function groupMenuLabel(g) {
        var grp = groups[g]
        if (!groupConfigured(grp)) return groupName(g) + " (empty)"
        return groupName(g) + " (" + memberList(grp.memberMask).length + " ch)"
    }

    // The merged channel / group picker: channel t is t, group g is 1000 + g
    function targetOptions(noun, rec, groupsAllowed) {
        var nd = nounDesc(noun)
        var opts = [{ header: targetNounPlural(nd) }]
        var ch = targetChoices(nd, noun)
        for (var i = 0; i < ch.length; i++) opts.push({ value: ch[i], text: targetName(nd, ch[i]) })
        var usable = groupsAllowed ? compatibleGroups(noun) : []
        var grouped = (rec.flags & flagGroup) !== 0
        if (usable.length > 0 || grouped) {
            opts.push({ header: "Groups" })
            for (var k = 0; k < usable.length; k++) opts.push({ value: 1000 + usable[k], text: groupMenuLabel(usable[k]) })
            // A group since emptied or re-kinded still shows, or the picker
            // would quietly retarget the record to a channel
            if (grouped && usable.indexOf(rec.target) < 0)
                opts.push({ value: 1000 + rec.target, text: groupMenuLabel(rec.target) })
        }
        return opts
    }
    function targetValue(rec) { return (rec.flags & flagGroup) ? 1000 + rec.target : rec.target }

    // PEQ bands 0-9 always; crossover bands 20-23 on outputs for frequency
    // and bypass
    function bandOptionsDsp(noun, dspCh) {
        var bands = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        if (dspCh >= bridge.numInputChannels && (noun === nounFilterFreq || noun === nounFilterBypass))
            bands = bands.concat([20, 21, 22, 23])
        return bands
    }
    // A group offers only the bands every member has
    function bandOptions(noun, target, grouped) {
        if (!grouped) return bandOptionsDsp(noun, target)
        var members = groups[target] ? memberList(groups[target].memberMask) : []
        if (members.length === 0) return bandOptionsDsp(noun, 0)
        var common = bandOptionsDsp(noun, members[0])
        for (var i = 1; i < members.length; i++) {
            var s = bandOptionsDsp(noun, members[i])
            common = common.filter(function (b) { return s.indexOf(b) >= 0 })
        }
        return common
    }

    // Retarget a record to a picker value (channel t or group 1000 + g)
    function withTarget(rec, value, groupFlags) {
        var r = copy(rec)
        if (value >= 1000) { r.flags |= flagGroup; r.target = value - 1000 }
        else { r.flags &= ~(groupFlags || flagGroup); r.target = value }
        var nd = nounDesc(r.noun)
        if (hasBand(nd)) {
            var opts = bandOptions(r.noun, r.target, (r.flags & flagGroup) !== 0)
            if (opts.indexOf(r.index) < 0) r.index = opts.length > 0 ? opts[0] : 0
        }
        return r
    }

    function groupChannelCount(kind) {
        for (var n = 0; n < nouns.length; n++) {
            var nd = nouns[n]
            if (nd.actions === 0 || nd.targetCount === 0) continue
            if (nd.targetKind === kind) return nd.targetCount
            if (kind === targetDsp && nd.targetKind === targetBand) return nd.targetCount
        }
        return 0
    }
    function groupChannelName(kind, ch) { return targetName({ targetKind: kind, targetCount: 255 }, ch) }

    // ── Units ──
    function unitIsFixed(u) { return u === unitDb || u === unitQ || u === unitPercent || u === unitMs }
    function unitIsLog(u) { return u === unitHz || u === unitQ || u === unitMsLog }
    function clamp16(v) { return Math.max(-32768, Math.min(32767, Math.round(v))) }
    function encodeValue(v, u) { return clamp16(unitIsFixed(u) ? v * 256 : v) }
    function decodeValue(q, u) { return unitIsFixed(u) ? q / 256 : q }
    function encodeStep(v, u) { return clamp16(u === unitNone ? v : v * 256) }
    function decodeStep(q, u) { return u === unitNone ? q : q / 256 }
    function defaultStep(u) {
        if (unitIsLog(u)) return 1 / 12
        return u === unitMs ? 0.1 : 1
    }
    function unitSymbol(u) {
        switch (u) {
        case unitDb: return "dB"
        case unitHz: return "Hz"
        case unitQ: return "Q"
        case unitPercent: return "%"
        case unitMs: case unitMsLog: return "ms"
        default: return ""
        }
    }
    function fmtUnit(v, u) {
        switch (u) {
        case unitHz: return v.toFixed(0) + " Hz"
        case unitQ: return "Q " + v.toFixed(2)
        case unitPercent: return v.toFixed(0) + " %"
        case unitDb: return v.toFixed(1) + " dB"
        case unitMs: return v.toFixed(2) + " ms"
        case unitMsLog: return v.toFixed(0) + " ms"
        default: return v.toFixed(0)
        }
    }
    function unitWheelStep(u) {
        switch (u) {
        case unitHz: case unitMsLog: return 10
        case unitQ: case unitMs: return 0.1
        case unitPercent: return 1
        default: return 0.5
        }
    }
    function unitDecimals(u) {
        switch (u) {
        case unitHz: case unitPercent: case unitMsLog: return 0
        case unitQ: case unitMs: return 2
        default: return 1
        }
    }
    function unitMinStep(u) { return u === unitMs ? 0.01 : 0.1 }
    function nounUnit(noun) { var nd = nounDesc(noun); return nd ? nd.unit : unitDb }
    function nounRange(noun) {
        var nd = nounDesc(noun), u = nd ? nd.unit : unitDb
        return { lo: decodeValue(nd ? nd.min : 0, u), hi: decodeValue(nd ? nd.max : 0, u) }
    }

    // Binding delays: 0.1 s units, entered in whole seconds
    function fmtDelay(raw) {
        var total = Math.floor(raw / 10), mins = Math.floor(total / 60), secs = total % 60
        if (mins === 0) return secs + " s"
        return secs === 0 ? mins + " min" : mins + " min " + secs + " s"
    }
    // Macro step waits: 10 ms units
    function fmtSeconds(s) {
        if (s < 60) return (s < 10 ? Number(s.toPrecision(2)) : Math.round(s)) + " s"
        var mins = s / 60
        return (mins === Math.round(mins) ? mins.toFixed(0) : mins.toFixed(1)) + " min"
    }

    // ── Rules ──
    readonly property var realTypes: {
        var list = []
        for (var t = 1; t < types.length; t++) list.push(t)
        return list
    }

    function validNouns(type) {
        var td = typeDesc(type), list = []
        if (!td) return list
        for (var n = 0; n < nouns.length; n++) if ((nouns[n].actions & td.actions) !== 0) list.push(n)
        return list
    }
    // The families for a component type: [{ cat, nouns }], unknown nouns under Other
    function nounGroups(type, nounList) {
        var valid = nounList || validNouns(type), used = {}, out = []
        for (var c = 0; c < nounCategories.length; c++) {
            var cat = nounCategories[c], ns = []
            for (var i = 0; i < cat.nouns.length; i++)
                if (valid.indexOf(cat.nouns[i]) >= 0) { ns.push(cat.nouns[i]); used[cat.nouns[i]] = true }
            if (ns.length > 0) out.push({ cat: cat, nouns: ns })
        }
        var others = valid.filter(function (n) { return !used[n] })
        if (others.length > 0) out.push({ cat: { name: "Other" }, nouns: others })
        return out
    }
    // Menu data for the function picker: CascadeMenu categories
    function nounMenu(type, nounList) {
        var groupsFor = nounGroups(type, nounList), out = []
        for (var g = 0; g < groupsFor.length; g++) {
            var opts = []
            for (var i = 0; i < groupsFor[g].nouns.length; i++) {
                var n = groupsFor[g].nouns[i]
                opts.push({ value: n, text: nounMenuLabel(n, type, groupsFor.length > 1 ? groupsFor[g].cat : null) })
            }
            out.push({ text: groupsFor[g].cat.name, options: opts })
        }
        return out
    }

    function validActions(type, noun) {
        var td = typeDesc(type), nd = nounDesc(noun), list = []
        if (!td || !nd) return list
        var eff = td.actions & nd.actions
        for (var a = 0; a < 16; a++) if (eff & (1 << a)) list.push(a)
        return list
    }
    function defaultAction(type, noun) {
        var avail = validActions(type, noun)
        if (avail.length === 0) return 0
        var pref = []
        switch (type) {
        case typePot: pref = [actAdjust]; break
        case typeEncoder: pref = [actStep]; break
        case typeSwitch: pref = [actFollow]; break
        case typeLed: pref = [actIndEquals, actIndAbove]; break
        case typeLedPwm: pref = [actIndLevel, actIndAbove, actIndEquals]; break
        case typeButton: case typeIr: pref = [actToggle, actTrigger, actInc, actSet, actDec, actMomentary]; break
        }
        for (var i = 0; i < pref.length; i++) if (avail.indexOf(pref[i]) >= 0) return pref[i]
        return avail[0]
    }

    // Delays are allowed on an LED following a condition, and on aux outputs
    function delaysAllowed(type, action) {
        return isAuxType(type) || (isIndicatorType(type) && (action === actIndEquals || action === actIndAbove))
    }

    // Reset the operands for the binding's action and kind; target and band stay
    function defaultOperands(binding) {
        var b = copy(binding)
        var nd = nounDesc(b.noun)
        var kind = nd ? nd.kind : kindBool
        var unit = nd ? nd.unit : unitDb
        b.value = 0; b.step = 0; b.rangeMin = 0; b.rangeMax = 0
        if (!delaysAllowed(b.type, b.action)) { b.onDelay = 0; b.offDelay = 0 }
        switch (b.action) {
        case actStep: case actInc: case actDec:
            if (kind === kindEnum) b.step = 1
            break
        case actSet: case actMomentary:
            if (kind === kindContinuous) b.value = nd.max
            else if (kind === kindBool) b.value = 1
            break
        case actIndEquals:
            if (kind === kindBool) b.value = 1
            break
        case actIndAbove:
            // A quarter of the way up the range (-45 dB on a -60..0 meter)
            if (kind === kindContinuous) {
                var lo = decodeValue(nd.min, unit), hi = decodeValue(nd.max, unit)
                b.value = encodeValue(lo + 0.25 * (hi - lo), unit)
            }
            break
        }
        if (b.noun === nounPageValue) { b.value = 0; b.step = 0; b.rangeMin = 0; b.rangeMax = 0 }
        return sanitizeGroupFlags(b)
    }

    // The firmware rejects a group flag left where it doesn't belong
    function sanitizeGroupFlags(binding) {
        var b = binding
        if (!(b.flags & flagGroup)) { b.flags &= ~(flagLinkAbs | flagGroupAll); return b }
        var usable = compatibleGroups(b.noun)
        if (usable.length === 0 || b.action === actTrigger) {
            b.flags &= ~(flagGroup | flagLinkAbs | flagGroupAll)
            b.target = 0
            return b
        }
        if (usable.indexOf(b.target) < 0) b.target = usable[0]
        var nd = nounDesc(b.noun), kind = nd ? nd.kind : kindBool
        if (!(b.action === actAdjust && kind === kindContinuous)) b.flags &= ~flagLinkAbs
        if (!(b.action === actIndEquals || b.action === actIndAbove)) b.flags &= ~flagGroupAll
        return b
    }

    // A remote button's operands for its action and kind; the learned code,
    // target and band stay
    function defaultIrOperands(c) {
        var d = nounDesc(c.noun)
        var k = c.noun === nounPageValue ? 255 : (d ? d.kind : kindBool)
        c.value = 0; c.step = 0; c.flags &= flagGroup
        if ((c.action === actInc || c.action === actDec) && k === kindEnum) c.step = 1
        if (c.action === actSet || c.action === actMomentary) {
            if (k === kindContinuous) c.value = d.max
            else if (k === kindBool) c.value = 1
        }
        return c
    }
    // A macro step's operands; only WRAP and GROUP are legal on a step
    function defaultStepOperands(st) {
        var d = nounDesc(st.noun)
        var k = d ? d.kind : kindBool
        st.value = 0; st.step = 0
        if (!(k === kindEnum && (st.action === actInc || st.action === actDec))) st.flags &= ~flagWrap
        if (st.action === actSet) {
            if (k === kindContinuous) st.value = d.max
            else if (k === kindBool) st.value = 1
        }
        if (st.action === actTrigger || !isTargeted(d)) { st.flags &= ~flagGroup; st.target = 0 }
        return st
    }
    readonly property var stepNouns: {
        var mask = 0, list = []
        for (var i = 0; i < macroStepActions.length; i++) mask |= 1 << macroStepActions[i]
        for (var n = 0; n < nouns.length; n++)
            if (n !== nounMacro && n !== nounPageValue && (nouns[n].actions & mask) !== 0) list.push(n)
        return list
    }
    function stepActions(noun) {
        var d = nounDesc(noun)
        return d ? macroStepActions.filter(function (a) { return (d.actions & (1 << a)) !== 0 }) : []
    }
    function newIrCommand() {
        var c = emptyIr()
        var vn = validNouns(typeIr)
        c.noun = vn.length > 0 ? vn[0] : nounUserVolume
        c.action = defaultAction(typeIr, c.noun)
        return defaultIrOperands(c)
    }
    function newStep() {
        var st = emptyStep()
        st.noun = stepNouns.length > 0 ? stepNouns[0] : nounUserMute
        var acts = stepActions(st.noun)
        st.action = acts.length > 0 ? acts[0] : actSet
        return defaultStepOperands(st)
    }

    function withNoun(binding, noun) {
        var b = copy(binding)
        b.noun = noun; b.target = 0; b.index = 0
        if (validActions(b.type, noun).indexOf(b.action) < 0) b.action = defaultAction(b.type, noun)
        return defaultOperands(b)
    }
    function withAction(binding, action) {
        var b = copy(binding)
        b.action = action
        return defaultOperands(b)
    }

    // A fresh binding of `type` in `slot`, with free pins chosen
    function makeBinding(type, slot) {
        var b = emptyBinding()
        if (type === typeNone) return b
        b.type = type
        var valid = bridge.validPins
        if (type === typeIr || isAuxType(type)) {
            var free = freePins(slot, false)
            b.gpio0 = free.length > 0 ? free[0] : (valid.length > 0 ? valid[0] : 0)
            return b
        }
        if (type === typeDisplay) {
            var pairs = i2cSdaCandidates(slot, null)
            var sda = pairs.length > 0 ? pairs[0] : 0
            if (pairs.length === 0) for (var k = 0; k < valid.length; k++) if (valid[k] % 2 === 0) { sda = valid[k]; break }
            b.gpio0 = sda; b.gpio1 = sda + 1
            b.index = 6          // OLED 128x64 (SSD1306)
            b.value = 0          // the model's usual address
            return b
        }
        var vn = validNouns(type)
        b.noun = vn.length > 0 ? vn[0] : nounMasterVolume
        b.action = defaultAction(type, b.noun)
        var td = typeDesc(type)
        var adc = !!td && td.pinClass === 1, twoPin = !!td && td.pins >= 2
        var pins = freePins(slot, adc)
        b.gpio0 = pins.length > 0 ? pins[0] : (adc ? 26 : (valid.length > 0 ? valid[0] : 0))
        b.gpio1 = twoPin ? (pins.length > 1 ? pins[1] : (b.gpio0 === 0 ? 1 : 0)) : 0xFF
        return defaultOperands(b)
    }

    // ── Pins ──
    function slotOwner(slot) { return "Control Surface " + (slot + 1) }
    // Who holds a pin, not counting `slot` itself ("" = free)
    function pinOwner(pin, slot) {
        var owners = bridge.pinOwners()
        for (var i = 0; i < owners.length; i++)
            if (owners[i].pin === pin && owners[i].owner !== slotOwner(slot)) return owners[i].owner
        return ""
    }
    function freePins(slot, adcOnly) {
        var base = adcOnly ? adcPins : bridge.validPins
        return base.filter(function (p) { return pinOwner(p, slot) === "" })
    }
    // Every live binding on `pin` (but `slot`) is a button: a button may share it
    function pinButtonShareable(pin, slot) {
        var saw = false
        for (var s = 0; s < slotCount; s++) {
            if (s === slot || !isSlotActive(s)) continue
            var b = bindings[s]
            if (b.gpio0 !== pin && !(b.gpio1 !== 0xFF && b.gpio1 === pin)) continue
            if (b.type !== typeButton) return false
            saw = true
        }
        return saw
    }
    function pinCandidates(slot, rec, isSecond) {
        var td = typeDesc(rec.type)
        var adc = !!td && td.pinClass === 1, twoPin = !!td && td.pins >= 2
        var base = adc ? adcPins : bridge.validPins
        var sibling = twoPin ? (isSecond ? rec.gpio0 : rec.gpio1) : -1
        var current = isSecond ? rec.gpio1 : rec.gpio0
        var list = base.filter(function (p) {
            if (p === sibling) return false
            if (p === current) return true
            if (pinOwner(p, slot) === "") return true
            return rec.type === typeButton && pinButtonShareable(p, slot)
        })
        if (list.indexOf(current) < 0) list.unshift(current)
        return list
    }
    // SDA is an even GPIO whose odd neighbour is SCL; the I2C control
    // interface's bus is off limits while it runs
    function i2cSdaCandidates(slot, rec) {
        var valid = bridge.validPins, hw = bridge.hardware
        var blocked = hw.i2cLive ? ((hw.i2cSda >> 1) & 1) : -1
        return valid.filter(function (sda) {
            if (blocked >= 0 && ((sda >> 1) & 1) === blocked) return false
            if (sda % 2 !== 0 || valid.indexOf(sda + 1) < 0) return false
            if (rec && rec.type === typeDisplay && sda === rec.gpio0) return true
            return pinOwner(sda, slot) === "" && pinOwner(sda + 1, slot) === ""
        })
    }

    // ── Wording ──
    function pinDetail(type) {
        switch (type) {
        case typePot: return "ADC pin (GPIO 26, 27, or 28), wiper to the pin."
        case typeLed: case typeLedPwm: return "Output pin driving the LED."
        case typeIr: return "GPIO wired to the receiver module's OUT (VCC to 3V3, GND to GND)."
        case typeAuxOut: return "Output pin driving the relay or MOSFET input."
        case typeAuxPwm: return "PWM output pin driving the dimmer or fan input."
        default: return "Wired between this GPIO and GND."
        }
    }
    function invertTitle(type) {
        switch (type) {
        case typeLed: case typeLedPwm: return "Active-Low LED"
        case typePot: case typeEncoder: return "Pull-Down Wiring"
        case typeIr: return "Idle-Low Receiver"
        case typeAuxOut: case typeAuxPwm: return "Active-Low Output"
        default: return "Active-High Wiring"
        }
    }
    function invertDetail(type) {
        switch (type) {
        case typeLed: return "Drive the pin low to light the LED (LED wired to 3V3 through a resistor)."
        case typeLedPwm: return "Invert the PWM duty for an LED wired to 3V3 through a resistor."
        case typePot: case typeEncoder: return "Wire the common terminal to 3V3 instead of GND (internal pull-down)."
        case typeIr: return "The receiver idles low and pulls high on a mark; default is the usual idle-high, active-low module."
        case typeAuxOut: return "Drive the pin low to switch the load on, which is what most relay and opto-isolator boards expect."
        case typeAuxPwm: return "Invert the PWM duty for a driver that switches on when the pin goes low."
        default: return "Component wired to 3V3 with the internal pull-down; default is to GND with pull-up."
        }
    }

    function pressWord(b) {
        if (b.type !== typeButton) return "Press"
        return b.event === eventLong ? "Long-press" : b.event === eventDouble ? "Double-press" : "Press"
    }
    function targetSuffix(rec) {
        var nd = nounDesc(rec.noun)
        if (!isTargeted(nd)) return ""
        var s = " (" + ((rec.flags & flagGroup) ? groupName(rec.target) : targetName(nd, rec.target))
        if (hasBand(nd)) s += ", " + bandName(rec.index)
        return s + ")"
    }
    function displayModelName(model) {
        switch (model) {
        case 1: return "LCD 16x2 (HD44780)"
        case 2: return "LCD 20x4 (HD44780)"
        case 3: return "Character OLED 16x2"
        case 4: return "Character OLED 20x2"
        case 5: return "Character OLED 20x4"
        case 6: return "OLED 128x64 (SSD1306)"
        case 7: return "OLED 128x32 (SSD1306)"
        case 8: return "OLED 128x64 (SH1106)"
        default: return "Model " + model
        }
    }
    function displayDefaultAddress(model) { return model === 1 || model === 2 ? 0x27 : 0x3C }
    function displayIsGraphic(model) { return model >= 6 }
    function hex(v, digits) { return ("00000000" + v.toString(16).toUpperCase()).slice(-digits) }
    function irProtocolName(p) {
        switch (p) {
        case 1: return "NEC"
        case 2: return "RC5"
        case 3: return "RC6"
        case 4: return "Generic"
        default: return "None"
        }
    }
    readonly property bool editGated: !!display.config && (display.config.flags & dcfgEditGated) !== 0

    function pageValuePhrase(b) {
        var press = pressWord(b)
        switch (b.action) {
        case actStep: return editGated ? "Turn to move through pages, or to adjust the shown value once editing is armed."
                                       : "Turn to adjust the shown value."
        case actInc: return editGated ? press + " for the next page, or to raise the shown value once editing is armed."
                                      : press + " to raise the shown value."
        case actDec: return editGated ? press + " for the previous page, or to lower the shown value once editing is armed."
                                      : press + " to lower the shown value."
        case actToggle: return editGated ? press + " to toggle the shown value, once editing is armed. Only acts on a page showing an on/off setting."
                                         : press + " to toggle the shown value. Only acts on a page showing an on/off setting."
        default: return ""
        }
    }
    function displayPagePhrase(b) {
        var press = pressWord(b)
        switch (b.action) {
        case actStep: return "Turn to move through the pages on screen."
        case actInc: return press + " to show the next page."
        case actDec: return press + " to show the previous page."
        case actSet: return press + " to show a set page."
        case actIndEquals: return "Lights while a set page is on screen."
        default: return ""
        }
    }
    function actionPhrase(b) {
        if (b.type === typeIr) return "Receives commands from an IR remote."
        if (isAuxType(b.type)) {
            var boots = (b.extras & auxBootSaved) ? "comes back as last saved"
                      : (b.extras & auxBootOn) ? "starts on" : "starts off"
            return (b.type === typeAuxPwm ? "Dimmable output" : "On/off output") + " on GPIO " + b.gpio0 + ", " + boots + "."
        }
        if (b.type === typeDisplay) {
            var addr = b.value === 0 ? displayDefaultAddress(b.index) : (b.value & 0xFF)
            return displayModelName(b.index) + " on I2C, address 0x" + hex(addr, 2) + "."
        }
        if (b.noun === nounPageValue) return pageValuePhrase(b)
        if (b.noun === nounDisplayPage) return displayPagePhrase(b)
        var noun = nounName(b.noun, b.type) + targetSuffix(b)
        var nd = nounDesc(b.noun), isEnum = !!nd && nd.kind === kindEnum
        var press = pressWord(b)
        switch (b.action) {
        case actAdjust: return "Turn to set " + noun + "."
        case actStep: return "Turn to step " + noun + "."
        case actInc: return isEnum ? press + " to select the next " + noun + "." : press + " to raise " + noun + "."
        case actDec: return isEnum ? press + " to select the previous " + noun + "." : press + " to lower " + noun + "."
        case actToggle: return press + " to toggle " + noun + "."
        case actSet: return press + " to set " + noun + "."
        case actMomentary: return "Hold to engage " + noun + "; releases when let go."
        case actFollow: return noun + " follows the switch position."
        case actTrigger: return press + " to " + noun.toLowerCase() + "."
        case actIndEquals: return "Lights to indicate " + noun + "."
        case actIndAbove: return "Lights when " + noun + " is above a level."
        case actIndLevel: return "Brightness follows " + noun + "."
        default: return ""
        }
    }
    function verbPhrase(b) {
        var phrase = actionPhrase(b)
        if (b.onDelay !== 0 || b.offDelay !== 0) {
            var parts = []
            if (b.onDelay !== 0) parts.push(fmtDelay(b.onDelay) + " on")
            if (b.offDelay !== 0) parts.push(fmtDelay(b.offDelay) + " off")
            phrase += " Delayed " + parts.join(", ") + "."
        }
        if (b.baseBright !== 0 && b.baseBright < ledBrightMax) phrase += " Up to " + b.baseBright + "% bright."
        return phrase
    }
    function irVerbPhrase(c) {
        if (c.noun === nounDisplayPage) {
            switch (c.action) {
            case actInc: return "Show the next page"
            case actDec: return "Show the previous page"
            case actSet: return "Show a set page"
            default: return "Show Page"
            }
        }
        if (c.noun === nounPageValue) {
            switch (c.action) {
            case actInc: return editGated ? "Next page, or value up when armed" : "Shown value up"
            case actDec: return editGated ? "Previous page, or value down when armed" : "Shown value down"
            case actToggle: return "Toggle the shown value (on/off pages only)"
            default: return "Browse/Adjust"
            }
        }
        var noun = nounName(c.noun, typeIr) + targetSuffix(c)
        var nd = nounDesc(c.noun), isEnum = !!nd && nd.kind === kindEnum
        switch (c.action) {
        case actInc: return (isEnum ? "Next " : "Raise ") + noun
        case actDec: return (isEnum ? "Previous " : "Lower ") + noun
        case actToggle: return "Toggle " + noun
        case actSet: return "Set " + noun
        case actMomentary: return "Hold " + noun
        default: return noun
        }
    }
    function macroStepSummary(st) {
        var noun = nounName(st.noun, typeButton)
        var nd = nounDesc(st.noun)
        var target = isTargeted(nd) ? " (" + ((st.flags & flagGroup) ? groupName(st.target) : targetName(nd, st.target)) + ")" : ""
        var wait = st.preDelay === 0 ? "" : "After " + fmtSeconds(st.preDelay / 100) + ", "
        var verb
        switch (st.action) {
        case actSet: verb = "set " + noun + target; break
        case actToggle: verb = "toggle " + noun + target; break
        case actInc: verb = "raise " + noun + target; break
        case actDec: verb = "lower " + noun + target; break
        case actTrigger: verb = noun.toLowerCase(); break
        default: verb = noun
        }
        return wait === "" ? verb.charAt(0).toUpperCase() + verb.substring(1) : wait + verb
    }

    function statusMessage(code) { return controlSurfaces.statusMessage(code) }
}
