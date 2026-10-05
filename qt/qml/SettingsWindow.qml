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
    width: 900
    height: 640 + titlebarHeight
    minimumWidth: 720
    minimumHeight: 480 + titlebarHeight

    readonly property int sidebarWidth: 232

    // Sidebar runs up under the shared titlebar and is blurred on KDE
    contentUnderTitlebar: true
    blurWidth: sidebarWidth
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
            { id: "about", title: "About", icon: "info", tint: "#8e8e93",
              source: "settings/pages/AboutPage.qml", keywords: "version links github discord patreon ko-fi youtube" },
            { id: "advanced", title: "Advanced", icon: "wrench", tint: "#636366",
              source: "settings/pages/AdvancedPage.qml", keywords: "channel names reset device serial firmware" }
        ]},
        { title: "Display", pages: [
            { id: "graphing", title: "Graphing", icon: "chart", tint: "#30b0c7",
              source: "settings/pages/GraphingPage.qml", keywords: "graph glow line width grid opacity labels range center frequency pop out popout window follow phase readout" },
            { id: "spectrum", title: "Spectrum Analyser", icon: "spectrum", tint: "#5e5ce6",
              source: "settings/pages/SpectrumPage.qml", keywords: "rta fft spectrum analyser analyzer bars peak hold smoothing floor ceiling transform averaging decay" }
        ]},
        { title: "System", pages: [
            { id: "overview", title: "Overview", icon: "pins", tint: "#636366", needsDevice: true,
              source: "settings/pages/OverviewPage.qml", keywords: "gpio pins map assignments in use free" },
            { id: "inputs", title: "Inputs", icon: "input", tint: "#04856f", needsDevice: true,
              source: "settings/pages/InputsPage.qml", keywords: "spdif toslink receiver i2s adat clock slave master lock channels lg sound sync tv" },
            { id: "outputs", title: "Outputs", icon: "output", tint: "#34c759", needsDevice: true,
              source: "settings/pages/OutputsPage.qml", keywords: "pins gpio spdif i2s pdm sub adat optical type reset" },
            { id: "i2s", title: "I2S Configuration", icon: "clock", tint: "#ba3822", needsDevice: true,
              source: "settings/pages/I2SPage.qml", keywords: "bck lrclk bit clock mck master clock multiplier sample rate split unified" },
            { id: "global", title: "Global Parameters", icon: "globe", tint: "#ff9f0a", needsDevice: true,
              source: "settings/pages/GlobalParametersPage.qml", keywords: "startup default preset master volume hardware independent dac mute amplifier pop" }
        ]},
        { title: "Control", pages: [
            { id: "control", title: "Control Interfaces", icon: "chip", tint: "#8f60ad", needsDevice: true,
              source: "settings/pages/ControlInterfacesPage.qml", keywords: "uart serial i2c target microcontroller baud address" }
        ]}
    ]

    function findPage(id) {
        for (var g = 0; g < groups.length; g++)
            for (var p = 0; p < groups[g].pages.length; p++)
                if (groups[g].pages[p].id === id) return groups[g].pages[p]
        return null
    }
    function pageAvailable(page) { return page && (!page.needsDevice || bridge.connected) }
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
        color: windowEffects.blurAvailable ? Qt.rgba(0.13, 0.13, 0.14, 0.35) : "#262628"

        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.rgba(0, 0, 0, 0.6) }

        Column {
            anchors.fill: parent
            anchors.topMargin: settingsWindow.titlebarHeight + 2
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 2

            // Search
            Rectangle {
                width: parent.width
                height: 30
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: search.activeFocus ? "#0a7cff" : "transparent"
                Icon {
                    id: searchIcon
                    x: 9
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
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
            Item { width: 1; height: 8 }

            // Groups and pages
            Repeater {
                model: settingsWindow.groups
                Column {
                    id: group
                    readonly property var groupData: modelData
                    readonly property int shownCount: {
                        search.text; bridge.connected
                        var n = 0
                        for (var i = 0; i < groupData.pages.length; i++)
                            if (settingsWindow.pageAvailable(groupData.pages[i]) && settingsWindow.matchesSearch(groupData.pages[i])) n++
                        return n
                    }
                    visible: shownCount > 0
                    width: parent.width
                    spacing: 2

                    Text {
                        text: group.groupData.title
                        leftPadding: 8
                        topPadding: 10
                        bottomPadding: 3
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                    Repeater {
                        model: group.groupData.pages
                        SettingsSidebarItem {
                            width: group.width
                            visible: { search.text; bridge.connected; return settingsWindow.pageAvailable(modelData) && settingsWindow.matchesSearch(modelData) }
                            height: visible ? 32 : 0
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
                    search.text; bridge.connected
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
        color: "#1e1e20"
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
        height: ctx.dirty ? 56 : 0
        visible: height > 0
        clip: true
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        canRevert: ctx.draftDirty
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
    Shortcut { sequence: "Alt+Left"; onActivated: settingsWindow.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: settingsWindow.goForward() }
    Shortcut { sequences: [StandardKey.Find]; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Escape"; enabled: !search.activeFocus; onActivated: settingsWindow.close() }
}
