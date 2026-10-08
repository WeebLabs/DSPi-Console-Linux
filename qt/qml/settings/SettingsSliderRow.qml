import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

// A row with a slider and its value. `format` turns the value into the
// label text; `moved` fires while dragging, `committed` on release.
SettingsRow {
    id: row
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property var format: function (v) { return v.toFixed(0) }
    signal moved(real value)
    signal committed(real value)

    Row {
        spacing: 12
        StyledSlider {
            id: slider
            width: 200
            from: row.from
            to: row.to
            stepSize: row.stepSize
            value: row.value
            anchors.verticalCenter: parent.verticalCenter
            onMoved: row.moved(value)
            onPressedChanged: if (!pressed) row.committed(value)
            Connections {
                target: row
                function onValueChanged() { if (!slider.pressed) slider.value = row.value }
            }
        }
        Text {
            width: 96
            horizontalAlignment: Text.AlignRight
            text: row.format(slider.value)
            font.pixelSize: 12
            font.family: "monospace"
            color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.75)
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
