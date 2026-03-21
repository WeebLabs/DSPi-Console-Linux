import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import DSPi 1.0
import "components"

Column {
    id: filterResponseRoot
    spacing: 0

    // Header
    Item {
        width: parent.width
        height: 40

        Text {
            text: "Filter Response"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: "white"
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
        }

        // Connection status
        Row {
            spacing: 6
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                width: 6; height: 6; radius: 3
                color: bridge.connected ? "#4caf50" : "#f44336"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: {
                    if (bridge.availableSerials.length === 0) return "No Devices"
                    return bridge.selectedSerial || "No Device"
                }
                font.pixelSize: 11
                color: bridge.connected ? Qt.rgba(1, 1, 1, 0.7) : "#f44336"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Bode plot
    Item {
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
                Component.onCompleted: setBridge(bridge)
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

    // Graph legend
    GraphLegend {
        width: parent.width
        leftPadding: 16
    }
}
