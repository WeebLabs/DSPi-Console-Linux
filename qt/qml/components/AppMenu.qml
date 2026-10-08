import QtQuick 2.15
import QtQuick.Controls 2.15

// The app menu opened from the titlebar's menu button, laid out like the
// macOS menu bar: the device summary, then Device, File, AutoEQ, Effects,
// Tools and Help, each opening its items in a submenu beside it, then Settings.
// Keyboard: Up/Down, Right or Enter opens a submenu, Esc closes.
Popup {
    id: menu
    width: Math.ceil(MenuStyle.sideInset + MenuStyle.iconSize + 10 + labelWidest.advanceWidth
                     + 40 + MenuStyle.sideInset + 2 * MenuStyle.padding)
    padding: MenuStyle.padding
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    TextMetrics {
        id: labelWidest
        font.pixelSize: MenuStyle.fontSize
        text: "No device connected   "
    }

    // Actions are supplied by the window that hosts the menu
    signal commitRequested()
    signal revertRequested()
    signal factoryResetRequested()
    signal openWindow(string name)
    // importFilters / exportFilters / importConfig / exportConfig
    signal fileAction(string name)
    signal autoeqUpdateRequested()

    // While the Getting Started wizard has the window: only Settings and Help
    property bool restricted: false

    // The menu button toggles the menu. Pressing the button while the menu is
    // open closes it as an outside press before the click arrives, so a click
    // right after such a close must not reopen it.
    property real closedAt: 0
    onClosed: { closedAt = Date.now(); sub.close(); openGroup = -1 }

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

    // ── Menus ──
    // Items: { icon, text, shortcut, action | window | autoeq, danger,
    //          help (allowed during setup), always (needs no device),
    //          enabled: false } or { sep: true }
    readonly property var groups: [
        { text: "Device", icon: "chip", items: [
            { icon: "save", text: "Commit Parameters", shortcut: "Ctrl+S", action: "commit" },
            { icon: "revert", text: "Revert to Saved", action: "revert" },
            { sep: true },
            { icon: "speaker", text: "Save Master Volume", action: "saveMasterVolume" },
            { icon: "chip", text: "Save Output Config", action: "saveOutputConfig" },
            { sep: true },
            { icon: "chip", text: "Firmware Update…", window: "firmware" },
            { icon: "warning", text: "Factory Reset…", action: "factoryReset", danger: true }
        ]},
        { text: "File", icon: "input", items: [
            { icon: "input", text: "Import Filters…", shortcut: "Ctrl+I", action: "importFilters" },
            { icon: "output", text: "Export Filters…", shortcut: "Ctrl+E", action: "exportFilters" },
            { sep: true },
            { icon: "input", text: "Import Device Configuration…", action: "importConfig" },
            { icon: "output", text: "Export Device Configuration…", action: "exportConfig" }
        ]},
        { text: "AutoEQ", icon: "headphones", items: autoeqItems },
        { text: "Effects", icon: "sliders", items: [
            { icon: "loudness", text: "Loudness Compensation", shortcut: "Ctrl+Shift+L", window: "loudness" },
            { icon: "headphones", text: "Headphone Crossfeed", shortcut: "Ctrl+Shift+X", window: "crossfeed" },
            { icon: "waveform", text: "Volume Leveller", shortcut: "Ctrl+Shift+V", window: "leveller" },
            { icon: "bassclef", text: "Psychoacoustic Bass", shortcut: "Ctrl+Shift+P", window: "psybass" },
            { icon: "subwave", text: "Subharmonic Synthesizer", shortcut: "Ctrl+Shift+S", window: "subharm" },
            { icon: "tube", text: "Tube Modeller", shortcut: "Ctrl+Shift+D", window: "tube" },
            { icon: "upmix", text: "Stereo Upmixer", shortcut: "Ctrl+Shift+U", window: "upmix" }
        ]},
        { text: "Tools", icon: "wrench", items: [
            { icon: "sliders", text: "Matrix Mixer", shortcut: "Ctrl+Shift+M", window: "matrix" },
            { sep: true },
            { icon: "spectrum", text: "Spectrum Analyser", shortcut: "Ctrl+Shift+A", window: "spectrum" },
            { icon: "signal", text: "Signal Generator", shortcut: "Ctrl+Shift+G", window: "siggen" },
            { icon: "info", text: "Stats for Nerds", shortcut: "Ctrl+Shift+T", window: "stats" },
            { icon: "identify", text: "Interrupt Monitor", shortcut: "Ctrl+Shift+I", window: "monitor" }
        ]},
        { text: "Help", icon: "question-circle", help: true, items: [
            { icon: "cap", text: "Getting Started…", window: "gettingStarted", help: true },
            { icon: "sparkles", text: "What's New in DSPi Console", window: "whatsNew", help: true },
            { sep: true },
            { icon: "github", text: "DSPi Console on GitHub", window: "url:https://github.com/WeebLabs/DSPi-Console-Linux", help: true },
            { icon: "github", text: "DSPi Firmware on GitHub", window: "url:https://github.com/WeebLabs/DSPi", help: true }
        ]}
    ]
    // Browse, the favourites (one click applies), and the database
    readonly property var autoeqItems: {
        var list = [{ icon: "search", text: "Browse Profiles…", shortcut: "Ctrl+Shift+B", window: "autoeq" }, { sep: true }]
        var favs = autoeq.favorites
        if (favs.length === 0) list.push({ icon: "heart", text: "No favorites yet", enabled: false })
        for (var i = 0; i < favs.length; i++) list.push({ icon: "heart", text: favs[i].name, autoeq: favs[i].id })
        list.push({ icon: "xmark", text: "Clear Favorites", action: "clearFavorites", always: true, enabled: favs.length > 0 })
        list.push({ sep: true })
        list.push({ icon: "revert", text: "Update Database…", action: "autoeqUpdate", always: true })
        return list
    }
    readonly property var settingsItem: ({ icon: "gear", text: "Settings", shortcut: "Ctrl+,", window: "settings" })

    function rowEnabled(r) {
        if (r.sep || r.enabled === false) return false
        if (restricted && !r.help && r.window !== "settings") return false
        if (r.window || r.always) return true
        return bridge.connected
    }
    function groupEnabled(g) {
        for (var i = 0; i < g.items.length; i++) if (rowEnabled(g.items[i])) return true
        return false
    }

    function activateItem(r) {
        if (!r || !rowEnabled(r)) return
        close()
        if (r.window) { openWindow(r.window); return }
        if (r.autoeq) { autoeq.apply(r.autoeq); return }
        switch (r.action) {
        case "commit": commitRequested(); break
        case "revert": revertRequested(); break
        case "saveMasterVolume": bridge.saveMasterVolume(); break
        case "saveOutputConfig": bridge.saveOutputConfig(); break
        case "factoryReset": factoryResetRequested(); break
        case "clearFavorites": autoeq.clearFavorites(); break
        case "autoeqUpdate": autoeqUpdateRequested(); break
        default: fileAction(r.action)
        }
    }

    // ── Top level: groups, then Settings ──
    property int current: -1          // 0..groups.length-1, groups.length = Settings
    property int openGroup: -1
    readonly property int rowCount: groups.length + 1

    function openSubmenu(i, focusIt) {
        if (i < 0 || i >= groups.length || !groupEnabled(groups[i])) { sub.close(); openGroup = -1; return }
        current = i
        openGroup = i
        var row = groupRows.itemAt(i)
        sub.items = groups[i].items.map(function (r, k) {
            return r.sep ? { separator: true }
                         : { key: "" + k, text: r.text, icon: r.icon, shortcut: r.shortcut || "",
                             enabled: rowEnabled(r), danger: r.danger === true }
        })
        sub.openAt(row, row.width + MenuStyle.padding + 2, -MenuStyle.padding)
        if (focusIt) { sub.contentItem.forceActiveFocus(); sub.step(1) }
    }
    function step(dir) {
        current = (current < 0 ? (dir > 0 ? -1 : 0) : current) + dir
        current = (current + rowCount) % rowCount
    }

    ActionMenu {
        id: sub
        parent: menu.parent
        onTriggered: {
            var g = menu.groups[menu.openGroup]
            if (g) menu.activateItem(g.items[parseInt(key)])
        }
        onClosed: if (menu.visible && menu.openGroup >= 0) { menu.openGroup = -1; menu.contentItem.forceActiveFocus() }
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
        Keys.onRightPressed: menu.openSubmenu(menu.current, true)
        Keys.onReturnPressed: menu.current === menu.groups.length ? menu.activateItem(menu.settingsItem) : menu.openSubmenu(menu.current, true)
        Keys.onEnterPressed: menu.current === menu.groups.length ? menu.activateItem(menu.settingsItem) : menu.openSubmenu(menu.current, true)

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
                onEntered: { sub.close(); menu.current = -1 }
            }
            ToolTip.visible: deviceMouse.containsMouse && bridge.connected
            ToolTip.delay: 500
            ToolTip.text: "Serial " + bridge.selectedSerial
        }
        Rectangle { width: parent.width; height: 1; color: isMacOS ? Qt.rgba(1, 1, 1, 0.15) : MenuStyle.separator }
        Item { width: 1; height: MenuStyle.padding }

        Repeater {
            id: groupRows
            model: menu.groups
            Item {
                id: row
                width: parent.width
                height: MenuStyle.rowHeight
                readonly property bool usable: menu.groupEnabled(modelData)
                readonly property bool hot: (menu.current === index || menu.openGroup === index) && usable
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
                    radius: MenuStyle.rowRadius
                    color: row.hot ? MenuStyle.highlight : "transparent"
                }
                Icon {
                    id: groupIcon
                    x: MenuStyle.sideInset
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.icon
                    size: MenuStyle.iconSize
                    color: isMacOS ? (row.hot ? "white" : row.usable ? MenuStyle.iconColor : MacColors.tertiaryLabel) : row.hot ? "white" : row.usable ? MenuStyle.iconColor : Qt.rgba(1, 1, 1, 0.25)
                }
                Text {
                    anchors.left: groupIcon.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    font.pixelSize: MenuStyle.fontSize
                    color: isMacOS ? (!row.usable ? MacColors.tertiaryLabel : row.hot ? "white" : MenuStyle.text) : !row.usable ? Qt.rgba(1, 1, 1, 0.3) : row.hot ? "white" : MenuStyle.text
                }
                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: MenuStyle.sideInset
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chev-right"
                    size: 12
                    color: isMacOS ? (row.hot ? "white" : Qt.rgba(1, 1, 1, 0.75)) : row.hot ? "white" : MenuStyle.dimText
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: menu.openSubmenu(index, false)
                    onClicked: menu.openSubmenu(index, false)
                }
            }
        }

        Item {
            width: parent.width
            height: 7
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 8; width: parent.width - 16; height: 1; color: isMacOS ? Qt.rgba(1, 1, 1, 0.15) : MenuStyle.separator }
        }

        // Settings
        Item {
            id: settingsRow
            width: parent.width
            height: MenuStyle.rowHeight
            readonly property bool hot: menu.current === menu.groups.length
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                radius: MenuStyle.rowRadius
                color: settingsRow.hot ? MenuStyle.highlight : "transparent"
            }
            Icon {
                id: settingsIcon
                x: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                name: "gear"
                size: MenuStyle.iconSize
                color: settingsRow.hot ? "white" : MenuStyle.iconColor
            }
            Text {
                anchors.left: settingsIcon.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Settings"
                font.pixelSize: MenuStyle.fontSize
                color: settingsRow.hot ? "white" : MenuStyle.text
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: MenuStyle.sideInset
                anchors.verticalCenter: parent.verticalCenter
                text: "Ctrl+,"
                font.pixelSize: MenuStyle.smallFontSize
                color: isMacOS ? (settingsRow.hot ? "white" : MenuStyle.dimText) : settingsRow.hot ? Qt.rgba(1, 1, 1, 0.8) : MenuStyle.dimText
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { sub.close(); menu.openGroup = -1; menu.current = menu.groups.length }
                onClicked: menu.activateItem(menu.settingsItem)
            }
        }
    }
}
