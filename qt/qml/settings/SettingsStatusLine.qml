import QtQuick 2.15
import "../components"

// The outcome of the last change on a settings page: green for done,
// orange with a warning sign when the device refused it.
Row {
    id: line
    property string text: ""
    property bool error: false
    visible: text !== ""
    spacing: 8
    width: parent ? parent.width : 400
    Icon {
        id: mark
        name: line.error ? "warning" : "chev-right"
        size: 15
        color: isMacOS ? (line.error ? MacColors.orange : MacColors.green) : line.error ? "#ff9f0a" : "#32d74b"
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        width: line.width - mark.width - line.spacing
        wrapMode: Text.WordWrap
        text: line.text
        font.pixelSize: 12
        color: isMacOS ? (line.error ? MacColors.orange : MacColors.secondaryLabel) : line.error ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.7)
        anchors.verticalCenter: parent.verticalCenter
    }
}
