import QtQuick 2.15

// Dot-and-text status capsule: Pending, Active or Inactive.
Rectangle {
    id: pill
    property string text: ""
    property color tint: "#32d74b"
    width: row.implicitWidth + 16
    height: 20
    radius: 10
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.13)
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Rectangle { width: 6; height: 6; radius: 3; color: pill.tint; anchors.verticalCenter: parent.verticalCenter }
        Text { text: pill.text; font.pixelSize: 11; font.weight: Font.Medium; color: pill.tint }
    }
}
