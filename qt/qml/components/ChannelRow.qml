import QtQuick 2.15
import QtQuick.Controls 2.15
import DSPi 1.0

Rectangle {
    id: rowRoot
    height: 34
    color: isSelected ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

    property int channelIndex: 0
    property string channelName: ""
    property string channelColor: "#FFFFFF"
    property color parsedColor: channelColor
    property string descriptor: ""
    property real meterLevel: 0
    property bool isClipping: false
    property bool isMuted: false
    property bool isSelected: false

    signal clicked()

    // Left accent bar
    Rectangle {
        id: accentBar
        x: 20
        width: 3
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        color: isSelected ? "#0078d4" : "transparent"
        radius: 1.5
    }

    // Channel name
    Text {
        id: nameText
        text: channelName
        font.pixelSize: 13
        color: isMuted ? Qt.rgba(1, 1, 1, 0.3) : (isSelected ? Qt.rgba(1, 1, 1, 0.9) : "white")
        anchors.left: accentBar.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        elide: Text.ElideNone
    }

    // Meter
    MeterBar {
        id: meter
        anchors.left: nameText.right
        anchors.leftMargin: 12
        anchors.right: descriptorBadge.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        level: meterLevel
        clipping: isClipping
        barColor: channelColor
    }

    // Descriptor badge
    Rectangle {
        id: descriptorBadge
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(28, descriptorText.width + 12)
        height: 16
        radius: 100
        color: Qt.rgba(parsedColor.r, parsedColor.g, parsedColor.b, 0.15)
        border.color: Qt.rgba(parsedColor.r, parsedColor.g, parsedColor.b, 0.4)
        border.width: 1

        Text {
            id: descriptorText
            anchors.centerIn: parent
            text: descriptor
            font.pixelSize: 8
            font.weight: Font.Bold
            color: channelColor
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: rowRoot.clicked()
    }
}
