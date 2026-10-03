import QtQuick 2.15
import QtQuick.Controls 2.15

// Band bypass dot: filled = active, hollow ring = bypassed. Click to toggle.
Item {
    id: dotRoot
    width: 18
    height: 18

    property bool active: true      // band is not Off
    property bool bypassed: false
    property color dotColor: "#3a96dd"

    signal toggled()

    Rectangle {
        anchors.centerIn: parent
        width: 9; height: 9; radius: 4.5
        visible: dotRoot.active
        color: dotRoot.bypassed ? "transparent" : dotRoot.dotColor
        border.color: dotRoot.dotColor
        border.width: 1.5
        scale: mouse.containsMouse ? 1.25 : 1.0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: dotRoot.active
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: dotRoot.toggled()
        ToolTip.visible: containsMouse
        ToolTip.delay: 600
        ToolTip.text: dotRoot.bypassed ? "Enable band" : "Bypass band"
    }
}
