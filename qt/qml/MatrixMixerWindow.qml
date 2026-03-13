import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

Window {
    id: matrixWindow
    title: "Matrix Mixer"
    visible: false
    width: matrixContent.implicitWidth + 32
    height: matrixContent.implicitHeight + 32
    minimumWidth: width
    minimumHeight: height
    maximumWidth: width
    maximumHeight: height
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    property int columnWidth: 72
    property int labelWidth: 75
    readonly property var inputNames: ["Input L", "Input R"]
    readonly property var inputColors: ["#4A8FE3", "#F57373"]

    // Build visible output list
    function visibleOutputs() {
        var outputs = []
        var numOut = bridge.numOutputChannels
        for (var i = 0; i < numOut; i++) {
            outputs.push(i)
        }
        return outputs
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 16
        radius: 10
        color: Qt.rgba(0.21, 0.21, 0.21, 0.4)
        border.color: Qt.rgba(1, 1, 1, 0.1)
        border.width: 1

        Column {
            id: matrixContent
            anchors.fill: parent
            spacing: 0

            // Column headers
            Row {
                spacing: 0

                Item { width: labelWidth; height: 48 }

                Repeater {
                    model: visibleOutputs()

                    Column {
                        width: columnWidth
                        height: 48
                        spacing: 3

                        property color parsedColor: bridge.channelColor(modelData + 2)

                        Item { width: 1; height: 6 }

                        Text {
                            width: parent.width
                            text: bridge.channelName(modelData + 2)
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.7)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: bridge.channelDescriptor(modelData + 2)
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            color: Qt.rgba(parent.parsedColor.r, parent.parsedColor.g, parent.parsedColor.b, 0.8)
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            // Section divider
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

            // ROUTING label
            Rectangle {
                width: parent.width; height: 22
                color: Qt.rgba(1, 1, 1, 0.015)
                Text {
                    text: "ROUTING"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.35)
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Input rows (2 inputs)
            Repeater {
                model: 2

                Column {
                    property int inputIndex: index
                    spacing: 0
                    width: parent.width

                    Row {
                        spacing: 0
                        height: 78

                        Text {
                            width: labelWidth
                            text: inputNames[index]
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: inputColors[index]
                            horizontalAlignment: Text.AlignCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Repeater {
                            model: visibleOutputs()

                            MatrixPoint {
                                isConnected: bridge.matrixRouting(inputIndex, modelData)
                                gain: bridge.matrixGain(inputIndex, modelData)
                                isInverted: bridge.matrixInvert(inputIndex, modelData)
                                inputColor: inputColors[inputIndex]
                                outputColor: bridge.channelColor(modelData + 2)

                                onConnectionToggled: {
                                    bridge.setMatrixRoute(inputIndex, modelData, connected,
                                        bridge.matrixGain(inputIndex, modelData),
                                        bridge.matrixInvert(inputIndex, modelData))
                                }
                                onGainEdited: {
                                    bridge.setMatrixRoute(inputIndex, modelData,
                                        bridge.matrixRouting(inputIndex, modelData),
                                        newGain,
                                        bridge.matrixInvert(inputIndex, modelData))
                                }
                                onInvertToggled: {
                                    bridge.setMatrixRoute(inputIndex, modelData,
                                        bridge.matrixRouting(inputIndex, modelData),
                                        bridge.matrixGain(inputIndex, modelData),
                                        inverted)
                                }
                            }
                        }
                    }

                    // Divider between input rows
                    Rectangle {
                        visible: index === 0
                        width: parent.width - labelWidth
                        x: labelWidth
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }
                }
            }

            // Section divider
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

            // OUTPUT label
            Rectangle {
                width: parent.width; height: 22
                color: Qt.rgba(1, 1, 1, 0.015)
                Text {
                    text: "OUTPUT"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.35)
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ENABLE row
            Row {
                height: 30
                spacing: 0

                Text {
                    width: labelWidth
                    text: "ENABLE"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: visibleOutputs()
                    Item {
                        width: columnWidth; height: 30

                        Text {
                            anchors.centerIn: parent
                            text: "\u23FB" // power symbol
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: bridge.outputEnabled(modelData) ? "#0078d4" : Qt.rgba(1, 1, 1, 0.3)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bridge.setOutputEnable(modelData, !bridge.outputEnabled(modelData))
                        }
                    }
                }
            }

            // Subtle divider
            Rectangle {
                width: parent.width - labelWidth
                x: labelWidth
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            // GAIN row
            Row {
                height: 30
                spacing: 0

                Text {
                    width: labelWidth
                    text: "GAIN"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: visibleOutputs()
                    Item {
                        width: columnWidth; height: 30
                        opacity: bridge.outputEnabled(modelData) ? 1.0 : 0.3

                        TextField {
                            width: 50; height: 20
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            font.family: "Menlo"
                            color: activeFocus ? "#0078d4" : Qt.rgba(1, 1, 1, 0.65)
                            horizontalAlignment: Text.AlignCenter
                            selectByMouse: true
                            padding: 2
                            background: Rectangle { color: "transparent" }

                            property real gainVal: bridge.outputGainDB(modelData)
                            text: gainVal === 0 ? "0 dB" : (gainVal > 0 ? "+" : "") + gainVal.toFixed(0) + " dB"

                            onEditingFinished: {
                                var v = parseFloat(text.replace("dB", "").trim())
                                if (!isNaN(v)) bridge.setOutputGain(modelData, Math.max(-60, Math.min(12, v)))
                            }

                            Connections {
                                target: bridge
                                function onStateChanged() {
                                    gainVal = bridge.outputGainDB(modelData)
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: {
                                    var delta = wheel.angleDelta.y > 0 ? 1 : -1
                                    bridge.setOutputGain(modelData, Math.max(-60, Math.min(12, bridge.outputGainDB(modelData) + delta)))
                                }
                            }
                        }
                    }
                }
            }

            // Subtle divider
            Rectangle { width: parent.width - labelWidth; x: labelWidth; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }

            // DELAY row
            Row {
                height: 30
                spacing: 0

                Text {
                    width: labelWidth
                    text: "DELAY"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: visibleOutputs()
                    Item {
                        width: columnWidth; height: 30
                        opacity: bridge.outputEnabled(modelData) ? 1.0 : 0.3

                        TextField {
                            width: 50; height: 20
                            anchors.centerIn: parent
                            font.pixelSize: 11
                            font.family: "Menlo"
                            color: activeFocus ? "#0078d4" : Qt.rgba(1, 1, 1, 0.65)
                            horizontalAlignment: Text.AlignCenter
                            selectByMouse: true
                            padding: 2
                            background: Rectangle { color: "transparent" }

                            property real delayVal: bridge.outputDelayMS(modelData)
                            text: delayVal === 0 ? "0 ms" : delayVal.toFixed(1) + " ms"

                            onEditingFinished: {
                                var v = parseFloat(text.replace("ms", "").trim())
                                if (!isNaN(v)) bridge.setOutputDelay(modelData, Math.max(0, Math.min(85, v)))
                            }

                            Connections {
                                target: bridge
                                function onStateChanged() {
                                    delayVal = bridge.outputDelayMS(modelData)
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: {
                                    var delta = wheel.angleDelta.y > 0 ? 0.5 : -0.5
                                    bridge.setOutputDelay(modelData, Math.max(0, Math.min(85, bridge.outputDelayMS(modelData) + delta)))
                                }
                            }
                        }
                    }
                }
            }

            // Subtle divider
            Rectangle { width: parent.width - labelWidth; x: labelWidth; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }

            // MUTE row
            Row {
                height: 30
                spacing: 0

                Text {
                    width: labelWidth
                    text: "MUTE"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                    horizontalAlignment: Text.AlignRight
                    rightPadding: 8
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: visibleOutputs()
                    Item {
                        width: columnWidth; height: 30
                        opacity: bridge.outputEnabled(modelData) ? 1.0 : 0.3

                        Text {
                            anchors.centerIn: parent
                            text: bridge.outputMuted(modelData) ? "\uD83D\uDD07" : "\uD83D\uDD0A"
                            font.pixelSize: 12
                            color: bridge.outputMuted(modelData) ? "#f44336" : Qt.rgba(1, 1, 1, 0.4)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bridge.setOutputMute(modelData, !bridge.outputMuted(modelData))
                        }
                    }
                }
            }

            Item { width: 1; height: 4 }
        }
    }
}
