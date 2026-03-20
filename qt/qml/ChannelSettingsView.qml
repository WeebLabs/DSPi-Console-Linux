import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

Rectangle {
    id: settingsRoot
    height: 60
    radius: 10
    color: Qt.rgba(0.21, 0.21, 0.21, 0.6)
    border.color: Qt.rgba(0.5, 0.5, 0.5, 0.2)
    border.width: 1

    property int outputIndex: 0
    property real gainDB: bridge.outputGainDB(outputIndex)
    property real delayMS: bridge.outputDelayMS(outputIndex)
    property bool isMuted: bridge.outputMuted(outputIndex)


    Connections {
        target: bridge
        function onStateChanged() {
            if (!gainSlider.pressed) gainDB = bridge.outputGainDB(outputIndex)
            if (!delaySlider.pressed) delayMS = bridge.outputDelayMS(outputIndex)
            isMuted = bridge.outputMuted(outputIndex)
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        anchors.rightMargin: 38
        spacing: 12

        // Gain section
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            width: (parent.width - muteBtn.width - 24) / 2

            Text {
                text: "\uD83D\uDD0A"  // speaker icon
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            ValueField {
                fieldWidth: 60
                value: gainDB
                suffix: "dB"
                decimals: 1
                minValue: -60
                maxValue: 10
                onValueEdited: bridge.setOutputGain(outputIndex, newValue)
                anchors.verticalCenter: parent.verticalCenter
            }

            Slider {
                id: gainSlider
                width: parent.width - 130
                height: 20
                topPadding: 0
                bottomPadding: 0
                from: -60; to: 10
                value: gainDB
                anchors.verticalCenter: parent.verticalCenter
                onMoved: bridge.sendOutputGainToDevice(outputIndex, value)
                onPressedChanged: {
                    if (!pressed) bridge.setOutputGain(outputIndex, value)
                }

                background: Rectangle {
                    x: gainSlider.leftPadding
                    y: (gainSlider.height - height) / 2
                    width: gainSlider.availableWidth
                    height: 3; radius: 2
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        width: gainSlider.visualPosition * parent.width
                        height: parent.height; radius: 2
                        color: "#0078d4"
                    }
                }
                handle: Rectangle {
                    x: gainSlider.leftPadding + gainSlider.visualPosition * (gainSlider.availableWidth - width)
                    y: (gainSlider.height - height) / 2
                    implicitWidth: 12; implicitHeight: 12
                    width: 12; height: 12; radius: 6; color: "white"
                }
            }
        }

        // Divider
        Rectangle { width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.1) }

        // Delay section
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            width: (parent.width - muteBtn.width - 24) / 2

            Text {
                text: "\u23F1"  // timer icon
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            ValueField {
                fieldWidth: 60
                value: delayMS
                suffix: "ms"
                decimals: 1
                minValue: 0
                maxValue: 85
                onValueEdited: bridge.setOutputDelay(outputIndex, newValue)
                anchors.verticalCenter: parent.verticalCenter
            }

            Slider {
                id: delaySlider
                width: parent.width - 130
                height: 20
                topPadding: 0
                bottomPadding: 0
                from: 0; to: 85
                value: delayMS
                anchors.verticalCenter: parent.verticalCenter
                onMoved: bridge.sendOutputDelayToDevice(outputIndex, value)
                onPressedChanged: {
                    if (!pressed) bridge.setOutputDelay(outputIndex, value)
                }

                background: Rectangle {
                    x: delaySlider.leftPadding
                    y: (delaySlider.height - height) / 2
                    width: delaySlider.availableWidth
                    height: 3; radius: 2
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        width: delaySlider.visualPosition * parent.width
                        height: parent.height; radius: 2
                        color: "#0078d4"
                    }
                }
                handle: Rectangle {
                    x: delaySlider.leftPadding + delaySlider.visualPosition * (delaySlider.availableWidth - width)
                    y: (delaySlider.height - height) / 2
                    implicitWidth: 12; implicitHeight: 12
                    width: 12; height: 12; radius: 6; color: "white"
                }
            }
        }

        // Divider
        Rectangle { width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.1) }

        // Mute button
        Rectangle {
            id: muteBtn
            width: 36
            height: 36
            radius: 5
            color: isMuted ? Qt.rgba(1, 0, 0, 0.1) : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: isMuted ? "\uD83D\uDD07" : "\uD83D\uDD0A"
                font.pixelSize: 16
                color: isMuted ? "#f44336" : Qt.rgba(1, 1, 1, 0.4)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: bridge.setOutputMute(outputIndex, !isMuted)
            }
        }
    }
}
