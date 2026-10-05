import QtQuick 2.15

// A button in the app's style: outlined (secondary) or filled accent
// (primary); 28 px, radius 8.
Rectangle {
    id: btn
    property string text: ""
    property bool primary: false
    signal clicked()
    width: Math.max(72, label.implicitWidth + 28)
    height: 28
    radius: 8
    opacity: enabled ? 1 : 0.4
    color: primary ? (mouse.pressed ? "#0060cc" : "#0a7cff")
         : mouse.pressed ? Qt.rgba(1, 1, 1, 0.13) : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
    border.color: primary ? "transparent" : Qt.rgba(1, 1, 1, 0.18)
    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        font.pixelSize: 13
        font.weight: btn.primary ? Font.DemiBold : Font.Normal
        color: "white"
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.clicked()
    }
}
