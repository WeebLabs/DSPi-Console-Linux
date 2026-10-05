import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

Flickable {
    id: dashboardRoot
    contentHeight: dashboardColumn.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Bumped on every state change: the cards' values re-read in place, and
    // the cards themselves are rebuilt only when the set of cards changes
    property int revision: 0
    Connections {
        target: bridge
        function onStateChanged() { dashboardRoot.revision++; grid.updateCards() }
    }
    Component.onCompleted: grid.updateCards()

    Column {
        id: dashboardColumn
        width: parent.width
        spacing: 18
        topPadding: 0
        leftPadding: 16
        rightPadding: 16

        // Third-octave bars of the dashboard's spectrum channels
        SpectrumBarStrip {
            width: parent.width - 32
            app: root
            onOpenAnalyser: root.openToolWindow("spectrum")
        }

        // The cards: inputs 1 and 2, then the outputs in fixed pairs (Out 1+2,
        // 3+4, ...; both enabled share a card, one alone gets its own) and the
        // PDM subwoofer on its own. Laid out in a grid: as many per row as
        // fit (Auto), or 1-3, set from the gear on any card
        Grid {
            id: grid
            width: dashboardColumn.width - 32
            property var cards: []
            function updateCards() {
                var list = [{ input: true, stereo: true, leftIdx: -1, rightIdx: -1 }]
                var numOut = bridge.numOutputChannels
                for (var i = 0; i < numOut; i++) {
                    if (bridge.isPdmOutput(i)) {
                        if (bridge.outputEnabled(i)) list.push({ stereo: false, leftIdx: i, rightIdx: -1 })
                        continue
                    }
                    var j = i + 1 < numOut && !bridge.isPdmOutput(i + 1) ? i + 1 : -1
                    var a = bridge.outputEnabled(i), b = j >= 0 && bridge.outputEnabled(j)
                    if (a && b) list.push({ stereo: true, leftIdx: i, rightIdx: j })
                    else if (a) list.push({ stereo: false, leftIdx: i, rightIdx: -1 })
                    else if (b) list.push({ stereo: false, leftIdx: j, rightIdx: -1 })
                    if (j >= 0) i = j
                }
                if (JSON.stringify(list) !== JSON.stringify(cards)) cards = list
            }
            // A stereo pair's two lists stay readable down to about 440 px;
            // never more columns than cards, so a short list fills the width
            readonly property int wanted: root.dashboardCardsPerRow > 0 ? root.dashboardCardsPerRow
                                                                         : Math.floor((width + columnSpacing) / (440 + columnSpacing))
            columns: Math.max(1, Math.min(wanted, cards.length))
            columnSpacing: 18
            rowSpacing: 18
            readonly property real cardWidth: (width - columnSpacing * (columns - 1)) / columns

            Repeater {
                model: grid.cards
                Item {
                    id: slot
                    readonly property var c: modelData
                    readonly property int leftCh: c.input ? 0 : c.leftIdx + 2
                    readonly property int rightCh: c.input ? 1 : (c.stereo ? c.rightIdx + 2 : -1)
                    readonly property bool gearShown: cardHover.containsMouse || gearMouse.containsMouse
                                                      || (layoutPopup.visible && layoutPopup.owner === slot)
                    width: grid.cardWidth
                    height: card.height

                    DashboardCard {
                        id: card
                        width: parent.width
                        isStereo: slot.c.stereo
                        leftChannel: slot.leftCh
                        rightChannel: slot.rightCh
                        leftName: { dashboardRoot.revision; return bridge.channelName(slot.leftCh) }
                        rightName: { dashboardRoot.revision; return slot.rightCh >= 0 ? bridge.channelName(slot.rightCh) : "" }
                        leftColor: { dashboardRoot.revision; return bridge.channelColor(slot.leftCh) }
                        rightColor: { dashboardRoot.revision; return slot.rightCh >= 0 ? bridge.channelColor(slot.rightCh) : "" }
                        leftDescriptor: { dashboardRoot.revision; return bridge.channelDescriptor(slot.leftCh) }
                        rightDescriptor: { dashboardRoot.revision; return slot.rightCh >= 0 ? bridge.channelDescriptor(slot.rightCh) : "" }
                        leftDelay: { dashboardRoot.revision; return slot.c.input ? -1 : bridge.outputDelayMS(slot.c.leftIdx) }
                        rightDelay: { dashboardRoot.revision; return !slot.c.input && slot.c.stereo ? bridge.outputDelayMS(slot.c.rightIdx) : -1 }
                        gearVisible: slot.gearShown
                        revision: dashboardRoot.revision
                        bandCount: 10
                    }
                    MouseArea {
                        id: cardHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                    // Layout gear: every card's edits the same dashboard-wide setting
                    Rectangle {
                        id: gear
                        x: parent.width - width - 6
                        y: 8
                        width: 18
                        height: 16
                        radius: 4
                        opacity: slot.gearShown ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
                        color: gearMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : gearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Icon {
                            anchors.centerIn: parent
                            name: "gear"
                            size: 12
                            color: Qt.rgba(1, 1, 1, layoutPopup.visible && layoutPopup.owner === slot ? 0.95 : 0.6)
                        }
                        MouseArea {
                            id: gearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { layoutPopup.owner = slot; layoutPopup.toggleBelow(gear) }
                        }
                        ToolTip.text: "Dashboard layout"
                        ToolTip.visible: gearMouse.containsMouse && !layoutPopup.visible
                        ToolTip.delay: 600
                    }
                }
            }
        }

        // Spacer at bottom
        Item { width: 1; height: 16 }
    }

    DashboardLayoutPopup {
        id: layoutPopup
        property Item owner: null
        parent: Overlay.overlay
    }
}
