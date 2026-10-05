import QtQuick 2.15
import QtQuick.Controls 2.15

// Sidebar footer: load of the busier core on the left, connection status on the right.
Item {
    id: cpuRoot
    height: 36

    property int cpu0: 0
    property int cpu1: 0
    readonly property int load: Math.max(cpu0, cpu1)
    readonly property bool connected: bridge.connected

    // Space left of the status for label, bar (28-44 px) and value; the bar gives
    // up width first, then the name drops its "DSPi" prefix.
    readonly property real fixedLeft: 16 + cpuLabel.width + 8 + 6 + cpuValue.width + 12 + 16
    readonly property string serialTail: bridge.selectedSerial.slice(-8)
    readonly property string fullName: bridge.selectedSerial.length >= 8 ? "DSPi (" + serialTail + ")" : "DSPi"
    TextMetrics { id: fullNameMetrics; font.pixelSize: 11; text: cpuRoot.fullName }

    Text {
        id: cpuLabel
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "CPU"
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    Rectangle {
        id: track
        anchors.left: cpuLabel.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(28, Math.min(44, cpuRoot.width - cpuRoot.fixedLeft - status.width))
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            visible: cpuRoot.connected
            width: parent.width * Math.min(1, Math.max(0, cpuRoot.load / 100))
            height: parent.height
            radius: 2
            color: cpuRoot.load > 80 ? "#ff9f0a" : "#0a7cff"
        }
    }

    Text {
        id: cpuValue
        anchors.left: track.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        text: cpuRoot.connected ? cpuRoot.load + "%" : "—"
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.65)

        ToolTip.visible: cpuHover.containsMouse && cpuRoot.connected
        ToolTip.text: "Core 0: " + cpuRoot.cpu0 + "%   Core 1: " + cpuRoot.cpu1 + "%"
        MouseArea { id: cpuHover; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true }
    }

    Row {
        id: status
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Status dot with a faint halo when connected
        Item {
            width: 12; height: 12
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.centerIn: parent
                width: 12; height: 12; radius: 6
                color: "#32d74b"
                opacity: 0.18
                visible: cpuRoot.connected
            }
            Rectangle {
                anchors.centerIn: parent
                width: 6; height: 6; radius: 3
                color: cpuRoot.connected ? "#32d74b" : "#ff453a"
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Short device name, as in the Windows Console: "DSPi (last 8 of the serial)"
            text: {
                if (!cpuRoot.connected)
                    return bridge.availableSerials.length === 0 ? "No Devices" : "Disconnected"
                var room = cpuRoot.width - cpuRoot.fixedLeft - 28 - 18
                return fullNameMetrics.advanceWidth <= room || cpuRoot.serialTail === "" ? cpuRoot.fullName : cpuRoot.serialTail
            }
            font.pixelSize: 11
            color: cpuRoot.connected ? Qt.rgba(1, 1, 1, 0.65)
                 : bridge.availableSerials.length === 0 ? "#ff453a" : Qt.rgba(1, 1, 1, 0.45)
        }

        ToolTip.visible: statusHover.containsMouse
        ToolTip.delay: 500
        ToolTip.text: cpuRoot.connected
                      ? "Connected · Serial " + bridge.selectedSerial
                        + (bridge.availableSerials.length > 1 ? "\nClick to switch device. Right-click to reconnect." : "\nRight-click to reconnect.")
                      : (bridge.connectionError || "Not connected. Right-click the device name to retry.")
    }

    // Several DSPis: click to choose one. Right-click rescans and reconnects.
    MouseArea {
        id: statusHover
        anchors.fill: status
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: bridge.availableSerials.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (mouse.button === Qt.RightButton) { bridge.rescan(); return }
            if (bridge.availableSerials.length > 1) deviceMenu.toggleAt(status)
        }
    }
    ChoiceMenu {
        id: deviceMenu
        parent: Overlay.overlay
        alignRight: true
        heading: "Devices"
        currentValue: bridge.selectedSerial
        options: bridge.availableSerials.map(function (s) { return { value: s, text: "DSPi " + s.slice(-8) } })
        onChosen: if (value !== bridge.selectedSerial) root.switchDevice(value)
    }
}
