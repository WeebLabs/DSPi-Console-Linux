import QtQuick 2.15
import "../../components"

// The display card's rows. Wiring is part of the binding (applied with the
// card's Apply); behaviour, editing, appearance and the dashboard pages
// apply as they are edited.
Column {
    id: ds
    property var cs
    property var host                // CsControlsView
    property int slot: 0
    width: parent ? parent.width : 400

    readonly property var b: host.drafts[slot]
    readonly property var cfg: cs.display.config || ({})
    readonly property var pages: cs.display.pages || []
    readonly property var st: controlSurfaces.displayState
    readonly property bool graphic: cs.displayIsGraphic(cs.bindings[slot] ? cs.bindings[slot].index : 0)

    function setB(field, v) { var nb = cs.copy(b); nb[field] = v; host.setDraft(slot, nb) }
    function applyConfig(changes) {
        var c = cs.copy(cfg)
        for (var k in changes) c[k] = changes[k]
        // A cycle mode has a dwell floor
        if (c.mode !== cs.dmodeFixed) c.dwell = Math.max(cs.displayMinDwell, c.dwell)
        var r = controlSurfaces.apply({ op: "displayConfig", config: c })
        host.displayStatus = host.result(r)
    }
    function setCfgFlag(mask, on) { applyConfig({ flags: on ? (cfg.flags | mask) : (cfg.flags & ~mask) }) }
    function applyPage(i, p) {
        var r = controlSurfaces.apply({ op: "displayPage", index: i, page: p })
        host.displayStatus = host.result(r)
    }
    function pageActive(p) { return !!p && (p.flags & cs.dpageActive) !== 0 }
    readonly property var pageNouns: {
        var list = []
        for (var n = 0; n < cs.nouns.length; n++)
            if (cs.nouns[n].actions !== 0 && n !== cs.nounDisplayPage && n !== cs.nounDisplayEdit && n !== cs.nounPageValue) list.push(n)
        return list
    }
    function pageSummary(p) {
        var noun = cs.nounName(p.noun, cs.typeNone)
        var nd = cs.nounDesc(p.noun)
        if (!cs.isTargeted(nd)) return noun
        return ((p.flags & cs.dpageGroup) ? cs.groupName(p.target) : cs.targetName(nd, p.target)) + " " + noun
    }
    function pageMenuLabel(i) {
        var p = pages[i]
        if (!pageActive(p)) return "Page " + (i + 1) + " (empty)"
        return (i + 1) + ". " + pageSummary(p)
    }
    function barAllowed(noun) {
        var nd = cs.nounDesc(noun)
        return !!nd && nd.kind === cs.kindContinuous && cs.decodeValue(nd.max, nd.unit) > cs.decodeValue(nd.min, nd.unit)
    }
    readonly property int firstFreePage: {
        for (var i = 0; i < cs.pageCount; i++) if (!pageActive(pages[i])) return i
        return -1
    }
    // Editing gated with nothing able to arm it: a Browse/Adjust control only browses
    readonly property bool editingUnreachable: {
        if (!(cfg.flags & cs.dcfgEditGated)) return false
        function writes(noun, action) {
            return noun === cs.nounDisplayEdit && action !== cs.actIndEquals && action !== cs.actIndAbove && action !== cs.actIndLevel
        }
        var uses = false, arms = false
        for (var s = 0; s < cs.slotCount; s++) {
            var d = host.drafts[s], l = cs.bindings[s]
            if ((cs.isConfigured(d) && d.noun === cs.nounPageValue) || (cs.isConfigured(l) && l.noun === cs.nounPageValue)) uses = true
            if (writes(d.noun, d.action) || writes(l.noun, l.action)) arms = true
        }
        for (var k = 0; k < cs.irCount; k++) {
            var c = host.irDrafts[k], lc = cs.irCommands[k]
            if ((cs.irConfigured(c) && c.noun === cs.nounPageValue) || (cs.irConfigured(lc) && lc.noun === cs.nounPageValue)) uses = true
            if ((cs.irConfigured(c) && writes(c.noun, c.action)) || (cs.irConfigured(lc) && writes(lc.noun, lc.action))) arms = true
        }
        for (var m = 0; m < cs.macroCount; m++)
            for (var i = 0; i < cs.macros[m].steps.length; i++)
                if (writes(cs.macros[m].steps[i].noun, cs.macros[m].steps[i].action)) arms = true
        return uses && !arms
    }

    CsNote {
        warning: true
        text: ds.host.displayStatus !== 0 ? ds.cs.statusMessage(ds.host.displayStatus) : ""
    }

    // ── Wiring ──
    CsHeading { text: "Wiring" }
    CsPickerRow {
        title: "Model"
        detail: "The type of display connected."
        options: {
            var list = []
            for (var mdl = 1; mdl < Math.max(2, Math.min(ds.cs.modelCount, 9)); mdl++)
                list.push({ value: mdl, text: ds.cs.displayModelName(mdl) })
            return list
        }
        value: ds.b.index
        onChosen: {
            var nb = ds.cs.copy(ds.b)
            // The address follows the model while it is the model's usual one
            if (nb.value !== 0 && (nb.value & 0xFF) === ds.cs.displayDefaultAddress(ds.b.index)) nb.value = 0
            nb.index = value
            ds.host.setDraft(ds.slot, nb)
        }
    }
    CsPickerRow {
        title: "SDA/SCL Pins"
        detail: "Clock and data pins are chosen in fixed pairs."
        options: { bridge.hardware; return ds.cs.i2cSdaCandidates(ds.slot, ds.b).map(function (p) { return { value: p, text: "GPIO " + p + " / " + (p + 1) } }) }
        value: ds.b.gpio0
        onChosen: { var nb = ds.cs.copy(ds.b); nb.gpio0 = value; nb.gpio1 = value + 1; ds.host.setDraft(ds.slot, nb) }
    }
    CsPickerRow {
        title: "Address"
        detail: "7-bit I2C address. Default is the model's usual one (0x" + ds.cs.hex(ds.cs.displayDefaultAddress(ds.b.index), 2) + ")."
        options: [{ value: 0, text: "Default" }].concat([0x27, 0x3C, 0x3D, 0x3E, 0x3F].map(function (a) { return { value: a, text: "0x" + ds.cs.hex(a, 2) } }))
        value: ds.b.value
        onChosen: ds.setB("value", value)
    }
    CsRow {
        title: "Panel State"
        detail: ds.st.naks > 0 ? ds.st.naks + " I2C error" + (ds.st.naks === 1 ? "" : "s") + " so far. Check wiring, pull-up resistors, and the address."
                               : "Reported by the device."
        Text {
            text: ds.st.init === 2 ? "Running" : ds.st.init === 1 ? "Starting up" : ds.st.init === 3 ? "Not responding" : "Not started"
            font.pixelSize: 12
            color: isMacOS ? (ds.st.init === 2 ? MacColors.green : ds.st.init === 3 ? MacColors.orange : MacColors.secondaryLabel) : ds.st.init === 2 ? "#32d74b" : ds.st.init === 3 ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // ── Behavior ──
    CsHeading { text: "Behavior" }
    CsPickerRow {
        title: "Idle Behavior"
        detail: "What the panel rests on between changes."
        options: [{ value: 0, text: "One page" }, { value: 1, text: "Cycle Dashboard" }, { value: 2, text: "Cycle All" }]
        value: ds.cfg.mode
        onChosen: ds.applyConfig({ mode: value })
    }
    CsPickerRow {
        visible: ds.cfg.mode === ds.cs.dmodeFixed
        title: "Page"
        detail: "Which page rests on screen."
        options: {
            var list = []
            for (var i = 0; i < ds.cs.pageCount; i++) list.push({ value: i, text: ds.pageMenuLabel(i) })
            return list
        }
        value: ds.cfg.homePage
        onChosen: ds.applyConfig({ homePage: value })
    }
    CsRow {
        visible: ds.cfg.mode !== ds.cs.dmodeFixed
        title: "Cycle Every"
        detail: "How long each page stays up."
        ValueField {
            value: ds.cfg.dwell / 10
            suffix: "s"
            decimals: 1
            minValue: 1
            maxValue: 655.3
            wheelStep: 1
            fieldWidth: 48
            onValueEdited: ds.applyConfig({ dwell: Math.max(ds.cs.displayMinDwell, Math.round(newValue * 10)) })
        }
    }
    CsRow {
        title: "Pop-Up Hold"
        detail: "Duration for which a change remains on-screen. Zero turns pop-ups off."
        ValueField {
            value: ds.cfg.overlayHold / 10
            suffix: "s"
            decimals: 1
            minValue: 0
            maxValue: 655.3
            wheelStep: 1
            fieldWidth: 48
            onValueEdited: ds.applyConfig({ overlayHold: Math.round(newValue * 10) })
        }
    }
    CsSwitchRow {
        visible: ds.cfg.overlayHold > 0
        title: "All Changes Pop-Up"
        detail: "Show changes made by a knob, button or remote key even if the parameter doesn't correspond to a dashboard page."
        checked: (ds.cfg.flags & ds.cs.dcfgOverlayAny) !== 0
        onToggled: ds.setCfgFlag(ds.cs.dcfgOverlayAny, on)
    }

    // ── Editing ──
    CsHeading { text: "Editing" }
    CsRow {
        title: "Editing Times Out"
        detail: "Disarm editing after this long untouched. Zero leaves it armed until switched off."
        ValueField {
            value: ds.cfg.editTimeout / 10
            suffix: "s"
            decimals: 1
            minValue: 0
            maxValue: 655.3
            wheelStep: 1
            fieldWidth: 48
            onValueEdited: ds.applyConfig({ editTimeout: Math.round(newValue * 10) })
        }
    }
    CsSwitchRow {
        title: "Arm Before Editing"
        detail: "When enabled, an encoder or button browses pages unless Allow Editing is toggled. When disabled, an encoder or button will always adjust the displayed value."
        checked: (ds.cfg.flags & ds.cs.dcfgEditGated) !== 0
        onToggled: ds.setCfgFlag(ds.cs.dcfgEditGated, on)
    }
    CsNote {
        warning: true
        text: ds.editingUnreachable ? "Nothing can arm editing, so a Browse/Adjust control can only browse pages. Bind a button or remote key to Allow Editing." : ""
    }

    // ── Appearance ──
    CsHeading { text: "Appearance" }
    CsRow {
        title: "Brightness"
        detail: "OLED contrast, applied when the panel next starts. Zero is the driver default."
        ValueField {
            value: ds.cfg.brightness
            decimals: 0
            minValue: 0
            maxValue: 255
            wheelStep: 8
            fieldWidth: 44
            onValueEdited: ds.applyConfig({ brightness: Math.round(newValue) })
        }
    }
    Repeater {
        model: [{ title: "Name Alignment", detail: "Horizontal placement of the current page's name.", shift: 2 },
                { title: "Value Alignment", detail: "Horizontal placement of the current page's value.", shift: 4 }]
        CsPickerRow {
            title: modelData.title
            detail: modelData.detail
            options: [{ value: 0, text: "Left" }, { value: 1, text: "Centre" }, { value: 2, text: "Right" }]
            value: (ds.cfg.flags >> modelData.shift) & 3
            onChosen: ds.applyConfig({ flags: (ds.cfg.flags & ~(3 << modelData.shift)) | (value << modelData.shift) })
        }
    }

    // ── Dashboard pages ──
    CsHeading { text: "Dashboard Pages" }
    Repeater {
        model: ds.cs.pageCount
        Column {
            id: pageRow
            readonly property var p: ds.pages[index] || ({})
            readonly property var nd: ds.cs.nounDesc(p.noun)
            readonly property bool shown: ds.st.page === index
            visible: ds.pageActive(p)
            width: ds.width

            Item {
                width: parent.width
                height: 40
                Rectangle { x: 14; width: parent.width - 14; height: 1; color: isMacOS ? Qt.rgba(1, 1, 1, 0.047) : Qt.rgba(1, 1, 1, 0.07) }
                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        width: 16
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                        font.pixelSize: 12
                        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // Holds its place when another page is on screen, so the
                    // pickers stay in a column
                    Icon {
                        name: "eye"
                        size: 13
                        color: isMacOS ? MacColors.accent : "#3a96ff"
                        opacity: pageRow.shown ? 1 : 0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    CsPicker {
                        categories: ds.cs.nounMenu(ds.cs.typeNone, ds.pageNouns)
                        value: pageRow.p.noun
                        text: ds.cs.nounName(pageRow.p.noun, ds.cs.typeNone)
                        anchors.verticalCenter: parent.verticalCenter
                        onChosen: {
                            var np = ds.cs.copy(pageRow.p)
                            np.noun = value; np.target = 0; np.index = 0
                            np.flags &= ~ds.cs.dpageGroup
                            if (!ds.barAllowed(value)) np.flags &= ~ds.cs.dpageBar
                            ds.applyPage(index, np)
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    CsCheck {
                        visible: ds.graphic
                        text: "Large value"
                        checked: (pageRow.p.flags & ds.cs.dpageLarge) !== 0
                        onToggled: {
                            var np = ds.cs.copy(pageRow.p)
                            if (on) np.flags |= ds.cs.dpageLarge; else np.flags &= ~ds.cs.dpageLarge
                            ds.applyPage(index, np)
                        }
                    }
                    CsCheck {
                        text: "Level bar"
                        enabled: ds.barAllowed(pageRow.p.noun)
                        tip: !enabled ? "Only a value with a range can be drawn as a bar."
                             : ds.graphic ? "Fills the value's own row behind the text, with no row given up."
                             : (ds.b.index === 2 || ds.b.index === 5) ? "Draws the bar on the bottom row."
                             : "Draws the bar on the bottom row, moving the value up beside its name."
                        checked: (pageRow.p.flags & ds.cs.dpageBar) !== 0
                        onToggled: {
                            var np = ds.cs.copy(pageRow.p)
                            if (on) np.flags |= ds.cs.dpageBar; else np.flags &= ~ds.cs.dpageBar
                            ds.applyPage(index, np)
                        }
                    }
                    CsButton {
                        bare: true
                        icon: "minus-circle"
                        tip: "Remove this page"
                        onClicked: ds.applyPage(index, { noun: 0, target: 0, index: 0, flags: 0 })
                    }
                }
            }
            Item {
                visible: ds.cs.isTargeted(pageRow.nd)
                width: parent.width
                height: 34
                CsPicker {
                    // Under the function picker (past the number and the eye)
                    x: 14 + 16 + 8 + 13 + 8
                    y: 0
                    options: parent.visible ? ds.cs.targetOptions(pageRow.p.noun,
                                 { flags: (pageRow.p.flags & ds.cs.dpageGroup) ? ds.cs.flagGroup : 0, target: pageRow.p.target }, true) : []
                    value: (pageRow.p.flags & ds.cs.dpageGroup) ? 1000 + pageRow.p.target : pageRow.p.target
                    onChosen: {
                        var np = ds.cs.copy(pageRow.p)
                        if (value >= 1000) { np.flags |= ds.cs.dpageGroup; np.target = value - 1000 }
                        else { np.flags &= ~ds.cs.dpageGroup; np.target = value }
                        ds.applyPage(index, np)
                    }
                }
            }
        }
    }
    Item {
        width: parent.width
        height: 44
        Rectangle { x: 14; width: parent.width - 14; height: 1; color: isMacOS ? Qt.rgba(1, 1, 1, 0.047) : Qt.rgba(1, 1, 1, 0.07) }
        CsButton {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "Add Page"
            icon: "plus"
            enabled: ds.firstFreePage >= 0 && ds.cs.connected
            onClicked: ds.applyPage(ds.firstFreePage, { noun: ds.pageNouns.length > 0 ? ds.pageNouns[0] : 0, target: 0, index: 0,
                                                        flags: ds.cs.dpageActive })
        }
        Text {
            visible: ds.firstFreePage < 0
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "All " + ds.cs.pageCount + " page slots are in use."
            font.pixelSize: 12
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
        }
    }
}
