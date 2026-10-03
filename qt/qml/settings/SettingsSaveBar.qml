import QtQuick 2.15
import QtQuick.Controls 2.15

// Shown while Settings holds changes not yet written to the device.
Rectangle {
    id: bar
    signal save()
    signal revert()

    height: 56
    color: "#242426"
    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    Column {
        x: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { text: "Unsaved changes"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white" }
        Text { text: "Saving writes these settings to the device's flash"; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Button {
            text: "Revert"
            onClicked: bar.revert()
        }
        Button {
            id: saveBtn
            text: "Save"
            highlighted: true
            onClicked: bar.save()
            contentItem: Text {
                text: saveBtn.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitWidth: 80
                implicitHeight: 30
                radius: 7
                color: saveBtn.down ? "#0060cc" : "#0a7cff"
            }
        }
    }
}
