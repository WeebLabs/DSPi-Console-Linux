import QtQuick 2.15
import QtQuick.Controls 2.15

// Dark rounded drop-down. Sizes itself to the longest option unless a width
// is given; the list shows a check mark on the current item.
ComboBox {
    id: box
    implicitHeight: 28
    implicitWidth: Math.max(96, Math.ceil(widest.advanceWidth) + 56)
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
        color: box.pressed || box.popup.visible ? Qt.rgba(1, 1, 1, 0.16)
             : box.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.08)
        border.color: box.activeFocus ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.10)
    }

    contentItem: Text {
        leftPadding: 10
        rightPadding: 26
        text: box.displayText
        font: box.font
        color: box.enabled ? "white" : Qt.rgba(1, 1, 1, 0.4)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Column {
        x: box.width - width - 9
        anchors.verticalCenter: parent.verticalCenter
        spacing: -4
        Icon { name: "chev-up"; size: 11; color: Qt.rgba(1, 1, 1, 0.6) }
        Icon { name: "chev-down"; size: 11; color: Qt.rgba(1, 1, 1, 0.6) }
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
                color: "white"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: box.textRole ? (Array.isArray(box.model) ? modelData[box.textRole] : model[box.textRole]) : modelData
                font: box.font
                color: "white"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            radius: 6
            color: opt.highlighted ? "#0a7cff" : "transparent"
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
