import QtQuick 2.15
import QtQuick.Controls 2.15

// A pick-one menu in the app-menu style: a dark card of rows with an icon,
// title, optional detail line and a check mark on the current choice.
// options: [{ value, text, detail?, icon?, prefix?, enabled? }]; `prefix` is a
// short dim label before the text (e.g. a slot number), and an option with
// enabled: false is shown dimmed and can't be chosen. { header: "Title" }
// starts a titled section. Keyboard: Up/Down, Enter, Esc.
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
    padding: MenuStyle.padding
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property int current: -1

    TextMetrics {
        id: widest
        font.pixelSize: MenuStyle.fontSize
        font.weight: Font.DemiBold
        text: {
            var t = ""
            for (var i = 0; i < menu.options.length; i++) {
                var s = menu.options[i].text || ""
                if (s.length > t.length) t = s
            }
            return t
        }
    }

    // The anchor's own click would reopen a menu its press just closed
    property real closedAt: 0
    onClosed: closedAt = Date.now()

    // Line the menu's right edge up with the anchor's (for right-aligned values)
    property bool alignRight: false

    // Opens below the anchor, or above it when there's more room there (a
    // picker near the bottom of the window); scrolls if neither side fits.
    function openAt(anchorItem) {
        var p = anchorItem.mapToItem(parent, 0, 0)
        x = alignRight ? Math.max(6, p.x + anchorItem.width - width + 4) : Math.max(6, p.x - 4)
        var fullHeight = list.implicitHeight + topPadding + bottomPadding
        var below = parent.height - (p.y + anchorItem.height + 6) - 8
        var above = p.y - 6 - 8
        var openUp = fullHeight > below && above > below
        height = Math.min(fullHeight, openUp ? above : below)
        y = openUp ? p.y - 6 - height : p.y + anchorItem.height + 6
        transformOrigin = openUp ? Popup.BottomLeft : Popup.TopLeft
        markCurrent()
        open()
    }
    // Opens beside the anchor (a submenu): to its right, or its left when
    // there's no room, top-aligned with it and kept inside the window
    function openBeside(anchorItem) {
        var p = anchorItem.mapToItem(parent, 0, 0)
        var fullHeight = list.implicitHeight + topPadding + bottomPadding
        height = Math.min(fullHeight, parent.height - 16)
        x = p.x + anchorItem.width + width + 4 <= parent.width - 6 ? p.x + anchorItem.width + 2
                                                                   : Math.max(6, p.x - width - 2)
        y = Math.max(8, Math.min(p.y - topPadding, parent.height - height - 8))
        transformOrigin = Popup.TopLeft
        markCurrent()
        open()
    }
    function markCurrent() {
        current = -1
        for (var i = 0; i < options.length; i++)
            if (options[i].header === undefined && options[i].value === currentValue) current = i
    }
    // Next usable row up or down, skipping headers and disabled rows
    function step(dir) {
        for (var k = 1; k <= options.length; k++) {
            var i = ((current < 0 ? (dir > 0 ? -1 : 0) : current) + dir * k + options.length * 2) % options.length
            if (optionEnabled(i)) { current = i; return }
        }
    }
    function toggleAt(anchorItem) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        openAt(anchorItem)
    }
    function optionEnabled(i) { return options[i] && options[i].header === undefined && options[i].enabled !== false }
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

    contentItem: Flickable {
        id: scroller
        focus: true
        clip: true
        contentHeight: list.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        ScrollIndicator.vertical: ScrollIndicator {}
        Keys.onUpPressed: menu.step(-1)
        Keys.onDownPressed: menu.step(1)
        Keys.onReturnPressed: menu.activate(menu.current)
        Keys.onEnterPressed: menu.activate(menu.current)

        Column {
            id: list
            width: scroller.width

            Text {
                visible: menu.heading !== ""
                text: menu.heading.toUpperCase()
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 0.8
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.38)
                leftPadding: 12
                topPadding: 6
                bottomPadding: 6
            }

            Repeater {
                model: menu.options
                Item {
                    id: row
                    width: parent.width
                    readonly property bool isHeader: modelData.header !== undefined
                    height: isHeader ? (index === 0 ? 22 : 28) : modelData.detail ? 42 : MenuStyle.rowHeight
                    readonly property bool usable: !isHeader && modelData.enabled !== false
                    readonly property bool hot: menu.current === index && usable
                    readonly property bool selected: !isHeader && modelData.value === menu.currentValue

                    Text {
                        visible: row.isHeader
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        x: 12
                        text: row.isHeader ? modelData.header.toUpperCase() : ""
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.38)
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        radius: MenuStyle.rowRadius
                        color: row.hot ? MenuStyle.highlight : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    Icon {
                        id: rowIcon
                        visible: !row.isHeader && !!modelData.icon
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: modelData.icon || ""
                        size: MenuStyle.iconSize
                        color: isMacOS ? (row.hot ? "white" : MacColors.label) : row.hot ? "white" : row.selected ? "#3a96ff" : Qt.rgba(1, 1, 1, 0.65)
                    }
                    Text {
                        id: rowPrefix
                        visible: menu.hasPrefix && !row.isHeader
                        x: rowIcon.visible ? rowIcon.x + rowIcon.width + 8 : 10
                        width: 14
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: modelData.prefix !== undefined ? modelData.prefix : ""
                        font.pixelSize: 11
                        color: isMacOS ? (row.hot ? "white" : MacColors.secondaryLabel) : row.hot ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.35)
                    }
                    Column {
                        visible: !row.isHeader
                        anchors.left: rowPrefix.visible ? rowPrefix.right : rowIcon.visible ? rowIcon.right : parent.left
                        anchors.leftMargin: rowPrefix.visible ? 8 : rowIcon.visible ? 8 : 10
                        anchors.right: check.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: modelData.text || ""
                            font.pixelSize: 13
                            font.weight: row.selected ? Font.DemiBold : Font.Normal
                            color: isMacOS ? (row.hot ? "white" : row.usable ? MacColors.label : MacColors.tertiaryLabel) : row.usable ? "white" : Qt.rgba(1, 1, 1, 0.3)
                        }
                        Text {
                            visible: !!modelData.detail
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.detail || ""
                            font.pixelSize: 11
                            color: isMacOS ? (row.hot ? "white" : MacColors.secondaryLabel) : row.hot ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.45)
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
                        color: isMacOS ? (row.hot ? "white" : MacColors.label) : row.hot ? "white" : "#3a96ff"
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !row.isHeader
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
}
