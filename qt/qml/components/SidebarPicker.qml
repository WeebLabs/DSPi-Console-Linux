import QtQuick 2.15
import QtQuick.Controls 2.15

// A sidebar setting with a pop-up choice: label on the left, the current
// value and a chevron on the right; clicking the value toggles a ChoiceMenu.
Item {
    id: picker
    property string label: ""
    property string valueText: ""
    property alias options: menu.options
    property alias currentValue: menu.currentValue
    signal chosen(var value)

    height: 26

    Text {
        text: picker.label
        font.pixelSize: 12
        font.weight: Font.Medium
        color: Qt.rgba(1, 1, 1, 0.6)
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
        id: valueButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(valueRow.implicitWidth + 16, picker.width - 70)
        height: 24
        radius: 6
        color: !picker.enabled ? "transparent"
             : menu.visible ? Qt.rgba(1, 1, 1, 0.12)
             : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

        Row {
            id: valueRow
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text {
                width: Math.min(implicitWidth, picker.width - 100)
                elide: Text.ElideRight
                text: picker.valueText
                font.pixelSize: 13
                color: picker.enabled ? "white" : Qt.rgba(1, 1, 1, 0.4)
                anchors.verticalCenter: parent.verticalCenter
            }
            Icon {
                visible: picker.enabled
                name: "chev-down"
                size: 12
                color: mouse.containsMouse || menu.visible ? "white" : Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: picker.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menu.toggleAt(valueButton)
        }
    }

    ChoiceMenu {
        id: menu
        parent: Overlay.overlay
        alignRight: true
        onChosen: picker.chosen(value)
    }
}
