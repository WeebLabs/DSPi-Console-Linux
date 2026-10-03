import QtQuick 2.15
import QtQuick.Controls 2.15

// A row of numbered channel chips: filled = on, grey = off. Click to toggle.
Row {
    id: chips
    property int count: 2
    property int mask: 0
    property var names: []          // tooltip per chip
    signal maskEdited(int mask)

    spacing: 8
    Repeater {
        model: chips.count
        Rectangle {
            readonly property bool isOn: (chips.mask >> index) & 1
            width: Math.max(36, (chips.width - (chips.count - 1) * chips.spacing) / chips.count)
            height: 36
            radius: 7
            color: isOn ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.08)
            border.color: isOn ? "transparent" : Qt.rgba(1, 1, 1, 0.12)
            Text {
                anchors.centerIn: parent
                text: index + 1
                font.pixelSize: 15
                font.weight: Font.Bold
                color: parent.isOn ? "white" : Qt.rgba(1, 1, 1, 0.5)
            }
            MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: bridge.connected
                cursorShape: Qt.PointingHandCursor
                onClicked: chips.maskEdited(chips.mask ^ (1 << index))
                ToolTip.visible: containsMouse && chips.names.length > index
                ToolTip.delay: 500
                ToolTip.text: chips.names.length > index ? chips.names[index] : ""
            }
        }
    }
}
