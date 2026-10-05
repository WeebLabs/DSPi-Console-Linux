import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components"

// A drop-down button: the current choice and a chevron; opens a ChoiceMenu
// (options may carry section headers) or, with `categories`, a CascadeMenu
// of families. Emits chosen(value).
Rectangle {
    id: picker
    property var options: []
    property var categories: null
    property var value
    property string text: {
        for (var i = 0; i < options.length; i++)
            if (options[i].header === undefined && options[i].value === value) return options[i].text
        return ""
    }
    property int maxWidth: 260
    signal chosen(var value)

    width: Math.min(maxWidth, label.implicitWidth + 40)
    height: 28
    radius: 7
    opacity: enabled ? 1 : 0.45
    color: mouse.pressed || flat.visible || cascade.visible ? Qt.rgba(1, 1, 1, 0.16)
         : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.08)
    border.color: Qt.rgba(1, 1, 1, 0.10)

    Text {
        id: label
        x: 10
        width: parent.width - 36
        anchors.verticalCenter: parent.verticalCenter
        text: picker.text
        elide: Text.ElideRight
        font.pixelSize: 13
        color: "white"
    }
    Column {
        x: parent.width - width - 9
        anchors.verticalCenter: parent.verticalCenter
        spacing: -4
        Icon { name: "chev-up"; size: 11; color: Qt.rgba(1, 1, 1, 0.6) }
        Icon { name: "chev-down"; size: 11; color: Qt.rgba(1, 1, 1, 0.6) }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (picker.categories) cascade.toggleAt(picker)
            else flat.toggleAt(picker)
        }
    }

    ChoiceMenu {
        id: flat
        parent: Overlay.overlay
        options: picker.options
        currentValue: picker.value
        onChosen: picker.chosen(value)
    }
    CascadeMenu {
        id: cascade
        parent: Overlay.overlay
        categories: picker.categories || []
        currentValue: picker.value
        onChosen: picker.chosen(value)
    }
}
