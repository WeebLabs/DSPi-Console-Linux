import QtQuick 2.15
import QtQuick.Controls 2.15

// A tool parameter: name, value field with unit, slider, and an explanation.
// Dragging the slider sends live (liveChanged, at most every 30 ms); release
// or typing commits (committed). displayValue follows the slider during a
// drag, for graphs. Right-click on the slider resets to `defaultValue` if set.
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
    property var defaultValue: undefined
    readonly property real displayValue: slider.pressed ? slider.value : value
    signal liveChanged(real v)
    signal committed(real v)

    spacing: 4
    width: parent ? parent.width : 300

    Item {
        width: parent.width
        height: 22
        Text {
            text: row.label
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.9)
            anchors.verticalCenter: parent.verticalCenter
        }
        ValueField {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            fieldWidth: 54
            height: 22
            value: row.displayValue
            decimals: row.decimals
            suffix: row.unit
            minValue: row.from
            maxValue: row.to
            wheelStep: row.stepSize
            onValueEdited: row.committed(newValue)
        }
    }

    StyledSlider {
        id: slider
        width: parent.width
        from: row.from
        to: row.to
        stepSize: row.stepSize
        enabled: bridge.connected
        value: row.value
        onMoved: live.push(value)
        onPressedChanged: if (!pressed) { live.cancel(); row.committed(value) }
        Throttle { id: live; onFire: row.liveChanged(value) }
        Connections {
            target: row
            function onValueChanged() { if (!slider.pressed) slider.value = row.value }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            enabled: row.defaultValue !== undefined
            onClicked: row.committed(row.defaultValue)
        }
    }

    Item {
        visible: row.leftHint !== "" || row.rightHint !== ""
        width: parent.width
        height: 14
        Text { text: row.leftHint; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
        Text { anchors.right: parent.right; text: row.rightHint; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
    }

    Text {
        visible: row.caption !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: row.caption
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.5)
    }
}
