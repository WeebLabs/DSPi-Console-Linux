import QtQuick 2.15
import "../components"

// A titled card of settings rows, with an optional footnote underneath.
// Rows are separated by hairlines automatically.
Column {
    id: section
    property string title: ""
    property string footnote: ""
    default property alias rows: card.data

    width: parent ? parent.width : 400
    spacing: 6

    Text {
        visible: section.title !== ""
        text: section.title
        leftPadding: 4
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.6)
    }

    Rectangle {
        width: parent.width
        height: card.height
        radius: 10
        color: isMacOS ? "#2b2b2b" : Qt.rgba(1, 1, 1, 0.045)
        border.color: isMacOS ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.07)

        Column {
            id: card
            width: parent.width
        }
    }

    Text {
        visible: section.footnote !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        leftPadding: 4
        rightPadding: 4
        text: section.footnote
        font.pixelSize: 11
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45)
    }
}
