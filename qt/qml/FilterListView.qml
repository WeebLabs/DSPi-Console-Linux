import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

Item {
    id: filterListRoot
    property int channelId: 0

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        radius: 10
        color: isMacOS ? Qt.rgba(0.21, 0.21, 0.21, 0.6) : nativeAltBaseColor
        border.color: Qt.rgba(1, 1, 1, 0.1)
        border.width: 1
        clip: true

        Column {
            anchors.fill: parent

            // Header row
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 0

                    Text {
                        width: 30
                        text: "#"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.5)
                        horizontalAlignment: Text.AlignLeft
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        width: 120
                        text: "TYPE"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.5)
                        leftPadding: 4
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item {
                        width: 100
                        height: parent.height
                        Text {
                            text: "FREQ"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.5)
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 32
                        }
                    }
                    Item {
                        width: 90
                        height: parent.height
                        Text {
                            text: "GAIN"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.5)
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 26
                        }
                    }
                    Item {
                        width: 80
                        height: parent.height
                        Text {
                            text: "WIDTH"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.5)
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                        }
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
}
