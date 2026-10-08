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

    // macOS: the native BypassCheckbox (Components.swift:2391) - 12 pt, and an
    // Off band keeps a faint hollow ring rather than no dot
    Rectangle {
        anchors.centerIn: parent
        width: isMacOS ? 12 : 9; height: isMacOS ? 12 : 9; radius: isMacOS ? 6 : 4.5
        visible: isMacOS ? true : dotRoot.active
        opacity: isMacOS ? (dotRoot.active ? 1 : 0.35) : 1
        color: isMacOS ? (dotRoot.active && !dotRoot.bypassed ? dotRoot.dotColor : "transparent") : dotRoot.bypassed ? "transparent" : dotRoot.dotColor
        border.color: isMacOS ? (!dotRoot.active ? MacColors.opacity(MacColors.secondaryLabel, 0.55) : dotRoot.bypassed ? MacColors.opacity(dotRoot.dotColor, 0.6) : dotRoot.dotColor) : dotRoot.dotColor
        border.width: isMacOS ? 1.2 : 1.5
        scale: isMacOS ? (mouse.containsMouse && dotRoot.active ? 1.1 : 1.0) : mouse.containsMouse ? 1.25 : 1.0
        Behavior on scale { enabled: isMacOS; NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
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
