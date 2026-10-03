import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

// Settings card of an output channel page: routing preview, gain, delay,
// mute and the output limiter.
Rectangle {
    id: settingsRoot
    height: 76
    radius: 10
    color: Qt.rgba(0.21, 0.21, 0.21, 0.6)
    border.color: Qt.rgba(0.5, 0.5, 0.5, 0.2)
    border.width: 1

    property int outputIndex: 0
    property real gainDB: bridge.outputGainDB(outputIndex)
    property real delayMS: bridge.outputDelayMS(outputIndex)
    property bool isMuted: bridge.outputMuted(outputIndex)
    property int routingRev: 0   // bumps on state change so routing bindings re-read

    Connections {
        target: bridge
        function onStateChanged() {
            if (!gainSlider.pressed) gainDB = bridge.outputGainDB(outputIndex)
            if (!delaySlider.pressed) delayMS = bridge.outputDelayMS(outputIndex)
            isMuted = bridge.outputMuted(outputIndex)
            routingRev++
        }
    }

    component SectionLabel: Text {
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(1, 1, 1, 0.45)
    }

    component CardSlider: Slider {
        id: sl
        property real resetValue: 0
        signal reset()
        height: 20
        topPadding: 0
        bottomPadding: 0
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: sl.reset()
        }
        background: Rectangle {
            x: sl.leftPadding
            y: (sl.height - height) / 2
            width: sl.availableWidth
            height: 3; radius: 2
            color: Qt.rgba(1, 1, 1, 0.15)
            Rectangle {
                width: sl.visualPosition * parent.width
                height: parent.height; radius: 2
                color: "#0078d4"
            }
        }
        handle: Rectangle {
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: (sl.height - height) / 2
            width: 12; height: 12; radius: 6; color: "white"
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: 14
        spacing: 14

        // 1. Routing preview: inputs 1 and 2 into this output
        Column {
            id: routing
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: 2
                Row {
                    spacing: 6
                    readonly property bool connected: { settingsRoot.routingRev; return bridge.matrixRouting(index, outputIndex) }
                    readonly property real level: { settingsRoot.routingRev; return bridge.matrixGain(index, outputIndex) }
                    readonly property bool inverted: { settingsRoot.routingRev; return bridge.matrixInvert(index, outputIndex) }

                    Text {
                        width: 54
                        text: bridge.channelName(bridge.inputAppId(index))
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: parent.connected ? bridge.channelColor(bridge.inputAppId(index)) : Qt.rgba(1, 1, 1, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bridge.setMatrixRoute(index, outputIndex, !parent.parent.connected,
                                                             parent.parent.level, parent.parent.inverted)
                        }
                    }
                    Item {
                        id: levelCell
                        readonly property var routeRow: parent
                        width: levelField.width
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        ValueField {
                            id: levelField
                            fieldWidth: 46; suffix: "dB"; decimals: 1; minValue: -60; maxValue: 12
                            height: 20
                            value: levelCell.routeRow.level
                            opacity: levelCell.routeRow.connected ? 1.0 : 0.45
                            onValueEdited: bridge.setMatrixRoute(index, outputIndex, levelCell.routeRow.connected,
                                                                 newValue, levelCell.routeRow.inverted)
                        }
                        // Right-click resets the level to 0 dB
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: bridge.setMatrixRoute(index, outputIndex, levelCell.routeRow.connected,
                                                             0, levelCell.routeRow.inverted)
                        }
                    }
                    Rectangle {
                        width: 30; height: 18; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.inverted ? Qt.rgba(1, 0.6, 0.2, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                        Text {
                            anchors.centerIn: parent
                            text: "INV"
                            font.pixelSize: 9; font.weight: Font.Bold
                            color: parent.parent.inverted ? "#ff9800" : Qt.rgba(1, 1, 1, 0.4)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bridge.setMatrixRoute(index, outputIndex, parent.parent.connected,
                                                             parent.parent.level, !parent.parent.inverted)
                        }
                    }
                }
            }
        }

        Rectangle { width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.1) }

        // 2. Gain and 3. Delay
        Column {
            id: levels
            width: settingsRoot.width - routing.width - sideButtons.width - 90
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: 8
                width: parent.width
                SectionLabel { text: "GAIN"; width: 42; anchors.verticalCenter: parent.verticalCenter }
                ValueField {
                    fieldWidth: 54; height: 20; suffix: "dB"; decimals: 1; minValue: -60; maxValue: 10
                    value: gainDB
                    onValueEdited: bridge.setOutputGain(outputIndex, newValue)
                }
                CardSlider {
                    id: gainSlider
                    width: parent.width - 140
                    from: -60; to: 10; stepSize: 0.1
                    value: gainDB
                    anchors.verticalCenter: parent.verticalCenter
                    onMoved: bridge.sendOutputGainToDevice(outputIndex, value)
                    onPressedChanged: if (!pressed) bridge.setOutputGain(outputIndex, value)
                    onReset: bridge.setOutputGain(outputIndex, 0)
                }
            }

            Row {
                spacing: 8
                width: parent.width
                SectionLabel { text: "DELAY"; width: 42; anchors.verticalCenter: parent.verticalCenter }
                ValueField {
                    fieldWidth: 54; height: 20; suffix: "ms"; decimals: 0; minValue: 0; maxValue: bridge.maxDelayMs
                    value: delayMS
                    onValueEdited: bridge.setOutputDelay(outputIndex, newValue)
                }
                CardSlider {
                    id: delaySlider
                    width: parent.width - 140
                    from: 0; to: bridge.maxDelayMs; stepSize: 1
                    value: delayMS
                    anchors.verticalCenter: parent.verticalCenter
                    onMoved: bridge.sendOutputDelayToDevice(outputIndex, value)
                    onPressedChanged: if (!pressed) bridge.setOutputDelay(outputIndex, value)
                    onReset: bridge.setOutputDelay(outputIndex, 0)
                }
            }
        }

        Rectangle { width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.1) }

        // 4. Mute and 5. Limiter
        Column {
            id: sideButtons
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                width: 36; height: 28; radius: 5
                color: isMuted ? Qt.rgba(1, 0, 0, 0.12) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: isMuted ? "🔇" : "🔊"
                    font.pixelSize: 16
                    color: isMuted ? "#f44336" : Qt.rgba(1, 1, 1, 0.4)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bridge.setOutputMute(outputIndex, !isMuted)
                }
            }

            LimiterButton { outputIndex: settingsRoot.outputIndex }
        }
    }
}
