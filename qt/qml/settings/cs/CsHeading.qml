import QtQuick 2.15

// Small-caps label naming a run of rows inside a card.
Item {
    property string text: ""
    property int indent: 0
    width: parent ? parent.width : 400
    height: 30
    Rectangle { x: 14 + parent.indent; width: parent.width - x; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
    Text {
        x: 14 + parent.indent
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 5
        text: parent.text.toUpperCase()
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.45)
    }
}
