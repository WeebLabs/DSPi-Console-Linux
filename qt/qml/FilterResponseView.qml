import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import DSPi 1.0
import "components"

Column {
    id: filterResponseRoot
    spacing: 0
    // The open channel's graph editor; the band list shares its selection
    property alias peqEditor: editor

    // Gap below the titlebar
    Item { width: parent.width; height: 6 }

    // Bode plot
    Item {
        id: plotContainer
        width: parent.width
        height: 250

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            radius: 8
            color: isMacOS ? "#2C2C2C" : Qt.lighter(nativeBaseColor, 1.4)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            clip: true

            BodePlotItem {
                id: bodePlot
                anchors.fill: parent
                showGlow: root.graphShowGlow
                lineWidth: root.graphLineWidth
                showFreqGrid: root.graphShowFreqGrid
                showFreqLabels: root.graphShowFreqLabels
                showDbGrid: root.graphShowDbGrid
                showDbLabels: root.graphShowDbLabels
                dbTop: root.graphDbCenter + root.graphDbRange / 2
                dbBottom: root.graphDbCenter - root.graphDbRange / 2
                minFreq: root.graphMinFreq
                maxFreq: root.graphMaxFreq
                // The open channel is drawn (and edited) by the editor above
                excludeChannel: editor.active ? editor.channel : -1
                showPhase: root.graphShowPhase
                phaseUnwrapped: root.graphPhaseUnwrapped
                phaseChannel: root.openChannelId
                Component.onCompleted: setBridge(bridge)
            }

            // Drag, select and create the open channel's bands on the graph
            PeqEditorItem {
                id: editor
                anchors.fill: parent
                channel: root.openChannelId
                showGlow: root.graphShowGlow
                lineWidth: root.graphLineWidth
                dbTop: bodePlot.dbTop
                dbBottom: bodePlot.dbBottom
                minFreq: root.graphMinFreq
                maxFreq: root.graphMaxFreq
                showFreqReadout: root.graphFreqReadout
                showLevelReadout: root.graphLevelReadout
                backgroundColor: parent.color
                Component.onCompleted: setBridge(bridge)
                onContextMenuRequested: {
                    var items = []
                    if (band >= 0) {
                        var info = editor.bandInfo(band)
                        items.push({ key: "header", text: selectionCount > 1 ? selectionCount + " Bands" : "Band " + (band + 1), enabled: false })
                        if (info.order > 0) {
                            var labels = info.allPass ? ["180\u00b0", "360\u00b0"] : ["6 dB/oct", "12 dB/oct"]
                            items.push({ key: "order1", text: labels[0], enabled: info.order !== 1 })
                            items.push({ key: "order2", text: labels[1], enabled: info.order !== 2 })
                        }
                        items.push({ separator: true })
                        items.push({ key: "bypass", text: info.bypass ? "Enable" : "Bypass" })
                        if (info.hasGain) items.push({ key: "invert", text: "Invert Gain" })
                        items.push({ separator: true })
                        items.push({ key: "delete", text: selectionCount > 1 ? "Delete " + selectionCount + " Bands" : "Delete Band", danger: true })
                    } else {
                        items.push({ key: "all", text: "Select All Bands", shortcut: "Ctrl+A" })
                        items.push({ key: "none", text: "Deselect All", shortcut: "Esc" })
                        if (selectionCount > 0) {
                            items.push({ separator: true })
                            items.push({ key: "delete", text: selectionCount > 1 ? "Delete Selected Bands" : "Delete Selected Band", danger: true })
                        }
                    }
                    graphMenu.items = items
                    graphMenu.openAt(editor, x, y)
                }
                onShapeCardRequested: {
                    shapeCard.createFreq = freq
                    shapeCard.createGain = gain
                    shapeCard.openBeside(x, y, boost)
                }
            }

            // Ctrl-click: the new band's shape, placed in the graph
            PeqShapeCard {
                id: shapeCard
                parent: editor
                editor: editor
            }

            // The hovered or selected band's controls
            PeqBandHud {
                id: bandHud
                editor: editor
            }

            // Scroll zone over dB axis labels for vertical zoom
            MouseArea {
                x: 0
                y: 0
                width: 48
                height: parent.height
                acceptedButtons: Qt.NoButton
                onWheel: {
                    var delta = wheel.angleDelta.y
                    var step = root.graphDbRange * 0.1
                    if (delta > 0) {
                        // Scroll up — zoom in (reduce range)
                        root.graphDbRange = Math.max(6, root.graphDbRange - step)
                    } else {
                        // Scroll down — zoom out (increase range)
                        root.graphDbRange = Math.min(120, root.graphDbRange + step)
                    }
                }
            }
        }
    }

    // Resize handle
    Item {
        width: parent.width
        height: 8

        Rectangle {
            width: 32
            height: 3
            radius: 1.5
            color: resizeArea.containsMouse || resizeArea.drag.active ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.15)
            anchors.centerIn: parent
        }

        MouseArea {
            id: resizeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SplitVCursor
            property real startY: 0
            property real startHeight: 0

            onPressed: {
                startY = mouseY + parent.mapToItem(filterResponseRoot, 0, 0).y
                startHeight = plotContainer.height
            }
            onPositionChanged: {
                if (pressed) {
                    var currentY = mouseY + parent.mapToItem(filterResponseRoot, 0, 0).y
                    var newHeight = startHeight + (currentY - startY)
                    plotContainer.height = Math.max(250, Math.min(350, newHeight))
                }
            }
        }
    }


    ActionMenu {
        id: graphMenu
        parent: Overlay.overlay
        onTriggered: {
            if (key === "delete") editor.deleteSelection()
            else if (key === "bypass") editor.toggleBypassSelection()
            else if (key === "invert") editor.invertGainSelection()
            else if (key === "order1") editor.setOrderSelection(1)
            else if (key === "order2") editor.setOrderSelection(2)
            else if (key === "all") editor.selectAll()
            else if (key === "none") editor.deselectAll()
        }
    }
}
