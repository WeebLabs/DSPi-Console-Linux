import QtQuick 2.15
import QtQuick.Controls 2.15

// A tool parameter: name, value field with unit, slider, and an explanation.
// Dragging the slider sends live (liveChanged); release or typing commits
// (committed).
Column {
    id: row
    property string label: ""
    property string unit: ""
    property string caption: ""
    property string leftHint: ""      // optional slider end labels
    property string rightHint: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 0.1
    property int decimals: 1
    signal liveChanged(real v)
    signal committed(real v)

    spacing: 6
    width: parent ? parent.width : 300

    Item {
        width: parent.width
        height: 26
        Text {
            text: row.label
            font.pixelSize: 15
            font.weight: Font.Medium
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
        }
        ValueField {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fieldWidth: 64
            height: 26
            value: row.value
            decimals: row.decimals
            suffix: row.unit
            minValue: row.from
            maxValue: row.to
            wheelStep: row.stepSize
            onValueEdited: row.committed(newValue)
        }
    }

    Slider {
        id: slider
        width: parent.width
        height: 22
        topPadding: 0
        bottomPadding: 0
        from: row.from
        to: row.to
        stepSize: row.stepSize
        enabled: bridge.connected
        value: row.value
        onMoved: row.liveChanged(value)
        onPressedChanged: if (!pressed) row.committed(value)
        Connections {
            target: row
            function onValueChanged() { if (!slider.pressed) slider.value = row.value }
        }
        background: Rectangle {
            x: slider.leftPadding
            y: (slider.height - height) / 2
            width: slider.availableWidth
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.12)
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: "#3A79DE"
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: (slider.height - height) / 2
            width: 20; height: 20; radius: 10
            color: "#a8a8a8"
            border.color: Qt.rgba(0, 0, 0, 0.3)
        }
    }

    Item {
        visible: row.leftHint !== "" || row.rightHint !== ""
        width: parent.width
        height: 16
        Text { text: row.leftHint; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.55) }
        Text { anchors.right: parent.right; text: row.rightHint; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.55) }
    }

    Text {
        visible: row.caption !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: row.caption
        font.pixelSize: 12
        color: Qt.rgba(1, 1, 1, 0.55)
    }
}
