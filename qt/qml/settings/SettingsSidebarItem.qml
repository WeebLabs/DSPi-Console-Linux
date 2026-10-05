import QtQuick 2.15
import "../components"

// A page entry in the Settings sidebar: coloured icon tile and title.
Rectangle {
    id: item
    property string title: ""
    property string icon: ""
    property color tint: "#8e8e93"
    property bool selected: false
    signal clicked()

    height: 28
    radius: 7
    color: selected ? "#0a7cff" : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

    Rectangle {
        id: tile
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; radius: 5
        color: item.tint
        Icon {
            anchors.centerIn: parent
            name: item.icon
            size: 13
            color: "white"
        }
    }
    Text {
        anchors.left: tile.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: item.title
        font.pixelSize: 13
        color: "white"
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: item.clicked()
    }
}
