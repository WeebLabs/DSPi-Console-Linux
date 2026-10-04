import QtQuick 2.15
import "../components"

// A row with a segmented choice. `options` are labels; `value` the index.
SettingsRow {
    id: row
    property var options: []
    property int value: 0
    property int controlWidth: 0           // 0 = 84 per option
    signal chosen(int index)

    SegmentedControl {
        width: row.controlWidth > 0 ? row.controlWidth : 84 * row.options.length
        model: row.options
        currentIndex: row.value
        onActivated: row.chosen(index)
    }
}
