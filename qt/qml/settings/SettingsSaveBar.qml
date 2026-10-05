import QtQuick 2.15

// Shown while Settings holds changes not yet written to the device.
Rectangle {
    id: bar
    property bool canRevert: true     // hardware edits saved to RAM can't be undone
    signal save()
    signal revert()

    height: 48
    color: "#242426"
    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    Column {
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text { text: "Unsaved changes"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white" }
        Text { text: "Saving writes these settings to the device's flash"; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
    }

    // A button in the app's style: outlined (secondary) or filled accent
    component BarButton: Rectangle {
        id: btn
        property string text: ""
        property bool primary: false
        signal clicked()
        width: Math.max(72, label.implicitWidth + 28)
        height: 28
        radius: 8
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
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        BarButton { visible: bar.canRevert; text: "Revert"; onClicked: bar.revert() }
        BarButton { text: "Save"; primary: true; onClicked: bar.save() }
    }
}
