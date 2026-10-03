import QtQuick 2.15
import QtQuick.Controls 2.15

// A numeric value with its unit, editable in place (macOS-style): plain text
// at rest, a soft rounded fill on hover, and a filled field with an accent
// ring while editing. Return commits, Esc cancels.
Row {
    id: valueFieldRoot
    spacing: 4
    height: 24

    property real value: 0
    property string suffix: ""
    property int decimals: 1
    property real minValue: -999
    property real maxValue: 999
    property int fieldWidth: 60
    property int fontSize: 13
    property color textColor: Qt.rgba(1, 1, 1, 0.9)
    // Values at or below this read as -∞ (e.g. the master volume mute sentinel)
    property real infinityAt: -1e9
    // Compact fields (Matrix Mixer) adjust on plain scrolling; otherwise
    // Ctrl+scroll steps the value and plain scrolling scrolls the page
    property bool plainWheel: false
    property real wheelStep: Math.pow(10, -decimals)

    signal valueEdited(real newValue)

    TextField {
        id: textField
        width: fieldWidth
        height: parent.height
        font.pixelSize: valueFieldRoot.fontSize
        color: valueFieldRoot.textColor
        selectionColor: "#0a7cff"
        selectedTextColor: "white"
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        selectByMouse: true
        hoverEnabled: true
        leftPadding: 6
        rightPadding: 6
        topPadding: 0
        bottomPadding: 0

        background: Rectangle {
            radius: 5
            color: textField.activeFocus ? Qt.rgba(1, 1, 1, 0.10)
                 : textField.hovered && textField.enabled ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            border.width: textField.activeFocus ? 1.5 : 0
            border.color: "#0a7cff"
            Behavior on color { ColorAnimation { duration: 90 } }
        }

        text: formatValue(value)

        function formatValue(v) {
            return v <= infinityAt ? "-∞" : v.toFixed(decimals)
        }

        onEditingFinished: {
            var cleaned = text.replace(suffix, "").trim()
            var parsed = parseFloat(cleaned)
            if (!isNaN(parsed)) {
                parsed = Math.max(minValue, Math.min(maxValue, parsed))
                valueFieldRoot.valueEdited(parsed)
            }
            text = formatValue(valueFieldRoot.value)
        }

        onActiveFocusChanged: {
            text = formatValue(value)
            if (activeFocus) selectAll()
        }

        // Esc drops the edit and the focus
        Keys.onEscapePressed: {
            text = formatValue(valueFieldRoot.value)
            focus = false
        }

        Connections {
            target: valueFieldRoot
            function onValueChanged() {
                if (!textField.activeFocus)
                    textField.text = textField.formatValue(valueFieldRoot.value)
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: {
                if (!plainWheel && !(wheel.modifiers & Qt.ControlModifier)) { wheel.accepted = false; return }
                var delta = wheel.angleDelta.y > 0 ? wheelStep : -wheelStep
                var newVal = Math.max(minValue, Math.min(maxValue, value + delta))
                valueFieldRoot.valueEdited(newVal)
            }
        }
    }

    Text {
        text: suffix
        font.pixelSize: Math.max(10, valueFieldRoot.fontSize - 2)
        color: Qt.rgba(1, 1, 1, 0.45)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(20, implicitWidth)   // room for longer units (dBFS)
        visible: suffix !== ""
    }
}
