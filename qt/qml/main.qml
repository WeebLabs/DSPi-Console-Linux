import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Qt.labs.platform 1.1 as Platform
import DSPi 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 950
    height: 813
    minimumWidth: 950
    minimumHeight: 600
    title: "DSPi Console"
    color: isMacOS ? "transparent" : "#303030"

    // Titlebar inset: macOS integrated titlebar needs offset, Linux uses standard decorations
    property int titlebarHeight: isMacOS ? 28 : 0

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

    // Selection state: "overview", "channel:N", "output:N"
    property string selection: "overview"
    property int selectedChannel: -1
    property int selectedOutput: -1

    function selectOverview() {
        selection = "overview"
        selectedChannel = -1
        selectedOutput = -1
    }

    function selectChannel(ch) {
        if (selection === "channel:" + ch) {
            selectOverview()
        } else {
            selection = "channel:" + ch
            selectedChannel = ch
            selectedOutput = -1
        }
    }

    function selectOutput(idx) {
        if (selection === "output:" + idx) {
            selectOverview()
        } else {
            selection = "output:" + idx
            selectedOutput = idx
            selectedChannel = -1
        }
    }

    // Native menu bar (Qt.labs.platform — uses macOS native menus with QApplication)
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

    // Main layout: Sidebar + Content
    Row {
        anchors.fill: parent

        // Sidebar
        Sidebar {
            id: sidebar
            width: 260
            height: parent.height
        }

        // Content area
        Rectangle {
            width: parent.width - 260
            height: parent.height
            color: isMacOS ? "transparent" : nativeWindowColor

            Column {
                anchors.fill: parent
                anchors.margins: 0
                anchors.topMargin: root.titlebarHeight
                spacing: 20

                // Graph section
                FilterResponseView {
                    id: filterResponse
                    width: parent.width
                }

                // Dynamic content
                Loader {
                    id: contentLoader
                    width: parent.width
                    height: parent.height - filterResponse.height - root.titlebarHeight - 20

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
            FilterListView {
                anchors.top: root.selectedOutput >= 0 ? outputSettings.bottom : parent.top
                anchors.topMargin: root.selectedOutput >= 0 ? 16 : 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                channelId: root.selectedOutput >= 0 ? root.selectedOutput + 2 : root.selectedChannel
            }
        }
    }

    // Native-style window border highlight (macOS only — Linux uses WM decorations)
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
    StatsWindow { id: statsWindow }
    SettingsWindow { id: settingsWindow }
}
