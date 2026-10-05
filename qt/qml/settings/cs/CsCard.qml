import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components"

// One card on the Control pages: a header (disclosure chevron, badge, an
// editable name over a one-line summary, trailing status, remove), the
// body rows while expanded, and a footer (the Apply row).
Rectangle {
    id: card
    property bool expanded: false
    property string name: ""
    property string placeholder: ""
    property bool nameEditable: true
    property string summary: ""
    property color summaryColor: Qt.rgba(1, 1, 1, 0.5)
    property bool removable: true
    property string removeTip: "Remove"
    default property alias body: bodyColumn.data
    property alias badge: badgeSlot.data
    property alias trailing: trailingRow.data
    property alias footer: footerColumn.data
    signal toggle()
    signal nameEdited(string text)
    signal removeClicked()

    width: parent ? parent.width : 400
    height: column.height
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.045)
    border.color: Qt.rgba(1, 1, 1, 0.07)

    Column {
        id: column
        width: parent.width

        Item {
            id: header
            width: parent.width
            height: 48

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: card.toggle()
            }
            Icon {
                id: chevron
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "chev-right"
                size: 13
                color: Qt.rgba(1, 1, 1, 0.5)
                rotation: card.expanded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            Item {
                id: badgeSlot
                x: chevron.x + chevron.width + 8
                width: childrenRect.width
                height: childrenRect.height
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.left: badgeSlot.right
                anchors.leftMargin: 10
                anchors.right: trailingRow.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                // The name edits in place; Return or a click elsewhere commits
                TextInput {
                    id: nameInput
                    width: Math.min(parent.width, Math.max(60, Math.max(contentWidth, placeholderText.implicitWidth) + 12))
                    height: 20
                    leftPadding: 4
                    rightPadding: 4
                    x: -4
                    verticalAlignment: Text.AlignVCenter
                    text: card.name
                    readOnly: !card.nameEditable
                    maximumLength: 31
                    selectByMouse: true
                    clip: true
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: "white"
                    selectionColor: "#0a7cff"
                    onEditingFinished: if (text !== card.name) card.nameEdited(text)
                    Keys.onEscapePressed: { text = card.name; focus = false }
                    Connections {
                        target: card
                        function onNameChanged() { if (!nameInput.activeFocus) nameInput.text = card.name }
                    }
                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        radius: 5
                        color: nameInput.activeFocus ? Qt.rgba(1, 1, 1, 0.10)
                             : nameHover.containsMouse && card.nameEditable ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        border.width: nameInput.activeFocus ? 1.5 : 0
                        border.color: "#0a7cff"
                    }
                    Text {
                        id: placeholderText
                        visible: nameInput.text === "" && !nameInput.activeFocus
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.placeholder
                        font: nameInput.font
                        color: "white"
                    }
                    MouseArea {
                        id: nameHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        cursorShape: card.nameEditable ? Qt.IBeamCursor : Qt.ArrowCursor
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: card.summary
                    font.pixelSize: 11
                    color: card.summaryColor
                }
            }
            Row {
                id: trailingRow
                anchors.right: removeButton.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
            }
            CsButton {
                id: removeButton
                visible: card.removable
                bare: true
                icon: "trash"
                tip: card.removeTip
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                onClicked: card.removeClicked()
            }
        }

        Column {
            id: bodyColumn
            width: parent.width
            visible: card.expanded
        }
        Column {
            id: footerColumn
            width: parent.width
        }
    }
}
