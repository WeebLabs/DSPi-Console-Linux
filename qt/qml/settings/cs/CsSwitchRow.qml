import QtQuick 2.15
import "../../components"

// An on/off option row.
CsRow {
    id: row
    property bool checked: false
    signal toggled(bool on)
    ToggleSwitch {
        checked: row.checked
        onToggled: row.toggled(checked)
    }
}
