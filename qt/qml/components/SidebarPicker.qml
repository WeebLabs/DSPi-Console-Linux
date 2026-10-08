import QtQuick 2.15
import QtQuick.Controls 2.15

// A sidebar setting with a pop-up choice: label on the left, the current
// value and a chevron on the right; clicking the value toggles a ChoiceMenu,
// right-clicking the row emits contextMenuRequested.
Item {
    id: picker
    property string label: ""
    property string valueText: ""
    property alias options: menu.options
    property alias currentValue: menu.currentValue
    signal chosen(var value)
    // Right-click anywhere on the row (x, y in the picker)
    signal contextMenuRequested(real x, real y)

    height: 26
    // Room the value may take: all but the label and a gap
    readonly property real valueRoom: picker.width - labelText.implicitWidth - 12

    MouseArea {
        anchors.fill: parent
        enabled: picker.enabled
        acceptedButtons: Qt.RightButton
        onClicked: picker.contextMenuRequested(mouse.x, mouse.y)
    }

    Text {
        id: labelText
        text: picker.label
        font.pixelSize: 12
        font.weight: Font.Medium
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.6)
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
        id: valueButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(valueRow.implicitWidth + 16, picker.valueRoom)
        height: 24
        radius: 6
        color: isMacOS ? (picker.enabled && (menu.visible || mouse.containsMouse) ? MacColors.control : "transparent") : !picker.enabled ? "transparent"
             : menu.visible ? Qt.rgba(1, 1, 1, 0.12)
             : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

        Row {
            id: valueRow
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text {
                width: Math.min(implicitWidth, picker.valueRoom - 33)
                elide: Text.ElideRight
                text: picker.valueText
                font.pixelSize: 13
                color: isMacOS ? (picker.enabled ? MacColors.label : MacColors.opacity(MacColors.label, 0.4)) : picker.enabled ? "#cccccc" : Qt.rgba(1, 1, 1, 0.4)   // Windows Console secondary text
                anchors.verticalCenter: parent.verticalCenter
            }
            Icon {
                visible: picker.enabled
                name: "chev-down"
                size: 12
                color: isMacOS ? MacColors.secondaryLabel : mouse.containsMouse || menu.visible ? "white" : Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: picker.enabled
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (mouse.button === Qt.RightButton) {
                    var p = mapToItem(picker, mouse.x, mouse.y)
                    picker.contextMenuRequested(p.x, p.y)
                } else menu.toggleAt(valueButton)
            }
        }
    }

    ChoiceMenu {
        id: menu
        parent: Overlay.overlay
        alignRight: true
        onChosen: picker.chosen(value)
    }
}
