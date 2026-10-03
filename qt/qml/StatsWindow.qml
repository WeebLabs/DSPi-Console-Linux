import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Stats for Nerds: device, processor and preset details, in the macOS
// layout (small-caps sections of label / value rows, status footer). The
// buffer and S/PDIF statistics the macOS window adds need core support
// (parity plan, phase 4).
AppWindow {
    id: win
    fitHeight: body.height + 32 + footer.height
    title: "System Statistics"
    visible: false
    width: 340
    height: 520 + titlebarHeight
    minimumWidth: 300
    minimumHeight: 300 + titlebarHeight

    readonly property string dash: "—"

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }
    component Divider: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    // Label on the left, value on the right
    component StatRow: Item {
        property string label: ""
        property string value: ""
        property color valueColor: Qt.rgba(1, 1, 1, 0.9)
        width: parent.width
        height: 24
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.75)
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: parent.valueColor
        }
    }

    // CPU load: value with a thin bar under the row (orange past 80 %)
    component CpuRow: Item {
        id: cpu
        property string label: ""
        property int load: 0
        width: parent.width
        height: 30
        StatRow {
            label: cpu.label
            value: bridge.connected ? cpu.load + " %" : win.dash
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 3
            radius: 1.5
            color: Qt.rgba(1, 1, 1, 0.08)
            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, cpu.load / 100))
                height: parent.height
                radius: 1.5
                color: cpu.load > 80 ? "#ff9f0a" : "#0a7cff"
                Behavior on width { NumberAnimation { duration: 180 } }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: footer.height
        contentHeight: body.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: body
            x: 16
            y: 16
            width: win.width - 32
            spacing: 10

            SectionLabel { text: "DEVICE INFORMATION" }
            Column {
                width: parent.width
                StatRow { label: "Platform"; value: bridge.connected ? bridge.platformName : win.dash }
                StatRow { label: "Firmware"; value: bridge.connected ? bridge.firmwareVersion : win.dash }
                StatRow { label: "Serial"; value: bridge.selectedSerial || win.dash }
                StatRow {
                    label: "Channels"
                    value: bridge.connected ? bridge.numInputChannels + " in · " + bridge.numOutputChannels + " out" : win.dash
                }
            }

            Divider {}
            SectionLabel { text: "SYSTEM INFORMATION" }
            Column {
                width: parent.width
                spacing: 2
                CpuRow { label: "Core 0 Load"; load: bridge.cpu0 }
                CpuRow { label: "Core 1 Load"; load: bridge.cpu1 }
                StatRow {
                    label: "Core 1 Mode"
                    value: !bridge.connected ? win.dash
                         : ["Idle", "PDM", "EQ Worker"][bridge.core1Mode] || "Unknown"
                }
                StatRow {
                    label: "Active Inputs"
                    value: bridge.connected ? String(bridge.activeInputChannels) : win.dash
                }
                StatRow {
                    label: "Input Source"
                    value: {
                        if (!bridge.connected) return win.dash
                        var s = bridge.inputSources
                        for (var i = 0; i < s.length; i++) if (s[i].id === bridge.inputSource) return s[i].name
                        return "USB"
                    }
                }
            }

            Divider {}
            SectionLabel { text: "PRESETS" }
            Column {
                width: parent.width
                StatRow { label: "Active Slot"; value: bridge.connected ? String(bridge.activePresetSlot + 1) : win.dash }
                StatRow {
                    label: "Startup"
                    value: !bridge.connected ? win.dash
                         : bridge.presetStartupMode === 0 ? "Slot " + (bridge.presetDefaultSlot + 1) : "Last Used"
                }
                StatRow {
                    label: "Output Config"
                    value: !bridge.connected ? win.dash
                         : bridge.outputConfigMode === 1 ? "Saved with Presets" : "Independent"
                }
            }
        }
    }

    // Footer: connection state
    Rectangle {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: 34
        color: Qt.rgba(1, 1, 1, 0.03)
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
        Row {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                width: 8; height: 8; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: bridge.connected ? "#32d74b" : "#ff453a"
            }
            Text {
                text: bridge.connected ? "Connected" : "Disconnected"
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.65)
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Updated live"
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.4)
        }
    }
}
