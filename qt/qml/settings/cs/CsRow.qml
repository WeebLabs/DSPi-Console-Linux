import QtQuick 2.15

// A row inside a Control Surfaces card: title and optional detail on the
// left, the trailing control (the row's children) on the right, a hairline
// above. `indent` insets it inside a nested card (remote buttons, steps).
Item {
    id: row
    property string title: ""
    property string detail: ""
    property color detailColor: Qt.rgba(1, 1, 1, 0.5)
    property bool hairline: true
    property int indent: 0
    default property alias control: trailing.data

    width: parent ? parent.width : 400
    height: Math.max(42, labels.height + 18)
    opacity: enabled ? 1.0 : 0.45

    Rectangle {
        visible: row.hairline
        x: 14 + row.indent
        width: parent.width - x
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }
    Column {
        id: labels
        x: 14 + row.indent
        width: parent.width - x - 14 - (trailing.width > 0 ? trailing.width + 16 : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: row.title
            font.pixelSize: 13
            color: "white"
        }
        Text {
            visible: row.detail !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: row.detail
            font.pixelSize: 11
            color: row.detailColor
        }
    }
    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
