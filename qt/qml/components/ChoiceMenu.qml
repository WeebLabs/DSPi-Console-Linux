import QtQuick 2.15
import QtQuick.Controls 2.15

// A pick-one menu in the app-menu style: a dark card of rows with an icon,
// title, optional detail line and a check mark on the current choice.
// options: [{ value, text, detail?, icon?, prefix?, enabled? }]; `prefix` is a
// short dim label before the text (e.g. a slot number), and an option with
// enabled: false is shown dimmed and can't be chosen. Keyboard: Up/Down,
// Enter, Esc.
Popup {
    id: menu
    property var options: []
    property var currentValue
    property string heading: ""
    signal chosen(var value)

    // Fits the longest option: icon + label + check mark
    readonly property bool hasPrefix: {
        for (var i = 0; i < options.length; i++) if (options[i].prefix !== undefined) return true
        return false
    }
    width: Math.max(140, widest.advanceWidth + 78 + (hasPrefix ? 18 : 0))
    padding: 4
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property int current: -1

    TextMetrics {
        id: widest
        font.pixelSize: 13
        font.weight: Font.DemiBold
        text: {
            var t = ""
            for (var i = 0; i < menu.options.length; i++)
                if (menu.options[i].text.length > t.length) t = menu.options[i].text
            return t
        }
    }

    // The anchor's own click would reopen a menu its press just closed
    property real closedAt: 0
    onClosed: closedAt = Date.now()

    // Line the menu's right edge up with the anchor's (for right-aligned values)
    property bool alignRight: false

    function openAt(anchorItem) {
        var p = anchorItem.mapToItem(parent, 0, anchorItem.height + 6)
        x = alignRight ? Math.max(6, p.x + anchorItem.width - width + 4) : Math.max(6, p.x - 4)
        y = p.y
        current = -1
        for (var i = 0; i < options.length; i++)
            if (options[i].value === currentValue) current = i
        open()
    }
    function toggleAt(anchorItem) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        openAt(anchorItem)
    }
    function optionEnabled(i) { return options[i] && options[i].enabled !== false }
    function activate(i) {
        if (i < 0 || i >= options.length || !optionEnabled(i)) return
        close()
        chosen(options[i].value)
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 140; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }
    transformOrigin: Popup.TopLeft

    background: Item {
        Repeater {
            model: 6
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1) * 2
                anchors.topMargin: -(index + 1) * 2 + 4
                radius: 9 + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 9
            color: "#1d1d1f"
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }
    }

    contentItem: Column {
        focus: true
        Keys.onUpPressed: menu.current = (menu.current <= 0 ? menu.options.length : menu.current) - 1
        Keys.onDownPressed: menu.current = (menu.current + 1) % menu.options.length
        Keys.onReturnPressed: menu.activate(menu.current)
        Keys.onEnterPressed: menu.activate(menu.current)

        Text {
            visible: menu.heading !== ""
            text: menu.heading.toUpperCase()
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.8
            color: Qt.rgba(1, 1, 1, 0.38)
            leftPadding: 12
            topPadding: 6
            bottomPadding: 6
        }

        Repeater {
            model: menu.options
            Item {
                id: row
                width: parent.width
                height: modelData.detail ? 42 : 28
                readonly property bool usable: modelData.enabled !== false
                readonly property bool hot: menu.current === index && usable
                readonly property bool selected: modelData.value === menu.currentValue

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
                    radius: 6
                    color: row.hot ? "#0a7cff" : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                }
                Icon {
                    id: rowIcon
                    visible: !!modelData.icon
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.icon || ""
                    size: 15
                    color: row.hot ? "white" : row.selected ? "#3a96ff" : Qt.rgba(1, 1, 1, 0.65)
                }
                Text {
                    id: rowPrefix
                    visible: menu.hasPrefix
                    x: rowIcon.visible ? rowIcon.x + rowIcon.width + 8 : 10
                    width: 14
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: modelData.prefix !== undefined ? modelData.prefix : ""
                    font.pixelSize: 11
                    color: row.hot ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.35)
                }
                Column {
                    anchors.left: rowPrefix.visible ? rowPrefix.right : rowIcon.visible ? rowIcon.right : parent.left
                    anchors.leftMargin: rowPrefix.visible ? 8 : rowIcon.visible ? 8 : 10
                    anchors.right: check.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: modelData.text
                        font.pixelSize: 13
                        font.weight: row.selected ? Font.DemiBold : Font.Normal
                        color: row.usable ? "white" : Qt.rgba(1, 1, 1, 0.3)
                    }
                    Text {
                        visible: !!modelData.detail
                        width: parent.width
                        elide: Text.ElideRight
                        text: modelData.detail || ""
                        font.pixelSize: 11
                        color: row.hot ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.45)
                    }
                }
                Text {
                    id: check
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.selected ? "✓" : ""
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: row.hot ? "white" : "#3a96ff"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: menu.current = index
                    onExited: if (menu.current === index) menu.current = -1
                    onClicked: menu.activate(index)
                }
            }
        }
    }
}
