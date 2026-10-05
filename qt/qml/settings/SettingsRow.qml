import QtQuick 2.15

// One row in a SettingsSection: title and optional detail on the left,
// a trailing control (the row's children) on the right.
Item {
    id: row
    property string title: ""
    property string detail: ""
    property color titleColor: "white"
    property real trailingWidth: trailing.childrenRect.width
    property bool clickable: false     // whole row acts as a button
    signal activated()
    default property alias control: trailing.data

    // Hairline above every row except the first in its card
    readonly property bool firstInCard: parent && parent.children.length > 0 && parent.children[0] === row

    width: parent ? parent.width : 400
    height: Math.max(40, labels.height + 16)
    opacity: enabled ? 1.0 : 0.45

    // Hover highlight and click target for clickable rows (below the controls)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 7
        visible: row.clickable && rowMouse.containsMouse
        color: Qt.rgba(1, 1, 1, 0.05)
    }
    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: row.clickable
        hoverEnabled: row.clickable
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.activated()
    }

    Rectangle {
        visible: !row.firstInCard
        x: 14
        width: parent.width - 14
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }

    Column {
        id: labels
        x: 14
        width: parent.width - 28 - (row.trailingWidth > 0 ? row.trailingWidth + 16 : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: row.title
            font.pixelSize: 13
            color: row.titleColor
        }
        Text {
            visible: row.detail !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: row.detail
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.5)
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
