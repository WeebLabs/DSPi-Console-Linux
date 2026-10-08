import QtQuick 2.15
import "../../components"

// A list's empty state: a hint of what can be added, a title, a line of
// text and the add button (children).
Rectangle {
    id: empty
    property string title: ""
    property string text: ""
    default property alias art: artRow.data
    property alias action: actionSlot.data
    width: parent ? parent.width : 400
    height: col.height + 36
    radius: isMacOS ? 5 : 10
    color: isMacOS ? "#2b2b2b" : Qt.rgba(1, 1, 1, 0.045)
    border.color: isMacOS ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.07)
    Column {
        id: col
        y: 18
        width: parent.width
        spacing: 12
        Row { id: artRow; anchors.horizontalCenter: parent.horizontalCenter; spacing: 10 }
        Column {
            width: parent.width
            spacing: 3
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: empty.title
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: isMacOS ? MacColors.label : "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(340, parent.width - 40)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: empty.text
                font.pixelSize: 12
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55)
            }
        }
        Item {
            id: actionSlot
            anchors.horizontalCenter: parent.horizontalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }
}
