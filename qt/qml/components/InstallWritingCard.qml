import QtQuick 2.15

// The firmware write in progress: how far along, which board, which
// firmware, and that the drive vanishing at the end is the normal ending.
Rectangle {
    id: card
    property real progress: 0
    property string boardName: ""
    property string version: ""

    radius: 8
    color: Qt.rgba(1, 1, 1, 0.045)
    border.color: Qt.rgba(1, 1, 1, 0.07)

    Column {
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 10
        Item {
            width: parent.width
            height: 18
            Text { text: "Writing firmware"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white" }
            Text {
                anchors.right: parent.right
                text: Math.round(card.progress * 100) + "%"
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Qt.rgba(1, 1, 1, 0.55)
            }
        }
        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.14)
            Rectangle { width: parent.width * card.progress; height: parent.height; radius: 2; color: "#0a7cff" }
        }
        Column {
            spacing: 4
            LabelValueRow { visible: card.boardName !== ""; label: "Board"; value: card.boardName }
            LabelValueRow { label: "Firmware"; value: card.version }
        }
    }
    Row {
        x: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        spacing: 6
        Icon { name: "info"; size: 13; color: Qt.rgba(1, 1, 1, 0.45) }
        Text {
            width: card.width - 28 - 19
            wrapMode: Text.WordWrap
            text: "Near the end the board restarts itself and its drive disappears. That is normal - do not unplug it."
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }
}
