import QtQuick 2.15

// A row choosing from a list (ChoiceMenu options, headers allowed), or with
// `categories` from a menu of families (then `text` names the choice).
CsRow {
    id: row
    property var options: []
    property var value
    property var categories: null
    property string text: ""
    signal chosen(var value)
    CsPicker {
        id: picker
        options: row.options
        categories: row.categories
        value: row.value
        onChosen: row.chosen(value)
        Binding on text { when: row.categories !== null; value: row.text }
    }
}
