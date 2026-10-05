import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "components"

// Settings card of an output channel page, laid out as on the macOS Console:
// routing preview | GAIN | DELAY | mute and limiter, separated by dividers.
Rectangle {
    id: settingsRoot
    height: 72
    radius: 10
    // Same surface as the band list below it
    color: isMacOS ? Qt.rgba(0.21, 0.21, 0.21, 0.6) : nativeAltBaseColor
    border.color: Qt.rgba(1, 1, 1, 0.1)
    border.width: 1

    property int outputIndex: 0
    property real gainDB: bridge.outputGainDB(outputIndex)
    property real delayMS: bridge.outputDelayMS(outputIndex)
    property bool isMuted: bridge.outputMuted(outputIndex)
    property int routingRev: 0   // bumps on state change so routing bindings re-read

    Connections {
        target: bridge
        function onStateChanged() {
            if (!gainSection.dragging) gainDB = bridge.outputGainDB(outputIndex)
            if (!delaySection.dragging) delayMS = bridge.outputDelayMS(outputIndex)
            isMuted = bridge.outputMuted(outputIndex)
            routingRev++
        }
    }

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    component Divider: Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }

    // Slider that resets on right-click
    component CardSlider: StyledSlider {
        id: sl
        signal reset()
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: sl.reset()
        }
    }

    // GAIN / DELAY: label and value on top, slider underneath. The value
    // follows the slider during a drag; the device gets live updates (moved,
    // at most every 30 ms), and release or typing commits (committed).
    component LevelSection: ColumnLayout {
        id: sec
        property string label: ""
        property string unit: ""
        property int decimals: 1
        property real value: 0
        property real from: 0
        property real to: 100
        property real stepSize: 1
        readonly property bool dragging: slider.pressed
        // What the field and slider show: the dragged value until the
        // stored value catches up, so release never flashes the old one
        property real shown: value
        onValueChanged: if (!slider.pressed) shown = value
        signal moved(real v)
        signal committed(real v)
        signal reset()

        spacing: 6
        Layout.fillWidth: true
        Layout.leftMargin: 18
        Layout.rightMargin: 18
        Layout.alignment: Qt.AlignVCenter

        RowLayout {
            Layout.fillWidth: true
            SectionLabel { text: sec.label }
            Item { Layout.fillWidth: true }
            ValueField {
                fieldWidth: 54; height: 22
                suffix: sec.unit; decimals: sec.decimals; wheelStep: sec.stepSize
                minValue: sec.from; maxValue: sec.to
                value: sec.shown
                onValueEdited: sec.committed(newValue)
            }
        }
        CardSlider {
            id: slider
            Layout.fillWidth: true
            from: sec.from; to: sec.to; stepSize: sec.stepSize
            value: sec.shown
            // A press that didn't move commits nothing, so a value set
            // outside the slider's range elsewhere stays as it is
            property bool dragged: false
            onMoved: { dragged = true; sec.shown = value; live.push(value) }
            onPressedChanged: if (!pressed) {
                live.cancel()
                if (dragged) sec.committed(value)
                dragged = false
            }
            onReset: sec.reset()
            Throttle { id: live; onFire: sec.moved(value) }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Routing preview: inputs 1 and 2 into this output ──
        Column {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            spacing: 2

            Repeater {
                model: 2
                Row {
                    id: route
                    spacing: 8
                    height: 26
                    readonly property bool connected: { settingsRoot.routingRev; return bridge.matrixRouting(index, outputIndex) }
                    readonly property real level: { settingsRoot.routingRev; return bridge.matrixGain(index, outputIndex) }
                    readonly property bool inverted: { settingsRoot.routingRev; return bridge.matrixInvert(index, outputIndex) }
                    readonly property color inputColor: bridge.channelColor(bridge.inputAppId(index))
                    function toggle() { bridge.setMatrixRoute(index, outputIndex, !connected, level, inverted) }

                    // Connection dot + name: click to connect / disconnect
                    Item {
                        width: 74
                        height: parent.height
                        Rectangle {
                            id: dot
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9; height: 9; radius: 4.5
                            color: route.connected ? route.inputColor : "transparent"
                            border.width: route.connected ? 0 : 1.2
                            border.color: Qt.rgba(1, 1, 1, 0.45)
                        }
                        Text {
                            anchors.left: dot.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: bridge.channelName(bridge.inputAppId(index))
                            font.pixelSize: 13
                            font.weight: route.connected ? Font.DemiBold : Font.Normal
                            color: route.connected ? route.inputColor : Qt.rgba(1, 1, 1, 0.75)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: route.toggle()
                        }
                    }

                    // Level (settable before connecting); right-click resets to 0 dB
                    Item {
                        width: levelField.width
                        height: parent.height
                        ValueField {
                            id: levelField
                            anchors.verticalCenter: parent.verticalCenter
                            fieldWidth: 44; height: 22; suffix: "dB"; decimals: 1
                            minValue: -60; maxValue: 12
                            value: route.level
                            textColor: route.connected ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.5)
                            onValueEdited: bridge.setMatrixRoute(index, outputIndex, route.connected, newValue, route.inverted)
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: bridge.setMatrixRoute(index, outputIndex, route.connected, 0, route.inverted)
                        }
                    }

                    // Polarity
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "INV"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: route.inverted ? "#ff9f0a" : Qt.rgba(1, 1, 1, route.connected ? 0.35 : 0.2)
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bridge.setMatrixRoute(index, outputIndex, route.connected, route.level, !route.inverted)
                        }
                    }
                }
            }
        }

        Divider {}

        // ── Gain ──
        LevelSection {
            id: gainSection
            label: "GAIN"; unit: "dB"; decimals: 1
            from: -60; to: 12; stepSize: 0.1      // the firmware's output gain range
            value: gainDB
            onMoved: bridge.sendOutputGainToDevice(outputIndex, v)
            onCommitted: { gainDB = v; bridge.setOutputGain(outputIndex, v) }
            onReset: bridge.setOutputGain(outputIndex, 0)
        }

        Divider {}

        // ── Delay ──
        LevelSection {
            id: delaySection
            label: "DELAY"; unit: "ms"; decimals: 0
            from: 0; to: bridge.maxDelayMs; stepSize: 1
            value: delayMS
            onMoved: bridge.sendOutputDelayToDevice(outputIndex, v)
            onCommitted: { delayMS = v; bridge.setOutputDelay(outputIndex, v) }
            onReset: bridge.setOutputDelay(outputIndex, 0)
        }

        Divider {}

        // ── Mute and output limiter ──
        Column {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            spacing: 4

            Rectangle {
                width: 36; height: 26; radius: 6
                color: muteMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                Icon {
                    anchors.centerIn: parent
                    name: isMuted ? "speaker-mute" : "speaker"
                    size: 18
                    color: isMuted ? "#ff453a" : Qt.rgba(1, 1, 1, 0.6)
                }
                MouseArea {
                    id: muteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bridge.setOutputMute(outputIndex, !isMuted)
                }
            }

            LimiterButton { outputIndex: settingsRoot.outputIndex; height: 26 }
        }
    }
}
