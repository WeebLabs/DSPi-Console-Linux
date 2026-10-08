import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

// A row that picks a GPIO. Lists the user-wirable pins that nothing else
// holds (the current pin always stays listed); `accept` narrows the list
// further (e.g. MCK-capable pins), `allowUnset` adds "Not set" (0xFF).
SettingsRow {
    id: row
    property int pin: 0xFF
    property var accept: null              // function(pin) -> bool
    property var alsoTaken: []             // pins this page holds for something else
    property var sharable: []              // owners this pin may share with
    property bool allowUnset: false
    property string unsetText: "Not set"
    property int menuWidth: 120
    signal chosen(int pin)

    // The page's SettingsContext
    readonly property var ctx: {
        for (var p = parent; p; p = p.parent) if (p.ctx !== undefined) return p.ctx
        return null
    }
    readonly property var options: {
        bridge.hardware; controlSurfaces.revision   // re-evaluate when anything changes
        return ctx ? ctx.pinOptions(pin, accept, sharable, allowUnset, unsetText) : []
    }

    StyledComboBox {
        macForm: true
        width: isMacOS ? Math.max(92, implicitWidth) : row.menuWidth
        model: row.options.map(function(o) { return o.text })
        currentIndex: row.ctx ? row.ctx.optionIndex(row.options, row.pin) : -1
        onActivated: if (row.options[index].value !== row.pin) row.chosen(row.options[index].value)
    }
}
