import QtQuick 2.15
import "../components"

// A read-only row: title on the left, value text on the right.
SettingsRow {
    id: row
    property string value: ""
    property bool mono: false

    Text {
        text: row.value
        font.pixelSize: 13
        font.family: row.mono ? "monospace" : Qt.application.font.family
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.6)
    }
}
