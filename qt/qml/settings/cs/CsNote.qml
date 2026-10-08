import QtQuick 2.15
import "../../components"

// A line of explanation or warning inside a card.
Item {
    id: note
    property string text: ""
    property bool warning: false
    property int indent: 0
    width: parent ? parent.width : 400
    height: visible ? label.height + 14 : 0
    visible: text !== ""
    Icon {
        id: mark
        visible: note.warning
        x: 14 + note.indent
        y: 7
        name: "warning"
        size: 14
        color: "#ff9f0a"
    }
    Text {
        id: label
        x: note.warning ? mark.x + 20 : 14 + note.indent
        y: 7
        width: parent.width - x - 14
        wrapMode: Text.WordWrap
        text: note.text
        font.pixelSize: 11
        color: isMacOS ? (note.warning ? MacColors.orange : MacColors.secondaryLabel) : note.warning ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.5)
    }
}
