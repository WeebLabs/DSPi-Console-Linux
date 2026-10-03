import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

// A row with a drop-down choice. `options` is a list of strings, or of
// {text, value} objects; `value` is the selected option's value (or index).
SettingsRow {
    id: row
    property var options: []
    property var value
    property int menuWidth: 0      // 0 = fit the longest option
    signal chosen(var value)

    function valueAt(i) {
        var o = options[i]
        return (o !== null && typeof o === "object") ? o.value : i
    }
    function textAt(i) {
        var o = options[i]
        return (o !== null && typeof o === "object") ? o.text : o
    }
    readonly property int currentIndex: {
        for (var i = 0; i < options.length; i++)
            if (valueAt(i) === value) return i
        return -1
    }

    StyledComboBox {
        width: row.menuWidth > 0 ? row.menuWidth : implicitWidth
        model: {
            var t = []
            for (var i = 0; i < row.options.length; i++) t.push(row.textAt(i))
            return t
        }
        currentIndex: row.currentIndex
        onActivated: row.chosen(row.valueAt(index))
    }
}
