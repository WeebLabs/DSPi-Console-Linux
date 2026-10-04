import QtQuick 2.15
import QtQuick.Controls 2.15

// Tool window header: icon tile, title, subtitle and the effect's on/off
// switch. Sized like the limiter popup header.
Rectangle {
    id: hdr
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool showSwitch: true
    // Extra controls left of the switch (a SOLO latch, a view picker)
    property alias accessories: accessoryRow.data
    signal toggled(bool enable)

    height: 52
    color: Qt.rgba(1, 1, 1, 0.03)

    Rectangle {
        id: tile
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 28; height: 28; radius: 7
        color: Qt.rgba(0.04, 0.49, 1, hdr.checked || !hdr.showSwitch ? 0.18 : 0.08)
        Icon {
            anchors.centerIn: parent
            name: hdr.icon
            size: 16
            color: hdr.checked || !hdr.showSwitch ? "#3a96ff" : Qt.rgba(1, 1, 1, 0.45)
        }
    }
    Column {
        anchors.left: tile.right
        anchors.leftMargin: 10
        anchors.right: accessoryRow.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text { width: parent.width; elide: Text.ElideRight; text: hdr.title; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white" }
        Text { width: parent.width; elide: Text.ElideRight; text: hdr.subtitle; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
    }
    Row {
        id: accessoryRow
        anchors.right: sw.visible ? sw.left : parent.right
        anchors.rightMargin: children.length > 0 ? 12 : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
    ToggleSwitch {
        id: sw
        visible: hdr.showSwitch
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        checked: hdr.checked
        enabled: bridge.connected
        onToggled: hdr.toggled(checked)
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
}
