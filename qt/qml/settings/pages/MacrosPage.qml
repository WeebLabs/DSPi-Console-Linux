import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"
import "../cs"
import "../../components"

// Macros: short sequences of changes fired by one press.
SettingsPage {
    id: page
    title: "Macros"
    subtitle: "Run a short sequence of changes from a single press: select an input and load a preset, switch monitors, mute after a delay."

    CsHelper { id: cs }
    readonly property var csHelper: cs

    property var drafts: []
    property var live: []
    property var expanded: ({})
    property var messages: ({})

    function seed() { drafts = cs.copy(cs.macros); live = cs.copy(cs.macros); messages = ({}) }
    function follow() {
        var nm = cs.macros, d = drafts.slice()
        if (d.length !== nm.length) { seed(); return }
        var moved = false
        for (var k = 0; k < nm.length; k++) if (!cs.sameMacro(nm[k], live[k])) moved = true
        if (!moved) return
        for (var m = 0; m < nm.length; m++) if (cs.sameMacro(d[m], live[m])) d[m] = cs.copy(nm[m])
        drafts = d
        live = cs.copy(nm)
    }
    Connections {
        target: controlSurfaces
        function onChanged() { page.follow() }
        function onReloaded() { page.seed() }
    }
    Component.onCompleted: seed()

    function setDraft(m, v) { var d = drafts.slice(); d[m] = v; drafts = d }
    function setStep(m, s, st) { var mc = cs.copy(drafts[m]); mc.steps[s] = st; setDraft(m, mc) }
    function setMap(name, key, v) {
        var o = Object.assign({}, page[name])
        if (v === undefined) delete o[key]; else o[key] = v
        page[name] = o
    }
    function inUse(m) { return cs.macroConfigured(drafts[m]) || cs.macroConfigured(live[m]) }
    readonly property var visibleMacros: {
        var list = []
        for (var m = 0; m < Math.min(cs.macroCount, drafts.length); m++) if (inUse(m)) list.push(m)
        return list
    }
    readonly property int firstFree: {
        for (var m = 0; m < Math.min(cs.macroCount, drafts.length); m++) if (!inUse(m)) return m
        return -1
    }
    readonly property int running: cs.ext.macroRunning !== undefined ? cs.ext.macroRunning : 0xFF

    function summary(mc, isRunning) {
        if (isRunning) return "Running - step " + ((cs.ext.macroStep || 0) + 1) + " of " + mc.steps.length + "."
        var n = mc.steps.length
        if (n === 0) return "No steps yet."
        var total = 0
        for (var i = 0; i < n; i++) total += mc.steps[i].preDelay / 100
        var base = n + " step" + (n === 1 ? "" : "s")
        return total > 0 ? base + ", " + cs.fmtSeconds(total) + " total" : base
    }
    function addMacro() {
        var m = firstFree
        if (m < 0) return
        setDraft(m, { name: "Macro " + (m + 1), steps: [] })
        setMap("expanded", m, true)
        setMap("messages", m, undefined)
    }
    function applyMacro(m) {
        var r = controlSurfaces.apply({ op: "macro", index: m, macro: drafts[m] })
        var st = r && r.status !== undefined ? r.status : 0xFF
        setDraft(m, cs.copy(cs.macros[m]))
        setMap("messages", m, st !== 0 ? cs.statusMessage(st) : undefined)
    }
    function removeMacro(m) {
        setMap("messages", m, undefined)
        setMap("expanded", m, undefined)
        var wasLive = cs.macroConfigured(live[m])
        setDraft(m, { name: "", steps: [] })
        if (wasLive) applyMacro(m)
    }
    function moveStep(m, s, delta) {
        var mc = cs.copy(drafts[m]), dest = s + delta
        if (dest < 0 || dest >= mc.steps.length) return
        var t = mc.steps[s]; mc.steps[s] = mc.steps[dest]; mc.steps[dest] = t
        setDraft(m, mc)
    }
    function removeStep(m, s) { var mc = cs.copy(drafts[m]); mc.steps.splice(s, 1); setDraft(m, mc) }
    function addStep(m) {
        var mc = cs.copy(drafts[m])
        if (mc.steps.length >= cs.stepCount) return
        mc.steps.push(cs.newStep())
        setDraft(m, mc)
    }

    Column {
        width: parent.width
        spacing: 12

        Text {
            visible: !cs.supported
            text: "Reading control-surface capabilities from the device..."
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.5)
        }

        CsEmptyState {
            visible: cs.supported && page.visibleMacros.length === 0
            title: "No Macros Configured"
            text: "Run a short sequence of changes from a single press: select an input and load a preset, switch monitors, mute after a delay."
            Icon { name: "list-number"; size: 28; color: Qt.rgba(1, 1, 1, 0.45) }
            action: CsButton {
                text: "Add Macro"; icon: "plus"; primary: true
                enabled: page.firstFree >= 0 && bridge.connected
                onClicked: page.addMacro()
            }
        }

        Repeater {
            model: page.drafts.length
            delegate: CsCard {
                id: card
                readonly property int m: index
                readonly property var d: page.drafts[m] || ({ name: "", steps: [] })
                readonly property bool dirty: !cs.sameMacro(d, page.live[m])
                readonly property bool isRunning: page.running === m
                readonly property int health: cs.ext.macroStatus ? cs.ext.macroStatus[m] : 0
                visible: m < cs.macroCount && page.inUse(m)
                expanded: page.expanded[m] === true
                name: d.name
                placeholder: "Macro " + (m + 1)
                summary: page.summary(d, isRunning)
                summaryColor: isRunning ? "#32d74b" : Qt.rgba(1, 1, 1, 0.5)
                removeTip: "Remove this macro"
                onToggle: page.setMap("expanded", m, expanded ? undefined : true)
                onNameEdited: { var nd = cs.copy(card.d); nd.name = text; page.setDraft(card.m, nd) }
                onRemoveClicked: page.removeMacro(m)

                badge: Icon { name: card.isRunning ? "play" : "list-number"; size: 18; color: card.isRunning ? "#32d74b" : "#3a96ff" }
                trailing: Row {
                    spacing: 4
                    Icon {
                        visible: card.health !== 0 && cs.macroConfigured(page.live[card.m])
                        name: "warning"
                        size: 14
                        color: "#ff9f0a"
                        anchors.verticalCenter: parent.verticalCenter
                        ToolTip.text: cs.statusMessage(card.health)
                        ToolTip.visible: warnMouse.containsMouse
                        MouseArea { id: warnMouse; anchors.fill: parent; hoverEnabled: true }
                    }
                    // Runs the version stored on the device, so only once applied
                    CsButton {
                        bare: true
                        icon: card.isRunning ? "stop" : "play"
                        tip: card.isRunning ? "Stop this macro" : "Run this macro now"
                        enabled: bridge.connected && (card.isRunning || (page.live[card.m] && page.live[card.m].steps.length > 0))
                        onClicked: controlSurfaces.apply({ op: card.isRunning ? "macroCancel" : "macroFire", index: card.m })
                    }
                }

                Repeater {
                    model: card.expanded ? card.d.steps.length : 0
                    Column {
                        readonly property int s: index
                        readonly property var st: card.d.steps[s]
                        width: card.width
                        Item {
                            width: parent.width
                            height: 36
                            Rectangle { x: 14; width: parent.width - 14; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                            Text {
                                id: num
                                x: 14
                                width: 16
                                horizontalAlignment: Text.AlignRight
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.s + 1
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Qt.rgba(1, 1, 1, 0.5)
                            }
                            Text {
                                anchors.left: num.right
                                anchors.leftMargin: 10
                                anchors.right: stepButtons.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: cs.macroStepSummary(parent.parent.st)
                                font.pixelSize: 12
                                color: Qt.rgba(1, 1, 1, 0.7)
                            }
                            Row {
                                id: stepButtons
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                CsButton { bare: true; icon: "arrow-up"; tip: "Move up"; enabled: index > 0; onClicked: page.moveStep(card.m, index, -1) }
                                CsButton { bare: true; icon: "arrow-down"; tip: "Move down"; enabled: index < card.d.steps.length - 1; onClicked: page.moveStep(card.m, index, 1) }
                                CsButton { bare: true; icon: "minus-circle"; tip: "Remove this step"; onClicked: page.removeStep(card.m, index) }
                            }
                        }
                        CsRecordEditor {
                            cs: page.csHelper
                            mode: "step"
                            indent: 26
                            rec: parent.st
                            onEdited: page.setStep(card.m, index, rec)
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: 42
                    Rectangle { x: 14; width: parent.width - 14; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                    CsButton {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add Step"
                        icon: "plus"
                        enabled: card.d.steps.length < cs.stepCount
                        onClicked: page.addStep(card.m)
                    }
                    Text {
                        visible: card.d.steps.length >= cs.stepCount
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "A macro holds up to " + cs.stepCount + " steps."
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.5)
                    }
                }

                footer: CsApplyRow {
                    visible: card.expanded || card.dirty || page.messages[card.m] !== undefined
                    dirty: card.dirty
                    message: page.messages[card.m] || ""
                    onApply: page.applyMacro(card.m)
                    onRevert: { page.setDraft(card.m, cs.copy(page.live[card.m])); page.setMap("messages", card.m, undefined) }
                }
            }
        }

        Item {
            visible: cs.supported && page.visibleMacros.length > 0
            width: parent.width
            height: 30
            CsButton {
                text: "Add Macro"; icon: "plus"
                enabled: page.firstFree >= 0 && bridge.connected
                anchors.verticalCenter: parent.verticalCenter
                onClicked: page.addMacro()
            }
            Text {
                visible: page.firstFree < 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "All " + cs.macroCount + " macro slots are in use."
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.5)
            }
        }
    }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        leftPadding: 4
        rightPadding: 4
        text: "To fire a macro, bind a push button or remote key to Tools > Macro with the action Set value. Each step can wait before it runs, and can address a channel group. One macro runs at a time - firing another cancels the first at its current step.\n\nMacros are stored on the device alongside the controls and share their Save and Revert."
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.45)
    }
}
