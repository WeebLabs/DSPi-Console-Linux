import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import "components"

// Signal Generator: the device's onboard test signals, after the macOS
// Console. Pick a signal and outputs (click again to invert polarity), set
// the level, parameters and timing, then Start. While it plays, edits apply
// live. Closing the window leaves a running signal playing.
AppWindow {
    id: win
    title: "Signal Generator"
    visible: false
    width: 780
    height: 600 + titlebarHeight
    minimumWidth: 720
    minimumHeight: 460 + titlebarHeight

    onVisibleChanged: siggen.watching = visible

    readonly property var d: siggen.draft
    readonly property var info: (siggen.supported, siggen.typeInfo(d.type))
    readonly property int timing: info.timing
    readonly property bool walking: d.type === 14 || (d.flags & 4) !== 0
    readonly property bool textFocused: activeFocusItem !== null && activeFocusItem.selectedText !== undefined
    property int rev: 0
    Connections { target: bridge; function onStateChanged() { win.rev++ } }

    // Display names and help, by firmware type id (as on macOS)
    readonly property var types: [
        { tile: "Sine", name: "Sine", blurb: "Pure tone, THD approx -139 dB", labels: ["Frequency"] },
        { tile: "Square", name: "Square wave", blurb: "Band-limited (polyBLEP) square", labels: ["Frequency"] },
        { tile: "White", name: "White noise", blurb: "Uniform white noise", labels: [] },
        { tile: "Pink", name: "Pink noise", blurb: "-3 dB/oct, level-safe normalized", labels: [] },
        { tile: "Log Swp", name: "Log sweep", blurb: "Exponential sweep for room measurement", labels: ["Start", "End"] },
        { tile: "Lin Swp", name: "Linear sweep", blurb: "Linear frequency sweep", labels: ["Start", "End"] },
        { tile: "Step Swp", name: "Stepped sweep", blurb: "Discrete tones stepping up the band", labels: ["Start", "End", "Steps/octave", "Dwell"] },
        { tile: "Impulse", name: "Impulse", blurb: "Single-sample unit impulses", labels: ["Period"] },
        { tile: "Clicks", name: "Alternating clicks", blurb: "Clicks with alternating polarity", labels: ["Period"] },
        { tile: "Polarity", name: "Polarity pulse", blurb: "Positive half-sine lobe per period", labels: ["Pulse width", "Period"] },
        { tile: "Burst", name: "Tone burst", blurb: "Sine bursts with raised-cosine edges", labels: ["Frequency", "On cycles", "Off cycles", "Edge cycles"] },
        { tile: "2-Tone", name: "Tone pair", blurb: "IMD test pair (SMPTE / CCIF)", labels: ["Tone 1", "Tone 2", "Ratio A1/A2"] },
        { tile: "Multi", name: "Multitone", blurb: "Log-spaced tones, Schroeder phases", labels: ["Tones", "Low", "High"] },
        { tile: "ISP", name: "ISP test", blurb: "Inter-sample-peak over patterns", labels: ["Pattern"] },
        { tile: "Chan ID", name: "Channel ID", blurb: "Counted pentatonic blips per channel", labels: ["Blip length"] }
    ]
    function typeName(t) { return (types[t] || types[0]).name }

    readonly property var stateNames: ["Idle", "Fading in", "Running", "Gap", "Fading out"]
    readonly property var stateColors: [Qt.rgba(1, 1, 1, 0.4), "#32d74b", "#32d74b", "#ffd60a", "#ff9f0a"]

    readonly property int outputCount: siggen.outputChannels > 0 ? siggen.outputChannels : bridge.numOutputChannels
    function outputName(o) { var n = bridge.channelName(o + 2); return n !== "" ? n : "Out " + (o + 1) }
    function popcount(m) { var n = 0; while (m) { n += m & 1; m >>= 1 } return n }

    readonly property string blocker: !bridge.connected ? "No device connected"
        : !siggen.supported ? "Firmware has no signal generator"
        : d.channelMask === 0 ? "Select at least one output"
        : timing === 1 && d.durationMs === 0 ? "Sweep length must be greater than 0" : ""

    function fmtTime(ms) {
        var s = ms / 1000
        if (s < 60) return s.toFixed(1) + " s"
        var m = Math.floor(s / 60)
        var r = s - m * 60
        return m + ":" + (r < 10 ? "0" : "") + r.toFixed(1)
    }

    function startOrStop() {
        if (siggen.running) { siggen.stop(); return }
        if (blocker !== "") return
        if (!siggen.start()) rejectedDialog.open()
    }
    Shortcut { sequence: "Space"; enabled: !win.textFocused && win.active; onActivated: win.startOrStop() }

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }
    component Caption: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.5)
    }
    component LinkText: Text {
        signal clicked()
        font.pixelSize: 11
        color: linkMouse.containsMouse ? "white" : "#3a96ff"
        MouseArea { id: linkMouse; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
    // Label left, value field right
    // (plain properties: aliases in inline components misbehave in Qt 5.15)
    component FieldRow: Item {
        id: fr
        property string label: ""
        property real value: 0
        property string suffix: ""
        property int decimals: 1
        property real minValue: 0
        property real maxValue: 1e9
        property real wheelStep: 1
        property string caption: ""
        signal edited(real v)
        width: parent ? parent.width : 0
        height: caption !== "" ? 44 : 28
        Text { y: (26 - height) / 2; text: parent.label; font.pixelSize: 12; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.9) }
        Text {
            visible: parent.caption !== ""
            y: 26
            text: parent.caption
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.5)
        }
        ValueField {
            anchors.right: parent.right
            y: 0
            height: 26
            fieldWidth: 66
            value: fr.value
            suffix: fr.suffix
            decimals: fr.decimals
            minValue: fr.minValue
            maxValue: fr.maxValue
            wheelStep: fr.wheelStep
            onValueEdited: fr.edited(newValue)
        }
    }
    // Title and caption left, switch right
    component OptionRow: Item {
        id: opt
        property string title: ""
        property string caption: ""
        property bool checked: false
        signal toggled(bool on)
        width: parent ? parent.width : 0
        height: Math.max(30, optText.height + 6)
        opacity: enabled ? 1 : 0.45
        Column {
            id: optText
            anchors.left: parent.left
            anchors.right: optSwitch.left
            anchors.rightMargin: 10
            spacing: 2
            Text { text: opt.title; font.pixelSize: 12; font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.9) }
            Text { width: parent.width; text: opt.caption; wrapMode: Text.WordWrap; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
        }
        ToggleSwitch {
            id: optSwitch
            anchors.right: parent.right
            y: 0
            checked: opt.checked
            // Shows the draft again after the click (a refused change, such
            // as a cancelled RAW confirmation, flips back)
            onToggled: { opt.toggled(checked); checked = Qt.binding(function () { return opt.checked }) }
        }
    }

    // ── Header ──
    ToolHeader {
        id: header
        width: parent.width
        icon: "signal"
        title: "Signal Generator"
        subtitle: "Onboard test and measurement signals"
        showSwitch: false
        accessories: [
            Rectangle {
                id: pill
                readonly property color tint: win.stateColors[siggen.state] || win.stateColors[0]
                width: pillRow.width + 20
                height: 24
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: Qt.rgba(tint.r, tint.g, tint.b, siggen.running ? 0.5 : 0.2)
                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        id: stateDot
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: pill.tint
                        SequentialAnimation on scale {
                            running: siggen.running && win.visible
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) stateDot.scale = 1
                            NumberAnimation { to: 0.75; duration: 700; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }
                    Text {
                        text: win.stateNames[siggen.state] || "Idle"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Qt.rgba(1, 1, 1, siggen.running ? 0.9 : 0.55)
                    }
                }
            }
        ]
    }
    Rectangle { id: headerRule; anchors.top: header.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    // ── Firmware without a generator ──
    Column {
        visible: bridge.connected && !siggen.supported
        anchors.centerIn: body
        spacing: 8
        width: 360
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "signal"; size: 32; color: Qt.rgba(1, 1, 1, 0.35) }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Signal generator not available"; font.pixelSize: 13; font.weight: Font.DemiBold; color: Qt.rgba(1, 1, 1, 0.85) }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "The connected firmware does not include the onboard test signal generator. Update the DSPi firmware to use this tool."
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // ── Body ──
    Item {
        id: body
        anchors.top: headerRule.bottom
        anchors.bottom: transportRule.top
        width: parent.width
        visible: !bridge.connected || siggen.supported
        enabled: bridge.connected && siggen.supported

        // Left: signal, outputs, level (scrolls in a short window)
        Flickable {
            id: leftFlick
            width: leftColumn.width + 32
            height: parent.height
            contentHeight: leftColumn.height + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

        Column {
            id: leftColumn
            x: 16
            y: 14
            width: 360
            spacing: 16

            Column {
                width: parent.width
                spacing: 8
                SectionLabel { text: "SIGNAL" }
                Grid {
                    columns: 5
                    spacing: 6
                    Repeater {
                        model: win.types
                        Rectangle {
                            readonly property bool selected: win.d.type === index
                            width: (leftColumn.width - 24) / 5
                            height: 42
                            radius: 7
                            color: selected ? Qt.rgba(0.04, 0.49, 1, 0.16) : tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                            border.color: selected ? Qt.rgba(0.04, 0.49, 1, 0.7) : Qt.rgba(1, 1, 1, 0.08)
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                SiggenGlyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 46; height: 20
                                    type: index
                                    color: parent.parent.selected ? "#3a96ff" : Qt.rgba(1, 1, 1, 0.6)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.tile
                                    font.pixelSize: 10
                                    font.weight: parent.parent.selected ? Font.DemiBold : Font.Normal
                                    color: Qt.rgba(1, 1, 1, parent.parent.selected ? 0.95 : 0.7)
                                }
                            }
                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: siggen.selectType(index)
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 600
                                ToolTip.text: modelData.name + ": " + modelData.blurb
                            }
                        }
                    }
                }
                Caption { text: win.types[win.d.type].blurb }
            }

            Column {
                width: parent.width
                spacing: 8
                RowLayout {
                    width: parent.width
                    SectionLabel { text: "OUTPUTS" }
                    Item { Layout.fillWidth: true }
                    LinkText { text: "All"; onClicked: siggen.selectAllOutputs() }
                    LinkText { text: "None"; onClicked: siggen.clearOutputs() }
                }
                Grid {
                    columns: 3
                    spacing: 6
                    Repeater {
                        model: win.outputCount
                        Rectangle {
                            readonly property bool on: (win.d.channelMask >> index & 1) === 1
                            readonly property bool inverted: (win.d.invertMask >> index & 1) === 1
                            readonly property bool walkActive: siggen.running && siggen.activeChannel === index
                            readonly property bool silent: (win.rev, !bridge.outputEnabled(index))
                            width: (leftColumn.width - 12) / 3
                            height: 26
                            radius: 6
                            opacity: silent ? 0.4 : 1
                            color: on ? Qt.rgba(0.04, 0.49, 1, 0.18) : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                            border.width: walkActive ? 1.5 : 1
                            border.color: walkActive ? "#32d74b" : on ? Qt.rgba(0.04, 0.49, 1, 0.6) : Qt.rgba(1, 1, 1, 0.08)
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: win.outputName(index)
                                    font.pixelSize: 11
                                    font.weight: parent.parent.on ? Font.DemiBold : Font.Normal
                                    color: Qt.rgba(1, 1, 1, parent.parent.on ? 0.95 : 0.65)
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, (leftColumn.width - 12) / 3 - 26)
                                }
                                Text {
                                    visible: parent.parent.inverted
                                    text: "ø"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: "#ff9f0a"
                                }
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: siggen.cycleOutput(index)
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 600
                                ToolTip.text: parent.silent ? "Output disabled in the matrix mixer: selected but silent until enabled"
                                                            : "Click: on → inverted → off"
                            }
                        }
                    }
                }
                Caption { text: "Click to select, click again to invert polarity (ø). Dimmed outputs are disabled in the matrix mixer and stay silent." }
            }

            Column {
                width: parent.width
                spacing: 6
                RowLayout {
                    width: parent.width
                    SectionLabel { text: "LEVEL" }
                    Item { Layout.fillWidth: true }
                    ValueField {
                        fieldWidth: 60; height: 24; suffix: "dB"; decimals: 1; wheelStep: 1
                        minValue: -120; maxValue: 0
                        value: win.d.levelDb
                        onValueEdited: siggen.setDraftValue("levelDb", newValue)
                    }
                }
                StyledSlider {
                    width: parent.width
                    from: -80; to: 0; stepSize: 0.5
                    value: win.d.levelDb
                    onMoved: siggen.setDraftValue("levelDb", value)
                }
                Caption { text: "Peak level in dBFS. Output trim, master volume and mute still apply downstream." }
            }
        }
        }

        Rectangle { id: colRule; x: leftFlick.width; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.08) }

        // Right: parameters, timing, options
        Flickable {
            anchors.left: colRule.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            contentHeight: rightColumn.height + 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: rightColumn
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 16

                // PARAMETERS
                Column {
                    readonly property var params: win.info.params || []
                    readonly property bool any: params.some(function (p) { return p.semantic !== 0 })
                    visible: any
                    width: parent.width
                    spacing: 4
                    SectionLabel { text: "PARAMETERS" }
                    Repeater {
                        model: win.d.type === 13 ? [] : parent.params
                        FieldRow {
                            visible: modelData.semantic !== 0
                            height: visible ? 28 : 0
                            readonly property int sem: modelData.semantic
                            label: (win.types[win.d.type].labels[index]) || "Value"
                            suffix: sem === 1 ? "Hz" : sem === 2 ? "ms" : sem === 3 ? "cyc" : sem === 5 ? "×" : ""
                            decimals: sem === 3 || sem === 4 ? 0 : sem === 5 ? 2 : 1
                            wheelStep: sem === 5 ? 0.1 : 1
                            minValue: modelData.min
                            maxValue: modelData.max > 0 ? modelData.max : 1e9
                            value: win.d.p[index]
                            onEdited: siggen.setParam(index, v)
                        }
                    }
                    // ISP: which over pattern
                    SegmentedControl {
                        visible: win.d.type === 13
                        width: parent.width
                        model: ["fs/4 · +3.01 dBTP", "fs/6 · +1.25 dBTP"]
                        currentIndex: win.d.p[0] >= 0.5 ? 1 : 0
                        onActivated: siggen.setParam(0, index)
                        tips: ["Alternating +1 +1 -1 -1 samples: the reconstructed peak is 3.01 dB over the samples",
                               "A sample pattern at fs/6: the reconstructed peak is 1.25 dB over the samples"]
                    }
                    Row {
                        visible: win.d.type === 11
                        spacing: 10
                        Text { text: "Presets:"; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
                        LinkText { text: "SMPTE 60/7k"; onClicked: { siggen.setParam(0, 60); siggen.setParam(1, 7000); siggen.setParam(2, 4) } }
                        LinkText { text: "CCIF 19k/20k"; onClicked: { siggen.setParam(0, 19000); siggen.setParam(1, 20000); siggen.setParam(2, 1) } }
                    }
                    Caption {
                        visible: win.d.type === 12 && siggen.multitoneMax > 0
                        text: "Up to " + siggen.multitoneMax + " tones on this device."
                    }
                }

                // TIMING
                Column {
                    width: parent.width
                    spacing: 4
                    SectionLabel { text: "TIMING" }
                    // Sweep
                    FieldRow {
                        visible: win.timing === 1
                        label: "Sweep length"
                        suffix: "s"; decimals: 2; wheelStep: 0.5; minValue: 0.01; maxValue: 3600
                        value: win.d.durationMs / 1000
                        onEdited: siggen.setDraftValue("durationMs", Math.round(v * 1000))
                    }
                    FieldRow {
                        visible: win.timing !== 0 || win.walking
                        label: win.timing === 0 ? "Passes" : "Repeat"
                        caption: win.timing === 1 ? "0 = repeat forever"
                               : win.d.type === 14 ? "Passes over the selected outputs. 0 = forever"
                               : win.timing === 2 ? "Pattern periods. 0 = repeat forever"
                               : "Full passes over the outputs. 0 = forever"
                        decimals: 0; wheelStep: 1; minValue: 0; maxValue: 65535
                        value: win.d.repeat
                        onEdited: siggen.setDraftValue("repeat", Math.round(v))
                    }
                    FieldRow {
                        visible: win.timing !== 0
                        label: win.timing === 1 ? "Gap between sweeps" : "Extra gap per period"
                        suffix: "ms"; decimals: 0; wheelStep: 50; minValue: 0; maxValue: 65535
                        value: win.d.gapMs
                        onEdited: siggen.setDraftValue("gapMs", Math.round(v))
                    }
                    // Continuous
                    FieldRow {
                        visible: win.timing === 0
                        label: win.walking ? "Dwell per channel" : "Duration"
                        caption: win.walking ? "0 = 2 s default" : "0 = play until stopped"
                        suffix: "s"; decimals: 2; wheelStep: 0.5; minValue: 0; maxValue: 86400
                        value: win.d.durationMs / 1000
                        onEdited: siggen.setDraftValue("durationMs", Math.round(v * 1000))
                    }
                }

                // OPTIONS
                Column {
                    width: parent.width
                    spacing: 8
                    SectionLabel { text: "OPTIONS" }
                    OptionRow {
                        title: "Bypass output EQ (RAW)"
                        caption: "Skips crossover and PEQ on the selected outputs. Trim, master volume, mute and delay still apply."
                        checked: (win.d.flags & 1) !== 0
                        onToggled: on ? rawDialog.open() : siggen.setFlag(1, false)
                    }
                    OptionRow {
                        visible: win.d.type === 2 || win.d.type === 3
                        title: "Decorrelate channels"
                        caption: "Independent noise per output instead of one copied signal."
                        checked: (win.d.flags & 2) !== 0
                        onToggled: siggen.setFlag(2, on)
                    }
                    OptionRow {
                        title: "Walk outputs one at a time"
                        caption: win.d.type === 14 ? "Channel ID always walks: each output plays its channel number as counted blips."
                                                   : "Plays the selected outputs sequentially instead of together."
                        enabled: win.d.type !== 14
                        checked: win.walking
                        onToggled: siggen.setFlag(4, on)
                    }
                }
            }
        }
    }

    // ── Transport ──
    Rectangle { id: transportRule; anchors.bottom: transport.top; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
    Item {
        id: transport
        anchors.bottom: parent.bottom
        width: parent.width
        height: 54
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: buttons.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: Qt.rgba(1, 1, 1, 0.9)
                text: siggen.running ? win.stateNames[siggen.state] + " · " + win.typeName(siggen.signalType)
                    : win.blocker !== "" && bridge.connected && siggen.supported ? win.blocker
                    : "Ready · " + win.typeName(win.d.type)
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.5)
                text: {
                    if (siggen.running) {
                        var parts = [win.fmtTime(siggen.elapsedMs)]
                        if (siggen.currentFreq > 0)
                            parts.push(siggen.currentFreq >= 1000 ? (siggen.currentFreq / 1000).toFixed(2) + " kHz" : siggen.currentFreq.toFixed(0) + " Hz")
                        if (siggen.cyclesDone > 0) parts.push("cycle " + siggen.cyclesDone)
                        if (siggen.activeChannel >= 0) parts.push(win.outputName(siggen.activeChannel))
                        parts.push("edits apply live")
                        return parts.join(" · ")
                    }
                    if (siggen.stopReason === 2) return "Finished after " + win.fmtTime(siggen.elapsedMs)
                    if (siggen.stopReason === 1) return "Stopped"
                    if (siggen.stopReason === 3) return "Stopped by preset load"
                    var n = win.popcount(win.d.channelMask)
                    return n + (n === 1 ? " output" : " outputs") + " · peak " + win.d.levelDb.toFixed(1) + " dBFS"
                }
            }
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            // Stop now (no fade)
            Rectangle {
                visible: siggen.running
                width: 30; height: 28; radius: 8
                color: nowMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : nowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.18)
                Icon { anchors.centerIn: parent; name: "stop"; size: 13; color: Qt.rgba(1, 1, 1, 0.8) }
                MouseArea {
                    id: nowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: siggen.stopNow()
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: "Stop immediately, no fade"
                }
            }
            // Start / Stop
            Rectangle {
                readonly property bool canStart: win.blocker === ""
                width: mainRow.width + 28
                height: 28
                radius: 8
                opacity: siggen.running || canStart ? 1 : 0.4
                color: siggen.running ? (mainMouse.pressed ? "#b52e35" : "#d9363e")
                                      : (mainMouse.pressed ? "#0868d6" : "#0a7cff")
                Row {
                    id: mainRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: siggen.running ? "stop" : "play"; size: 13; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: siggen.running ? "Stop" : "Start"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    id: mainMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: siggen.running || parent.canStart
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.startOrStop()
                }
                ToolTip.visible: mainHover.containsMouse && !parent.canStart && !siggen.running
                ToolTip.delay: 400
                ToolTip.text: win.blocker
                MouseArea { id: mainHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
        }
    }

    AppDialog {
        id: rawDialog
        icon: "warning"
        iconTint: "#ff9f0a"
        title: "Bypass the Output EQ?"
        message: "The signal skips each selected output's crossover and PEQ. A full-range signal can damage a tweeter or other driver that relies on its crossover for protection."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "bypass", text: "Bypass", role: "destructive" }
        ]
        onChosen: if (key === "bypass") siggen.setFlag(1, true)
    }

    AppDialog {
        id: rejectedDialog
        icon: "warning"
        iconTint: "#ff9f0a"
        title: "Signal Refused"
        message: "The device declined the signal configuration."
        buttons: [{ key: "ok", text: "OK", role: "primary" }]
    }
}
