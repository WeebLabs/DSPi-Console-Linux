import QtQuick 2.15

// One firmware-install state: an icon, or a spinner while the app or the
// hardware is working, a short title, a sentence or two, and optionally a
// control belonging to the state (declared as children).
Rectangle {
    id: card
    property string icon: ""
    property color tint: "#3a96ff"
    property bool spin: false
    property int iconSize: 28
    property string title: ""
    property string text: ""
    default property alias accessory: accessorySlot.data

    radius: 8
    color: isMacOS ? MacColors.opacity(MacColors.controlBackground, 0.6) : Qt.rgba(1, 1, 1, 0.045)
    border.color: isMacOS ? MacColors.opacity(MacColors.gray, 0.2) : Qt.rgba(1, 1, 1, 0.07)

    Column {
        anchors.centerIn: parent
        width: Math.min(340, parent.width - 28)
        spacing: 8
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: card.iconSize
            height: card.iconSize
            Spinner { anchors.centerIn: parent; visible: card.spin; size: 26 }
            Icon { anchors.centerIn: parent; visible: !card.spin; name: card.icon; size: card.iconSize; color: card.tint }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: card.title
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: isMacOS ? MacColors.label : "white"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: card.text
            font.pixelSize: 11
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55)
        }
        Item {
            id: accessorySlot
            anchors.horizontalCenter: parent.horizontalCenter
            visible: children.length > 0
            width: childrenRect.width
            height: childrenRect.height + 4
        }
    }
}
