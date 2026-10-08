import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components"

// A tick box with a label.
Item {
    id: box
    property bool checked: false
    property string text: ""
    property string tip: ""
    signal toggled(bool on)
    width: row.implicitWidth
    height: 22
    opacity: enabled ? 1 : 0.4
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Rectangle {
            width: 15; height: 15; radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: isMacOS ? (box.checked ? MacColors.checkboxOn : MacColors.control) : box.checked ? "#0a7cff" : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06)
            border.color: isMacOS ? "transparent" : box.checked ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.25)
            Icon { anchors.centerIn: parent; visible: box.checked; name: "check"; size: 12; color: isMacOS ? MacColors.label : "white" }
        }
        Text { text: box.text; font.pixelSize: 12; color: isMacOS ? MacColors.label : "white"; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: box.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: box.toggled(!box.checked)
    }
    ToolTip.text: box.tip
    ToolTip.visible: box.tip !== "" && mouse.containsMouse
    ToolTip.delay: 600
}
