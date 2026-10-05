import QtQuick 2.15
import QtQuick.Controls 2.15

// The app menu opened from the titlebar's menu button: device summary,
// device actions, tool windows and settings. Keyboard: Up/Down, Enter, Esc.
Popup {
    id: menu
    // Fits icon + longest label + gap + longest shortcut
    width: Math.ceil(MenuStyle.sideInset + MenuStyle.iconSize + 10 + labelWidest.advanceWidth
                     + 28 + shortcutWidest.advanceWidth + MenuStyle.sideInset + 2 * MenuStyle.padding)
    padding: MenuStyle.padding

    TextMetrics {
        id: labelWidest
        font.pixelSize: MenuStyle.fontSize
        text: {
            var t = ""
            for (var i = 0; i < menu.rows.length; i++)
                if (menu.rows[i].kind === "item" && menu.rows[i].text.length > t.length) t = menu.rows[i].text
            return t
        }
    }
    TextMetrics {
        id: shortcutWidest
        font.pixelSize: MenuStyle.smallFontSize
        text: "Ctrl+Shift+M"
    }
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
        { kind: "item", icon: "subwave", text: "Subharmonic Synthesizer", shortcut: "Ctrl+Shift+S", window: "subharm" },
        { kind: "item", icon: "tube", text: "Tube Modeller", shortcut: "Ctrl+Shift+D", window: "tube" },
        { kind: "item", icon: "upmix", text: "Stereo Upmixer", shortcut: "Ctrl+Shift+U", window: "upmix" },
        { kind: "item", icon: "spectrum", text: "Spectrum Analyser", shortcut: "Ctrl+Shift+A", window: "spectrum" },
        { kind: "item", icon: "signal", text: "Signal Generator", shortcut: "Ctrl+Shift+G", window: "siggen" },
        { kind: "item", icon: "info", text: "Stats for Nerds", shortcut: "Ctrl+Shift+T", window: "stats" },
        { kind: "item", icon: "identify", text: "Interrupt Monitor", shortcut: "Ctrl+Shift+I", window: "monitor" },
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
        spacing: 0
        focus: true

        Keys.onUpPressed: menu.step(-1)
        Keys.onDownPressed: menu.step(1)
        Keys.onReturnPressed: menu.activate(menu.current)
        Keys.onEnterPressed: menu.activate(menu.current)

        // Device summary: one line; the serial number is in the tooltip
        Item {
            width: parent.width
            height: MenuStyle.rowHeight + 2
            Rectangle {
                id: dot
                x: MenuStyle.sideInset + 3
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: bridge.connected ? (bridge.compat >= 2 ? "#ff9f0a" : "#32d74b") : "#ff453a"
            }
            Text {
                anchors.left: dot.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: bridge.connected
                      ? "<b>DSPi " + bridge.platformName + "</b>"
                        + (bridge.firmwareVersion ? "<font color='#8c8c90'>  ·  " + bridge.firmwareVersion + "</font>" : "")
                      : "No device connected"
                font.pixelSize: MenuStyle.fontSize - 1
                color: "white"
            }
            MouseArea {
                id: deviceMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            ToolTip.visible: deviceMouse.containsMouse && bridge.connected
            ToolTip.delay: 500
            ToolTip.text: "Serial " + bridge.selectedSerial
        }
        Rectangle { width: parent.width; height: 1; color: MenuStyle.separator }
        Item { width: 1; height: MenuStyle.padding }

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
            font.pixelSize: MenuStyle.headerFontSize
            font.weight: Font.Bold
            font.letterSpacing: 0.8
            color: Qt.rgba(1, 1, 1, 0.38)
            leftPadding: MenuStyle.sideInset
            topPadding: 6
            bottomPadding: 3
        }
    }

    Component {
        id: sepRow
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
        id: itemRow
        Item {
            id: item
            height: MenuStyle.rowHeight
            readonly property bool enabled_: menu.rowEnabled(row)
            readonly property bool hot: menu.current === rowIndex && enabled_
            readonly property color fg: !enabled_ ? Qt.rgba(1, 1, 1, 0.3)
                                       : hot ? "white"
                                       : row.danger ? MenuStyle.dangerText : MenuStyle.text

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                radius: MenuStyle.rowRadius
                color: item.hot ? (row.danger ? MenuStyle.danger : MenuStyle.highlight) : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
            }
            Icon {
                id: rowIcon
                x: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                name: row.icon
                size: MenuStyle.iconSize
                color: item.hot ? "white" : row.danger && item.enabled_ ? MenuStyle.dangerText
                     : item.enabled_ ? MenuStyle.iconColor : Qt.rgba(1, 1, 1, 0.25)
            }
            Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: row.text
                font.pixelSize: MenuStyle.fontSize
                color: item.fg
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                text: row.shortcut || ""
                font.pixelSize: MenuStyle.smallFontSize
                color: item.hot ? Qt.rgba(1, 1, 1, 0.8) : MenuStyle.dimText
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
