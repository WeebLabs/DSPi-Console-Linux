import QtQuick 2.15
import QtQuick.Controls 2.15

// Dark rounded drop-down. Sizes itself to the longest option unless a width
// is given; the list shows a check mark on the current item.
ComboBox {
    id: box
    // macOS: the menu Picker of a grouped Form row - the title, right-aligned,
    // then the up/down chevrons in a small rounded box, no bezel
    property bool macForm: false
    readonly property bool form: isMacOS && macForm
    implicitHeight: form ? 20 : 28
    implicitWidth: form ? Math.ceil(widest.advanceWidth) + 22 : Math.max(96, Math.ceil(widest.advanceWidth) + 56)
    font.pixelSize: 13

    // Measures the longest option for implicitWidth
    TextMetrics { id: widest; font: box.font; text: {
        var t = "", m = box.model
        if (m && m.length !== undefined)
            for (var i = 0; i < m.length; i++) {
                var s = String(box.textRole && m[i] ? m[i][box.textRole] : m[i])
                if (s.length > t.length) t = s
            }
        return t
    } }

    background: Rectangle {
        radius: 7
        visible: !box.form
        color: isMacOS ? (!box.enabled ? Qt.rgba(1, 1, 1, 0.125) : box.pressed || box.popup.visible ? Qt.rgba(1, 1, 1, 0.36) : Qt.rgba(1, 1, 1, 0.25)) : box.pressed || box.popup.visible ? Qt.rgba(1, 1, 1, 0.16)
             : box.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.08)
        border.color: isMacOS ? (box.activeFocus ? MacColors.keyboardFocusIndicator : "transparent") : box.activeFocus ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.10)
    }

    // In the form style the text runs from the left edge to 4 pt before the
    // chevron box, whatever padding the style gives the control
    contentItem: Text {
        leftPadding: box.form ? -box.leftPadding : 10
        rightPadding: box.form ? 22 - box.rightPadding : 26
        text: box.displayText
        font: box.font
        color: isMacOS ? (box.form ? (box.enabled ? MacColors.label : MacColors.tertiaryLabel) : box.enabled ? Qt.rgba(1, 1, 1, 0.89) : Qt.rgba(1, 1, 1, 0.35)) : box.enabled ? "white" : Qt.rgba(1, 1, 1, 0.4)
        horizontalAlignment: box.form ? Text.AlignRight : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Rectangle {
        x: box.form ? box.width - 18 : box.width - width - 9
        anchors.verticalCenter: parent.verticalCenter
        width: box.form ? 16 : chevrons.width
        height: box.form ? 16 : chevrons.height
        radius: 4
        color: box.form ? Qt.rgba(1, 1, 1, box.enabled ? 0.1 : 0.05) : "transparent"
        Column {
            id: chevrons
            anchors.centerIn: parent
            spacing: box.form ? -5 : -4
            Icon { name: "chev-up"; size: box.form ? 10 : 11; color: isMacOS ? (box.form && !box.enabled ? MacColors.tertiaryLabel : "white") : Qt.rgba(1, 1, 1, 0.6) }
            Icon { name: "chev-down"; size: box.form ? 10 : 11; color: isMacOS ? (box.form && !box.enabled ? MacColors.tertiaryLabel : "white") : Qt.rgba(1, 1, 1, 0.6) }
        }
    }

    delegate: ItemDelegate {
        id: opt
        width: box.popup.width - 8
        x: 4
        height: 28
        highlighted: box.highlightedIndex === index
        contentItem: Row {
            spacing: 6
            Text {
                width: 14
                text: index === box.currentIndex ? "✓" : ""
                font.pixelSize: 12
                color: isMacOS ? (opt.highlighted ? "white" : MacColors.label) : "white"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: box.textRole ? (Array.isArray(box.model) ? modelData[box.textRole] : model[box.textRole]) : modelData
                font: box.font
                color: isMacOS ? (opt.highlighted ? "white" : MacColors.label) : "white"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 6
            color: isMacOS ? (opt.highlighted ? MacColors.selectedContentBackground : "transparent") : opt.highlighted ? "#0a7cff" : "transparent"
        }
    }

    popup: Popup {
        y: box.height + 4
        width: Math.max(box.width, widest.width + 56)
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 320)
        padding: 4
        background: Rectangle {
            radius: 9
            color: "#1d1d1f"
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: box.popup.visible ? box.delegateModel : null
            currentIndex: box.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
