import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: pointRoot
    width: 72
    height: 78

    property bool isConnected: false
    property real gain: 0
    property bool isInverted: false
    property string inputColor: "#4A8FE3"
    property string outputColor: "#45C2A3"
    property bool isHovering: false

    signal connectionToggled(bool newConnected)
    signal gainEdited(real newGain)
    signal invertToggled(bool newInverted)

    Column {
        anchors.fill: parent
        spacing: 0

        // Gain field (when connected)
        Item {
            width: parent.width
            height: 22
            visible: isConnected

            TextField {
                id: gainField
                width: 50
                height: 20
                anchors.centerIn: parent
                font.pixelSize: 11
                font.family: "Menlo"
                color: activeFocus ? "#0078d4" : Qt.rgba(1, 1, 1, 0.65)
                horizontalAlignment: Text.AlignCenter
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                padding: 2

                background: Rectangle { color: "transparent" }

                text: gain === 0 ? "0 dB" : (gain > 0 ? "+" : "") + gain.toFixed(0) + " dB"

                onEditingFinished: {
                    var cleaned = text.replace("dB", "").trim()
                    var v = parseFloat(cleaned)
                    if (!isNaN(v)) {
                        v = Math.max(-60, Math.min(12, v))
                        pointRoot.gainEdited(v)
                    }
                    text = Qt.binding(function() {
                        return gain === 0 ? "0 dB" : (gain > 0 ? "+" : "") + gain.toFixed(0) + " dB"
                    })
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: {
                        var delta = wheel.angleDelta.y > 0 ? 1 : -1
                        var newVal = Math.max(-60, Math.min(12, gain + delta))
                        pointRoot.gainEdited(newVal)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 16
            visible: !isConnected
        }

        Item { width: 1; height: 4 }

        // Connection circle
        Item {
            width: parent.width
            height: 28

            Rectangle {
                anchors.centerIn: parent
                width: 28; height: 28
                color: "transparent"
                radius: 14

                Rectangle {
                    anchors.centerIn: parent
                    width: isConnected ? 16 : 18
                    height: isConnected ? 16 : 18
                    radius: isConnected ? 8 : 9
                    color: isConnected ? inputColor : "transparent"
                    border.color: isConnected ? "transparent" : (pointRoot.isHovering ? Qt.rgba(0.5, 0.5, 0.5, 0.3) : Qt.rgba(0.5, 0.5, 0.5, 0.12))
                    border.width: pointRoot.isHovering ? 2 : 1.5
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: pointRoot.isHovering = true
                    onExited: pointRoot.isHovering = false
                    onClicked: pointRoot.connectionToggled(!isConnected)
                }
            }
        }

        Item { width: 1; height: 4 }

        // Invert label (when connected)
        Item {
            width: parent.width
            height: 16
            visible: isConnected

            Text {
                anchors.centerIn: parent
                text: "INV"
                font.pixelSize: 9
                font.weight: isInverted ? Font.Bold : Font.Medium
                color: isInverted ? "#ff9800" : Qt.rgba(1, 1, 1, 0.3)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pointRoot.invertToggled(!isInverted)
                }
            }
        }

        Item {
            width: parent.width
            height: 16
            visible: !isConnected
        }
    }
}
