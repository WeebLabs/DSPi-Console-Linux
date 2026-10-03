import QtQuick 2.15
import QtQuick.Controls 2.15

// A settings page: title, optional subtitle, and a scrolling column of
// SettingsSection cards. Declare sections as children.
Flickable {
    id: page
    property string title: ""
    property string subtitle: ""
    property var ctx                       // SettingsContext, set by the window
    default property alias content: body.data

    contentWidth: width
    contentHeight: column.height + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    Column {
        id: column
        x: 32
        y: 24
        width: page.width - 64
        spacing: 6

        Text {
            text: page.title
            font.pixelSize: 24
            font.weight: Font.Bold
            color: "white"
        }
        Text {
            visible: page.subtitle !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.subtitle
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.55)
        }
        Item { width: 1; height: 12 }

        Column {
            id: body
            width: parent.width
            spacing: 22
        }
    }
}
