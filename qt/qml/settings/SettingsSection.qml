import QtQuick 2.15
import "../components"

// A titled card of settings rows, with an optional footnote underneath.
// Rows are separated by hairlines automatically.
Column {
    id: section
    property string title: ""
    property string icon: ""           // macOS: the header's SF Symbol stand-in
    property int iconSize: 16          // its glyph starts 4/24 of this in
    property string footnote: ""
    default property alias rows: card.data

    width: parent ? parent.width : 400
    spacing: isMacOS ? 0 : 6

    // macOS: Label(title, systemImage:) above the card, in a 46 pt band with
    // the title centred 28.5 pt down
    Item {
        visible: isMacOS && section.title !== ""
        width: parent.width
        height: 46
        Row {
            x: section.icon !== "" ? 11 - section.iconSize * 4 / 24 : 11
            y: 28.5 - height / 2
            spacing: 11 - section.iconSize * 4 / 24
            Icon {
                visible: section.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: section.icon
                size: section.iconSize
                color: MacColors.label
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: section.title
                font.pixelSize: 13
                font.weight: Font.DemiBold      // measured against the native header
                color: MacColors.label
            }
        }
    }

    Text {
        visible: !isMacOS && section.title !== ""
        text: section.title
        leftPadding: 4
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.6)
    }

    Rectangle {
        width: parent.width
        height: card.height
        radius: isMacOS ? 5 : 10      // the native grouped form section
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
        topPadding: isMacOS ? 6 : 0
        text: section.footnote
        font.pixelSize: isMacOS ? 10 : 11
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45)
    }
}
