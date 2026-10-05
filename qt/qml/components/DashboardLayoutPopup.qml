import QtQuick 2.15
import QtQuick.Controls 2.15

// The dashboard layout panel (the gear on a card): Auto, or 1, 2 or 3 cards
// per row. Edits root.dashboardCardsPerRow, which is remembered.
Popup {
    id: pop
    width: 220
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    readonly property int chosen: Math.max(0, Math.min(3, root.dashboardCardsPerRow))

    // The gear's own click would reopen a panel its press just closed
    property real closedAt: 0
    onClosed: closedAt = Date.now()
    function toggleBelow(anchorItem) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        var p = anchorItem.mapToItem(parent, anchorItem.width, anchorItem.height + 6)
        x = Math.max(6, Math.min(p.x - width + 10, parent.width - width - 6))
        y = p.y
        open()
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 140; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }
    transformOrigin: Popup.TopRight

    background: Item {
        Repeater {
            model: 6
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1) * 2
                anchors.topMargin: -(index + 1) * 2 + 4
                radius: MenuStyle.radius + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: MenuStyle.radius
            color: MenuStyle.background
            border.color: MenuStyle.border
        }
    }

    contentItem: Column {
        spacing: 8
        Text {
            text: "DASHBOARD LAYOUT"
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.6
            color: Qt.rgba(1, 1, 1, 0.45)
        }
        Row {
            id: tiles
            width: parent.width
            spacing: 6
            Repeater {
                model: 4
                Rectangle {
                    id: tile
                    readonly property int cols: index
                    readonly property bool on: pop.chosen === index
                    width: (tiles.width - 3 * tiles.spacing) / 4
                    height: 38
                    radius: 6
                    color: on ? Qt.rgba(0.04, 0.49, 1, 0.16) : tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                    border.color: on ? Qt.rgba(0.04, 0.49, 1, 0.7) : "transparent"
                    readonly property color fg: on ? "#3a96ff" : Qt.rgba(1, 1, 1, 0.55)
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        // Auto: arrows; 1-3: two rows of that many cells
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 22
                            height: 13
                            Icon { visible: index === 0; anchors.centerIn: parent; name: "arrows-h"; size: 15; color: tile.fg }
                            Grid {
                                visible: tile.cols > 0
                                anchors.fill: parent
                                columns: Math.max(1, tile.cols)
                                spacing: 2
                                Repeater {
                                    model: tile.cols * 2
                                    Rectangle {
                                        width: (22 - 2 * (tile.cols - 1)) / Math.max(1, tile.cols)
                                        height: 5.5
                                        radius: 1.5
                                        color: tile.fg
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: index === 0 ? "Auto" : index
                            font.pixelSize: 10
                            font.weight: tile.on ? Font.DemiBold : Font.Normal
                            color: tile.fg
                        }
                    }
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dashboardCardsPerRow = index
                    }
                    ToolTip.text: index === 0 ? "Fit cards to the window width" : index + (index === 1 ? " card" : " cards") + " per row"
                    ToolTip.visible: tileMouse.containsMouse
                    ToolTip.delay: 600
                }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: pop.chosen === 0 ? "Fits as many cards per row as the window allows."
                                   : "Up to " + pop.chosen + (pop.chosen === 1 ? " card" : " cards") + " per row."
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }
}
