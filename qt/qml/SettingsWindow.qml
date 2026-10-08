import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.0
import "components"
import "settings"

// Settings: a translucent sidebar of grouped pages, page content on the
// right, Back/Forward history, search, and a save bar for draft changes.
//
// To add a page: write settings/pages/<Name>Page.qml (a SettingsPage built
// from SettingsSection and the Settings*Row components) and add one entry
// to `groups` below.
AppWindow {
    id: settingsWindow
    title: "Settings"
    visible: false
    // macOS: the native Settings window's size (664 x 584 pt, measured)
    width: isMacOS ? 664 : 860
    height: isMacOS ? 584 : 600 + titlebarHeight
    minimumWidth: isMacOS ? 600 : 720
    minimumHeight: isMacOS ? 480 : 480 + titlebarHeight

    readonly property int sidebarWidth: isMacOS ? 180 : 232
    // macOS: the sidebar follows System Settings ▸ Appearance ▸ Sidebar icon
    // size, as the native List does: rows of 24 / 28 / 32 pt with 11 / 13 / 15 pt text
    readonly property int sidebarRowHeight: isMacOS ? [28, 24, 28, 32][macSidebarSizeMode] : 28
    readonly property int sidebarFontSize: isMacOS ? [13, 11, 13, 15][macSidebarSizeMode] : 13

    // Sidebar runs up under the shared titlebar and is blurred on KDE
    contentUnderTitlebar: true
    blurWidth: sidebarWidth
    // macOS: unified titlebar over the sidebar material, as the native Settings
    macUnifiedSidebar: isMacOS ? sidebarWidth : 0
    titleBar.titleText: currentPage ? currentPage.title : "Settings"
    titleBar.showNav: true
    titleBar.canGoBack: historyIndex > 0
    titleBar.canGoForward: historyIndex < history.length - 1
    Connections {
        target: settingsWindow.titleBar
        function onGoBack() { settingsWindow.goBack() }
        function onGoForward() { settingsWindow.goForward() }
    }

    // ── Page registry ──
    // id: stable key (history, deep links); icon: Icon name; tint: tile colour;
    // keywords: extra search terms; needsDevice: hidden while disconnected.
    readonly property var groups: [
        { title: "Application", pages: [
            { id: "about", title: "About", icon: isMacOS ? "gear" : "info", tint: isMacOS ? "#646971" : "#8e8e93",
              source: "settings/pages/AboutPage.qml", keywords: "version links github discord patreon ko-fi youtube" },
            { id: "advanced", title: "Advanced", icon: isMacOS ? "gears" : "wrench", tint: isMacOS ? "#727880" : "#636366",
              source: "settings/pages/AdvancedPage.qml", keywords: "channel names reset device serial firmware" }
        ]},
        { title: "Display", pages: [
            { id: "graphing", title: "Graphing", icon: isMacOS ? "ecg" : "chart", tint: isMacOS ? "#587a89" : "#30b0c7",
              source: "settings/pages/GraphingPage.qml", keywords: "graph glow line width grid opacity labels range center frequency pop out popout window follow phase readout" },
            { id: "spectrum", title: "Spectrum Analyser", icon: isMacOS ? "wave-search" : "spectrum", tint: isMacOS ? "#4c808a" : "#5e5ce6",
              source: "settings/pages/SpectrumPage.qml", keywords: "rta fft spectrum analyser analyzer bars peak hold smoothing floor ceiling transform averaging decay" }
        ]},
        { title: "System", pages: [
            { id: "overview", title: "Overview", icon: isMacOS ? "chip-fill" : "pins", tint: isMacOS ? "#627080" : "#636366", needsDevice: true,
              source: "settings/pages/OverviewPage.qml", keywords: "gpio pins map assignments in use free" },
            { id: "inputs", title: "Inputs", icon: "input", tint: "#04856f", needsDevice: true,
              source: "settings/pages/InputsPage.qml", keywords: "spdif toslink receiver i2s adat clock slave master lock channels lg sound sync tv" },
            { id: "outputs", title: "Outputs", icon: isMacOS ? "connector" : "output", tint: isMacOS ? "#0278c7" : "#34c759", needsDevice: true,
              source: "settings/pages/OutputsPage.qml", keywords: "pins gpio spdif i2s pdm sub adat optical type reset" },
            { id: "i2s", title: "I2S Configuration", icon: isMacOS ? "waveform" : "clock", tint: "#ba3822", needsDevice: true,
              source: "settings/pages/I2SPage.qml", keywords: "bck lrclk bit clock mck master clock multiplier sample rate split unified" },
            { id: "global", title: "Global Parameters", icon: isMacOS ? "drive" : "globe", tint: isMacOS ? "#807701" : "#ff9f0a", needsDevice: true,
              source: "settings/pages/GlobalParametersPage.qml", keywords: "startup default preset master volume hardware independent dac mute amplifier pop" }
        ]},
        { title: "Control", pages: [
            { id: "surfaces", title: "Control Surfaces", icon: isMacOS ? "dial" : "cs-pot", tint: "#8354a0", needsDevice: true, needs: "cs",
              source: "settings/pages/ControlSurfacesPage.qml", keywords: "buttons switches knobs potentiometer fader encoder led ir remote receiver learn display oled lcd gpio bindings" },
            { id: "control", title: "Control Interfaces", icon: "chip", tint: "#8f60ad", needsDevice: true,
              source: "settings/pages/ControlInterfacesPage.qml", keywords: "uart serial i2c target microcontroller baud address" },
            { id: "groups", title: "Channel Groups", icon: "group", tint: "#6c64b7", needsDevice: true, needs: "groups",
              source: "settings/pages/ChannelGroupsPage.qml", keywords: "group zone stereo pair members control surfaces" },
            { id: "macros", title: "Macros", icon: "list-number", tint: "#9e528d", needsDevice: true, needs: "macros",
              source: "settings/pages/MacrosPage.qml", keywords: "macro sequence steps fire run delay control surfaces" },
            { id: "aux", title: "Auxiliary Outputs", icon: "power", tint: "#7a5aac", needsDevice: true, needs: "aux",
              source: "settings/pages/AuxOutputsPage.qml", keywords: "aux relay trigger amplifier lamp fan dimmer pwm gpio output" }
        ]}
    ]

    function findPage(id) {
        for (var g = 0; g < groups.length; g++)
            for (var p = 0; p < groups[g].pages.length; p++)
                if (groups[g].pages[p].id === id) return groups[g].pages[p]
        return null
    }
    // Control pages appear when the connected firmware has the feature
    function featureAvailable(need) {
        switch (need) {
        case "cs": return controlSurfaces.supported
        case "groups": return controlSurfaces.hasGroups
        case "macros": return controlSurfaces.hasMacros
        case "aux": return controlSurfaces.hasAux
        default: return true
        }
    }
    // Follows the connection only: bridge.connected notifies on every status
    // poll (the meters), and the sidebar shouldn't re-run with it
    readonly property bool deviceConnected: bridge.connected
    function pageAvailable(page) {
        return page && (!page.needsDevice || deviceConnected) && (!page.needs || featureAvailable(page.needs))
    }
    function matchesSearch(page) {
        var q = search.text.trim().toLowerCase()
        if (q === "") return true
        return (page.title + " " + (page.keywords || "")).toLowerCase().indexOf(q) >= 0
    }

    // ── Navigation with history ──
    property var history: []
    property int historyIndex: -1
    readonly property var currentPage: historyIndex >= 0 ? findPage(history[historyIndex]) : null

    function navigate(id) {
        if (!findPage(id) || (currentPage && currentPage.id === id)) return
        var h = history.slice(0, historyIndex + 1)
        h.push(id)
        history = h
        historyIndex = h.length - 1
        remembered.lastPage = id
    }
    function goBack() { if (historyIndex > 0) { historyIndex--; remembered.lastPage = history[historyIndex] } }
    function goForward() { if (historyIndex < history.length - 1) { historyIndex++; remembered.lastPage = history[historyIndex] } }

    Settings {
        id: remembered
        category: "settingsWindow"
        property string lastPage: "about"
    }

    // Reopen on the last page used; leave a device page if the device goes
    onVisibleChanged: if (visible && historyIndex < 0) navigate(remembered.lastPage)
    Connections {
        target: bridge
        function onStatusChanged() {
            if (settingsWindow.currentPage && !settingsWindow.pageAvailable(settingsWindow.currentPage))
                settingsWindow.navigate("about")
        }
    }
    Connections {
        target: controlSurfaces
        function onChanged() {
            // Leave a Control page the new device doesn't have (once it has been read)
            if (controlSurfaces.loaded && settingsWindow.currentPage
                && !settingsWindow.pageAvailable(settingsWindow.currentPage))
                settingsWindow.navigate("about")
        }
    }

    // Pending changes for the current device (asked about before a device switch)
    readonly property bool hasPendingChanges: ctx.dirty
    function discardPending() { ctx.load() }

    SettingsContext {
        id: ctx
        app: root
        window: settingsWindow
        onNavigateRequested: settingsWindow.navigate(pageId)
    }


    // ── Sidebar ──
    Rectangle {
        id: sidebar
        width: settingsWindow.sidebarWidth
        height: parent.height
        color: isMacOS ? "transparent" : windowEffects.blurAvailable ? Qt.rgba(0.13, 0.13, 0.14, 0.35) : "#262628"

        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: isMacOS ? "black" : Qt.rgba(0, 0, 0, 0.6) }

        Column {
            anchors.fill: parent
            anchors.topMargin: settingsWindow.titlebarHeight + 2
            anchors.leftMargin: isMacOS ? 9 : 10
            anchors.rightMargin: isMacOS ? 11 : 10
            spacing: 2

            // Search (macOS: none - the native sidebar has no search field)
            Rectangle {
                visible: !isMacOS
                width: parent.width
                height: isMacOS ? 22 : 28
                radius: isMacOS ? 6 : 7
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: search.activeFocus ? "#0a7cff" : "transparent"
                Icon {
                    id: searchIcon
                    x: isMacOS ? 7 : 9
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: isMacOS ? 12 : 14
                    color: Qt.rgba(1, 1, 1, 0.45)
                }
                TextInput {
                    id: search
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 7
                    anchors.right: clearSearch.left
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 13
                    color: "white"
                    selectByMouse: true
                    clip: true
                    Text {
                        visible: !search.text && !search.activeFocus
                        text: "Search"
                        font: search.font
                        color: Qt.rgba(1, 1, 1, 0.4)
                    }
                    // Enter opens the first match
                    onAccepted: {
                        for (var g = 0; g < settingsWindow.groups.length; g++)
                            for (var p = 0; p < settingsWindow.groups[g].pages.length; p++) {
                                var pg = settingsWindow.groups[g].pages[p]
                                if (settingsWindow.pageAvailable(pg) && settingsWindow.matchesSearch(pg)) {
                                    settingsWindow.navigate(pg.id)
                                    return
                                }
                            }
                    }
                    Keys.onEscapePressed: text = ""
                }
                Text {
                    id: clearSearch
                    visible: search.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.5)
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: search.text = "" }
                }
            }
            Item { visible: !isMacOS; width: 1; height: isMacOS ? 0 : 8 }

            // Groups and pages
            Repeater {
                model: settingsWindow.groups
                Column {
                    id: group
                    readonly property var groupData: modelData
                    readonly property int shownCount: {
                        search.text; settingsWindow.deviceConnected; controlSurfaces.revision
                        var n = 0
                        for (var i = 0; i < groupData.pages.length; i++)
                            if (settingsWindow.pageAvailable(groupData.pages[i]) && settingsWindow.matchesSearch(groupData.pages[i])) n++
                        return n
                    }
                    visible: shownCount > 0
                    width: parent.width
                    spacing: isMacOS ? 0 : 2

                    // macOS: measured from the native sidebar, the same at every size
                    Text {
                        text: group.groupData.title
                        leftPadding: isMacOS ? 4 : 8
                        topPadding: isMacOS ? (index === 0 ? 2 : 14) : 9
                        bottomPadding: 3
                        font.pixelSize: 11
                        font.weight: isMacOS ? Font.Bold : Font.DemiBold
                        color: isMacOS ? Qt.rgba(1, 1, 1, 0.31) : Qt.rgba(1, 1, 1, 0.45)   // macOS: tertiary label, vibrancy-brightened (measured)
                    }
                    Repeater {
                        model: group.groupData.pages
                        SettingsSidebarItem {
                            width: group.width
                            visible: { search.text; settingsWindow.deviceConnected; controlSurfaces.revision; return settingsWindow.pageAvailable(modelData) && settingsWindow.matchesSearch(modelData) }
                            height: visible ? settingsWindow.sidebarRowHeight : 0
                            fontSize: settingsWindow.sidebarFontSize
                            title: modelData.title
                            icon: modelData.icon
                            tint: modelData.tint
                            selected: settingsWindow.currentPage !== null && settingsWindow.currentPage.id === modelData.id
                            onClicked: settingsWindow.navigate(modelData.id)
                        }
                    }
                }
            }

            Text {
                visible: {
                    search.text; settingsWindow.deviceConnected; controlSurfaces.revision
                    for (var g = 0; g < settingsWindow.groups.length; g++)
                        for (var p = 0; p < settingsWindow.groups[g].pages.length; p++)
                            if (settingsWindow.pageAvailable(settingsWindow.groups[g].pages[p])
                                && settingsWindow.matchesSearch(settingsWindow.groups[g].pages[p])) return false
                    return true
                }
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 20
                text: "No matching settings"
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.4)
            }
        }
    }

    // ── Page area ──
    // Painted opaque: with blur the window itself is transparent, and only
    // the sidebar strip should show the blurred backdrop.
    Rectangle {
        anchors.left: sidebar.right
        anchors.right: parent.right
        height: parent.height
        color: isMacOS ? "#282828" : "#1e1e20"
    }
    Item {
        id: content
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: settingsWindow.titlebarHeight
        anchors.bottom: saveBar.top

        Loader {
            id: pageLoader
            anchors.fill: parent
            source: settingsWindow.currentPage ? settingsWindow.currentPage.source : ""
            onLoaded: item.ctx = ctx
        }
    }

    SettingsSaveBar {
        id: saveBar
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: ctx.dirty ? 48 : 0
        visible: height > 0
        clip: true
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        canRevert: ctx.draftDirty || ctx.csDirty
        onSave: ctx.save()
        onRevert: ctx.revert()
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: ctx.dirty && !search.activeFocus
        onActivated: ctx.save()
    }

    // ── Titlebar (Linux draws its own) ──
    Rectangle {
        // Opaque strip behind the title over the page area
        visible: !isMacOS
        anchors.left: sidebar.right
        anchors.right: parent.right
        height: settingsWindow.titlebarHeight
        color: "#1e1e20"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }
    }
    // ── macOS titlebar: back / forward and the page name over the page area,
    // the native toolbar's navigation group (DSPi_ConsoleApp.swift:499) ──
    component MacNavButton: Item {
        id: nav
        property alias icon: navIcon.name
        property bool active: true
        property string tip: ""
        signal clicked()
        width: 30; height: 24
        ToolTip.visible: navMouse.containsMouse && nav.active
        ToolTip.delay: 600
        ToolTip.text: tip
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle {
            anchors.fill: parent
            radius: 6
            color: navMouse.pressed && nav.active ? MacColors.opacity(MacColors.label, 0.18)
                 : navMouse.containsMouse && nav.active ? MacColors.opacity(MacColors.label, 0.1) : "transparent"
        }
        Icon {
            id: navIcon
            anchors.centerIn: parent
            size: 19
            color: nav.active ? MacColors.label : MacColors.tertiaryLabel
        }
        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: nav.active
            onClicked: nav.clicked()
        }
    }
    Loader {
        active: isMacOS
        anchors.left: sidebar.right
        anchors.leftMargin: 3
        height: settingsWindow.titlebarHeight + 2
        sourceComponent: Row {
            spacing: 0
            MacNavButton { icon: "chev-left"; tip: "Back"; active: settingsWindow.historyIndex > 0; onClicked: settingsWindow.goBack() }
            MacNavButton { icon: "chev-right"; tip: "Forward"; active: settingsWindow.historyIndex < settingsWindow.history.length - 1; onClicked: settingsWindow.goForward() }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 1.5
                text: settingsWindow.currentPage ? settingsWindow.currentPage.title : "Settings"
                font.pixelSize: 13
                font.weight: Font.Bold
                color: MacColors.label
            }
        }
    }

    Shortcut { sequence: "Alt+Left"; onActivated: settingsWindow.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: settingsWindow.goForward() }
    Shortcut { enabled: !isMacOS; sequences: [StandardKey.Find]; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Escape"; enabled: !search.activeFocus; onActivated: settingsWindow.close() }
}
