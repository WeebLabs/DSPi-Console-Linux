import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

// A row with an on/off switch.
SettingsRow {
    id: row
    property bool checked: false
    signal toggled(bool checked)
    trailingAtTop: isMacOS && row.detail !== ""

    ToggleSwitch {
        mini: true
        checked: row.checked
        onToggled: row.toggled(checked)
    }
}
