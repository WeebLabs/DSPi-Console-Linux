import QtQuick 2.15
import QtQuick.Controls 2.15

// The app menu opened from the titlebar's menu button: device summary,
// device actions, tool windows and settings. Keyboard: Up/Down, Enter, Esc.
Popup {
    id: menu
    width: 300
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Actions are supplied by the window that hosts the menu
    signal commitRequested()
    signal revertRequested()
    signal factoryResetRequested()
    signal openWindow(string name)

    // The menu button toggles the menu. Pressing the button while the menu is
    // open closes it as an outside press before the click arrives, so a click
    // right after such a close must not reopen it.
    property real closedAt: 0
    onClosed: closedAt = Date.now()

    function toggleAt(anchorItem) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        openAt(anchorItem)
    }

    function openAt(anchorItem) {
        var p = anchorItem.mapToItem(parent, 0, anchorItem.height + 6)
        x = Math.max(6, p.x - 4)
        y = p.y
        current = -1
        open()
    }

    // ── Rows ──
    // kind: "header" | "item" | "sep"
    readonly property var rows: [
        { kind: "header", text: "Device" },
        { kind: "item", icon: "save", text: "Commit Parameters", shortcut: "Ctrl+S", action: "commit" },
        { kind: "item", icon: "revert", text: "Revert to Saved", shortcut: "", action: "revert" },
        { kind: "item", icon: "speaker", text: "Save Master Volume", shortcut: "", action: "saveMasterVolume",
          show: bridge.masterVolumeMode === 0 },
        { kind: "item", icon: "chip", text: "Save Output Config", shortcut: "", action: "saveOutputConfig",
          show: bridge.outputConfigMode === 0 },
        { kind: "sep" },
        { kind: "header", text: "Tools" },
        { kind: "item", icon: "sliders", text: "Matrix Mixer", shortcut: "Ctrl+Shift+M", window: "matrix" },
        { kind: "item", icon: "loudness", text: "Loudness Compensation", shortcut: "Ctrl+Shift+L", window: "loudness" },
        { kind: "item", icon: "headphones", text: "Headphone Crossfeed", shortcut: "Ctrl+Shift+X", window: "crossfeed" },
        { kind: "item", icon: "waveform", text: "Volume Leveller", shortcut: "Ctrl+Shift+V", window: "leveller" },
        { kind: "item", icon: "bassclef", text: "Psychoacoustic Bass", shortcut: "Ctrl+Shift+P", window: "psybass" },
        { kind: "item", icon: "info", text: "Stats for Nerds", shortcut: "Ctrl+Shift+T", window: "stats" },
        { kind: "sep" },
        { kind: "item", icon: "gear", text: "Settings", shortcut: "Ctrl+,", window: "settings" },
        { kind: "sep" },
        { kind: "item", icon: "warning", text: "Factory Reset…", shortcut: "", action: "factoryReset", danger: true }
    ]

    // Items that are shown and can be activated, in order
    readonly property var activeRows: {
        var out = []
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            if (r.kind === "item" && r.show !== false && rowEnabled(r)) out.push(i)
        }
        return out
    }
    property int current: -1   // index into rows

    function rowEnabled(r) {
        if (r.window) return true
        return bridge.connected
    }

    function activate(i) {
        var r = rows[i]
        if (!r || r.kind !== "item" || !rowEnabled(r)) return
        close()
        if (r.window) { openWindow(r.window); return }
        switch (r.action) {
        case "commit": commitRequested(); break
        case "revert": revertRequested(); break
        case "saveMasterVolume": bridge.saveMasterVolume(); break
        case "saveOutputConfig": bridge.saveOutputConfig(); break
        case "factoryReset": factoryResetRequested(); break
        }
    }

    function step(dir) {
        var list = activeRows
        if (list.length === 0) return
        var pos = list.indexOf(current)
        pos = pos < 0 ? (dir > 0 ? 0 : list.length - 1) : (pos + dir + list.length) % list.length
        current = list[pos]
    }

    // ── Open / close animation ──
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 140; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 }
    }
    transformOrigin: Popup.TopLeft

    // ── Card with a soft layered shadow (no shader effects) ──
    background: Item {
        Repeater {
            model: 6
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1) * 2
                anchors.topMargin: -(index + 1) * 2 + 4
                radius: 12 + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: "#1d1d1f"
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }
    }

    contentItem: Column {
        spacing: 0
        focus: true

        Keys.onUpPressed: menu.step(-1)
        Keys.onDownPressed: menu.step(1)
        Keys.onReturnPressed: menu.activate(menu.current)
        Keys.onEnterPressed: menu.activate(menu.current)

        // Device summary
        Item {
            width: parent.width
            height: 54
            Rectangle {
                id: dot
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: bridge.connected ? (bridge.compat >= 2 ? "#ff9f0a" : "#32d74b") : "#ff453a"
            }
            Column {
                anchors.left: dot.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: bridge.connected ? "DSPi " + bridge.platformName : "No device connected"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    visible: bridge.connected
                    text: (bridge.firmwareVersion ? "Firmware " + bridge.firmwareVersion + "  ·  " : "") + bridge.selectedSerial
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.5)
                }
            }
        }
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Item { width: 1; height: 4 }

        Repeater {
            model: menu.rows

            Loader {
                width: parent.width
                readonly property var row: modelData
                readonly property int rowIndex: index
                active: row.show !== false
                visible: active
                sourceComponent: row.kind === "header" ? headerRow : row.kind === "sep" ? sepRow : itemRow
            }
        }
    }

    Component {
        id: headerRow
        Text {
            text: row.text.toUpperCase()
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.8
            color: Qt.rgba(1, 1, 1, 0.38)
            leftPadding: 12
            topPadding: 8
            bottomPadding: 4
        }
    }

    Component {
        id: sepRow
        Item {
            height: 9
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                width: parent.width - 16
                height: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }
        }
    }

    Component {
        id: itemRow
        Item {
            id: item
            height: 32
            readonly property bool enabled_: menu.rowEnabled(row)
            readonly property bool hot: menu.current === rowIndex && enabled_
            readonly property color fg: !enabled_ ? Qt.rgba(1, 1, 1, 0.3)
                                       : hot ? "white"
                                       : row.danger ? "#ff6961" : Qt.rgba(1, 1, 1, 0.9)

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                radius: 7
                color: item.hot ? (row.danger ? "#d9363e" : "#0a7cff") : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
            }
            Icon {
                id: rowIcon
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: row.icon
                size: 16
                color: item.hot ? "white" : row.danger && item.enabled_ ? "#ff6961"
                     : Qt.rgba(1, 1, 1, item.enabled_ ? 0.65 : 0.25)
            }
            Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: row.text
                font.pixelSize: 13
                color: item.fg
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.shortcut || ""
                font.pixelSize: 11
                color: item.hot ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.35)
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: item.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: menu.current = rowIndex
                onExited: if (menu.current === rowIndex) menu.current = -1
                onClicked: menu.activate(rowIndex)
            }
            ToolTip.visible: false
        }
    }
}
