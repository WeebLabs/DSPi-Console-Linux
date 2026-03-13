import QtQuick 2.15
import QtQuick.Controls 2.15

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

    signal valueEdited(real newValue)

    TextField {
        id: textField
        width: fieldWidth
        height: parent.height
        font.pixelSize: 12
        font.family: "Menlo"
        color: activeFocus ? "#0078d4" : "white"
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        selectByMouse: true
        padding: 4

        background: Rectangle {
            color: "transparent"
            border.color: textField.activeFocus ? "#0078d4" : "transparent"
            border.width: 1
            radius: 3
        }

        text: formatValue(value)

        function formatValue(v) {
            return v.toFixed(decimals)
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
            if (activeFocus) {
                text = formatValue(value)
                selectAll()
            } else {
                text = formatValue(value)
            }
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
                var delta = wheel.angleDelta.y > 0 ? 0.1 : -0.1
                var newVal = Math.max(minValue, Math.min(maxValue, value + delta))
                valueFieldRoot.valueEdited(newVal)
            }
        }
    }

    Text {
        text: suffix
        font.pixelSize: 10
        color: Qt.rgba(1, 1, 1, 0.5)
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        visible: suffix !== ""
    }
}
