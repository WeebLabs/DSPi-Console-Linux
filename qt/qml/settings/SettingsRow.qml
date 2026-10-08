import QtQuick 2.15
import "../components"

// One row in a SettingsSection: title and optional detail on the left,
// a trailing control (the row's children) on the right.
Item {
    id: row
    property string title: ""
    property string detail: ""
    property string icon: ""           // macOS: a 16 pt icon column before the text
    property int extraPadding: 0       // macOS: a row's own .padding(.vertical)
    property bool trailingAtTop: false // macOS: the control on the first line (Toggle)
    property real detailTracking: 0    // macOS: letter spacing of the detail (.caption is tighter than .caption2)
    property color titleColor: isMacOS ? MacColors.label : "white"
    property real trailingWidth: trailing.childrenRect.width
    property bool clickable: false     // whole row acts as a button
    signal activated()
    default property alias control: trailing.data

    // Hairline above every row except the first in its card
    readonly property bool firstInCard: parent && parent.children.length > 0 && parent.children[0] === row

    width: parent ? parent.width : 400
    // macOS: the native grouped form's rows: 10 pt inset, 10.5 pt above and
    // below the content (37 pt for one line of text)
    readonly property int inset: isMacOS ? 10 : 14
    readonly property real textX: isMacOS && icon !== "" ? inset + 24 : inset
    height: isMacOS ? Math.max(37, labels.height + 21 + 2 * extraPadding, trailing.height + 21) : Math.max(40, labels.height + 16)
    opacity: enabled ? 1.0 : 0.45

    // Hover highlight and click target for clickable rows (below the controls)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 7
        visible: row.clickable && rowMouse.containsMouse
        color: Qt.rgba(1, 1, 1, 0.05)
    }
    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: row.clickable
        hoverEnabled: row.clickable
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.activated()
    }

    Rectangle {
        visible: !row.firstInCard
        x: row.inset
        width: parent.width - row.inset
        height: 1
        color: isMacOS ? Qt.rgba(1, 1, 1, 0.047) : Qt.rgba(1, 1, 1, 0.07)
    }

    Icon {
        visible: isMacOS && row.icon !== ""
        x: row.inset
        anchors.verticalCenter: labels.verticalCenter
        width: 16; height: 16
        size: 16
        name: row.icon
        color: MacColors.secondaryLabel
    }

    Column {
        id: labels
        x: row.textX
        width: parent.width - row.textX - row.inset - (row.trailingWidth > 0 ? row.trailingWidth + (isMacOS ? 8 : 16) : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: row.title
            font.pixelSize: 13
            color: row.titleColor
        }
        Text {
            visible: row.detail !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: row.detail
            font.pixelSize: isMacOS ? 10 : 11
            font.letterSpacing: row.detailTracking
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
        }
    }

    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: row.inset
        anchors.verticalCenter: row.trailingAtTop ? undefined : parent.verticalCenter
        y: row.trailingAtTop ? labels.y + 8 - height / 2 : 0
        width: childrenRect.width
        height: childrenRect.height
    }
}
