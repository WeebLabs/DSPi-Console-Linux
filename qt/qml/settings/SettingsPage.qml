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
    contentHeight: column.height + (isMacOS ? 20 : 36)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    // macOS: cards 20 pt in from the column edges, sections 11 pt apart (a
    // section's header adds its own 46 pt band above the card), no subtitle -
    // as the native grouped Form
    Column {
        id: column
        x: isMacOS ? 20 : 24
        y: isMacOS ? 0 : 18
        width: page.width - (isMacOS ? 40 : 48)
        spacing: 14

        Text {
            visible: !isMacOS && page.subtitle !== ""
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
            spacing: isMacOS ? 11 : 18
        }
    }
}
