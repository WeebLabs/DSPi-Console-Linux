import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Qt.labs.platform 1.1 as Platform
import Qt.labs.settings 1.0
import DSPi 1.0
import "components"

ApplicationWindow {
    id: root
    visible: true
    width: 950
    height: 813
    minimumWidth: 950
    minimumHeight: 600
    title: "DSPi Console"
    color: isMacOS ? "transparent" : "#303030"
    // Linux draws its own titlebar (with the menu button in it)
    flags: isMacOS ? Qt.Window : (Qt.Window | Qt.FramelessWindowHint)

    // Titlebar inset: macOS integrated titlebar needs offset, Linux uses standard decorations
    property int titlebarHeight: isMacOS ? 28 : 30
    // Sidebar width: drag its right edge (220-300 px), double-click to reset
    readonly property int sidebarMinWidth: 220
    readonly property int sidebarMaxWidth: 300
    readonly property int sidebarDefaultWidth: 270
    property int sidebarWidth: sidebarDefaultWidth
    onSidebarWidthChanged: if (!isMacOS) windowEffects.setBlurWidth(root, sidebarWidth)

    Settings {
        category: "sidebar"
        property alias width: root.sidebarWidth
    }

    // Platform-aware monospace font
    readonly property string monoFont: isMacOS ? "Menlo" : "monospace"

    // Graph settings (shared between SettingsWindow and BodePlotItem)
    property bool graphShowGlow: false
    property real graphLineWidth: 1.5
    property bool graphShowFreqGrid: true
    property bool graphShowFreqLabels: true
    property bool graphShowDbGrid: true
    property bool graphShowDbLabels: true
    property real graphDbRange: 50.0
    property real graphDbCenter: 0.0
    property real graphMinFreq: 15.0
    property real graphMaxFreq: 20000.0
    property bool graphShowPhase: false
    property bool graphPhaseUnwrapped: false
    property bool graphFreqReadout: true
    property bool graphLevelReadout: true
    property real graphGridOpacity: 0.5      // grid line strength, 0-2 (macOS default 50%)
    property bool graphPopOutFollows: true    // the pop-out graph shows what the main window shows
    property real graphHeight: 250          // the response graph, resized by its handle (250-350)

    // Graph preferences persist between sessions
    Settings {
        category: "graph"
        property alias showGlow: root.graphShowGlow
        property alias lineWidth: root.graphLineWidth
        property alias showFreqGrid: root.graphShowFreqGrid
        property alias showFreqLabels: root.graphShowFreqLabels
        property alias showDbGrid: root.graphShowDbGrid
        property alias showDbLabels: root.graphShowDbLabels
        property alias dbRange: root.graphDbRange
        property alias dbCenter: root.graphDbCenter
        property alias minFreq: root.graphMinFreq
        property alias maxFreq: root.graphMaxFreq
        property alias showPhase: root.graphShowPhase
        property alias phaseUnwrapped: root.graphPhaseUnwrapped
        property alias freqReadout: root.graphFreqReadout
        property alias levelReadout: root.graphLevelReadout
        property alias height: root.graphHeight
        property alias gridOpacity: root.graphGridOpacity
        property alias popOutFollows: root.graphPopOutFollows
    }

    // ── Spectrum analyser ──
    // Where it shows (dashboard and channel pages separately) and how
    property bool rtaDashboardShowGraph: true
    property bool rtaDashboardShowBars: false
    property bool rtaChannelShowGraph: true
    property bool rtaChannelShowBars: false
    property bool rtaChannelPagesShowSpectrum: true
    property string rtaDashboardSource: ""        // "out:0,1" / "in:0"; "out:" = none
    property string rtaDashboardOtherSide: ""     // the other tap's last selection
    property int rtaBarColumns: 2
    property real rtaBarHeight: 96
    property real rtaGraphOpacity: 1.0
    property bool rtaShowPeakHold: true
    property bool rtaSmoothing: true
    property int rtaFloorDb: -90
    property int rtaCeilingDb: 6
    property int rtaFftOrder: 10
    property int rtaAvgMs: 300
    property int rtaPeakDecay: 12

    Settings {
        category: "spectrum"
        property alias dashboardShowGraph: root.rtaDashboardShowGraph
        property alias dashboardShowBars: root.rtaDashboardShowBars
        property alias channelShowGraph: root.rtaChannelShowGraph
        property alias channelShowBars: root.rtaChannelShowBars
        property alias channelPagesShowSpectrum: root.rtaChannelPagesShowSpectrum
        property alias dashboardSource: root.rtaDashboardSource
        property alias dashboardOtherSide: root.rtaDashboardOtherSide
        property alias barColumns: root.rtaBarColumns
        property alias barHeight: root.rtaBarHeight
        property alias graphOpacity: root.rtaGraphOpacity
        property alias showPeakHold: root.rtaShowPeakHold
        property alias smoothing: root.rtaSmoothing
        property alias floorDb: root.rtaFloorDb
        property alias ceilingDb: root.rtaCeilingDb
        property alias fftOrder: root.rtaFftOrder
        property alias avgMs: root.rtaAvgMs
        property alias peakDecay: root.rtaPeakDecay
    }
    // Engine options go to the device (never stored there)
    Binding { target: rta; property: "fftOrder"; value: root.rtaFftOrder }
    Binding { target: rta; property: "avgMs"; value: root.rtaAvgMs }
    Binding { target: rta; property: "peakDecay"; value: root.rtaPeakDecay }

    readonly property bool onDashboard: selection === "overview"
    readonly property bool rtaShowGraph: onDashboard ? rtaDashboardShowGraph : rtaChannelShowGraph
    readonly property bool rtaShowBars: onDashboard ? rtaDashboardShowBars : rtaChannelShowBars
    // A channel page's selection starts on its own channel each time it opens
    property string rtaPageSource: ""
    property string rtaPageOtherSide: ""

    // Channels that can be analysed now, as "in:0,1|out:0,2"; changes rarely
    property string rtaAvailable: ""
    function rtaRefreshAvailable() {
        var k = rta.availableChannels(0).join(",") + "|" + rta.availableChannels(1).join(",")
        if (k !== rtaAvailable) rtaAvailable = k
    }
    Connections {
        target: bridge
        function onStateChanged() { root.rtaRefreshAvailable() }
        function onStatusChanged() { root.rtaRefreshAvailable() }
    }
    Connections { target: rta; function onCapsChanged() { root.rtaRefreshAvailable() } }

    function rtaAvailableAt(tap) {
        var part = rtaAvailable.split("|")[tap] || ""
        return part === "" ? [] : part.split(",").map(Number)
    }
    function rtaDefaultSource() {
        var outs = rtaAvailableAt(1)
        return outs.length ? "out:" + outs[0] : "in:0"
    }
    // {tap, channels} of a source key, keeping only channels that exist now
    function rtaParse(src) {
        var tap = src.indexOf("in:") === 0 ? 0 : 1
        var body = src.slice(tap === 0 ? 3 : 4)
        var avail = rtaAvailableAt(tap)
        var chans = body === "" ? [] : body.split(",").map(Number).filter(function (c) { return avail.indexOf(c) >= 0 })
        return { tap: tap, channels: chans }
    }
    function rtaKey(tap, channels) {
        return (tap === 0 ? "in:" : "out:") + channels.slice().sort(function (a, b) { return a - b }).join(",")
    }
    readonly property var rtaSelection: {
        rtaAvailable
        return rtaParse(onDashboard ? (rtaDashboardSource !== "" ? rtaDashboardSource : rtaDefaultSource()) : rtaPageSource)
    }

    function rtaSetSource(src) {
        if (onDashboard) rtaDashboardSource = src
        else {
            rtaPageSource = src
            // Clearing a page's spectrum keeps the next pages clear too
            rtaChannelPagesShowSpectrum = rtaParse(src).channels.length > 0
        }
    }
    function rtaToggle(ch) {
        var sel = rtaSelection, chans = sel.channels.slice(), i = chans.indexOf(ch)
        if (i >= 0) chans.splice(i, 1); else chans.push(ch)
        rtaSetSource(rtaKey(sel.tap, chans))
    }
    function rtaClear() { rtaSetSource(rtaKey(rtaSelection.tap, [])) }
    // Inputs and outputs are never mixed: the device listens at one tap
    function rtaSwitchSide(tap) {
        var sel = rtaSelection
        if (sel.tap === tap) return
        var here = rtaKey(sel.tap, sel.channels)
        var back = onDashboard ? rtaDashboardOtherSide : rtaPageOtherSide
        var next = back !== "" && rtaParse(back).tap === tap ? back
                 : rtaKey(tap, rtaAvailableAt(tap).slice(0, 1))
        if (onDashboard) rtaDashboardOtherSide = here; else rtaPageOtherSide = here
        rtaSetSource(next)
    }
    function rtaSetShowGraph(v) { if (onDashboard) rtaDashboardShowGraph = v; else rtaChannelShowGraph = v }
    function rtaSetShowBars(v) { if (onDashboard) rtaDashboardShowBars = v; else rtaChannelShowBars = v }

    onSelectionChanged: {
        if (onDashboard) return
        // (selectedChannel / selectedOutput are set after selection)
        var n = parseInt(selection.split(":")[1])
        var own = selection.indexOf("output:") === 0 ? "out:" + n : "in:" + rta.tapIndex(n)
        rtaPageSource = rtaChannelPagesShowSpectrum ? own : own.slice(0, own.indexOf(":") + 1)
        rtaPageOtherSide = ""
    }
    Component.onCompleted: { rtaRefreshAvailable(); startOnboarding() }

    // Selection state: "overview", "channel:N", "output:N"
    property string selection: "overview"
    property int selectedChannel: -1
    property int selectedOutput: -1

    // Curve visibility on the dashboard, restored when a channel page closes
    property var dashboardVisibility: null

    function showOnlyCurves(ids) {
        if (dashboardVisibility === null) {
            var saved = []
            for (var i = 0; i < 17; i++) saved.push(bridge.channelVisible(i))
            dashboardVisibility = saved
        }
        for (var c = 0; c < 17; c++) bridge.setChannelVisible(c, ids.indexOf(c) >= 0)
    }

    function selectOverview() {
        selection = "overview"
        selectedChannel = -1
        selectedOutput = -1
        if (dashboardVisibility !== null) {
            for (var c = 0; c < 17; c++) bridge.setChannelVisible(c, dashboardVisibility[c])
            dashboardVisibility = null
        }
    }

    function selectChannel(ch) {
        if (selection === "channel:" + ch) {
            selectOverview()
        } else {
            selection = "channel:" + ch
            selectedChannel = ch
            selectedOutput = -1
            // Only this channel's curve, and its linked partner's
            var partner = bridge.linkedPartner(ch)
            showOnlyCurves(partner >= 0 ? [ch, partner] : [ch])
        }
    }

    function selectOutput(idx) {
        if (selection === "output:" + idx) {
            selectOverview()
        } else {
            selection = "output:" + idx
            selectedOutput = idx
            selectedChannel = -1
            showOnlyCurves([idx + 2])
        }
    }

    readonly property bool textFocused: activeFocusItem !== null && activeFocusItem.selectedText !== undefined

    // App id of the open channel page, or -1 on the dashboard
    readonly property int openChannelId: selectedOutput >= 0 ? selectedOutput + 2 : selectedChannel

    // Copy / Paste Parameters for the open channel page (skipped while a
    // text field has focus, so ordinary text copy/paste still works)
    Shortcut {
        sequences: [StandardKey.Copy]
        enabled: root.openChannelId >= 0 && !root.textFocused
        onActivated: bridge.copyChannel(root.openChannelId)
    }
    Shortcut {
        sequences: [StandardKey.Paste]
        enabled: root.openChannelId >= 0 && !root.textFocused
        onActivated: bridge.pasteChannel(root.openChannelId)
    }

    // Leave the channel page when the device goes away
    Connections {
        target: bridge
        function onStatusChanged() { if (!bridge.connected && root.selection !== "overview") root.selectOverview() }
    }

    // Native menu bar: macOS only (Linux uses the titlebar menu and the
    // Shortcuts below, which would clash with a second set)
    Loader {
        active: isMacOS
        sourceComponent: Component {
            Platform.MenuBar {
            Platform.Menu {
                title: "File"
                Platform.MenuItem {
                    text: "Commit Parameters..."
                    shortcut: StandardKey.Save
                    onTriggered: {
                        var status = bridge.saveParams()
                        if (status !== 0) {
                            console.warn("Save params failed:", status)
                        }
                    }
                }
                Platform.MenuItem {
                    text: "Revert to Saved..."
                    onTriggered: {
                        var status = bridge.loadParams()
                        if (status !== 0) {
                            console.warn("Load params failed:", status)
                        }
                    }
                }
                Platform.MenuSeparator {}
                Platform.MenuItem {
                    text: "Factory Reset..."
                    onTriggered: {
                        var status = bridge.factoryReset()
                        if (status !== 0) {
                            console.warn("Factory reset failed:", status)
                        }
                    }
                }
            }
            Platform.Menu {
                title: "Tools"
                Platform.MenuItem {
                    text: "Matrix Mixer..."
                    shortcut: "Ctrl+Shift+M"
                    onTriggered: matrixWindow.visible = true
                }
                Platform.MenuItem {
                    text: "Loudness Compensation..."
                    shortcut: "Ctrl+Shift+L"
                    onTriggered: loudnessWindow.visible = true
                }
                Platform.MenuItem {
                    text: "Headphone Crossfeed..."
                    shortcut: "Ctrl+Shift+X"
                    onTriggered: crossfeedWindow.visible = true
                }
                Platform.MenuItem {
                    text: "Stats..."
                    shortcut: "Ctrl+Shift+T"
                    onTriggered: statsWindow.visible = true
                }
                Platform.MenuSeparator {}
                Platform.MenuItem {
                    text: "Settings..."
                    shortcut: "Ctrl+,"
                    onTriggered: settingsWindow.visible = true
                }
            }
        }
        }
    }

    // Main layout: Sidebar + Content
    Row {
        anchors.fill: parent

        // Sidebar
        Sidebar {
            id: sidebar
            width: root.sidebarWidth
            height: parent.height
        }

        // Content area
        Rectangle {
            width: parent.width - root.sidebarWidth
            height: parent.height
            color: isMacOS ? "transparent" : nativeWindowColor

            Column {
                anchors.fill: parent
                anchors.margins: 0
                anchors.topMargin: root.titlebarHeight
                // Graph's 8 px resize handle + 10 = 18 px, the same gap as between cards
                spacing: 10

                // Firmware compatibility banner
                Rectangle {
                    id: compatBanner
                    visible: bridge.compat >= 2
                    width: parent.width - 32
                    x: 16
                    height: visible ? compatText.implicitHeight + 20 : 0
                    radius: 8
                    color: Qt.rgba(0.95, 0.6, 0.2, 0.15)
                    border.color: Qt.rgba(0.95, 0.6, 0.2, 0.5)

                    Text {
                        id: compatText
                        anchors.fill: parent
                        anchors.margins: 10
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        color: "white"
                        text: bridge.compatMessage
                    }
                }

                // Firmware version mismatch: the device runs another version
                // than this Console expects (hidden until the next launch)
                Rectangle {
                    id: versionBanner
                    property bool hiddenThisLaunch: false
                    visible: !hiddenThisLaunch && !compatBanner.visible && (firmware.match === 2 || firmware.match === 3)
                    width: parent.width - 32
                    x: 16
                    height: visible ? Math.max(versionText.implicitHeight + 16, 40) : 0
                    radius: 8
                    color: Qt.rgba(1, 0.62, 0.04, 0.12)
                    border.color: Qt.rgba(1, 0.62, 0.04, 0.45)

                    Icon {
                        id: versionIcon
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        name: "warning"
                        size: 15
                        color: "#ff9f0a"
                    }
                    Text {
                        id: versionText
                        anchors.left: versionIcon.right
                        anchors.leftMargin: 9
                        anchors.right: versionButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                        color: "white"
                        text: firmware.match === 3
                              ? "This device runs firmware " + firmware.deviceVersion + ", which is newer than DSPi Console "
                                + firmware.expectedVersion + ". Some of its features may not be shown."
                              : "This device runs firmware " + firmware.deviceVersion + "; DSPi Console expects " + firmware.expectedVersion + "."
                    }
                    Row {
                        id: versionButtons
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: [firmware.match === 3 ? "Details…" : "Update…", "Hide"]
                            Rectangle {
                                width: label.implicitWidth + 20
                                height: 24
                                radius: 7
                                color: bannerMouse.pressed ? Qt.rgba(1, 1, 1, 0.13) : bannerMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.18)
                                Text { id: label; anchors.centerIn: parent; text: modelData; font.pixelSize: 12; color: "white" }
                                MouseArea {
                                    id: bannerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: index === 0 ? root.openToolWindow("firmware") : (versionBanner.hiddenThisLaunch = true)
                                }
                                ToolTip.text: index === 1 ? "Hide this warning until DSPi Console is next started" : ""
                                ToolTip.visible: index === 1 && bannerMouse.containsMouse
                                ToolTip.delay: 600
                            }
                        }
                    }
                }

                // Graph section
                FilterResponseView {
                    id: filterResponse
                    width: parent.width
                }

                // Dynamic content
                Loader {
                    id: contentLoader
                    width: parent.width
                    // The column already starts below the titlebar
                    height: parent.height - filterResponse.height - 10
                            - (compatBanner.visible ? compatBanner.height + 10 : 0)
                            - (versionBanner.visible ? versionBanner.height + 10 : 0)

                    sourceComponent: {
                        if (root.selection === "overview")
                            return dashboardComponent
                        else if (root.selection.startsWith("channel:") || root.selection.startsWith("output:"))
                            return channelEditorComponent
                        return dashboardComponent
                    }
                }
            }
        }
    }

    // Dynamic content components
    Component {
        id: dashboardComponent
        DashboardView {}
    }

    Component {
        id: channelEditorComponent
        Item {
            SpectrumBarStrip {
                id: pageStrip
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                app: root
                onOpenAnalyser: root.openToolWindow("spectrum")
            }
            // Below the bars when they show
            readonly property real pageTop: pageStrip.visible ? pageStrip.height + 16 : 0
            ChannelSettingsView {
                id: outputSettings
                visible: root.selectedOutput >= 0
                anchors.top: parent.top
                anchors.topMargin: parent.pageTop
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                outputIndex: root.selectedOutput >= 0 ? root.selectedOutput : 0
            }
            InputHeaderCard {
                id: inputHeader
                visible: root.selectedChannel >= 0
                anchors.top: parent.top
                anchors.topMargin: parent.pageTop
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                channelId: root.selectedChannel >= 0 ? root.selectedChannel : 0
            }
            FilterListView {
                anchors.top: root.selectedOutput >= 0 ? outputSettings.bottom
                           : root.selectedChannel >= 0 ? inputHeader.bottom : pageStrip.bottom
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16      // same as the side margins
                channelId: root.selectedOutput >= 0 ? root.selectedOutput + 2 : root.selectedChannel
                editor: filterResponse.peqEditor
            }
        }
    }

    // Sidebar resize handle on its right edge
    MouseArea {
        id: sidebarSplitter
        x: root.sidebarWidth - 3
        y: root.titlebarHeight
        width: 6
        height: parent.height - root.titlebarHeight
        z: 800
        hoverEnabled: true
        cursorShape: Qt.SplitHCursor
        onPositionChanged: {
            if (!pressed) return
            var x = mapToItem(root.contentItem, mouse.x, 0).x
            root.sidebarWidth = Math.round(Math.max(root.sidebarMinWidth, Math.min(root.sidebarMaxWidth, x)))
        }
        onDoubleClicked: root.sidebarWidth = root.sidebarDefaultWidth
    }

    // Linux: client-side titlebar, resize edges and window outline
    // ── Onboarding ──
    // The Getting Started wizard takes over the main window for a new user
    // (and from Help); What's New shows once after Console is updated.
    Settings {
        id: onboarding
        category: "onboarding"
        property bool setupDone: false
        property string whatsNewShown: ""
    }
    property bool setupRequested: false
    readonly property bool showWizard: setupRequested || !onboarding.setupDone
    Loader {
        id: wizardLoader
        anchors.fill: parent
        anchors.topMargin: root.titlebarHeight
        active: root.showWizard
        sourceComponent: GettingStartedView {
            onFinished: { onboarding.setupDone = true; root.setupRequested = false }
        }
    }
    function startOnboarding() {
        // Someone who used Console before this existed isn't sent through setup
        if (!onboarding.setupDone && hadSettingsAtLaunch) onboarding.setupDone = true
        if (onboarding.whatsNewShown === "") {
            // A new install starts caught up
            onboarding.whatsNewShown = Qt.application.version
        } else if (whatsNewWindow.unread(onboarding.whatsNewShown).length > 0) {
            openToolWindow("whatsNew")
        }
    }

    WindowTitleBar {
        visible: !isMacOS
        z: 900
        width: parent.width
        height: root.titlebarHeight
        window: root
        sidebarWidth: sidebar.width
        showTitle: false
        onMenuRequested: appMenu.toggleAt(anchorItem)
    }

    WindowResizeEdges {
        window: root
        visible: !isMacOS && root.visibility !== Window.Maximized
        z: 950
    }

    Rectangle {
        visible: !isMacOS && root.visibility !== Window.Maximized
        anchors.fill: parent
        z: 1000
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
    }

    // Native-style window border highlight (macOS only)
    Rectangle {
        visible: isMacOS
        anchors.fill: parent
        z: 1000
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.2)
        border.width: 1
        radius: 10
    }

    // Separate windows
    MatrixMixerWindow { id: matrixWindow }
    LoudnessWindow { id: loudnessWindow }
    CrossfeedWindow { id: crossfeedWindow }
    VolumeLevellerWindow { id: levellerWindow }
    PsychoacousticBassWindow { id: psybassWindow }
    SubharmonicSynthWindow { id: subharmWindow }
    TubeModellerWindow { id: tubeWindow }
    UpmixerWindow { id: upmixWindow }
    FirmwareUpdateWindow { id: firmwareWindow; onExportRequested: root.fileAction("exportConfig") }
    AutoEqBrowserWindow { id: autoeqWindow }
    AutoEqRebuildWindow { id: autoeqRebuildWindow }
    WhatsNewWindow { id: whatsNewWindow; onVisibleChanged: if (visible) onboarding.whatsNewShown = Qt.application.version }

    function openToolWindow(name) {
        if (name.indexOf("url:") === 0) { Qt.openUrlExternally(name.substring(4)); return }
        if (name === "gettingStarted") { setupRequested = true; return }
        var w = { matrix: matrixWindow, loudness: loudnessWindow, crossfeed: crossfeedWindow,
                  leveller: levellerWindow, psybass: psybassWindow, subharm: subharmWindow,
                  tube: tubeWindow, upmix: upmixWindow, stats: statsWindow,
                  spectrum: spectrumWindow, graph: graphWindow, siggen: siggenWindow, monitor: monitorWindow,
                  settings: settingsWindow, firmware: firmwareWindow, whatsNew: whatsNewWindow,
                  autoeq: autoeqWindow, autoeqRebuild: autoeqRebuildWindow }[name]
        if (w) { w.visible = true; w.raise(); w.requestActivate() }
    }

    function openSettingsPage(id) {
        settingsWindow.navigate(id)
        openToolWindow("settings")
    }

    // App menu (titlebar menu button)
    AppMenu {
        id: appMenu
        parent: Overlay.overlay
        onCommitRequested: bridge.saveParams()
        onRevertRequested: bridge.loadParams()
        onFactoryResetRequested: factoryResetDialog.open()
        onOpenWindow: root.openToolWindow(name)
        onFileAction: root.fileAction(name)
        onAutoeqUpdateRequested: autoeqUpdate.open()
        // As on macOS, setup leaves only Settings and Help in the menu
        restricted: root.showWizard
    }

    // ── Configuration and filter files ──
    readonly property url documentsFolder: Platform.StandardPaths.writableLocation(Platform.StandardPaths.DocumentsLocation)
    property string pendingFileAction: ""

    function fileAction(name) {
        if (!bridge.connected) return
        pendingFileAction = name
        if (name === "exportConfig") {
            saveDialog.title = "Export Device Configuration"
            saveDialog.nameFilters = ["DSPi configuration (*.dspipreset)", "JSON (*.json)"]
            saveDialog.defaultSuffix = "dspipreset"
            saveDialog.currentFile = documentsFolder + "/DSPi Configuration.dspipreset"
            saveDialog.open()
        } else if (name === "exportFilters") {
            saveDialog.title = "Export Filters"
            saveDialog.nameFilters = ["Text (*.txt)"]
            saveDialog.defaultSuffix = "txt"
            saveDialog.currentFile = documentsFolder + "/DSPi Filters.txt"
            saveDialog.open()
        } else if (name === "importConfig") {
            openDialog.title = "Import Device Configuration"
            openDialog.nameFilters = ["DSPi configuration (*.dspipreset *.json)", "All files (*)"]
            openDialog.open()
        } else if (name === "importFilters") {
            openDialog.title = "Import Filters"
            openDialog.nameFilters = ["Filter files (*.txt)", "All files (*)"]
            openDialog.open()
        }
    }

    function showFileResult(title, lines, ok) {
        fileResult.title = title
        fileResult.icon = ok ? "check" : "warning"
        fileResult.iconTint = ok ? "#32d74b" : "#ff9f0a"
        fileResult.message = lines.join("\n\n")
        fileResult.open()
    }

    Platform.FileDialog {
        id: saveDialog
        fileMode: Platform.FileDialog.SaveFile
        folder: root.documentsFolder
        onAccepted: {
            var r = root.pendingFileAction === "exportConfig" ? configFiles.exportConfiguration(file)
                                                               : configFiles.exportFilters(file)
            if (!r.ok) root.showFileResult("Export Failed", [r.error], false)
            else if (root.pendingFileAction === "exportConfig") root.showFileResult("Configuration Exported", [r.message], true)
        }
    }

    Platform.FileDialog {
        id: openDialog
        fileMode: Platform.FileDialog.OpenFile
        folder: root.documentsFolder
        onAccepted: {
            if (root.pendingFileAction === "importConfig") {
                var info = configFiles.inspectConfiguration(file)
                if (!info.ok) { root.showFileResult("Import Failed", [info.error], false); return }
                var lines = []
                var from = "Saved from " + (info.platform || "a DSPi")
                         + (info.firmware ? ", firmware " + info.firmware : "") + (info.saved ? ", " + info.saved : "") + "."
                lines.push(from)
                if (info.crossPlatform)
                    lines.push("This file comes from a " + info.platform + "; channels this " + bridge.platformName + " doesn't have are left out.")
                lines.push("EQ, crossover, delays, gains, routing and the DSP features are always applied.")
                fileChoice.mode = "config"
                fileChoice.configFile = file
                fileChoice.title = "Import Device Configuration"
                fileChoice.message = lines.join("\n\n")
                fileChoice.checks = [
                    { key: "volumes", text: "Volume levels", detail: "Master and listening volume", checked: false },
                    { key: "hardware", text: "Hardware I/O", detail: "GPIO pins, clocks, ADAT, inputs, output limiters", checked: false }
                ]
                fileChoice.buttons = [{ key: "cancel", text: "Cancel" }, { key: "import", text: "Import", role: "primary" }]
                fileChoice.open()
            } else {
                var f = configFiles.inspectFilters(file)
                if (!f.ok) { root.showFileResult("Import Failed", [f.error], false); return }
                fileChoice.mode = "filters"
                fileChoice.title = "Import Filters"
                fileChoice.message = f.kind === "rew"
                    ? "Found " + f.filters + (f.filters === 1 ? " filter" : " filters")
                      + (f.preamp !== null && f.preamp !== undefined ? " and a " + (f.preamp > 0 ? "+" : "") + Number(f.preamp).toFixed(1) + " dB preamp" : "")
                      + ". Pick the channels to apply them to."
                    : "Pick the channels to load from the file."
                fileChoice.checks = f.channels.map(function (c) {
                    return { key: c.wire, text: c.label, checked: c.checked,
                             detail: c.bands + (c.bands === 1 ? " band" : " bands") }
                })
                fileChoice.buttons = [{ key: "cancel", text: "Cancel" }, { key: "import", text: "Import", role: "primary" }]
                fileChoice.open()
            }
        }
    }

    AppDialog {
        id: fileChoice
        property string mode: ""
        property url configFile
        icon: "input"
        onChosen: {
            if (key !== "import") return
            var r = mode === "config"
                ? configFiles.importConfiguration(configFile, checkedKeys.indexOf("volumes") >= 0, checkedKeys.indexOf("hardware") >= 0)
                : configFiles.importFilters(checkedKeys)
            if (!r.ok) root.showFileResult("Import Failed", [r.error], false)
            else root.showFileResult(r.clean === false ? "Import Finished" : "Import Complete", r.lines, r.clean !== false)
        }
    }

    AppDialog {
        id: fileResult
        buttons: [{ key: "ok", text: "OK", role: "primary" }]
    }

    // ── AutoEQ database ──
    AppDialog {
        id: autoeqUpdate
        icon: "headphones"
        title: "Update AutoEQ Database"
        message: { autoeq.entryCount; return "Current database: " + (autoeq.databaseDate || "Unknown") + "\nEntries: " + autoeq.entryCount + "\n\nChoose an update method:" }
        onAboutToShow: autoeq.load()
        buttons: [{ key: "rebuild", text: "Rebuild from GitHub", role: "primary" }, { key: "import", text: "Import File…" }]
                 .concat(autoeq.hasUserDatabase ? [{ key: "reset", text: "Reset to Built-in" }] : [])
                 .concat([{ key: "cancel", text: "Cancel" }])
        onChosen: {
            if (key === "rebuild") autoeqRebuildConfirm.open()
            else if (key === "import") autoeqImportDialog.open()
            else if (key === "reset") { var r = autoeq.resetToBuiltIn(); root.showFileResult(r.ok ? "AutoEQ Database" : "Reset Failed", [r.message], r.ok) }
        }
    }
    AppDialog {
        id: autoeqRebuildConfirm
        icon: "warning"
        iconTint: "#ff9f0a"
        title: "Rebuild AutoEQ Database"
        message: "You are about to rebuild the AutoEQ database by downloading all profiles from GitHub.\n\nThis requires an internet connection and may take several minutes.\n\nDo you wish to proceed?"
        buttons: [{ key: "cancel", text: "Cancel" }, { key: "rebuild", text: "Rebuild", role: "primary" }]
        onChosen: if (key === "rebuild") { autoeq.startRebuild(); root.openToolWindow("autoeqRebuild") }
    }
    Connections {
        target: autoeq
        function onRebuildFinished(ok, message) {
            autoeqRebuildWindow.close()
            root.showFileResult(ok ? "AutoEQ Database" : "Rebuild Failed", [message], ok)
        }
    }
    Platform.FileDialog {
        id: autoeqImportDialog
        title: "Import AutoEQ Database"
        fileMode: Platform.FileDialog.OpenFile
        folder: root.documentsFolder
        nameFilters: ["AutoEQ database (*.json)", "All files (*)"]
        onAccepted: { var r = autoeq.importFile(file); root.showFileResult(r.ok ? "AutoEQ Database" : "Import Failed", [r.message], r.ok) }
    }

    AppDialog {
        id: factoryResetDialog
        icon: "warning"
        iconTint: "#ff6961"
        title: "Factory Reset?"
        message: "Every parameter on the device returns to its factory default. This cannot be undone."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "reset", text: "Factory Reset", role: "destructive" }
        ]
        onChosen: if (key === "reset") bridge.factoryReset()
    }

    // Shortcuts (Linux has no native menu bar to carry them); like the
    // menu, off while the Getting Started wizard has the window
    Shortcut { sequence: "Ctrl+S"; enabled: !root.showWizard && bridge.connected; onActivated: bridge.saveParams() }
    Shortcut { sequence: "Ctrl+Shift+M"; enabled: !root.showWizard; onActivated: matrixWindow.visible = !matrixWindow.visible }
    Shortcut { sequence: "Ctrl+Shift+L"; enabled: !root.showWizard; onActivated: root.openToolWindow("loudness") }
    Shortcut { sequence: "Ctrl+Shift+X"; enabled: !root.showWizard; onActivated: root.openToolWindow("crossfeed") }
    Shortcut { sequence: "Ctrl+Shift+V"; enabled: !root.showWizard; onActivated: root.openToolWindow("leveller") }
    Shortcut { sequence: "Ctrl+Shift+P"; enabled: !root.showWizard; onActivated: root.openToolWindow("psybass") }
    Shortcut { sequence: "Ctrl+Shift+S"; enabled: !root.showWizard; onActivated: root.openToolWindow("subharm") }
    Shortcut { sequence: "Ctrl+Shift+D"; enabled: !root.showWizard; onActivated: root.openToolWindow("tube") }
    Shortcut { sequence: "Ctrl+Shift+U"; enabled: !root.showWizard; onActivated: root.openToolWindow("upmix") }
    Shortcut { sequence: "Ctrl+Shift+T"; enabled: !root.showWizard; onActivated: root.openToolWindow("stats") }
    Shortcut { sequence: "Ctrl+Shift+A"; enabled: !root.showWizard; onActivated: root.openToolWindow("spectrum") }
    Shortcut { sequence: "Ctrl+Shift+G"; enabled: !root.showWizard; onActivated: root.openToolWindow("siggen") }
    Shortcut { sequence: "Ctrl+I"; enabled: !root.showWizard && bridge.connected && !root.textFocused; onActivated: root.fileAction("importFilters") }
    Shortcut { sequence: "Ctrl+E"; enabled: !root.showWizard && bridge.connected && !root.textFocused; onActivated: root.fileAction("exportFilters") }
    Shortcut { sequence: "Ctrl+Shift+I"; enabled: !root.showWizard; onActivated: root.openToolWindow("monitor") }
    Shortcut { sequence: "Ctrl+,"; onActivated: root.openToolWindow("settings") }
    Shortcut { sequence: "Ctrl+Shift+B"; enabled: !root.showWizard; onActivated: root.openToolWindow("autoeq") }
    StatsWindow { id: statsWindow }
    SpectrumAnalyserWindow { id: spectrumWindow; app: root }
    GraphWindow { id: graphWindow }
    SignalGeneratorWindow { id: siggenWindow }
    InterruptMonitorWindow { id: monitorWindow }
    SettingsWindow { id: settingsWindow }
}
