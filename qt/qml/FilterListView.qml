import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

Item {
    id: filterListRoot
    property int channelId: 0

    Column {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0

        // Header row
        Rectangle {
            width: parent.width
            height: 32
            color: "transparent"

            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 0

                Text {
                    width: 24
                    text: "#"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: 100
                    text: "TYPE"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    leftPadding: 4
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: 104
                    text: "FREQ"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: 84
                    text: "GAIN"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: 74
                    text: "WIDTH"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Separator
        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.1)
        }

        // Filter rows
        Repeater {
            model: 10

            FilterRow {
                id: filterRowDelegate
                width: parent.width
                channelId: filterListRoot.channelId
                bandIndex: index
                filterType: bridge.filterType(filterListRoot.channelId, index)
                filterFreq: bridge.filterFreq(filterListRoot.channelId, index)
                filterGain: bridge.filterGain(filterListRoot.channelId, index)
                filterQ: bridge.filterQ(filterListRoot.channelId, index)

                onFilterChanged: {
                    bridge.setFilter(filterListRoot.channelId, bandIndex, type, freq, gain, q)
                }

                Connections {
                    target: bridge
                    function onStateChanged() {
                        filterRowDelegate.filterType = bridge.filterType(filterListRoot.channelId, index)
                        filterRowDelegate.filterFreq = bridge.filterFreq(filterListRoot.channelId, index)
                        filterRowDelegate.filterGain = bridge.filterGain(filterListRoot.channelId, index)
                        filterRowDelegate.filterQ = bridge.filterQ(filterListRoot.channelId, index)
                    }
                }
            }
        }
    }
}
