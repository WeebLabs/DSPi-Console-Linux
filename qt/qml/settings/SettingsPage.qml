import QtQuick 2.15
import QtQuick.Controls 2.15

// A settings page: an optional subtitle and a scrolling column of
// SettingsSection cards. Declare sections as children. The page title shows
// in the window's titlebar (as in the macOS toolbar), not on the page.
Flickable {
    id: page
    property string title: ""
    property string subtitle: ""
    property var ctx                       // SettingsContext, set by the window
    default property alias content: body.data

    contentWidth: width
    contentHeight: column.height + 36
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    Column {
        id: column
        x: 24
        y: 18
        width: page.width - 48
        spacing: 14

        Text {
            visible: page.subtitle !== ""
            width: parent.width
            leftPadding: 4
            rightPadding: 4
            wrapMode: Text.WordWrap
            text: page.subtitle
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.55)
        }

        Column {
            id: body
            width: parent.width
            spacing: 18
        }
    }
}
