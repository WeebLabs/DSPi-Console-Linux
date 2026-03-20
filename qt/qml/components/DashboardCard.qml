import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: cardRoot

    property bool isStereo: false
    property int leftChannel: 0
    property int rightChannel: -1
    property string leftName: ""
    property string rightName: ""
    property string leftColor: "#FFFFFF"
    property string rightColor: "#FFFFFF"
    property color parsedLeftColor: leftColor
    property color parsedRightColor: rightColor
    property string leftDescriptor: ""
    property string rightDescriptor: ""

    property int bandCount: 10
    height: 32 + 1 + (bandCount * 24)

    readonly property var typeShort: ["OFF", "PK", "LS", "HS", "LP", "HP"]

    // Gradient border (left color → right color for stereo, single color for mono)
    Rectangle {
        id: borderRect
        anchors.fill: parent
        radius: 10
        color: "transparent"

        // Gradient fill that acts as the border
        Rectangle {
            anchors.fill: parent
            radius: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(parsedLeftColor.r, parsedLeftColor.g, parsedLeftColor.b, 0.3) }
                GradientStop { position: 0.4; color: Qt.rgba(parsedLeftColor.r, parsedLeftColor.g, parsedLeftColor.b, 0.3) }
                GradientStop { position: 0.6; color: isStereo ? Qt.rgba(parsedRightColor.r, parsedRightColor.g, parsedRightColor.b, 0.3) : Qt.rgba(parsedLeftColor.r, parsedLeftColor.g, parsedLeftColor.b, 0.3) }
                GradientStop { position: 1.0; color: isStereo ? Qt.rgba(parsedRightColor.r, parsedRightColor.g, parsedRightColor.b, 0.3) : Qt.rgba(parsedLeftColor.r, parsedLeftColor.g, parsedLeftColor.b, 0.3) }
            }
        }

        // Inner fill (opaque, covers everything except 1px gradient border)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 9
            color: "#252525"
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            width: parent.width
            height: 32
            color: Qt.rgba(1, 1, 1, 0.01)
            radius: 10

            Row {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Left channel header
                Row {
                    spacing: 6
                    width: isStereo ? parent.width / 2 - 4 : parent.width
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 6; height: 6; radius: 3
                        color: leftColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: leftName
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.7)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: leftDescriptor
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: Qt.rgba(parsedLeftColor.r, parsedLeftColor.g, parsedLeftColor.b, 0.8)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Divider (stereo only)
                Rectangle {
                    visible: isStereo
                    width: 1
                    height: parent.height
                    color: Qt.rgba(0.5, 0.5, 0.5, 0.1)
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Right channel header (stereo only)
                Row {
                    visible: isStereo
                    spacing: 6
                    width: parent.width / 2 - 4
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 6; height: 6; radius: 3
                        color: rightColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: rightName
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.7)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: rightDescriptor
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: Qt.rgba(parsedRightColor.r, parsedRightColor.g, parsedRightColor.b, 0.8)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // Separator
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.5, 0.5, 0.5, 0.1) }

        // Band rows
        Repeater {
            model: bandCount

            Rectangle {
                width: cardRoot.width
                height: 24
                color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 0

                    // Band number
                    Text {
                        width: 20
                        text: (index + 1).toString()
                        font.pixelSize: 10
                        font.family: root.monoFont
                        color: Qt.rgba(1, 1, 1, 0.5)
                        horizontalAlignment: Text.AlignCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Left channel values
                    Item {
                        width: isStereo ? (parent.width - 20) / 2 : parent.width - 20
                        height: parent.height

                        Row {
                            anchors.fill: parent
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: 24
                                text: typeShort[bridge.filterType(leftChannel, index)] || "OFF"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: bridge.filterType(leftChannel, index) > 0 ? "white" : Qt.rgba(1, 1, 1, 0.3)
                                horizontalAlignment: Text.AlignCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                visible: bridge.filterType(leftChannel, index) > 0
                                text: bridge.filterFreq(leftChannel, index).toFixed(1) + " Hz"
                                font.pixelSize: 10
                                font.family: root.monoFont
                                color: Qt.rgba(1, 1, 1, 0.7)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: bridge.filterType(leftChannel, index) > 0
                                text: bridge.filterGain(leftChannel, index).toFixed(1) + " dB"
                                font.pixelSize: 10
                                font.family: root.monoFont
                                color: Qt.rgba(1, 1, 1, 0.7)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: bridge.filterType(leftChannel, index) > 0
                                text: "Q " + bridge.filterQ(leftChannel, index).toFixed(3)
                                font.pixelSize: 10
                                font.family: root.monoFont
                                color: Qt.rgba(1, 1, 1, 0.7)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Right channel values (stereo)
                    Item {
                        visible: isStereo
                        width: (parent.width - 20) / 2
                        height: parent.height

                        Row {
                            anchors.fill: parent
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: 24
                                text: rightChannel >= 0 ? (typeShort[bridge.filterType(rightChannel, index)] || "OFF") : ""
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: rightChannel >= 0 && bridge.filterType(rightChannel, index) > 0 ? "white" : Qt.rgba(1, 1, 1, 0.3)
                                horizontalAlignment: Text.AlignCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                visible: rightChannel >= 0 && bridge.filterType(rightChannel, index) > 0
                                text: bridge.filterFreq(rightChannel, index).toFixed(1) + " Hz"
                                font.pixelSize: 10
                                font.family: root.monoFont
                                color: Qt.rgba(1, 1, 1, 0.7)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: rightChannel >= 0 && bridge.filterType(rightChannel, index) > 0
                                text: bridge.filterGain(rightChannel, index).toFixed(1) + " dB"
                                font.pixelSize: 10
                                font.family: root.monoFont
                                color: Qt.rgba(1, 1, 1, 0.7)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: rightChannel >= 0 && bridge.filterType(rightChannel, index) > 0
                                text: "Q " + bridge.filterQ(rightChannel, index).toFixed(3)
                                font.pixelSize: 10
                                font.family: root.monoFont
                                color: Qt.rgba(1, 1, 1, 0.7)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
