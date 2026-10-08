import QtQuick 2.15
import QtQuick.Controls 2.15

// Filter type picker in the shared menu style. Types that come in two slopes
// share a row with inline slope chips: click the name for the usual slope,
// or a chip for a specific one. The current type is checked.
Popup {
    id: menu
    property int currentType: 0
    property bool allowLinkwitz: false
    signal chosen(int type)

    // types: firmware filter types; chips label each when there's more than one.
    // The last type is the one the row's name picks.
    readonly property var rows: [
        { text: "Off", types: [0] },
        { text: "Peaking", types: [1] },
        { text: "Low Shelf", types: [9, 2], chips: ["6", "12"] },
        { text: "High Shelf", types: [10, 3], chips: ["6", "12"] },
        { text: "High Cut", types: [12, 4], chips: ["6", "12"] },
        { text: "Low Cut", types: [13, 5], chips: ["6", "12"] },
        { text: "Notch", types: [6] },
        { text: "All Pass", types: [8, 7], chips: ["180°", "360°"] },
        { separator: true, lt: true },
        { text: "Linkwitz Transform", types: [11], lt: true }
    ]

    padding: MenuStyle.padding
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.ceil(MenuStyle.sideInset + 16 + labelWidest.advanceWidth + 24 + 2 * 44 + 4
                     + MenuStyle.sideInset + 2 * MenuStyle.padding)

    TextMetrics { id: labelWidest; font.pixelSize: MenuStyle.fontSize; font.weight: Font.DemiBold; text: "Linkwitz Transform" }

    property int current: -1          // hovered row
    property real closedAt: 0
    onClosed: closedAt = Date.now()

    function rowShown(r) { return !r.lt || allowLinkwitz }
    function rowIndexOfType(t) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].types && rows[i].types.indexOf(t) >= 0) return i
        return -1
    }

    function toggleAt(anchorItem) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        var p = anchorItem.mapToItem(parent, 0, 0)
        var h = list.implicitHeight + topPadding + bottomPadding
        x = Math.max(6, Math.min(p.x - 4, parent.width - width - 6))
        var below = parent.height - (p.y + anchorItem.height + 4) - 6
        y = h > below && p.y - 4 - h > 6 ? p.y - 4 - h : p.y + anchorItem.height + 4
        current = rowIndexOfType(currentType)
        open()
    }
    function pick(type) { close(); if (type !== currentType) chosen(type) }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 120; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }

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
        Keys.onUpPressed: {
            for (var i = menu.current - 1; i >= 0; i--)
                if (menu.rows[i].types && menu.rowShown(menu.rows[i])) { menu.current = i; return }
        }
        Keys.onDownPressed: {
            for (var i = menu.current + 1; i < menu.rows.length; i++)
                if (menu.rows[i].types && menu.rowShown(menu.rows[i])) { menu.current = i; return }
        }
        Keys.onReturnPressed: if (menu.current >= 0) menu.pick(menu.rows[menu.current].types.slice(-1)[0])
        Keys.onEnterPressed: if (menu.current >= 0) menu.pick(menu.rows[menu.current].types.slice(-1)[0])

        Repeater {
            model: menu.rows
            Loader {
                width: list.width
                readonly property var entry: modelData
                readonly property int entryIndex: index
                active: menu.rowShown(modelData)
                visible: active
                sourceComponent: modelData.separator ? separatorRow : typeRow
            }
        }
    }

    Component {
        id: separatorRow
        Item {
            height: 7
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: MenuStyle.separator }
        }
    }

    Component {
        id: typeRow
        Item {
            id: row
            height: MenuStyle.rowHeight
            readonly property bool hot: menu.current === entryIndex
            readonly property bool selected: entry.types.indexOf(menu.currentType) >= 0

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                radius: MenuStyle.rowRadius
                color: isMacOS ? (row.hot ? MenuStyle.highlight : "transparent") : row.hot ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            }
            // Row name: picks the usual slope
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: menu.current = entryIndex
                onClicked: menu.pick(entry.types[entry.types.length - 1])
            }
            Text {
                id: check
                x: MenuStyle.sideInset
                width: 16
                anchors.verticalCenter: parent.verticalCenter
                text: row.selected ? "✓" : ""
                font.pixelSize: 12
                font.weight: Font.Bold
                color: isMacOS ? (row.hot ? "white" : MacColors.label) : "#3a96ff"
            }
            Text {
                anchors.left: check.right
                anchors.verticalCenter: parent.verticalCenter
                text: entry.text
                font.pixelSize: MenuStyle.fontSize
                font.weight: row.selected ? Font.DemiBold : Font.Normal
                color: isMacOS ? (row.hot ? "white" : MacColors.label) : entry.types[0] === 0 && !row.selected ? Qt.rgba(1, 1, 1, 0.6) : "white"
            }
            // Slope chips
            Row {
                visible: !!entry.chips
                anchors.right: parent.right
                anchors.rightMargin: MenuStyle.sideInset - 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: entry.chips || []
                    Rectangle {
                        readonly property int type: entry.types[index]
                        readonly property bool isCurrent: type === menu.currentType
                        width: 44
                        height: 20
                        radius: 5
                        color: isMacOS ? (isCurrent ? (row.hot ? Qt.rgba(1, 1, 1, 0.25) : MenuStyle.highlight) : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)) : isCurrent ? MenuStyle.highlight
                             : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.07)
                        Text {
                            anchors.centerIn: parent
                            text: modelData + (modelData.indexOf("°") < 0 ? " dB" : "")
                            font.pixelSize: MenuStyle.smallFontSize
                            font.weight: parent.isCurrent ? Font.DemiBold : Font.Normal
                            color: parent.isCurrent || chipMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.65)
                        }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: menu.current = entryIndex
                            onClicked: menu.pick(parent.type)
                        }
                    }
                }
            }
        }
    }
}
