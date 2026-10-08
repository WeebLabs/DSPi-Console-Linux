import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

// A row with an on/off switch.
SettingsRow {
    id: row
    property bool checked: false
    signal toggled(bool checked)
    trailingAtTop: isMacOS && row.detail !== ""
    detailTracking: isMacOS ? -0.12 : 0    // a Toggle's description is .caption (measured)

    ToggleSwitch {
        mini: true
        checked: row.checked
        onToggled: row.toggled(checked)
    }
}
