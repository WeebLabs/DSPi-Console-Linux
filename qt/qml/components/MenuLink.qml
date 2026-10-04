import QtQuick 2.15

// "Presets ⌄" link that opens an ActionMenu under itself
Item {
    id: link
    property string text: ""
    property ActionMenu menu
    width: linkRow.width
    height: linkRow.height
    Row {
        id: linkRow
        spacing: 4
        Text {
            text: link.text
            font.pixelSize: 12
            color: linkMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.75)
        }
        Icon { name: "chev-down"; size: 11; color: Qt.rgba(1, 1, 1, 0.6); anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea {
        id: linkMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: link.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: link.menu.openAt(link, 0, link.height + 4)
    }
}
