import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components"

// A compact button: outlined (secondary), filled accent (primary), or a
// bare glyph (icon only, for trash / reorder / run).
Rectangle {
    id: btn
    property string text: ""
    property string icon: ""
    property bool primary: false
    property bool bare: false
    property color glyphColor: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.6)
    property string tip: ""
    signal clicked()

    implicitWidth: bare ? 24 : Math.max(64, row.implicitWidth + 24)
    implicitHeight: bare ? 24 : 26
    width: implicitWidth
    height: implicitHeight
    radius: bare ? 6 : 8
    opacity: enabled ? 1 : 0.4
    color: isMacOS ? (primary ? (mouse.pressed ? MacColors.defaultButtonPressed : MacColors.prominentButton) : bare ? "transparent" : mouse.pressed ? Qt.rgba(1, 1, 1, 0.36) : MacColors.control)
         : primary ? (mouse.pressed ? "#0060cc" : "#0a7cff")
         : mouse.pressed ? Qt.rgba(1, 1, 1, 0.13) : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
    border.color: isMacOS ? "transparent" : primary || bare ? "transparent" : Qt.rgba(1, 1, 1, 0.18)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            visible: btn.icon !== ""
            name: btn.icon
            size: btn.bare ? 14 : 13
            color: isMacOS ? (btn.bare ? btn.glyphColor : MacColors.label) : btn.bare ? (mouse.containsMouse && btn.enabled ? "white" : btn.glyphColor) : "white"
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: btn.text !== ""
            text: btn.text
            font.pixelSize: 13
            font.weight: btn.primary ? Font.DemiBold : Font.Normal
            color: isMacOS ? MacColors.label : "white"
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.clicked()
    }
    ToolTip.text: btn.tip
    ToolTip.visible: btn.tip !== "" && mouse.containsMouse
    ToolTip.delay: 600
}
