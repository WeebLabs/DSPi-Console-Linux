import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components"

// A row with an action button. `destructive` colours it red.
SettingsRow {
    id: row
    property string buttonText: ""
    property bool destructive: false
    signal clicked()

    Button {
        id: button
        text: row.buttonText
        onClicked: row.clicked()
        contentItem: Text {
            text: button.text
            font.pixelSize: 13
            color: isMacOS ? (row.destructive ? MacColors.red : MacColors.label) : row.destructive ? "#ff6961" : "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            implicitWidth: 96
            implicitHeight: 30
            radius: 7
            color: isMacOS ? (button.down ? Qt.rgba(1, 1, 1, 0.36) : MacColors.control) : button.down ? Qt.rgba(1, 1, 1, 0.20) : button.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.09)
            border.color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.10)
        }
    }
}
