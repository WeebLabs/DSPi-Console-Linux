import QtQuick 2.15

// "LABEL   value": a small-caps label in a fixed column, then the value.
Row {
    property string label: ""
    property string value: ""
    property bool secondary: false
    property int labelWidth: 120
    spacing: 8
    Text {
        width: parent.labelWidth
        text: parent.label.toUpperCase()
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.45)
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: parent.value
        font.pixelSize: 12
        font.weight: Font.Medium
        color: parent.secondary ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.9)
        anchors.verticalCenter: parent.verticalCenter
    }
}
