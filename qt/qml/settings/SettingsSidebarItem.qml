import QtQuick 2.15
import "../components"

// A page entry in the Settings sidebar: coloured icon tile and title.
Rectangle {
    id: item
    property string title: ""
    property string icon: ""
    property color tint: "#8e8e93"
    property bool selected: false
    property int fontSize: 13
    signal clicked()

    height: 28
    radius: isMacOS ? 6 : 7
    color: isMacOS ? (selected ? MacColors.sidebarSelection : "transparent") : selected ? "#0a7cff" : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

    // macOS: the native SettingsBadge (DSPi_ConsoleApp.swift:342), a 15 pt
    // tile with the tint's gradient
    Rectangle {
        id: tile
        x: isMacOS ? 6 : 8
        anchors.verticalCenter: parent.verticalCenter
        width: isMacOS ? 15 : 20; height: isMacOS ? 15 : 20; radius: isMacOS ? 4 : 5
        color: item.tint
        gradient: isMacOS ? macTileGradient : null
        Icon {
            anchors.centerIn: parent
            name: item.icon
            size: isMacOS ? 10 : 13
            color: "white"
        }
    }
    property Gradient macTileGradient: Gradient {
        GradientStop { position: 0; color: Qt.hsla(item.tint.hslHue, item.tint.hslSaturation, Math.min(1, item.tint.hslLightness + 0.145), 1) }
        GradientStop { position: 1; color: item.tint }
    }
    Text {
        anchors.left: tile.right
        anchors.leftMargin: isMacOS ? 6 : 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: item.title
        font.pixelSize: item.fontSize
        // macOS: the label colour as the sidebar's vibrancy brightens it (measured)
        color: isMacOS ? (item.selected ? "white" : Qt.rgba(1, 1, 1, 0.9)) : "white"
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: item.clicked()
    }
}
