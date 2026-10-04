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
    }

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
            ChannelSettingsView {
                id: outputSettings
                visible: root.selectedOutput >= 0
                anchors.top: parent.top
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
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                channelId: root.selectedChannel >= 0 ? root.selectedChannel : 0
            }
            FilterListView {
                anchors.top: root.selectedOutput >= 0 ? outputSettings.bottom
                           : root.selectedChannel >= 0 ? inputHeader.bottom : parent.top
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16      // same as the side margins
                channelId: root.selectedOutput >= 0 ? root.selectedOutput + 2 : root.selectedChannel
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

    function openToolWindow(name) {
        var w = { matrix: matrixWindow, loudness: loudnessWindow, crossfeed: crossfeedWindow,
                  leveller: levellerWindow, psybass: psybassWindow, stats: statsWindow,
                  settings: settingsWindow }[name]
        if (w) { w.visible = true; w.raise(); w.requestActivate() }
    }

    // App menu (titlebar menu button)
    AppMenu {
        id: appMenu
        parent: Overlay.overlay
        onCommitRequested: bridge.saveParams()
        onRevertRequested: bridge.loadParams()
        onFactoryResetRequested: factoryResetDialog.open()
        onOpenWindow: root.openToolWindow(name)
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

    // Shortcuts (Linux has no native menu bar to carry them)
    Shortcut { sequence: "Ctrl+S"; enabled: bridge.connected; onActivated: bridge.saveParams() }
    Shortcut { sequence: "Ctrl+Shift+M"; onActivated: matrixWindow.visible = !matrixWindow.visible }
    Shortcut { sequence: "Ctrl+Shift+L"; onActivated: root.openToolWindow("loudness") }
    Shortcut { sequence: "Ctrl+Shift+X"; onActivated: root.openToolWindow("crossfeed") }
    Shortcut { sequence: "Ctrl+Shift+V"; onActivated: root.openToolWindow("leveller") }
    Shortcut { sequence: "Ctrl+Shift+P"; onActivated: root.openToolWindow("psybass") }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: root.openToolWindow("stats") }
    Shortcut { sequence: "Ctrl+,"; onActivated: root.openToolWindow("settings") }
    StatsWindow { id: statsWindow }
    SettingsWindow { id: settingsWindow }
}
