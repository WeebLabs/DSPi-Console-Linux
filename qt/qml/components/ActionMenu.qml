import QtQuick 2.15
import QtQuick.Controls 2.15

// A right-click / action menu in the shared menu style (MenuStyle).
// items: [{ key, text, icon?, shortcut?, enabled?, danger? } | { separator: true }]
// Emits triggered(key). openAt(item, x, y) opens at a point in `item`
// (e.g. the click position), kept inside the window.
Popup {
    id: menu
    property var items: []
    signal triggered(string key)

    padding: MenuStyle.padding
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property int current: -1

    readonly property bool hasShortcuts: {
        for (var i = 0; i < items.length; i++) if (items[i].shortcut) return true
        return false
    }
    width: Math.ceil(MenuStyle.sideInset + MenuStyle.iconSize + 10 + labelWidest.advanceWidth
                     + (hasShortcuts ? 28 + shortcutWidest.advanceWidth : 16)
                     + MenuStyle.sideInset + 2 * MenuStyle.padding)

    TextMetrics {
        id: labelWidest
        font.pixelSize: MenuStyle.fontSize
        text: {
            var t = ""
            for (var i = 0; i < menu.items.length; i++)
                if (menu.items[i].text && menu.items[i].text.length > t.length) t = menu.items[i].text
            return t
        }
    }
    TextMetrics {
        id: shortcutWidest
        font.pixelSize: MenuStyle.smallFontSize
        text: {
            var t = ""
            for (var i = 0; i < menu.items.length; i++)
                if (menu.items[i].shortcut && menu.items[i].shortcut.length > t.length) t = menu.items[i].shortcut
            return t
        }
    }

    function itemEnabled(i) { return items[i] && !items[i].separator && items[i].enabled !== false }

    // Worked out from the items, not the list: items set just before
    // openAt aren't laid out yet
    function itemsHeight() {
        var h = 0
        for (var i = 0; i < items.length; i++) h += items[i].separator ? 7 : MenuStyle.rowHeight
        return h
    }

    function openAt(item, px, py) {
        var p = item.mapToItem(parent, px, py)
        var h = itemsHeight() + topPadding + bottomPadding
        x = Math.max(6, Math.min(p.x, parent.width - width - 6))
        y = p.y + h > parent.height - 6 ? Math.max(6, p.y - h) : p.y
        current = -1
        open()
    }

    function activate(i) {
        if (!itemEnabled(i)) return
        close()
        triggered(items[i].key)
    }

    function step(dir) {
        var n = items.length
        for (var k = 1; k <= n; k++) {
            var i = ((current < 0 ? (dir > 0 ? -1 : 0) : current) + dir * k + n * 2) % n
            if (itemEnabled(i)) { current = i; return }
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 120; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }
    transformOrigin: Popup.TopLeft

    background: Item {
        Repeater {
            model: 6
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1) * 2
                anchors.topMargin: -(index + 1) * 2 + 4
                radius: MenuStyle.radius + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: MenuStyle.radius
            color: MenuStyle.background
            border.color: MenuStyle.border
        }
    }

    contentItem: Column {
        id: list
        focus: true
        Keys.onUpPressed: menu.step(-1)
        Keys.onDownPressed: menu.step(1)
        Keys.onReturnPressed: menu.activate(menu.current)
        Keys.onEnterPressed: menu.activate(menu.current)

        Repeater {
            model: menu.items
            Loader {
                width: list.width
                readonly property var entry: modelData
                readonly property int entryIndex: index
                sourceComponent: modelData.separator ? separatorRow : actionRow
            }
        }
    }

    Component {
        id: separatorRow
        Item {
            height: 7
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                width: parent.width - 16
                height: 1
                color: MenuStyle.separator
            }
        }
    }

    Component {
        id: actionRow
        Item {
            id: row
            height: MenuStyle.rowHeight
            readonly property bool usable: menu.itemEnabled(entryIndex)
            readonly property bool hot: menu.current === entryIndex && usable
            readonly property bool danger: entry.danger === true

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                radius: MenuStyle.rowRadius
                color: row.hot ? (row.danger ? MenuStyle.danger : MenuStyle.highlight) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
            }
            Icon {
                id: rowIcon
                x: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                name: entry.icon || ""
                size: MenuStyle.iconSize
                color: row.hot ? "white" : !row.usable ? Qt.rgba(1, 1, 1, 0.25)
                     : row.danger ? MenuStyle.dangerText : MenuStyle.iconColor
            }
            Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: entry.text
                font.pixelSize: MenuStyle.fontSize
                color: row.hot ? "white" : !row.usable ? Qt.rgba(1, 1, 1, 0.3)
                     : row.danger ? MenuStyle.dangerText : MenuStyle.text
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                text: entry.shortcut || ""
                font.pixelSize: MenuStyle.smallFontSize
                color: row.hot ? Qt.rgba(1, 1, 1, 0.8) : MenuStyle.dimText
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: menu.current = entryIndex
                onExited: if (menu.current === entryIndex) menu.current = -1
                onClicked: menu.activate(entryIndex)
            }
        }
    }
}
