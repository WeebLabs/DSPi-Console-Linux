import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Matrix Mixer: inputs (rows) to outputs (columns), plus each output's
// enable, gain, delay and mute. Laid out as on the macOS Console, styled
// like the Settings cards.
AppWindow {
    id: matrixWindow
    title: "Matrix Mixer"
    visible: false

    // ── App palette ──
    readonly property color accent: isMacOS ? MacColors.blue : "#0a7cff"
    readonly property color warn: isMacOS ? MacColors.orange : "#ff9f0a"
    readonly property color danger: isMacOS ? MacColors.red : "#ff453a"
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.07)
    readonly property color cardFill: isMacOS ? MacColors.opacity(MacColors.controlBackground, 0.4) : Qt.rgba(1, 1, 1, 0.045)

    readonly property int colWidth: 80
    readonly property int labelWidth: 96
    readonly property int rowHeight: 78
    readonly property int numOut: bridge.numOutputChannels
    // On a stereo input the upmixer's Centre / Surround outputs are source
    // rows 3-5 (3 only with surround off); otherwise the inputs carrying
    // audio right now (at least the stereo pair)
    readonly property bool upmixRows: bridge.upmixSupported && bridge.upmixParams[0] > 0
                                      && Math.max(2, bridge.activeInputChannels) === 2
    readonly property int inputCount: upmixRows ? (bridge.upmixParams[2] === 0 ? 3 : 5)
                                    : Math.min(bridge.numInputChannels, Math.max(2, bridge.activeInputChannels))
    readonly property bool multichannel: !upmixRows && inputCount > 2
    readonly property int pdm: numOut - 1
    readonly property int gridWidth: labelWidth + numOut * colWidth + 12

    property int rev: 0
    Connections { target: bridge; function onStateChanged() { matrixWindow.rev++ } }

    // Size to the content; with many inputs the window can be resized and scrolls
    readonly property int contentW: body.implicitWidth + 48
    readonly property int contentH: body.implicitHeight + 22 + titlebarHeight
    width: Math.min(contentW, Screen.desktopAvailableWidth - 40)
    height: Math.min(contentH, Screen.desktopAvailableHeight - 80)
    minimumWidth: Math.min(contentW, 480)
    minimumHeight: Math.min(contentH, 360)
    onContentWChanged: width = Math.min(contentW, Screen.desktopAvailableWidth - 40)
    onContentHChanged: height = Math.min(contentH, Screen.desktopAvailableHeight - 80)

    function inName(i) { return upmixRows && i >= 2 ? ["Upmix C", "Upmix Ls", "Upmix Rs"][i - 2] : bridge.channelName(bridge.inputAppId(i)) }
    function inColor(i) {
        if (upmixRows && i >= 2)
            return isMacOS ? [Qt.rgba(0.45, 0.78, 0.55, 1), Qt.rgba(0.93, 0.70, 0.30, 1), Qt.rgba(0.60, 0.55, 0.92, 1)][i - 2] : i === 2 && bridge.upmixParams[1] === 2 ? Qt.rgba(1, 1, 1, 0.35)   // centre off: silent row
                 : ["#32d74b", "#bf5af2", "#ff375f"][i - 2]
        return bridge.channelColor(bridge.inputAppId(i))
    }
    function outEnabled(o) { rev; return bridge.outputEnabled(o) }
    function conflicts(o) { rev; return bridge.core1ConflictOutputs(o) }

    function toggleEnable(o) {
        if (outEnabled(o)) { bridge.setOutputEnable(o, false); return }
        var c = conflicts(o)
        if (c.length === 0) { bridge.setOutputEnable(o, true); return }
        pdmDialog.output = o
        pdmDialog.conflicting = c
        pdmDialog.open()
    }

    // Section title above a card (as in Settings)
    component SectionTitle: Text {
        leftPadding: 4
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: isMacOS ? MacColors.opacity(MacColors.secondaryLabel, 0.5) : Qt.rgba(1, 1, 1, 0.6)
    }

    // Row label on the left of the Output card
    component RowLabel: Text {
        width: labelWidth - 14
        horizontalAlignment: Text.AlignRight
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55)
    }

    component CardButton: Rectangle {
        property alias label: lbl.text
        signal clicked()
        width: lbl.implicitWidth + 22
        height: 26
        radius: 7
        color: isMacOS ? MacColors.control : cbMouse.pressed ? Qt.rgba(1, 1, 1, 0.20) : cbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.09)
        border.color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.10)
        Text { id: lbl; anchors.centerIn: parent; font.pixelSize: 13; color: isMacOS ? MacColors.label : "white" }
        MouseArea { id: cbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    component Card: Rectangle {
        default property alias rows: cardColumn.data
        width: gridWidth
        height: cardColumn.implicitHeight
        radius: 10
        color: cardFill
        border.color: isMacOS ? Qt.rgba(1, 1, 1, 0.1) : hairline
        Column { id: cardColumn; width: parent.width }
    }

    component Hairline: Rectangle {
        x: 14
        width: gridWidth - 28
        height: 1
        color: isMacOS ? MacColors.opacity(MacColors.separator, 0.3) : hairline
    }

    Flickable {
        anchors.fill: parent
        contentWidth: body.implicitWidth + 48
        contentHeight: body.implicitHeight + 22
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        ScrollBar.horizontal: ScrollBar {}

        Column {
            id: body
            x: 24
            y: 2        // the titlebar already provides the top margin
            spacing: 8

            // ── Routing ──
            Item {
                width: gridWidth
                height: 28
                SectionTitle { text: "Routing"; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    visible: multichannel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    CardButton { label: "Direct 1:1"; onClicked: bridge.directRouting() }
                    CardButton { label: "Clear"; onClicked: bridge.clearRouting() }
                }
            }

            Card {
                // Column headers
                Row {
                    height: 58
                    Item { width: labelWidth; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            id: hdr
                            width: colWidth
                            height: 58
                            property bool renaming: false
                            opacity: isMacOS ? 1.0 : outEnabled(index) ? 1.0 : 0.4
                            Column {
                                visible: !hdr.renaming
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: colWidth - 6
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: { rev; return bridge.channelName(index + 2) }
                                    font.pixelSize: 13; font.weight: Font.DemiBold
                                    color: isMacOS ? MacColors.secondaryLabel : "white"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "OUT" + (index + 1)
                                    font.pixelSize: 10; font.weight: Font.Bold
                                    color: isMacOS ? MacColors.opacity(Qt.lighter(bridge.channelColor(index + 2), 1.0), 0.8) : bridge.channelColor(index + 2)
                                }
                            }
                            TextField {
                                id: renameField
                                visible: hdr.renaming
                                anchors.centerIn: parent
                                width: colWidth - 6
                                font.pixelSize: 12
                                maximumLength: 31
                                onAccepted: { if (text.trim() !== "") bridge.setChannelName(index + 2, text.trim()); hdr.renaming = false }
                                onActiveFocusChanged: if (!activeFocus) hdr.renaming = false
                                Keys.onEscapePressed: hdr.renaming = false
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !hdr.renaming
                                acceptedButtons: Qt.RightButton
                                onClicked: {
                                    hdrMenu.items = [
                                        { key: "rename", text: "Rename", icon: "pencil" },
                                        { separator: true },
                                        { key: "copy", text: "Copy Parameters", icon: "copy" },
                                        { key: "paste", text: "Paste Parameters", icon: "paste", enabled: bridge.canPaste() }
                                    ]
                                    if (bridge.connected && siggen.supported)
                                        hdrMenu.items = hdrMenu.items.concat([
                                            { separator: true },
                                            { key: "identify", text: "Identify", icon: "identify", enabled: bridge.outputEnabled(index) }
                                        ])
                                    hdrMenu.openAt(hdr, mouse.x, mouse.y)
                                }
                            }
                            ActionMenu {
                                id: hdrMenu
                                parent: Overlay.overlay
                                onTriggered: {
                                    if (key === "rename") {
                                        hdr.renaming = true
                                        renameField.text = bridge.channelName(index + 2)
                                        renameField.forceActiveFocus()
                                        renameField.selectAll()
                                    } else if (key === "copy") {
                                        bridge.copyChannel(index + 2)
                                    } else if (key === "paste") {
                                        bridge.pasteChannel(index + 2)
                                    } else if (key === "identify") {
                                        siggen.identify(index)
                                    }
                                }
                            }
                        }
                    }
                }

                Hairline {}

                // Input rows
                Repeater {
                    model: inputCount
                    Column {
                        readonly property int inputIndex: index
                        Row {
                            height: rowHeight
                            // Row label (and input trim on multichannel inputs)
                            Column {
                                width: labelWidth
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: labelWidth - 10
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: { rev; return inName(inputIndex) }
                                    font.pixelSize: 13; font.weight: Font.DemiBold
                                    color: inColor(inputIndex)
                                }
                                ValueField {
                                    visible: multichannel
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    fieldWidth: 50; height: 20; suffix: "dB"; decimals: 1
                                    minValue: -60; maxValue: bridge.preampMaxDB; plainWheel: true
                                    value: { rev; return bridge.inputPreampDB(inputIndex) }
                                    onValueEdited: bridge.setInputPreamp(inputIndex, newValue)
                                }
                            }
                            Repeater {
                                model: numOut
                                Item {
                                    width: colWidth
                                    height: rowHeight
                                    readonly property int o: index
                                    readonly property bool connected: { rev; return bridge.matrixRouting(inputIndex, o) }
                                    readonly property real gain: { rev; return bridge.matrixGain(inputIndex, o) }
                                    readonly property bool inverted: { rev; return bridge.matrixInvert(inputIndex, o) }
                                    // A PDM column that would displace enabled outputs
                                    readonly property bool conflictRing: o === pdm && !outEnabled(o) && conflicts(o).length > 0
                                    opacity: isMacOS ? (outEnabled(o) ? 1.0 : 0.3) : outEnabled(o) ? 1.0 : 0.4

                                    ValueField {
                                        visible: parent.connected
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 4
                                        fieldWidth: 44; height: 20; suffix: "dB"; decimals: 1
                                        minValue: -60; maxValue: 12; plainWheel: true
                                        value: parent.gain
                                        onValueEdited: bridge.setMatrixRoute(inputIndex, o, true, newValue, parent.inverted)
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22; height: 22; radius: 11
                                        color: parent.connected ? inColor(inputIndex) : "transparent"
                                        border.width: parent.connected ? 0 : 1.5
                                        border.color: isMacOS ? MacColors.opacity(parent.conflictRing ? MacColors.orange : MacColors.secondaryLabel, parent.conflictRing ? (pointMouse.containsMouse ? 0.5 : 0.35) : (pointMouse.containsMouse ? 0.3 : 0.12)) : parent.conflictRing ? warn
                                                    : pointMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.20)
                                        scale: pointMouse.containsMouse ? 1.08 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 90 } }
                                        MouseArea {
                                            id: pointMouse
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: bridge.setMatrixRoute(inputIndex, o, !parent.parent.connected,
                                                                             parent.parent.gain, parent.parent.inverted)
                                        }
                                    }
                                    Text {
                                        visible: parent.connected
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 6
                                        text: "INV"
                                        font.pixelSize: 10; font.weight: Font.Bold
                                        color: isMacOS ? (parent.inverted ? MacColors.orange : MacColors.opacity(MacColors.secondaryLabel, 0.3)) : parent.inverted ? warn : Qt.rgba(1, 1, 1, 0.35)
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: bridge.setMatrixRoute(inputIndex, o, true, parent.parent.gain,
                                                                             !parent.parent.inverted)
                                        }
                                    }
                                }
                            }
                        }
                        // Divider after each stereo pair
                        Hairline { visible: inputIndex % 2 === 1 && inputIndex < inputCount - 1 }
                    }
                }
            }

            Item { width: 1; height: 14 }

            // ── Output ──
            SectionTitle { text: "Output" }

            Card {
                // Enable
                Row {
                    height: 44
                    RowLabel { text: "Enable"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 14; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 44
                            readonly property bool isOn: outEnabled(index)
                            readonly property bool wouldConflict: !isOn && conflicts(index).length > 0
                            Icon {
                                anchors.centerIn: parent
                                name: "power"
                                size: 20
                                color: isMacOS ? (parent.isOn ? MacColors.blue : parent.wouldConflict ? MacColors.opacity(MacColors.orange, 0.4) : MacColors.opacity(MacColors.secondaryLabel, 0.3)) : parent.wouldConflict ? warn : parent.isOn ? accent : Qt.rgba(1, 1, 1, 0.3)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toggleEnable(index)
                            }
                        }
                    }
                }
                Hairline {}

                // Gain
                Row {
                    height: 40
                    RowLabel { text: "Gain"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 14; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 40
                            opacity: isMacOS ? (outEnabled(index) ? 1.0 : 0.3) : outEnabled(index) ? 1.0 : 0.4
                            ValueField {
                                anchors.centerIn: parent
                                fieldWidth: 44; height: 22; suffix: "dB"; decimals: 1
                                minValue: -60; maxValue: 12; plainWheel: true
                                value: { rev; return bridge.outputGainDB(index) }
                                onValueEdited: bridge.setOutputGain(index, newValue)
                            }
                        }
                    }
                }
                Hairline {}

                // Delay
                Row {
                    height: 40
                    RowLabel { text: "Delay"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 14; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 40
                            opacity: isMacOS ? (outEnabled(index) ? 1.0 : 0.3) : outEnabled(index) ? 1.0 : 0.4
                            ValueField {
                                anchors.centerIn: parent
                                fieldWidth: 60; height: 22; suffix: "ms"; decimals: 2; maxDecimals: 4; wheelStep: 1
                                minValue: 0; maxValue: bridge.maxDelayMs; plainWheel: true
                                value: { rev; return bridge.outputDelayMS(index) }
                                onValueEdited: bridge.setOutputDelay(index, newValue)
                            }
                        }
                    }
                }
                Hairline {}

                // Mute
                Row {
                    height: 44
                    RowLabel { text: "Mute"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 14; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 44
                            opacity: isMacOS ? (outEnabled(index) ? 1.0 : 0.3) : outEnabled(index) ? 1.0 : 0.4
                            readonly property bool muted: { rev; return bridge.outputMuted(index) }
                            Icon {
                                anchors.centerIn: parent
                                name: parent.muted ? "speaker-mute" : "speaker"
                                size: 20
                                color: isMacOS ? (parent.muted ? MacColors.red : MacColors.opacity(MacColors.secondaryLabel, 0.4)) : parent.muted ? danger : Qt.rgba(1, 1, 1, 0.5)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bridge.setOutputMute(index, !parent.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    // PDM and the Core 1 EQ-worker outputs cannot run together
    AppDialog {
        id: pdmDialog
        property int output: 0
        property var conflicting: []
        readonly property bool enablingPdm: output === pdm
        icon: "power"
        title: enablingPdm ? "Enable PDM?" : "Disable PDM?"
        message: {
            var names = pdmDialog.conflicting.map(function (o) { return "OUT" + (o + 1) }).join(", ")
            return pdmDialog.enablingPdm
                ? "The PDM output shares a processor core with " + names + ". Enabling PDM disables them."
                : "OUT" + (pdmDialog.output + 1) + " shares a processor core with the PDM output. Enabling it disables PDM."
        }
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "confirm", text: enablingPdm ? "Enable PDM" : "Disable PDM", role: "primary" }
        ]
        onChosen: if (key === "confirm") bridge.enableOutputResolvingConflict(pdmDialog.output)
    }
}
