import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQml 2.15
import "../../components"

// The control cards (Control Surfaces page) or the aux output cards
// (Auxiliary Outputs page): both are binding slots. Each card edits a draft;
// Apply sends it, and the shared save bar keeps it across a restart. Adding
// applies at once with defaults, removing a live control clears its slot.
Column {
    id: view
    property var cs
    property bool auxPage: false
    width: parent ? parent.width : 400
    spacing: 12

    // ── Drafts ──
    property var drafts: []           // per slot: the binding being edited
    property var live: []             // the bindings the drafts were seeded from
    property var nameEdits: ({})      // slot -> staged name
    property var irDrafts: []
    property var liveIr: []
    property var expanded: ({})
    property var messages: ({})       // slot -> failed apply text
    property var subMessages: ({})    // remote button -> { text, error }
    property var expandedSubs: ({})
    property int learningSub: -1
    property string learnMessage: ""
    property int displayStatus: 0     // the last display edit the device refused

    function seed() {
        drafts = cs.copy(cs.bindings)
        live = cs.copy(cs.bindings)
        irDrafts = cs.copy(cs.irCommands)
        liveIr = cs.copy(cs.irCommands)
        nameEdits = ({})
        messages = ({})
        subMessages = ({})
        displayStatus = 0
    }
    // Follow the device in every slot without an edit of its own
    function follow() {
        var nb = cs.bindings, ni = cs.irCommands
        if (drafts.length !== nb.length || irDrafts.length !== ni.length) { seed(); return }
        var bindingsMoved = false, irMoved = false
        for (var s = 0; s < nb.length; s++) if (!cs.sameBinding(nb[s], live[s])) bindingsMoved = true
        for (var k = 0; k < ni.length; k++) if (!cs.sameIr(ni[k], liveIr[k])) irMoved = true
        if (bindingsMoved) {
            var d = drafts.slice()
            for (var i = 0; i < nb.length; i++) if (cs.sameBinding(d[i], live[i])) d[i] = cs.copy(nb[i])
            drafts = d
            live = cs.copy(nb)
        }
        if (irMoved) {
            var di = irDrafts.slice()
            for (var j = 0; j < ni.length; j++)
                if (j !== learningSub && cs.sameIr(di[j], liveIr[j])) di[j] = cs.copy(ni[j])
            irDrafts = di
            liveIr = cs.copy(ni)
        }
    }
    Connections {
        target: controlSurfaces
        function onChanged() { view.follow() }
        function onReloaded() { view.cancelLearn(); view.seed() }
        function onLearnFinished(state, protocol, code) { view.finishLearn(state, protocol, code) }
    }
    Component.onCompleted: seed()
    Component.onDestruction: { cancelLearn(); controlSurfaces.watchDisplay = false }

    function setDraft(slot, b) { var d = drafts.slice(); d[slot] = b; drafts = d }
    function setIrDraft(sub, c) { var d = irDrafts.slice(); d[sub] = c; irDrafts = d }
    function setMap(name, key, v) {
        var o = Object.assign({}, view[name])
        if (v === undefined) delete o[key]; else o[key] = v
        view[name] = o
    }

    // ── Slots ──
    function isAuxSlot(s) { return cs.isAuxType(drafts[s].type) || cs.isAuxType(live[s].type) }
    function slotShown(s) {
        return s < drafts.length && (cs.isConfigured(drafts[s]) || cs.isConfigured(live[s])) && isAuxSlot(s) === auxPage
    }
    readonly property var visibleSlots: {
        var list = []
        for (var s = 0; s < Math.min(cs.slotCount, drafts.length); s++) if (slotShown(s)) list.push(s)
        return list
    }
    readonly property int firstFreeSlot: {
        for (var s = 0; s < Math.min(cs.slotCount, drafts.length); s++)
            if (!cs.isConfigured(drafts[s]) && !cs.isConfigured(live[s])) return s
        return -1
    }
    function slotName(s) { return nameEdits[s] !== undefined ? nameEdits[s] : (cs.names[s] || "") }
    function stagedName(s) {
        if (nameEdits[s] === undefined) return null
        return nameEdits[s] === (cs.names[s] || "") ? null : nameEdits[s]
    }
    readonly property bool anyIrDirty: {
        for (var k = 0; k < Math.min(cs.irCount, irDrafts.length); k++) {
            var d = irDrafts[k], l = liveIr[k]
            if (!cs.sameIr(d, l) && (cs.irConfigured(d) || cs.irConfigured(l))) return true
        }
        return false
    }
    function slotSelfDirty(s) { return !cs.sameBinding(drafts[s], live[s]) || stagedName(s) !== null }
    function slotDirty(s) { return slotSelfDirty(s) || (drafts[s].type === cs.typeIr && anyIrDirty) }

    readonly property int irSlot: {
        for (var s = 0; s < drafts.length; s++)
            if (drafts[s].type === cs.typeIr || live[s].type === cs.typeIr) return s
        return -1
    }
    readonly property int displaySlot: {
        for (var s = 0; s < drafts.length; s++) if (drafts[s].type === cs.typeDisplay) return s
        return -1
    }
    readonly property var addableTypes: cs.realTypes.filter(function (t) {
        if (cs.isAuxType(t) !== view.auxPage) return false
        if (t === cs.typeIr) return view.irSlot < 0
        if (t === cs.typeDisplay) return view.displaySlot < 0
        return true
    })
    // A card's badge switches between controls, or between aux kinds
    function typeMenuItems(slot) {
        return cs.realTypes.filter(function (t) { return cs.isAuxType(t) === view.auxPage }).map(function (t) {
            var taken = (t === cs.typeIr && view.irSlot >= 0 && view.irSlot !== slot)
                     || (t === cs.typeDisplay && view.displaySlot >= 0 && view.displaySlot !== slot)
            return { key: "" + t, text: cs.typeName(t), icon: cs.typeIcon(t), enabled: !taken }
        })
    }

    // The display card is open: watch the panel's state
    Binding {
        target: controlSurfaces
        restoreMode: Binding.RestoreNone
        property: "watchDisplay"
        value: !view.auxPage && view.displaySlot >= 0 && view.expanded[view.displaySlot] === true
               && cs.isConfigured(view.live[view.displaySlot])
    }

    // ── Apply / add / remove ──
    function result(r) { return r && r.status !== undefined ? r.status : (r && r.ok ? 0 : 0xFF) }

    function applySlot(slot) {
        var b = drafts[slot]
        var bindingChanged = !cs.sameBinding(b, live[slot])
        var name = stagedName(slot)
        var subs = []
        if (b.type === cs.typeIr)
            for (var k = 0; k < Math.min(cs.irCount, irDrafts.length); k++) {
                var d = irDrafts[k], l = liveIr[k]
                if (!cs.sameIr(d, l) && (cs.irConfigured(d) || cs.irConfigured(l))) subs.push({ sub: k, cmd: d })
            }
        var status = 0
        if (bindingChanged) status = result(controlSurfaces.apply({ op: "binding", index: slot, binding: b }))
        if (name !== null && status === 0) status = result(controlSurfaces.apply({ op: "name", index: slot, name: name }))
        for (var i = 0; i < subs.length && status === 0; i++)
            status = result(controlSurfaces.apply({ op: "ir", index: subs[i].sub, command: subs[i].cmd }))
        if (status === 0) {
            // Now live: the drafts follow the device again
            setDraft(slot, cs.copy(cs.bindings[slot]))
            setMap("nameEdits", slot, undefined)
            for (var j = 0; j < subs.length; j++) {
                setIrDraft(subs[j].sub, cs.copy(cs.irCommands[subs[j].sub]))
                setMap("subMessages", subs[j].sub, undefined)
            }
            setMap("messages", slot, undefined)
        } else {
            // The rejected draft stays, so the reason can be fixed and applied again
            setMap("messages", slot, cs.statusMessage(status))
        }
    }
    function revertSlot(slot) {
        setDraft(slot, cs.copy(live[slot]))
        setMap("nameEdits", slot, undefined)
        setMap("messages", slot, undefined)
        if (drafts[slot].type === cs.typeIr) {
            irDrafts = cs.copy(liveIr)
            subMessages = ({})
        }
    }
    function addControl(type) {
        var slot = firstFreeSlot
        if (slot < 0) return
        setDraft(slot, cs.makeBinding(type, slot))
        setMap("expanded", slot, true)
        setMap("messages", slot, undefined)
        applySlot(slot)
    }
    function removeControl(slot) {
        setMap("messages", slot, undefined)
        setMap("nameEdits", slot, undefined)
        setMap("expanded", slot, undefined)
        var hadName = !!cs.names[slot]
        if (!cs.isConfigured(live[slot])) {
            setDraft(slot, cs.emptyBinding())
            if (hadName) controlSurfaces.apply({ op: "name", index: slot, name: "" })
            return
        }
        controlSurfaces.apply({ op: "binding", index: slot, binding: cs.emptyBinding() })
        if (hadName) controlSurfaces.apply({ op: "name", index: slot, name: "" })
        setDraft(slot, cs.copy(cs.bindings[slot]))
    }
    function changeType(slot, type) {
        if (type !== drafts[slot].type) setDraft(slot, cs.makeBinding(type, slot))
    }

    // ── Remote buttons ──
    function subOccupied(k) {
        return (k < irDrafts.length && !cs.sameIr(irDrafts[k], cs.emptyIr())) || (k < liveIr.length && cs.irConfigured(liveIr[k]))
    }
    readonly property var visibleSubs: {
        var list = []
        for (var k = 0; k < Math.min(cs.irCount, irDrafts.length); k++) if (subOccupied(k)) list.push(k)
        return list
    }
    readonly property int firstFreeSub: {
        for (var k = 0; k < Math.min(cs.irCount, irDrafts.length); k++) if (!subOccupied(k)) return k
        return -1
    }
    function addIrCommand() {
        var k = firstFreeSub
        if (k < 0) return
        setIrDraft(k, cs.newIrCommand())
        setMap("expandedSubs", k, true)
        setMap("subMessages", k, undefined)
    }
    function removeIrCommand(k) {
        setMap("subMessages", k, undefined)
        setMap("expandedSubs", k, undefined)
        if (!cs.irConfigured(liveIr[k])) { setIrDraft(k, cs.emptyIr()); return }
        controlSurfaces.apply({ op: "ir", index: k, command: cs.emptyIr() })
        setIrDraft(k, cs.copy(cs.irCommands[k]))
    }
    function startLearn(k) {
        setMap("subMessages", k, undefined)
        var r = controlSurfaces.apply({ op: "learnArm" })
        if (!r.ok) {
            setMap("subMessages", k, { text: "No IR receiver is active - apply the receiver first.", error: true })
            return
        }
        learningSub = k
        learnMessage = "Point the remote at the receiver and press the button to learn."
        learnTimeout.restart()
    }
    function finishLearn(state, protocol, code) {
        if (learningSub < 0) return
        var k = learningSub
        learningSub = -1
        learnTimeout.stop()
        if (state === 2 && code !== 0) {
            var c = cs.copy(irDrafts[k])
            c.protocol = protocol
            c.code = code
            setIrDraft(k, c)
            setMap("subMessages", k, { text: "Learned a " + cs.irProtocolName(protocol) + " code. Apply to keep it.", error: false })
        } else {
            var timedOut = state === 3
            setMap("subMessages", k, { text: timedOut ? "No remote button was detected - try again." : "Learn stopped.", error: timedOut })
        }
    }
    function cancelLearn() {
        if (learningSub < 0) return
        var k = learningSub
        learningSub = -1
        learnTimeout.stop()
        setMap("subMessages", k, { text: "Learn cancelled.", error: false })
        controlSurfaces.apply({ op: "learnCancel" })
    }
    // The device listens for 10 s and says how it ended; ask if it hasn't
    Timer {
        id: learnTimeout
        interval: 11500
        onTriggered: {
            var r = controlSurfaces.apply({ op: "learnRead" })
            view.finishLearn(r.ok && r.state !== 1 ? r.state : 3, r.protocol || 0, r.code || 0)
        }
    }

    // ── Aux ──
    function driversOf(slot) {
        var list = []
        for (var s = 0; s < cs.slotCount; s++) {
            var b = drafts[s]
            if (cs.isConfigured(b) && b.target === slot && !(b.flags & cs.flagGroup)
                && (b.noun === cs.nounAux || b.noun === cs.nounAuxLevel)) list.push(s)
        }
        return list
    }
    function otherDrivers(slot) {
        var remotes = 0, macros = []
        for (var k = 0; k < cs.irCount; k++) {
            var c = cs.irCommands[k]
            if (cs.irConfigured(c) && c.target === slot && !(c.flags & cs.flagGroup)
                && (c.noun === cs.nounAux || c.noun === cs.nounAuxLevel)) remotes++
        }
        for (var m = 0; m < cs.macroCount; m++) {
            var steps = cs.macros[m].steps
            for (var i = 0; i < steps.length; i++)
                if (steps[i].target === slot && !(steps[i].flags & cs.flagGroup)
                    && (steps[i].noun === cs.nounAux || steps[i].noun === cs.nounAuxLevel)) { macros.push(cs.macroName(m)); break }
        }
        var parts = []
        if (remotes > 0) parts.push(remotes + " remote key" + (remotes === 1 ? "" : "s"))
        if (macros.length > 0) parts.push("the macro" + (macros.length === 1 ? " " : "s ") + macros.join(", "))
        return parts.length > 0 ? "Also driven by " + parts.join(" and ") + "." : ""
    }

    // ── Layout ──
    Text {
        visible: !cs.supported
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Reading control-surface capabilities from the device..."
        font.pixelSize: 12
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    CsEmptyState {
        visible: cs.supported && view.visibleSlots.length === 0
        title: view.auxPage ? "No Auxiliary Outputs Set Up" : "No Controls Configured"
        text: view.auxPage ? "Put a relay, lamp or fan on a spare GPIO, then point a button, knob or remote key at it from the Control Surfaces page."
                           : "Wire a button, switch, knob, encoder, or LED to a spare GPIO and bind it to a device function."
        Repeater {
            model: cs.realTypes.filter(function (t) { return cs.isAuxType(t) === view.auxPage })
            CsBadge { icon: cs.typeIcon(modelData); tint: cs.typeTint(modelData); size: 28 }
        }
        action: CsButton {
            id: emptyAdd
            text: view.auxPage ? "Add Output" : "Add Control"
            icon: "plus"
            primary: true
            enabled: view.firstFreeSlot >= 0 && bridge.connected
            onClicked: addMenu.openAt(emptyAdd, 0, emptyAdd.height + 4)
        }
    }

    Repeater {
        model: view.drafts.length
        delegate: Loader {
            width: view.width
            active: view.slotShown(index)
            visible: active
            sourceComponent: slotCard
            property int slot: index
        }
    }

    Item {
        visible: cs.supported && view.visibleSlots.length > 0
        width: parent.width
        height: 30
        CsButton {
            id: addButton
            text: view.auxPage ? "Add Output" : "Add Control"
            icon: "plus"
            enabled: view.firstFreeSlot >= 0 && bridge.connected
            anchors.verticalCenter: parent.verticalCenter
            onClicked: addMenu.openAt(addButton, 0, addButton.height + 4)
        }
        Text {
            visible: view.firstFreeSlot < 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "All " + cs.slotCount + " control slots are in use."
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }

    ActionMenu {
        id: addMenu
        parent: Overlay.overlay
        items: view.addableTypes.map(function (t) { return { key: "" + t, text: cs.typeName(t), icon: cs.typeIcon(t) } })
        onTriggered: view.addControl(parseInt(key))
    }
    ActionMenu {
        id: typeMenu
        property int slot: -1
        parent: Overlay.overlay
        items: slot >= 0 ? view.typeMenuItems(slot) : []
        onTriggered: view.changeType(slot, parseInt(key))
    }

    // ── One card ──
    Component {
        id: slotCard
        CsCard {
            id: card
            readonly property int slot: parent ? parent.slot : 0
            readonly property var b: view.drafts[slot]
            readonly property var liveB: view.live[slot]
            readonly property bool dirty: view.slotDirty(slot)
            readonly property bool active: cs.isSlotActive(slot)
            readonly property bool hasName: view.slotName(slot) !== ""

            expanded: view.expanded[slot] === true
            name: view.slotName(slot)
            placeholder: cs.typeName(b.type)
            summary: hasName ? cs.typeName(b.type) + " - " + cs.verbPhrase(b) : cs.verbPhrase(b)
            removeTip: "Remove this control"
            enabled: true
            onToggle: view.setMap("expanded", slot, !expanded ? true : undefined)
            onNameEdited: view.setMap("nameEdits", slot, text)
            onRemoveClicked: view.removeControl(slot)

            badge: Item {
                width: 28
                height: 28
                CsBadge { icon: cs.typeIcon(card.b.type); tint: cs.typeTint(card.b.type); size: 28 }
                MouseArea {
                    id: badgeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { typeMenu.slot = card.slot; typeMenu.openAt(parent, 0, parent.height + 4) }
                }
                ToolTip.text: "Change the component type"
                ToolTip.visible: badgeMouse.containsMouse
                ToolTip.delay: 600
            }
            trailing: CsPill {
                text: card.dirty ? "Pending" : card.active ? "Active" : "Inactive"
                tint: card.dirty || !card.active ? "#ff9f0a" : "#32d74b"
            }

            CsNote {
                warning: true
                text: cs.isConfigured(card.liveB) && !card.active
                      ? "Not running: " + (cs.slotHealth(card.slot) ? cs.statusMessage(cs.slotHealth(card.slot)).toLowerCase() + "." : "it isn't running.")
                        + " Reassign the conflicting pin, then apply." : ""
            }

            // A control: its function, target, action, pins, values and options
            Loader {
                width: parent.width
                active: card.expanded && !cs.isAuxType(card.b.type) && card.b.type !== cs.typeIr && card.b.type !== cs.typeDisplay
                visible: active
                sourceComponent: CsRecordEditor {
                    cs: view.cs
                    mode: "binding"
                    rec: card.b
                    slot: card.slot
                    onEdited: view.setDraft(card.slot, rec)
                }
            }

            // The IR receiver: its pin and sense, then the learned remote buttons
            Loader {
                width: parent.width
                active: card.expanded && card.b.type === cs.typeIr
                visible: active
                sourceComponent: Column {
                    width: parent ? parent.width : 400
                    CsPickerRow {
                        title: "GPIO"
                        detail: cs.pinDetail(cs.typeIr)
                        options: { bridge.hardware; return cs.pinCandidates(card.slot, card.b, false).map(function (p) { return { value: p, text: "GPIO " + p } }) }
                        value: card.b.gpio0
                        onChosen: { var nb = cs.copy(card.b); nb.gpio0 = value; view.setDraft(card.slot, nb) }
                    }
                    CsSwitchRow {
                        title: cs.invertTitle(cs.typeIr)
                        detail: cs.invertDetail(cs.typeIr)
                        checked: (card.b.flags & cs.flagInvert) !== 0
                        onToggled: { var nb = cs.copy(card.b); if (on) nb.flags |= cs.flagInvert; else nb.flags &= ~cs.flagInvert; view.setDraft(card.slot, nb) }
                    }
                    CsRemoteButtons { cs: view.cs; host: view; receiverLive: card.active }
                }
            }

            // The display: wiring here, what it shows below
            Loader {
                width: parent.width
                active: card.expanded && card.b.type === cs.typeDisplay
                visible: active
                sourceComponent: CsDisplaySection { cs: view.cs; host: view; slot: card.slot }
            }

            // An aux output: live switch and level, wiring, timing, power-on
            Loader {
                width: parent.width
                active: card.expanded && cs.isAuxType(card.b.type)
                visible: active
                sourceComponent: Column {
                    id: aux
                    width: parent ? parent.width : 400
                    readonly property bool live: cs.isConfigured(card.liveB) && card.active && bridge.connected
                    readonly property bool pwm: card.b.type === cs.typeAuxPwm
                    function setB(field, v) { var nb = cs.copy(card.b); nb[field] = v; view.setDraft(card.slot, nb) }
                    function setExtra(mask, on) {
                        var nb = cs.copy(card.b)
                        if (on) nb.extras |= mask; else nb.extras &= ~mask
                        view.setDraft(card.slot, nb)
                    }

                    CsSwitchRow {
                        title: "Output"
                        detail: aux.live ? "Switches the pin now. Instant, and never written to flash."
                                         : "Apply the output first; the switch works once it is running."
                        enabled: aux.live
                        checked: controlSurfaces.auxLive.state ? controlSurfaces.auxLive.state[card.slot] !== 0 : false
                        onToggled: controlSurfaces.apply({ op: "auxState", index: card.slot, on: on })
                    }
                    CsRow {
                        id: levelRow
                        visible: aux.pwm
                        enabled: aux.live
                        title: "Level"
                        detail: "How bright or fast the load runs while the output is on."
                        readonly property real stored: controlSurfaces.auxLive.level ? controlSurfaces.auxLive.level[card.slot] / 256 : 0
                        Row {
                            spacing: 10
                            StyledSlider {
                                id: levelSlider
                                width: 160
                                from: 0
                                to: 100
                                value: levelRow.stored
                                anchors.verticalCenter: parent.verticalCenter
                                onMoved: levelThrottle.push(value)
                                Connections {
                                    target: levelRow
                                    function onStoredChanged() { if (!levelSlider.pressed) levelSlider.value = levelRow.stored }
                                }
                                onPressedChanged: if (!pressed) {
                                    levelThrottle.cancel()
                                    controlSurfaces.apply({ op: "auxLevel", index: card.slot, percent: value })
                                }
                            }
                            Text {
                                width: 38
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(levelSlider.value) + "%"
                                font.pixelSize: 13
                                color: Qt.rgba(1, 1, 1, 0.8)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Throttle {
                                id: levelThrottle
                                onFire: controlSurfaces.sendOnly({ op: "auxLevel", index: card.slot, percent: value })
                            }
                        }
                    }
                    CsPickerRow {
                        title: "GPIO"
                        detail: cs.pinDetail(card.b.type)
                        options: { bridge.hardware; return cs.pinCandidates(card.slot, card.b, false).map(function (p) { return { value: p, text: "GPIO " + p } }) }
                        value: card.b.gpio0
                        onChosen: aux.setB("gpio0", value)
                    }
                    CsSwitchRow {
                        title: cs.invertTitle(card.b.type)
                        detail: cs.invertDetail(card.b.type)
                        checked: (card.b.flags & cs.flagInvert) !== 0
                        onToggled: { var nb = cs.copy(card.b); if (on) nb.flags |= cs.flagInvert; else nb.flags &= ~cs.flagInvert; view.setDraft(card.slot, nb) }
                    }
                    CsRow {
                        visible: aux.pwm
                        title: "Level Limit"
                        detail: "Cap on the output's duty as a share of full. Everything below the cap scales with it."
                        ValueField {
                            value: card.b.baseBright === 0 ? 100 : card.b.baseBright
                            suffix: "%"
                            decimals: 0
                            minValue: 1
                            maxValue: 100
                            wheelStep: 5
                            fieldWidth: 48
                            onValueEdited: aux.setB("baseBright", Math.round(newValue))
                        }
                    }
                    CsSwitchRow {
                        visible: aux.pwm
                        title: "Linear Response"
                        detail: "Off: the level follows the eye's curve, right for a lamp. On: duty is proportional to the level, right for a fan or heater."
                        checked: (card.b.extras & cs.auxLinear) !== 0
                        onToggled: aux.setExtra(cs.auxLinear, on)
                    }
                    CsDelayRow {
                        title: "Turn-On Delay"
                        detail: "Hold off until the condition has been true this long. Any interruption restarts the wait. Up to 109 min 13 s."
                        raw: card.b.onDelay
                        onChanged: aux.setB("onDelay", raw)
                    }
                    CsDelayRow {
                        title: "Turn-Off Delay"
                        detail: "Stay on until the condition has been false this long - long enough to hold an amplifier trigger on through quiet passages. Up to 109 min 13 s."
                        raw: card.b.offDelay
                        onChanged: aux.setB("offDelay", raw)
                    }
                    CsNote {
                        text: card.b.onDelay !== 0 || card.b.offDelay !== 0
                              ? "Applying, reverting, or rebooting briefly releases the pin and restarts the timing from off. Driving an amplifier trigger, that is a power cycle." : ""
                    }
                    CsPickerRow {
                        title: "At Power-On"
                        detail: "What this output does when the device starts up."
                        options: [{ value: 0, text: "Fixed" }, { value: 1, text: "As Last Saved" }]
                        value: (card.b.extras & cs.auxBootSaved) ? 1 : 0
                        onChosen: aux.setExtra(cs.auxBootSaved, value === 1)
                    }
                    CsNote {
                        text: (card.b.extras & cs.auxBootSaved)
                              ? "Saving takes a copy of the switch and level as they are at that moment, and the output comes back that way after a restart. Changing them afterwards does not move the stored values until the next save." : ""
                    }
                    CsSwitchRow {
                        visible: !(card.b.extras & cs.auxBootSaved)
                        title: "Starts On"
                        detail: "Leave this off for anything that should never wake with the device, such as an amplifier trigger."
                        checked: (card.b.extras & cs.auxBootOn) !== 0
                        onToggled: aux.setExtra(cs.auxBootOn, on)
                    }
                    CsRow {
                        visible: aux.pwm && !(card.b.extras & cs.auxBootSaved)
                        title: "Starting Level"
                        detail: "The level this output comes up at."
                        Row {
                            spacing: 10
                            StyledSlider {
                                id: bootSlider
                                width: 160
                                from: 0
                                to: 100
                                value: card.b.value / 256
                                anchors.verticalCenter: parent.verticalCenter
                                Connections {
                                    target: card
                                    function onBChanged() { if (!bootSlider.pressed) bootSlider.value = card.b.value / 256 }
                                }
                                onPressedChanged: if (!pressed) aux.setB("value", Math.max(0, Math.min(25600, Math.round(value * 256))))
                            }
                            Text {
                                width: 38
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(bootSlider.pressed ? bootSlider.value : card.b.value / 256) + "%"
                                font.pixelSize: 13
                                color: Qt.rgba(1, 1, 1, 0.8)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    // What drives it: a new output does nothing until something points at it
                    CsRow {
                        title: "Driven By"
                        detail: "Controls on the Control Surfaces page, remote keys and macros pointed at this output."
                    }
                    Column {
                        width: parent.width
                        readonly property var drivers: view.driversOf(card.slot)
                        readonly property string others: view.otherDrivers(card.slot)
                        CsNote {
                            text: parent.drivers.length === 0 && parent.others === ""
                                  ? (aux.pwm ? "Nothing yet. Add a button on \"Aux Switch\" or an encoder or fader on \"Aux Level\" and point it at this output."
                                             : "Nothing yet. Add a button or switch on \"Aux Switch\" and point it at this output.") : ""
                        }
                        Repeater {
                            model: parent.drivers
                            Item {
                                width: parent.width
                                height: 22
                                readonly property var d: view.drafts[modelData]
                                Row {
                                    x: 14
                                    spacing: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    Icon { name: cs.typeIcon(parent.parent.d.type); size: 13; color: Qt.rgba(1, 1, 1, 0.5); anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: view.slotName(modelData) !== "" ? view.slotName(modelData) : cs.typeName(parent.parent.d.type)
                                        font.pixelSize: 12
                                        color: "white"
                                    }
                                    Text {
                                        text: "- " + cs.actionName(parent.parent.d.action, parent.parent.d.noun) + " on " + cs.nounName(parent.parent.d.noun, parent.parent.d.type)
                                        font.pixelSize: 12
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                    }
                                }
                            }
                        }
                        CsNote { text: parent.others }
                        Item { width: 1; height: 6 }
                    }
                }
            }

            footer: CsApplyRow {
                visible: card.expanded || card.dirty || view.messages[card.slot] !== undefined
                dirty: card.dirty
                message: view.messages[card.slot] || ""
                onApply: view.applySlot(card.slot)
                onRevert: view.revertSlot(card.slot)
                leading: CsButton {
                    visible: card.b.type === cs.typeIr && card.expanded
                    text: "Add Remote Button"
                    enabled: view.firstFreeSub >= 0 && bridge.connected
                    onClicked: view.addIrCommand()
                }
            }
        }
    }
}
