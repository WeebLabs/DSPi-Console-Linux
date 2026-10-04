import QtQuick 2.15
import QtQuick.Controls 2.15

// Pick one of a few choices: rounded track, the current segment filled
// with the accent. `tips` gives an optional tooltip per segment.
Rectangle {
    id: seg
    property var model: []
    property int currentIndex: -1
    property var tips: []
    signal activated(int index)

    implicitWidth: 240
    height: 26
    radius: 7
    color: Qt.rgba(1, 1, 1, 0.06)
    border.color: Qt.rgba(1, 1, 1, 0.08)
    opacity: enabled ? 1 : 0.5

    Row {
        anchors.fill: parent
        anchors.margins: 2
        Repeater {
            model: seg.model
            Rectangle {
                readonly property bool isCurrent: seg.currentIndex === index
                width: parent.width / Math.max(1, seg.model.length)
                height: parent.height
                radius: 5
                color: isCurrent ? MenuStyle.highlight
                     : segMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 12
                    font.weight: parent.isCurrent ? Font.DemiBold : Font.Normal
                    color: parent.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.75)
                }
                MouseArea {
                    id: segMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!parent.isCurrent) seg.activated(index)
                    ToolTip.visible: containsMouse && seg.tips.length > index && seg.tips[index] !== ""
                    ToolTip.delay: 500
                    ToolTip.text: seg.tips.length > index ? seg.tips[index] : ""
                }
            }
        }
    }
}
