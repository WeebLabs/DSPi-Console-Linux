import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import DSPi 1.0
import "components"

Column {
    id: filterResponseRoot
    spacing: 0
    // The open channel's graph editor; the band list shares its selection
    property alias peqEditor: editor
    // In the pop-out window: fills its height, has a legend, and can keep
    // its own channel visibility instead of following the main window
    property bool popOut: false
    readonly property bool follows: !popOut || root.graphPopOutFollows
    property var popOutChannels: []
    function togglePopOutChannel(ch) {
        var l = popOutChannels.slice(), i = l.indexOf(ch)
        if (i >= 0) l.splice(i, 1); else l.push(ch)
        popOutChannels = l
    }
    // Its own selection starts with the live inputs and enabled outputs
    Component.onCompleted: {
        if (!popOut) return
        var l = []
        for (var i = 0; i < bridge.liveInputCount(); i++) l.push(bridge.inputAppId(i))
        for (var o = 0; o < bridge.numOutputChannels; o++) if (bridge.outputEnabled(o)) l.push(o + 2)
        popOutChannels = l
    }

    // Gap below the titlebar
    Item { width: parent.width; height: 6 }

    // Bode plot
    Item {
        id: plotContainer
        width: parent.width
        height: filterResponseRoot.popOut ? filterResponseRoot.height - 6 - legend.height
                                          : Math.max(250, Math.min(350, root.graphHeight))

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            radius: 8
            // The dark row colour of the dashboard cards, as on macOS
            color: isMacOS ? Qt.tint(MacColors.mainContentOpaque, MacColors.opacity(MacColors.controlBackground, 0.6)) : nativeAltBaseColor
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            clip: true

            // Pointer over the graph, whatever item under it takes the hover
            PointerTracker { id: plotPointer; anchors.fill: parent }

            // Grid and labels, under the spectrum
            BodePlotItem {
                anchors.fill: parent
                drawLayer: 1
                gridOpacity: root.graphGridOpacity
                lineWidth: root.graphLineWidth
                showFreqGrid: root.graphShowFreqGrid
                showFreqLabels: root.graphShowFreqLabels
                showDbGrid: root.graphShowDbGrid
                showDbLabels: root.graphShowDbLabels
                dbTop: bodePlot.dbTop
                dbBottom: bodePlot.dbBottom
                minFreq: root.graphMinFreq
                maxFreq: root.graphMaxFreq
            }

            // The device's spectrum, behind the response curves
            SpectrumCurveItem {
                id: spectrum
                anchors.fill: parent
                controller: rta
                // Not while its window is minimised: nobody sees it
                active: root.rtaShowGraph && bridge.connected && Window.visibility !== Window.Minimized
                readonly property bool wanted: active && rta.supported && channels.length > 0
                opacity: wanted ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                tap: root.rtaSelection.tap
                channels: root.rtaSelection.channels
                colors: channels.map(function (c) { return bridge.channelColor(rta.appChannel(tap, c)) })
                floorDb: root.rtaFloorDb
                ceilingDb: root.rtaCeilingDb
                minFreq: root.graphMinFreq
                maxFreq: root.graphMaxFreq
                strength: root.rtaGraphOpacity
                glow: root.graphShowGlow
                showPeak: root.rtaShowPeakHold
                smoothing: root.rtaSmoothing
            }

            // The response curves and phase, over the spectrum
            BodePlotItem {
                id: bodePlot
                anchors.fill: parent
                drawLayer: 2
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
                followVisibility: filterResponseRoot.follows
                shownChannels: filterResponseRoot.popOutChannels
                showPhase: root.graphShowPhase
                phaseUnwrapped: root.graphPhaseUnwrapped
                phaseChannel: root.openChannelId
                Component.onCompleted: setBridge(bridge)
            }

            // Drag, select and create the open channel's bands on the graph
            PeqEditorItem {
                id: editor
                anchors.fill: parent
                channel: filterResponseRoot.follows && !root.crossoverTabOpen ? root.openChannelId : -1
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
                    graphMenu.band = band
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

            // Graph options: shown while the pointer is over the graph
            Rectangle {
                id: gearButton
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                width: 24
                height: 22
                radius: 6
                opacity: plotPointer.containsPointer || graphOptions.visible ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
                color: isMacOS ? "transparent" : gearMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : gearMouse.containsMouse || graphOptions.visible
                       ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                Icon {
                    anchors.centerIn: parent
                    name: "gear"
                    size: 14
                    color: Qt.rgba(1, 1, 1, graphOptions.visible ? 0.95 : 0.7)
                }
                MouseArea {
                    id: gearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: graphOptions.toggleBelow(gearButton)
                    ToolTip.visible: containsMouse && !graphOptions.visible
                    ToolTip.delay: 600
                    ToolTip.text: "Graph and spectrum options"
                }
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

    // Pop-out: the channel pills
    GraphLegend {
        id: legend
        visible: filterResponseRoot.popOut
        height: visible ? 36 : 0
        width: parent.width
        leftPadding: 16
        follow: filterResponseRoot.follows
        shown: filterResponseRoot.popOutChannels
        onToggled: filterResponseRoot.togglePopOutChannel(channel)
    }

    // Resize handle
    Item {
        visible: !filterResponseRoot.popOut
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
                    root.graphHeight = Math.max(250, Math.min(350, newHeight))
                }
            }
        }
    }


    GraphOptionsPopup {
        id: graphOptions
        transientParent: filterResponseRoot.Window.window
        app: root
        inPopOut: filterResponseRoot.popOut
        onPopOutRequested: root.openToolWindow("graph")
    }

    ActionMenu {
        id: graphMenu
        parent: Overlay.overlay
        property int band: -1             // the band right-clicked, -1 = empty graph
        onTriggered: {
            if (key === "delete") editor.deleteSelection()
            else if (key === "bypass") editor.toggleBypass(band)
            else if (key === "invert") editor.invertGainSelection()
            else if (key === "order1") editor.setOrderSelection(1)
            else if (key === "order2") editor.setOrderSelection(2)
            else if (key === "all") editor.selectAll()
            else if (key === "none") editor.deselectAll()
        }
    }
}
