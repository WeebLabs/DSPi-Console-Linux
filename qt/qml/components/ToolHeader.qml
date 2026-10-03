import QtQuick 2.15
import QtQuick.Controls 2.15

// Tool window header: icon, title, subtitle and the effect's on/off switch.
Rectangle {
    id: hdr
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool showSwitch: true
    signal toggled(bool enable)

    height: 72
    color: Qt.rgba(1, 1, 1, 0.03)

    Icon {
        id: ic
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        name: hdr.icon
        size: 30
        color: "#3a96dd"
    }
    Column {
        anchors.left: ic.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: hdr.title; font.pixelSize: 18; font.weight: Font.DemiBold; color: "white" }
        Text { text: hdr.subtitle; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
    }
    ToggleSwitch {
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
