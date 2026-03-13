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
        topPadding: 4
        leftPadding: 16
        rightPadding: 16

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
            model: {
                // Build list of output card definitions
                var cards = []
                var numOut = bridge.numOutputChannels
                var i = 0
                while (i < numOut) {
                    if (bridge.outputEnabled(i)) {
                        // Check if next output forms a stereo pair
                        if (i + 1 < numOut && bridge.outputEnabled(i + 1)) {
                            cards.push({
                                stereo: true,
                                leftIdx: i,
                                rightIdx: i + 1
                            })
                            i += 2
                        } else {
                            cards.push({
                                stereo: false,
                                leftIdx: i,
                                rightIdx: -1
                            })
                            i++
                        }
                    } else {
                        i++
                    }
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
                bandCount: 10
            }
        }

        // Spacer at bottom
        Item { width: 1; height: 16 }
    }
}
