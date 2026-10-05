import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import DSPi 1.0

// Third-octave bars of the page's spectrum channels, in a grid of 1-4
// columns. The gear (on hover) picks the columns or opens the analyser
// window; the handle along the bottom sets the height.
Item {
    id: strip
    property var app                      // main window: selection and settings
    signal openAnalyser()

    readonly property var sel: app.rtaSelection
    readonly property int count: sel.channels.length
    readonly property bool shown: app.rtaShowBars && rta.supported && bridge.connected && count > 0
    readonly property int columns: Math.max(1, Math.min(count, app.rtaBarColumns))
    readonly property int rows: Math.ceil(count / columns)
    readonly property real cellHeight: count === 1 ? app.rtaBarHeight : Math.round(app.rtaBarHeight * 0.75)

    visible: shown
    height: shown ? card.height : 0

    Rectangle {
        id: card
        width: parent.width
        height: grid.height + 20
        radius: 10
        color: isMacOS ? Qt.rgba(0.21, 0.21, 0.21, 0.6) : nativeAltBaseColor
        border.color: {
            if (strip.count !== 1) return Qt.rgba(1, 1, 1, 0.1)
            var c = Qt.lighter(bridge.channelColor(rta.appChannel(strip.sel.tap, strip.sel.channels[0])), 1.0)
            return Qt.rgba(c.r, c.g, c.b, 0.3)
        }

        HoverHandler { id: cardHover }

        Grid {
            id: grid
            x: 10
            y: 10
            width: parent.width - 20
            columns: strip.columns
            columnSpacing: 12
            rowSpacing: 8
            Repeater {
                model: strip.sel.channels
                Column {
                    readonly property int app: rta.appChannel(strip.sel.tap, modelData)
                    width: (grid.width - (strip.columns - 1) * 12) / strip.columns
                    spacing: 2
                    Row {
                        height: 14
                        spacing: 5
                        Rectangle { width: 5; height: 5; radius: 2.5; color: bridge.channelColor(parent.parent.app); anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: bridge.channelName(parent.parent.app)
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Qt.rgba(1, 1, 1, 0.6)
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, parent.parent.width - 30)
                        }
                    }
                    SpectrumBarsItem {
                        width: parent.width
                        height: strip.cellHeight
                        controller: rta
                        active: strip.shown && Window.visibility !== Window.Minimized
                        tap: strip.sel.tap
                        channel: modelData
                        color: bridge.channelColor(parent.app)
                        floorDb: strip.app.rtaFloorDb
                        ceilingDb: strip.app.rtaCeilingDb
                        showPeak: strip.app.rtaShowPeakHold
                        smoothing: strip.app.rtaSmoothing
                    }
                }
            }
        }

        // Gear: columns and the window, on hover
        Rectangle {
            id: gear
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: 20
            height: 18
            radius: 5
            opacity: cardHover.hovered || options.visible ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
            color: gearMouse.containsMouse || options.visible ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            Icon { anchors.centerIn: parent; name: "gear"; size: 12; color: Qt.rgba(1, 1, 1, 0.7) }
            MouseArea {
                id: gearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (options.visible) { options.close(); return }
                    var p = gear.mapToItem(options.parent, 0, 0)
                    options.x = Math.max(6, Math.min(p.x + gear.width - options.width, options.parent.width - options.width - 6))
                    options.y = p.y + gear.height + 4
                    options.open()
                }
            }
        }

        // Height handle along the bottom edge
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 10
            cursorShape: Qt.SizeVerCursor
            property real startY: 0
            property real startHeight: 0
            onPressed: { startY = mapToItem(null, 0, mouse.y).y; startHeight = strip.app.rtaBarHeight }
            onPositionChanged: {
                if (!pressed) return
                var dy = mapToItem(null, 0, mouse.y).y - startY
                var scale = strip.rows * (strip.count === 1 ? 1 : 0.75)
                strip.app.rtaBarHeight = Math.max(64, Math.min(240, Math.round(startHeight + dy / scale)))
            }
        }
    }

    Popup {
        id: options
        parent: Overlay.overlay
        width: 200
        padding: 10
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 130; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
        background: Item {
            Repeater {
                model: 6
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -(index + 1) * 2
                    anchors.topMargin: -(index + 1) * 2 + 4
                    radius: 11 + (index + 1) * 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
                }
            }
            Rectangle { anchors.fill: parent; radius: 11; color: MenuStyle.background; border.color: MenuStyle.border }
        }

        contentItem: Column {
            spacing: 8
            Text {
                visible: strip.count > 1
                text: "LAYOUT"
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.4
                color: Qt.rgba(1, 1, 1, 0.5)
            }
            Row {
                visible: strip.count > 1
                spacing: 4
                Repeater {
                    model: 4
                    Rectangle {
                        id: tile
                        readonly property int cols: index + 1
                        readonly property bool isCurrent: strip.app.rtaBarColumns === cols
                        width: (180 - 12) / 4
                        height: 38
                        radius: 6
                        color: isCurrent ? Qt.rgba(0.04, 0.49, 1, 0.16) : tileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                        border.color: isCurrent ? Qt.rgba(0.04, 0.49, 1, 0.7) : Qt.rgba(1, 1, 1, 0.08)
                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            // A tiny grid of the layout
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 1.5
                                Repeater {
                                    model: tile.cols
                                    Rectangle {
                                        width: (22 - 1.5 * (tile.cols - 1)) / tile.cols
                                        height: 13
                                        radius: 1.5
                                        color: Qt.rgba(1, 1, 1, 0.45)
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.cols
                                font.pixelSize: 10
                                color: Qt.rgba(1, 1, 1, 0.75)
                            }
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: strip.app.rtaBarColumns = tile.cols
                        }
                    }
                }
            }
            Rectangle { visible: strip.count > 1; width: 180; height: 1; color: MenuStyle.separator }
            Rectangle {
                width: 180
                height: 28
                radius: 6
                color: openMouse.containsMouse ? MenuStyle.highlight : "transparent"
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Icon { name: "spectrum"; size: 15; color: openMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.65); anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Open in Window"; font.pixelSize: 13; color: openMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.9); anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { options.close(); strip.openAnalyser() }
                }
            }
        }
    }
}
