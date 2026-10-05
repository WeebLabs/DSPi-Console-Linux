import QtQuick 2.15
import QtQuick.Controls 2.15

// Channel pills that show or hide curves: the main window's visibility, or
// (follow false) a list of its own, changed through `toggled`.
Item {
    id: legendRoot
    height: 36
    property int leftPadding: 0
    property bool follow: true
    property var shown: []
    signal toggled(int channel)

    property int rev: 0
    Connections { target: bridge; function onMagnitudesChanged() { legendRoot.rev++ } }
    function isVisible(ch) { rev; return follow ? bridge.channelVisible(ch) : shown.indexOf(ch) >= 0 }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: legendRoot.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Master L
        LegendPill {
            eqChannel: 0
            label: bridge.channelDescriptor(0)
            pillColor: bridge.channelColor(0)
        }

        // Master R
        LegendPill {
            eqChannel: 1
            label: bridge.channelDescriptor(1)
            pillColor: bridge.channelColor(1)
        }

        // Live inputs beyond the first pair
        Repeater {
            model: Math.max(0, bridge.liveInputCount() - 2)
            LegendPill {
                eqChannel: bridge.inputAppId(index + 2)
                label: bridge.channelDescriptor(eqChannel)
                pillColor: bridge.channelColor(eqChannel)
            }
        }

        // Enabled outputs
        Repeater {
            model: bridge.numOutputChannels
            LegendPill {
                visible: bridge.outputEnabled(index)
                eqChannel: index + 2
                label: bridge.channelDescriptor(index + 2)
                pillColor: bridge.channelColor(index + 2)
            }
        }
    }

    component LegendPill: Rectangle {
        property int eqChannel: 0
        property string label: ""
        property string pillColor: "#FFFFFF"
        property color parsedColor: pillColor

        width: pillRow.width + 16
        height: 22
        radius: 100
        color: {
            var isVis = legendRoot.isVisible(eqChannel)
            return isVis ? Qt.rgba(parsedColor.r, parsedColor.g, parsedColor.b, 0.15) : Qt.rgba(0.5, 0.5, 0.5, 0.1)
        }
        border.color: {
            var isVis = legendRoot.isVisible(eqChannel)
            return isVis ? Qt.rgba(parsedColor.r, parsedColor.g, parsedColor.b, 0.5) : "transparent"
        }
        border.width: 1

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                width: 6; height: 6; radius: 3
                color: {
                    var isVis = legendRoot.isVisible(eqChannel)
                    return isVis ? pillColor : Qt.rgba(0.5, 0.5, 0.5, 0.5)
                }
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: label
                font.pixelSize: 10
                font.weight: Font.Bold
                color: legendRoot.isVisible(eqChannel) ? "white" : Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (legendRoot.follow) bridge.setChannelVisible(eqChannel, !bridge.channelVisible(eqChannel))
                else legendRoot.toggled(eqChannel)
            }
        }
    }
}
