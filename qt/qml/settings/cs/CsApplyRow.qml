import QtQuick 2.15
import "../../components"

// A card's footer: the reason the last apply failed, anything the card adds
// on the left (e.g. Add Remote Button), then Revert and Apply.
Item {
    id: row
    property bool dirty: false
    property bool canApply: dirty
    property string message: ""          // a failed apply, shown while not dirty
    property string hint: ""             // why an edit can't be applied yet
    property alias leading: leadRow.data
    signal apply()
    signal revert()

    width: parent ? parent.width : 400
    height: 40

    Rectangle { x: 14; width: parent.width - 14; height: 1; color: isMacOS ? Qt.rgba(1, 1, 1, 0.047) : Qt.rgba(1, 1, 1, 0.07) }
    Row {
        id: leadRow
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
    Row {
        x: leadRow.width > 0 ? leadRow.x + leadRow.width + 12 : 14
        width: buttons.x - x - 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        visible: row.message !== "" && !row.dirty
        Icon { name: "warning"; size: 14; color: "#ff9f0a"; anchors.verticalCenter: parent.verticalCenter }
        Text {
            width: parent.width - 20
            elide: Text.ElideRight
            text: row.message
            font.pixelSize: 12
            color: "#ff9f0a"
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Text {
        visible: row.hint !== "" && row.dirty
        x: leadRow.width > 0 ? leadRow.x + leadRow.width + 12 : 14
        width: buttons.x - x - 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: row.hint
        font.pixelSize: 12
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
    }
    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        CsButton { text: "Revert"; enabled: row.dirty; onClicked: row.revert() }
        CsButton { text: "Apply"; primary: true; enabled: row.canApply; onClicked: row.apply() }
    }
}
