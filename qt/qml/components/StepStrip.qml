import QtQuick 2.15

// A row of labelled dots showing where a linear process is: steps before
// `current` are ticked, and the last step turns green when reached.
Item {
    id: strip
    property var labels: []
    property int current: 0
    property bool dimmed: false        // a failure: the status card tells the story
    height: 36
    opacity: dimmed ? 0.4 : 1
    readonly property real slot: (width - 16) / Math.max(1, labels.length)
    readonly property int last: labels.length - 1

    Repeater {
        model: Math.max(0, strip.labels.length - 1)
        Rectangle {
            x: 8 + strip.slot * (index + 0.5) + 13
            y: 6
            width: strip.slot - 26
            height: 2
            radius: 1
            color: index + 1 <= strip.current ? Qt.rgba(0.04, 0.49, 1, 0.6) : Qt.rgba(1, 1, 1, 0.12)
        }
    }
    Repeater {
        model: strip.labels
        Column {
            x: 8 + strip.slot * index
            width: strip.slot
            spacing: 3
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 14; height: 14; radius: 7
                color: index < strip.current ? "#0a7cff"
                     : index === strip.current ? (strip.current === strip.last ? "#32d74b" : "#0a7cff")
                     : Qt.rgba(1, 1, 1, 0.15)
                Icon {
                    anchors.centerIn: parent
                    visible: index < strip.current || (index === strip.last && strip.current === strip.last)
                    name: "check"
                    size: 10
                    color: "white"
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData
                font.pixelSize: 10
                font.weight: index === strip.current ? Font.Bold : Font.Normal
                color: index === strip.current ? "white" : Qt.rgba(1, 1, 1, 0.5)
            }
        }
    }
}
