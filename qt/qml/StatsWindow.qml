import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

Window {
    id: statsWindow
    title: "System Statistics"
    visible: false
    width: 320
    height: 420
    minimumWidth: 320
    minimumHeight: 420
    maximumWidth: 320
    maximumHeight: 420
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Device Information
        Text {
            text: "Device Information"
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Qt.rgba(1, 1, 1, 0.5)
        }

        Column {
            width: parent.width
            spacing: 4

            StatInfoRow { title: "Platform"; value: bridge.platformName }
            StatInfoRow { title: "Channels"; value: bridge.numChannels.toString() }
            StatInfoRow { title: "Outputs"; value: bridge.numOutputChannels.toString() }
            StatInfoRow { title: "Serial"; value: bridge.selectedSerial || "—" }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

        // System Information
        Text {
            text: "System Information"
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Qt.rgba(1, 1, 1, 0.5)
        }

        Column {
            width: parent.width
            spacing: 4

            StatInfoRow { title: "Core 0 CPU"; value: bridge.cpu0 + "%" }
            StatInfoRow { title: "Core 1 CPU"; value: bridge.cpu1 + "%" }
            StatInfoRow {
                title: "Core 1 Mode"
                value: {
                    var mode = bridge.core1Mode
                    if (mode === 0) return "Idle"
                    if (mode === 1) return "PDM"
                    if (mode === 2) return "EQ Worker"
                    return "Unknown"
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

        // Preset Information
        Text {
            text: "Preset Information"
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Qt.rgba(1, 1, 1, 0.5)
        }

        Column {
            width: parent.width
            spacing: 4

            StatInfoRow { title: "Active Slot"; value: (bridge.activePresetSlot + 1).toString() }
            StatInfoRow {
                title: "Startup Mode"
                value: bridge.presetStartupMode === 0 ? "Specified Default" : "Last Used"
            }
            StatInfoRow { title: "Default Slot"; value: (bridge.presetDefaultSlot + 1).toString() }
            StatInfoRow { title: "Include Pins"; value: bridge.presetIncludePins ? "Yes" : "No" }
        }

        // Footer
        Item { width: 1; height: 8 }
        Row {
            spacing: 6
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                width: 6; height: 6; radius: 3
                color: bridge.connected ? "#4caf50" : "#f44336"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: bridge.connected ? "Connected" : "Disconnected"
                font.pixelSize: 10
                color: Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    component StatInfoRow: Row {
        property string title: ""
        property string value: ""
        width: parent.width
        height: 22

        Text {
            text: title
            font.pixelSize: 11
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.7)
            width: parent.width / 2
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: value
            font.pixelSize: 12
            font.weight: Font.Bold
            font.family: "Menlo"
            color: "white"
            horizontalAlignment: Text.AlignRight
            width: parent.width / 2
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
