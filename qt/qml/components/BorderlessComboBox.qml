import QtQuick 2.15
import QtQuick.Controls 2.15

ComboBox {
    id: comboRoot
    height: 24
    font.pixelSize: 11

    background: Rectangle {
        color: isMacOS ? (comboRoot.hovered && comboRoot.enabled ? Qt.rgba(1, 1, 1, 0.25) : "transparent") : "transparent"
        border.color: isMacOS ? "transparent" : comboRoot.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
        border.width: 1
        radius: 4
    }

    contentItem: Text {
        text: comboRoot.displayText
        font: comboRoot.font
        color: isMacOS ? (comboRoot.enabled ? Qt.rgba(1, 1, 1, 0.89) : Qt.rgba(1, 1, 1, 0.35)) : comboRoot.enabled ? "white" : Qt.rgba(1, 1, 1, 0.4)
        verticalAlignment: Text.AlignVCenter
        leftPadding: 6
        rightPadding: 16
        elide: Text.ElideRight
    }

    indicator: Text {
        text: "\u25B4\u25BE" // up/down triangles
        font.pixelSize: 8
        font.weight: Font.Bold
        color: Qt.rgba(1, 1, 1, 0.5)
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
    }

    popup: Popup {
        y: comboRoot.height
        width: comboRoot.width
        implicitHeight: contentItem.implicitHeight + 2
        padding: 1

        background: Rectangle {
            color: "#353535"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
            radius: 6
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: comboRoot.popup.visible ? comboRoot.delegateModel : null
            currentIndex: comboRoot.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
        }
    }

    delegate: ItemDelegate {
        width: comboRoot.width
        height: 24

        contentItem: Text {
            text: modelData
            font.pixelSize: 11
            color: isMacOS ? (highlighted ? "white" : MacColors.label) : highlighted ? "white" : Qt.rgba(1, 1, 1, 0.8)
            verticalAlignment: Text.AlignVCenter
            leftPadding: 6
        }

        highlighted: comboRoot.highlightedIndex === index

        background: Rectangle {
            color: isMacOS ? (highlighted ? MacColors.selectedContentBackground : "transparent") : highlighted ? "#0078d4" : "transparent"
            radius: 3
        }
    }
}
