import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

Flickable {
    id: dashboardRoot
    contentHeight: dashboardColumn.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

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

        // Master L/R stereo card
        DashboardCard {
            width: parent.width - 32
            isStereo: true
            leftChannel: 0
            rightChannel: 1
            leftName: bridge.channelName(0)
            rightName: bridge.channelName(1)
            leftColor: bridge.channelColor(0)
            rightColor: bridge.channelColor(1)
            leftDescriptor: bridge.channelDescriptor(0)
            rightDescriptor: bridge.channelDescriptor(1)
            bandCount: 10
        }

        // Output channel cards (stereo pairs where applicable)
        Repeater {
            // Fixed pairs (Out 1+2, 3+4, ...): both enabled share a card, one
            // alone gets its own; the PDM subwoofer has a card of its own
            model: {
                bridge.numOutputChannels
                var cards = []
                var numOut = bridge.numOutputChannels
                for (var i = 0; i < numOut; i++) {
                    if (bridge.isPdmOutput(i)) {
                        if (bridge.outputEnabled(i)) cards.push({ stereo: false, leftIdx: i, rightIdx: -1 })
                        continue
                    }
                    var j = i + 1 < numOut && !bridge.isPdmOutput(i + 1) ? i + 1 : -1
                    var a = bridge.outputEnabled(i), b = j >= 0 && bridge.outputEnabled(j)
                    if (a && b) cards.push({ stereo: true, leftIdx: i, rightIdx: j })
                    else if (a) cards.push({ stereo: false, leftIdx: i, rightIdx: -1 })
                    else if (b) cards.push({ stereo: false, leftIdx: j, rightIdx: -1 })
                    if (j >= 0) i = j
                }
                return cards
            }

            DashboardCard {
                width: dashboardColumn.width - 32
                isStereo: modelData.stereo
                leftChannel: modelData.leftIdx + 2
                rightChannel: modelData.stereo ? modelData.rightIdx + 2 : -1
                leftName: bridge.channelName(modelData.leftIdx + 2)
                rightName: modelData.stereo ? bridge.channelName(modelData.rightIdx + 2) : ""
                leftColor: bridge.channelColor(modelData.leftIdx + 2)
                rightColor: modelData.stereo ? bridge.channelColor(modelData.rightIdx + 2) : ""
                leftDescriptor: bridge.channelDescriptor(modelData.leftIdx + 2)
                rightDescriptor: modelData.stereo ? bridge.channelDescriptor(modelData.rightIdx + 2) : ""
                leftDelay: bridge.outputDelayMS(modelData.leftIdx)
                rightDelay: modelData.stereo ? bridge.outputDelayMS(modelData.rightIdx) : -1
                bandCount: 10
            }
        }

        // Spacer at bottom
        Item { width: 1; height: 16 }
    }
}
