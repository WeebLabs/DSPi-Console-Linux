import QtQuick 2.15
import "../../components"

// The rows that set what a record does: a control's binding, a learned
// remote button, or a macro step. The rows shown follow the record's
// component, function and action, as on macOS. Edits come back through
// edited(record); nothing here talks to the device.
Column {
    id: ed
    property var cs                  // CsHelper
    property string mode: "binding"  // "binding", "ir" or "step"
    property var rec
    property int slot: -1            // binding: its slot (pin choices)
    property int indent: 0
    signal edited(var rec)

    width: parent ? parent.width : 400

    readonly property bool isBinding: mode === "binding"
    readonly property bool isIr: mode === "ir"
    readonly property bool isStep: mode === "step"
    // The component whose rules apply: a step is button-shaped
    readonly property int type: isBinding ? rec.type : isIr ? cs.typeIr : cs.typeButton
    readonly property var nd: cs.nounDesc(rec.noun)
    // Browse/Adjust takes everything from the page on screen: no operands
    readonly property int kind: rec.noun === cs.nounPageValue ? 255 : (nd ? nd.kind : cs.kindBool)
    readonly property int unit: nd ? nd.unit : cs.unitDb
    readonly property var range: cs.nounRange(rec.noun)

    readonly property var actions: {
        return isStep ? cs.stepActions(rec.noun) : cs.validActions(type, rec.noun)
    }
    readonly property bool groupsAllowed: rec.action !== cs.actTrigger

    function change(field, v) {
        var r = cs.copy(rec)
        r[field] = v
        edited(r)
    }
    function setFlag(mask, on) {
        var r = cs.copy(rec)
        if (on) r.flags |= mask; else r.flags &= ~mask
        edited(r)
    }

    function chooseNoun(n) {
        if (n === rec.noun) return
        if (isBinding) { edited(cs.withNoun(rec, n)); return }
        var r = cs.copy(rec)
        r.noun = n; r.target = 0; r.index = 0; r.flags &= ~cs.flagGroup
        if (isIr) {
            if (cs.validActions(cs.typeIr, n).indexOf(r.action) < 0) r.action = cs.defaultAction(cs.typeIr, n)
            edited(cs.defaultIrOperands(r))
        } else {
            var acts = cs.stepActions(n)
            if (acts.indexOf(r.action) < 0) r.action = acts.length > 0 ? acts[0] : cs.actSet
            edited(cs.defaultStepOperands(r))
        }
    }
    function chooseAction(a) {
        if (a === rec.action) return
        if (isBinding) { edited(cs.withAction(rec, a)); return }
        var r = cs.copy(rec)
        r.action = a
        edited(isIr ? cs.defaultIrOperands(r) : cs.defaultStepOperands(r))
    }

    // ── Function ──
    CsPickerRow {
        indent: ed.indent
        title: ed.isStep ? "Change" : "Controls"
        detail: ed.isStep ? "Which function this step changes."
              : ed.isIr ? "The device function this remote button drives." : "The device function this control drives."
        categories: ed.cs.nounMenu(ed.type, ed.isStep ? ed.cs.stepNouns : null)
        value: ed.rec.noun
        text: ed.cs.nounName(ed.rec.noun, ed.type)
        onChosen: ed.chooseNoun(value)
    }

    // A step names its action before its target, as on macOS
    CsPickerRow {
        visible: ed.isStep && ed.actions.length > 1
        indent: ed.indent
        title: "How"
        detail: "What this step does to it."
        options: ed.actions.map(function (a) { return { value: a, text: ed.cs.actionName(a, ed.rec.noun) } })
        value: ed.rec.action
        onChosen: ed.chooseAction(value)
    }

    // ── Channel or group, band ──
    CsPickerRow {
        id: targetRow
        visible: ed.cs.isTargeted(ed.nd)
        readonly property bool grouped: (ed.rec.flags & ed.cs.flagGroup) !== 0
        readonly property bool hasGroups: ed.groupsAllowed && ed.cs.compatibleGroups(ed.rec.noun).length > 0
        indent: ed.indent
        title: !hasGroups && !grouped ? (ed.nd ? ed.cs.targetNoun(ed.nd) : "") : "Channel or Group"
        detail: {
            var what = ed.isStep ? "this step affects." : ed.isIr ? "this affects." : "this control affects."
            return !hasGroups && !grouped ? "Which " + (ed.nd ? ed.cs.targetNoun(ed.nd).toLowerCase() : "") + " " + what
                                          : "Which channel, or named set of channels, " + what
        }
        options: visible ? ed.cs.targetOptions(ed.rec.noun, ed.rec, ed.groupsAllowed) : []
        value: ed.cs.targetValue(ed.rec)
        onChosen: ed.edited(ed.cs.withTarget(ed.rec, value,
                            ed.isBinding ? (ed.cs.flagGroup | ed.cs.flagLinkAbs | ed.cs.flagGroupAll) : ed.cs.flagGroup))
    }
    CsPickerRow {
        visible: ed.cs.hasBand(ed.nd)
        indent: ed.indent
        title: "Band"
        detail: ed.isBinding && targetRow.grouped ? "Which filter band this control affects, on every member of the group."
              : ed.isStep ? "Which filter band this step affects."
              : ed.isIr ? "Which filter band this affects." : "Which filter band this control affects."
        options: visible ? ed.cs.bandOptions(ed.rec.noun, ed.rec.target, targetRow.grouped)
                             .map(function (b) { return { value: b, text: ed.cs.bandName(b) } }) : []
        value: ed.rec.index
        onChosen: ed.change("index", value)
    }

    // ── Action ──
    CsPickerRow {
        visible: !ed.isStep && ed.actions.length > 1
        indent: ed.indent
        title: ed.isIr || ed.type === ed.cs.typeButton ? "On Press"
             : ed.cs.isIndicatorType(ed.type) ? "Indicates" : "Behavior"
        detail: ed.isIr ? "What pressing the remote button does."
              : ed.type === ed.cs.typeButton ? "What a press does."
              : ed.cs.isIndicatorType(ed.type) ? "How the LED reflects the function." : "How this control drives the function."
        options: ed.actions.map(function (a) { return { value: a, text: ed.cs.actionName(a, ed.rec.noun) } })
        value: ed.rec.action
        onChosen: ed.chooseAction(value)
    }
    CsPickerRow {
        visible: ed.isBinding && ed.type === ed.cs.typeButton
        indent: ed.indent
        title: "Gesture"
        detail: "Which press gesture triggers this. Bind several to one button GPIO for multiple functions."
        options: [{ value: 0, text: "Press" }, { value: 1, text: "Long press" }, { value: 2, text: "Double press" }]
        value: ed.rec.event
        onChosen: ed.change("event", value)
    }

    // ── Pins ──
    Repeater {
        model: ed.isBinding ? ((ed.cs.typeDesc(ed.type) || {}).pins >= 2 ? 2 : 1) : 0
        CsPickerRow {
            readonly property bool second: index === 1
            readonly property bool twoPin: (ed.cs.typeDesc(ed.type) || {}).pins >= 2
            indent: ed.indent
            title: twoPin ? (second ? "GPIO B" : "GPIO A") : "GPIO"
            detail: twoPin ? (second ? "Encoder channel B." : "Encoder channel A.") : ed.cs.pinDetail(ed.type)
            options: { bridge.hardware; return ed.cs.pinCandidates(ed.slot, ed.rec, second)
                         .map(function (p) { return { value: p, text: p === 0xFF ? "None" : "GPIO " + p } }) }
            value: second ? ed.rec.gpio1 : ed.rec.gpio0
            onChosen: ed.change(second ? "gpio1" : "gpio0", value)
        }
    }

    // ── Values ──
    // A continuous value: Set To, Hold Value, Light Above
    CsRow {
        id: valueRow
        readonly property bool hold: ed.rec.action === ed.cs.actMomentary
        readonly property bool above: ed.rec.action === ed.cs.actIndAbove
        visible: ed.kind === ed.cs.kindContinuous
                 && (ed.rec.action === ed.cs.actSet || hold || (above && ed.isBinding))
        readonly property bool atFloor: above && ed.nd && ed.rec.value <= ed.nd.min
        readonly property string span: "(" + ed.cs.fmtUnit(ed.range.lo, ed.unit) + " to " + ed.cs.fmtUnit(ed.range.hi, ed.unit) + ")."
        indent: ed.indent
        title: above ? "Light Above" : hold ? "Hold Value" : "Set To"
        detail: above ? "Light the LED once the value reaches this. " + span
                        + (atFloor ? " At the " + ed.cs.fmtUnit(ed.range.lo, ed.unit) + " floor this is always true, so the LED stays lit." : "")
              : ed.isStep ? "The value this step applies " + span
              : "Level each press applies " + span
        ValueField {
            value: ed.cs.decodeValue(ed.rec.value, ed.unit)
            suffix: ed.cs.unitSymbol(ed.unit)
            decimals: ed.cs.unitDecimals(ed.unit)
            minValue: ed.range.lo
            maxValue: ed.range.hi
            wheelStep: ed.cs.unitWheelStep(ed.unit)
            fieldWidth: 64
            onValueEdited: ed.change("value", ed.cs.encodeValue(newValue, ed.unit))
        }
    }
    // An on/off state: Set To, Hold Value, Light When
    CsPickerRow {
        readonly property bool light: ed.rec.action === ed.cs.actIndEquals
        visible: ed.kind === ed.cs.kindBool
                 && (ed.rec.action === ed.cs.actSet || ed.rec.action === ed.cs.actMomentary || light)
        indent: ed.indent
        title: light ? "Light When" : ed.rec.action === ed.cs.actMomentary ? "Hold Value" : "Set To"
        detail: light ? "Light the LED when the function is in this state."
              : ed.isStep ? "The state this step applies." : "The state a press applies."
        options: [{ value: 1, text: ed.cs.boolLabel(ed.rec.noun, true) }, { value: 0, text: ed.cs.boolLabel(ed.rec.noun, false) }]
        value: ed.rec.value !== 0 ? 1 : 0
        onChosen: ed.change("value", value)
    }
    // A selection: Set To, Hold Value, Light When
    CsPickerRow {
        readonly property bool light: ed.rec.action === ed.cs.actIndEquals
        visible: ed.kind === ed.cs.kindEnum
                 && (ed.rec.action === ed.cs.actSet || ed.rec.action === ed.cs.actMomentary || light)
        indent: ed.indent
        title: light ? "Light When" : ed.rec.action === ed.cs.actMomentary ? "Hold Value" : "Set To"
        detail: light ? "Light the LED for this selection."
              : ed.isStep ? "The selection this step applies." : "The selection a press applies."
        options: {
            if (!visible) return []
            var list = []
            for (var i = 0; i < Math.max(1, ed.nd ? ed.nd.enumCount : 1); i++)
                list.push({ value: i, text: ed.cs.enumValueLabel(ed.rec.noun, i) })
            return list
        }
        value: ed.rec.value
        onChosen: ed.change("value", value)
    }
    // A continuous step: Step Size (octaves for frequency and Q)
    CsRow {
        id: stepRow
        readonly property bool isLog: ed.cs.unitIsLog(ed.unit)
        readonly property real minStep: isLog ? 1 / 48 : ed.cs.unitMinStep(ed.unit)
        visible: ed.kind === ed.cs.kindContinuous
                 && (ed.rec.action === ed.cs.actStep || ed.rec.action === ed.cs.actInc || ed.rec.action === ed.cs.actDec)
        indent: ed.indent
        title: "Step Size"
        detail: ed.isStep ? (isLog ? "How far each run moves it, in octaves." : "How far each run moves it.")
              : ed.isIr ? (isLog ? "Ratio per press, in octaves." : "Amount added or removed per press.")
              : (isLog ? "Ratio per detent/press, in octaves." : "Amount added or removed per detent/press.")
        ValueField {
            value: ed.rec.step === 0 ? ed.cs.defaultStep(ed.unit) : ed.cs.decodeStep(ed.rec.step, ed.unit)
            suffix: stepRow.isLog ? "oct" : ed.cs.unitSymbol(ed.unit)
            decimals: stepRow.isLog ? 3 : ed.cs.unitDecimals(ed.unit)
            minValue: ed.isStep ? 0 : stepRow.minStep
            maxValue: 100
            wheelStep: stepRow.isLog ? ed.cs.defaultStep(ed.unit) : ed.cs.unitWheelStep(ed.unit)
            fieldWidth: 64
            onValueEdited: ed.change("step", ed.cs.encodeStep(newValue, ed.unit))
        }
    }
    // A list step: positions per detent or press
    CsRow {
        visible: !ed.isStep && ed.kind === ed.cs.kindEnum
                 && (ed.rec.action === ed.cs.actStep || ed.rec.action === ed.cs.actInc || ed.rec.action === ed.cs.actDec)
        indent: ed.indent
        title: "Step Size"
        detail: ed.isIr ? "Positions advanced per press." : "Positions advanced per detent/press."
        ValueField {
            value: ed.rec.step <= 0 ? 1 : ed.rec.step
            decimals: 0
            minValue: 1
            maxValue: Math.max(1, (ed.nd ? ed.nd.enumCount : 2) - 1)
            wheelStep: 1
            fieldWidth: 40
            onValueEdited: ed.change("step", Math.round(newValue))
        }
    }
    // A span: the knob's range, or the values an LED's brightness maps to
    CsSwitchRow {
        id: spanRow
        readonly property bool level: ed.rec.action === ed.cs.actIndLevel
        visible: ed.isBinding && ed.kind === ed.cs.kindContinuous && (ed.rec.action === ed.cs.actAdjust || level)
        indent: ed.indent
        title: level ? "Brightness Range" : "Limit Range"
        detail: "Map onto a portion of the " + ed.cs.fmtUnit(ed.range.lo, ed.unit) + " to " + ed.cs.fmtUnit(ed.range.hi, ed.unit) + " range."
        checked: !!ed.rec.rangeMin || !!ed.rec.rangeMax
        onToggled: {
            var r = ed.cs.copy(ed.rec)
            r.rangeMin = on ? ed.nd.min : 0
            r.rangeMax = on ? ed.nd.max : 0
            ed.edited(r)
        }
    }
    Repeater {
        model: spanRow.visible && spanRow.checked ? 2 : 0
        CsRow {
            readonly property bool hi: index === 1
            indent: ed.indent
            title: hi ? "Maximum" : "Minimum"
            detail: spanRow.level ? (hi ? "Value mapped to the LED fully lit." : "Value mapped to the LED fully off.")
                                  : (hi ? "Level at the fully clockwise position." : "Level at the fully counter-clockwise position.")
            ValueField {
                value: ed.cs.decodeValue(hi ? ed.rec.rangeMax : ed.rec.rangeMin, ed.unit)
                suffix: ed.cs.unitSymbol(ed.unit)
                decimals: ed.cs.unitDecimals(ed.unit)
                minValue: ed.range.lo
                maxValue: ed.range.hi
                wheelStep: ed.cs.unitWheelStep(ed.unit)
                fieldWidth: 64
                onValueEdited: ed.change(hi ? "rangeMax" : "rangeMin", ed.cs.encodeValue(newValue, ed.unit))
            }
        }
    }

    // ── Timing and brightness (LEDs) ──
    Column {
        width: parent.width
        visible: ed.isBinding && ed.cs.delaysAllowed(ed.type, ed.rec.action) && !ed.cs.isAuxType(ed.type)
        CsDelayRow {
            indent: ed.indent
            title: "Turn-On Delay"
            detail: "Hold off until the condition has been true this long. Any interruption restarts the wait. Up to 109 min 13 s."
            raw: ed.rec.onDelay || 0
            onChanged: ed.change("onDelay", raw)
        }
        CsDelayRow {
            indent: ed.indent
            title: "Turn-Off Delay"
            detail: "Stay lit until the condition has been false this long - long enough to hold an amplifier trigger on through quiet passages. Up to 109 min 13 s."
            raw: ed.rec.offDelay || 0
            onChanged: ed.change("offDelay", raw)
        }
        CsNote {
            indent: ed.indent
            text: (ed.rec.onDelay || ed.rec.offDelay)
                  ? "Applying, reverting, or rebooting briefly releases the pin and restarts the timing from off. Driving an amplifier trigger, that is a power cycle." : ""
        }
    }
    CsRow {
        visible: ed.isBinding && ed.type === ed.cs.typeLedPwm
        indent: ed.indent
        title: "Brightness Limit"
        detail: "Cap on how bright this LED gets, as a share of full. Everything below the cap scales with it."
        ValueField {
            value: !ed.rec.baseBright ? 100 : ed.rec.baseBright
            suffix: "%"
            decimals: 0
            minValue: 1
            maxValue: 100
            wheelStep: 5
            fieldWidth: 48
            onValueEdited: ed.change("baseBright", Math.round(newValue))
        }
    }

    // ── Options ──
    CsSwitchRow {
        visible: ed.isBinding && (ed.type === ed.cs.typePot || ed.type === ed.cs.typeEncoder)
        indent: ed.indent
        title: "Reverse Direction"
        detail: ed.type === ed.cs.typePot ? "Clockwise decreases the value." : "Clockwise steps down."
        checked: (ed.rec.flags & ed.cs.flagReverse) !== 0
        onToggled: ed.setFlag(ed.cs.flagReverse, on)
    }
    CsSwitchRow {
        visible: ed.isBinding && ed.type === ed.cs.typeEncoder
        indent: ed.indent
        title: "Acceleration"
        detail: "Fast spins move in larger steps; slow spins stay fine."
        checked: (ed.rec.flags & ed.cs.flagAccel) !== 0
        onToggled: ed.setFlag(ed.cs.flagAccel, on)
    }
    CsSwitchRow {
        visible: ed.kind === ed.cs.kindEnum
                 && (ed.rec.action === ed.cs.actStep || ed.rec.action === ed.cs.actInc || ed.rec.action === ed.cs.actDec)
        indent: ed.indent
        title: "Wrap Around"
        detail: "Step past the last position back to the first."
        checked: (ed.rec.flags & ed.cs.flagWrap) !== 0
        onToggled: ed.setFlag(ed.cs.flagWrap, on)
    }
    CsSwitchRow {
        visible: (ed.isIr && (ed.rec.action === ed.cs.actInc || ed.rec.action === ed.cs.actDec))
                 || (ed.isBinding && ed.type === ed.cs.typeButton && ed.rec.event === ed.cs.eventPress
                     && (ed.rec.action === ed.cs.actInc || ed.rec.action === ed.cs.actDec))
        indent: ed.indent
        title: "Repeat While Held"
        detail: ed.isIr ? "Holding the remote button repeats the step." : "After holding ~0.4 s the press repeats automatically."
        checked: (ed.rec.flags & ed.cs.flagRepeat) !== 0
        onToggled: ed.setFlag(ed.cs.flagRepeat, on)
    }
    CsSwitchRow {
        visible: ed.isBinding && targetRow.grouped && ed.rec.action === ed.cs.actAdjust && ed.kind === ed.cs.kindContinuous
        indent: ed.indent
        title: "Match Members Exactly"
        detail: "Drive every member to the same value. Off keeps the offsets between them, moving the group's average to the knob."
        checked: (ed.rec.flags & ed.cs.flagLinkAbs) !== 0
        onToggled: ed.setFlag(ed.cs.flagLinkAbs, on)
    }
    CsSwitchRow {
        visible: ed.isBinding && targetRow.grouped && (ed.rec.action === ed.cs.actIndEquals || ed.rec.action === ed.cs.actIndAbove)
        indent: ed.indent
        title: "Require Every Member"
        detail: "Light only when all members match. Off lights when any one does."
        checked: (ed.rec.flags & ed.cs.flagGroupAll) !== 0
        onToggled: ed.setFlag(ed.cs.flagGroupAll, on)
    }
    CsSwitchRow {
        visible: ed.isBinding
        indent: ed.indent
        title: ed.cs.invertTitle(ed.type)
        detail: ed.cs.invertDetail(ed.type)
        checked: (ed.rec.flags & ed.cs.flagInvert) !== 0
        onToggled: ed.setFlag(ed.cs.flagInvert, on)
    }

    // ── Step timing ──
    CsRow {
        visible: ed.isStep
        indent: ed.indent
        title: "Wait Before"
        detail: "Delay after the previous step before this one runs."
        ValueField {
            value: ed.rec.preDelay / 100
            suffix: "s"
            decimals: 2
            minValue: 0
            maxValue: 655.35
            wheelStep: 0.1
            fieldWidth: 64
            onValueEdited: ed.change("preDelay", Math.max(0, Math.min(65535, Math.round(newValue * 100))))
        }
    }
}
