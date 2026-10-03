import QtQuick 2.15
import QtQuick.Controls 2.15

// A sidebar channel row: name, live meter, and a pill that shows or hides the
// channel's curve on the graph.
Rectangle {
    id: rowRoot
    height: 30
    radius: 6
    color: isSelected ? Qt.rgba(1, 1, 1, 0.10)
         : isLinkedHighlight ? Qt.rgba(1, 1, 1, 0.05)
         : hover.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

    property int channelIndex: 0
    property string channelName: ""
    property string channelColor: "#FFFFFF"
    property color parsedColor: channelColor
    property string descriptor: ""
    property real meterLevel: 0
    property bool isClipping: false
    property bool isMuted: false
    property bool isSelected: false
    property bool isLinkedHighlight: false   // partner of the selected linked input
    property bool curveVisible: bridge.channelVisible(channelIndex)
    property bool renaming: false

    signal clicked()

    Connections {
        target: bridge
        function onMagnitudesChanged() { rowRoot.curveVisible = bridge.channelVisible(rowRoot.channelIndex) }
    }

    function startRename() {
        renaming = true
        nameEdit.text = channelName
        nameEdit.forceActiveFocus()
        nameEdit.selectAll()
    }
    function finishRename(commit) {
        if (!renaming) return
        renaming = false
        var name = nameEdit.text.trim()
        if (commit && name.length > 0 && name !== channelName)
            bridge.setChannelName(channelIndex, name.substring(0, 31))
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            if (mouse.button === Qt.RightButton) contextMenu.popup()
            else if (mouse.modifiers & Qt.AltModifier) rowRoot.startRename()
            else rowRoot.clicked()
        }
    }

    // Channel name (or the in-place rename field)
    Text {
        id: nameText
        visible: !renaming
        text: channelName
        width: 96
        elide: Text.ElideRight
        font.pixelSize: 14
        color: isMuted ? Qt.rgba(1, 1, 1, 0.35) : "white"
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
    }
    TextField {
        id: nameEdit
        visible: renaming
        width: 150
        height: 24
        font.pixelSize: 13
        maximumLength: 31
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        onAccepted: rowRoot.finishRename(true)
        onActiveFocusChanged: if (!activeFocus) rowRoot.finishRename(true)
        Keys.onEscapePressed: rowRoot.finishRename(false)
    }

    // Meter (faded while the output is muted)
    MeterBar {
        id: meter
        visible: !renaming
        anchors.left: nameText.right
        anchors.leftMargin: 8
        anchors.right: pill.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        opacity: isMuted ? 0.35 : 1.0
        targetLevel: meterLevel
        clipping: isClipping
        barColor: channelColor
    }

    // Pill: click shows or hides the curve; grey while hidden
    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(40, pillText.implicitWidth + 18)
        height: 20
        radius: 10
        readonly property color tint: curveVisible ? parsedColor : Qt.rgba(0.6, 0.6, 0.6, 1)
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.15)
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.55)
        border.width: 1

        Text {
            id: pillText
            anchors.centerIn: parent
            text: descriptor
            font.pixelSize: 10
            font.weight: Font.Bold
            color: pill.tint
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: bridge.setChannelVisible(rowRoot.channelIndex, !rowRoot.curveVisible)
        }
    }

    Menu {
        id: contextMenu
        MenuItem { text: "Rename"; onTriggered: rowRoot.startRename() }
        MenuSeparator {}
        MenuItem { text: "Copy Parameters"; onTriggered: bridge.copyChannel(rowRoot.channelIndex) }
        MenuItem {
            text: "Paste Parameters"
            onTriggered: bridge.pasteChannel(rowRoot.channelIndex)
        }
    }
}
