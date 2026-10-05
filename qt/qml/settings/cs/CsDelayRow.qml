import QtQuick 2.15
import "../../components"

// A delay in whole minutes and seconds (0.1 s units on the wire).
CsRow {
    id: row
    property int raw: 0
    property int maxSeconds: 6553
    signal changed(int raw)
    readonly property int total: Math.floor(raw / 10)

    function set(seconds) { row.changed(Math.max(0, Math.min(maxSeconds, Math.round(seconds))) * 10) }

    Row {
        spacing: 4
        ValueField {
            value: Math.floor(row.total / 60)
            decimals: 0
            minValue: 0
            maxValue: Math.floor(row.maxSeconds / 60)
            fieldWidth: 40
            suffix: "m"
            wheelStep: 1
            onValueEdited: row.set(newValue * 60 + row.total % 60)
        }
        ValueField {
            value: row.total % 60
            decimals: 0
            minValue: 0
            maxValue: 5999
            fieldWidth: 34
            suffix: "s"
            wheelStep: 1
            onValueEdited: row.set(Math.floor(row.total / 60) * 60 + newValue)
        }
    }
}
