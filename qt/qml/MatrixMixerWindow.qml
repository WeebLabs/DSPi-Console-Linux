import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Matrix Mixer: inputs (rows) to outputs (columns), plus each output's
// enable, gain, delay and mute. Laid out as on the macOS Console.
Window {
    id: matrixWindow
    title: "Matrix Mixer"
    visible: false
    color: "#232325"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    readonly property int colWidth: 80
    readonly property int labelWidth: 96
    readonly property int rowHeight: 78
    readonly property int numOut: bridge.numOutputChannels
    // Inputs carrying audio right now (at least the stereo pair)
    readonly property int inputCount: Math.min(bridge.numInputChannels, Math.max(2, bridge.activeInputChannels))
    readonly property bool multichannel: inputCount > 2
    readonly property int pdm: numOut - 1

    property int rev: 0
    Connections { target: bridge; function onStateChanged() { matrixWindow.rev++ } }

    // Size to the content; with many inputs the window can be resized and scrolls
    readonly property int contentW: card.implicitWidth + 32
    readonly property int contentH: card.implicitHeight + 32
    width: Math.min(contentW, Screen.desktopAvailableWidth - 40)
    height: Math.min(contentH, Screen.desktopAvailableHeight - 80)
    minimumWidth: Math.min(contentW, 480)
    minimumHeight: Math.min(contentH, 360)
    onContentWChanged: width = Math.min(contentW, Screen.desktopAvailableWidth - 40)
    onContentHChanged: height = Math.min(contentH, Screen.desktopAvailableHeight - 80)

    function inName(i) { return bridge.channelName(bridge.inputAppId(i)) }
    function inColor(i) { return bridge.channelColor(bridge.inputAppId(i)) }
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

    component SmallLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    component SmallButton: Rectangle {
        property alias label: lbl.text
        signal clicked()
        width: lbl.implicitWidth + 18
        height: 22
        radius: 5
        color: sbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14)
        Text { id: lbl; anchors.centerIn: parent; font.pixelSize: 12; color: "white" }
        MouseArea { id: sbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: card.implicitWidth + 32
        contentHeight: card.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        ScrollBar.horizontal: ScrollBar {}

        Rectangle {
            id: card
            x: 16; y: 16
            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight
            width: implicitWidth
            height: implicitHeight
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.025)
            border.color: Qt.rgba(1, 1, 1, 0.1)

            Column {
                id: content

                // ── Column headers ──
                Row {
                    height: 56
                    Item { width: labelWidth; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            id: hdr
                            width: colWidth
                            height: 56
                            property bool renaming: false
                            opacity: outEnabled(index) ? 1.0 : 0.4
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
                                    color: Qt.rgba(1, 1, 1, 0.75)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "OUT" + (index + 1)
                                    font.pixelSize: 10; font.weight: Font.Bold
                                    color: bridge.channelColor(index + 2)
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
                                onClicked: hdrMenu.popup()
                            }
                            Menu {
                                id: hdrMenu
                                MenuItem {
                                    text: "Rename"
                                    onTriggered: {
                                        hdr.renaming = true
                                        renameField.text = bridge.channelName(index + 2)
                                        renameField.forceActiveFocus()
                                        renameField.selectAll()
                                    }
                                }
                                MenuSeparator {}
                                MenuItem { text: "Copy Parameters"; onTriggered: bridge.copyChannel(index + 2) }
                                MenuItem { text: "Paste Parameters"; onTriggered: bridge.pasteChannel(index + 2) }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                // ── ROUTING ──
                Rectangle {
                    width: parent.width
                    height: 34
                    color: Qt.rgba(1, 1, 1, 0.03)
                    SmallLabel { text: "ROUTING"; x: 16; anchors.verticalCenter: parent.verticalCenter }
                    Row {
                        visible: multichannel
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        SmallButton { label: "Direct 1:1"; onClicked: bridge.directRouting() }
                        SmallButton { label: "Clear"; onClicked: bridge.clearRouting() }
                    }
                }

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
                                    minValue: -60; maxValue: 12; plainWheel: true
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
                                    opacity: outEnabled(o) ? 1.0 : 0.4

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
                                        border.color: parent.conflictRing ? "#ff9f0a"
                                                    : pointMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.22)
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
                                        color: parent.inverted ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.35)
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
                        Rectangle {
                            visible: inputIndex % 2 === 1 && inputIndex < inputCount - 1
                            x: labelWidth
                            width: numOut * colWidth
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.06)
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                // ── OUTPUT ──
                Rectangle {
                    width: parent.width
                    height: 34
                    color: Qt.rgba(1, 1, 1, 0.03)
                    SmallLabel { text: "OUTPUT"; x: 16; anchors.verticalCenter: parent.verticalCenter }
                }

                // ENABLE
                Row {
                    height: 40
                    SmallLabel { width: labelWidth - 12; horizontalAlignment: Text.AlignRight; text: "ENABLE"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 12; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 40
                            readonly property bool isOn: outEnabled(index)
                            readonly property bool wouldConflict: !isOn && conflicts(index).length > 0
                            Icon {
                                anchors.centerIn: parent
                                name: "power"
                                size: 20
                                color: parent.wouldConflict ? "#ff9f0a" : parent.isOn ? "#3a96dd" : Qt.rgba(1, 1, 1, 0.3)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toggleEnable(index)
                            }
                        }
                    }
                }

                // GAIN
                Row {
                    height: 36
                    SmallLabel { width: labelWidth - 12; horizontalAlignment: Text.AlignRight; text: "GAIN"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 12; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 36
                            opacity: outEnabled(index) ? 1.0 : 0.4
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

                // DELAY
                Row {
                    height: 36
                    SmallLabel { width: labelWidth - 12; horizontalAlignment: Text.AlignRight; text: "DELAY"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 12; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 36
                            opacity: outEnabled(index) ? 1.0 : 0.4
                            ValueField {
                                anchors.centerIn: parent
                                fieldWidth: 44; height: 22; suffix: "ms"; decimals: 0; wheelStep: 1
                                minValue: 0; maxValue: bridge.maxDelayMs; plainWheel: true
                                value: { rev; return bridge.outputDelayMS(index) }
                                onValueEdited: bridge.setOutputDelay(index, newValue)
                            }
                        }
                    }
                }

                // MUTE
                Row {
                    height: 40
                    SmallLabel { width: labelWidth - 12; horizontalAlignment: Text.AlignRight; text: "MUTE"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 12; height: 1 }
                    Repeater {
                        model: numOut
                        Item {
                            width: colWidth; height: 40
                            opacity: outEnabled(index) ? 1.0 : 0.4
                            readonly property bool muted: { rev; return bridge.outputMuted(index) }
                            Icon {
                                anchors.centerIn: parent
                                name: parent.muted ? "speaker-mute" : "speaker"
                                size: 20
                                color: parent.muted ? "#ff453a" : Qt.rgba(1, 1, 1, 0.5)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bridge.setOutputMute(index, !parent.muted)
                            }
                        }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }
    }

    // PDM and the Core 1 EQ-worker outputs cannot run together
    Dialog {
        id: pdmDialog
        property int output: 0
        property var conflicting: []
        readonly property bool enablingPdm: output === pdm
        title: enablingPdm ? "Enable PDM?" : "Disable PDM?"
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380

        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
                var names = pdmDialog.conflicting.map(function (o) { return "OUT" + (o + 1) }).join(", ")
                return pdmDialog.enablingPdm
                    ? "The PDM output shares a processor core with " + names + ". Enabling PDM disables them."
                    : "OUT" + (pdmDialog.output + 1) + " shares a processor core with the PDM output. Enabling it disables PDM."
            }
        }
        footer: DialogButtonBox {
            Button {
                text: pdmDialog.enablingPdm ? "Enable PDM" : "Disable PDM"
                onClicked: { bridge.enableOutputResolvingConflict(pdmDialog.output); pdmDialog.close() }
            }
            Button { text: "Cancel"; onClicked: pdmDialog.close() }
        }
    }
}
