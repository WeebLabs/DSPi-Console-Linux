import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

Window {
    id: loudnessWindow
    title: "Loudness Compensation"
    visible: false
    width: 380
    height: 520
    minimumWidth: 380
    minimumHeight: 520
    maximumWidth: 380
    maximumHeight: 520
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Flickable {
        anchors.fill: parent
        contentHeight: loudnessContent.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: loudnessContent
            width: parent.width
            spacing: 0

            // Header
            Rectangle {
                width: parent.width
                height: 60
                color: "transparent"

                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        text: "\uD83D\uDC42" // ear
                        font.pixelSize: 22
                        color: "#0078d4"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Loudness Compensation"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: "white"
                        }
                        Text {
                            text: "ISO 226:2003 Fletcher-Munson"
                            font.pixelSize: 10
                            color: Qt.rgba(1, 1, 1, 0.5)
                        }
                    }

                    Item { width: 1; height: 1 }

                    Switch {
                        id: loudnessSwitch
                        checked: bridge.loudnessEnabled
                        anchors.verticalCenter: parent.verticalCenter
                        onToggled: bridge.setLoudness(checked)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

            // Graph placeholder
            Item {
                width: parent.width
                height: 180

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        text: "COMPENSATION CURVE"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.5)
                    }

                    Rectangle {
                        width: parent.width
                        height: 140
                        radius: 8
                        color: Qt.rgba(0.21, 0.21, 0.21, 0.6)
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Loudness curve visualization"
                            font.pixelSize: 11
                            color: Qt.rgba(1, 1, 1, 0.3)
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

            // Parameters
            Column {
                width: parent.width
                spacing: 4

                Item { width: 1; height: 8 }

                // Section label
                Text {
                    text: "PARAMETERS"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    leftPadding: 16
                }

                Item { width: 1; height: 4 }

                // Reference SPL
                Column {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    Row {
                        width: parent.width
                        Text {
                            text: "Reference SPL"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item { width: 1; height: 1 }
                        ValueField {
                            fieldWidth: 60
                            value: bridge.loudnessRefSPL
                            suffix: "dB"
                            decimals: 0
                            minValue: 40
                            maxValue: 100
                            onValueEdited: bridge.setLoudnessRef(newValue)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    CustomSlider {
                        width: parent.width
                        from: 40; to: 100
                        value: bridge.loudnessRefSPL
                        enabled: bridge.loudnessEnabled
                        onMoved: bridge.setLoudnessRef(value)
                    }

                    Text {
                        text: "Listening volume in dB SPL at which no correction is applied."
                        font.pixelSize: 9
                        color: Qt.rgba(1, 1, 1, 0.4)
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }

                Item { width: 1; height: 12 }

                // Intensity
                Column {
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    Row {
                        width: parent.width
                        Text {
                            text: "Intensity"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: "white"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item { width: 1; height: 1 }
                        ValueField {
                            fieldWidth: 60
                            value: bridge.loudnessIntensity
                            suffix: "%"
                            decimals: 0
                            minValue: 0
                            maxValue: 200
                            onValueEdited: bridge.setLoudnessIntensity(newValue)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    CustomSlider {
                        width: parent.width
                        from: 0; to: 200
                        value: bridge.loudnessIntensity
                        enabled: bridge.loudnessEnabled
                        onMoved: bridge.setLoudnessIntensity(value)
                    }

                    Text {
                        text: "Scales the compensation strength. 100% = standard ISO 226 curves."
                        font.pixelSize: 9
                        color: Qt.rgba(1, 1, 1, 0.4)
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }

                Item { width: 1; height: 16 }
            }
        }
    }
}
