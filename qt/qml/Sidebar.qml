import QtQuick 2.15
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0
import "components"

// Sidebar, laid out as on the macOS Console: channel list, quick-access
// icons, preset / source / volume, CPU meters.
Rectangle {
    id: sidebarRoot
    color: windowEffects.blurAvailable ? Qt.rgba(0.15, 0.15, 0.15, 0.30) : "#262628"

    Settings {
        id: volumeSettings
        category: "sidebar"
        property bool showMaster: false
    }

    // Right edge separator
    Rectangle {
        width: 1
        height: parent.height
        anchors.right: parent.right
        color: "black"
        z: 1
    }

    component SectionHeader: Text {
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Qt.rgba(1, 1, 1, 0.45)
        leftPadding: 16
        topPadding: 10
        bottomPadding: 4
    }

    component QuickButton: Item {
        id: qb
        property string icon: ""
        property string tip: ""
        property bool lit: false
        property color litColor: "#3a96dd"
        signal clicked()
        signal rightClicked()
        width: 24
        height: 28
        Rectangle {
            anchors.fill: parent
            radius: 5
            color: qbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        }
        Icon {
            anchors.centerIn: parent
            name: qb.icon
            size: 18
            color: qb.lit ? qb.litColor : (qbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.5))
        }
        MouseArea {
            id: qbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse.button === Qt.RightButton ? qb.rightClicked() : qb.clicked()
            ToolTip.visible: containsMouse && qb.tip !== ""
            ToolTip.delay: 600
            ToolTip.text: qb.tip
        }
    }

    component GlobalLabel: Text {
        font.pixelSize: 12
        font.weight: Font.Medium
        color: Qt.rgba(1, 1, 1, 0.6)
    }

    Column {
        anchors.fill: parent

        Item { width: parent.width; height: root.titlebarHeight + 4 }

        // ── Channel list ───────────────────────────────────────────
        Flickable {
            id: channelList
            width: parent.width
            height: parent.height - root.titlebarHeight - 4 - bottomPanel.height
            clip: true
            contentHeight: channelColumn.height + 8
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: channelColumn
                x: 8
                width: parent.width - 16
                spacing: 2

                SectionHeader { text: "INPUTS"; leftPadding: 8 }

                // Inputs carrying audio right now (at least the stereo pair)
                Repeater {
                    model: bridge.connected ? Math.min(bridge.numInputChannels, Math.max(2, bridge.activeInputChannels)) : 0

                    ChannelRow {
                        id: inputRow
                        readonly property int appId: bridge.inputAppId(index)
                        width: channelColumn.width
                        channelIndex: appId
                        channelName: bridge.channelName(appId)
                        channelColor: bridge.channelColor(appId)
                        descriptor: bridge.channelDescriptor(appId)
                        isSelected: root.selection === "channel:" + appId
                        // Both rows of a linked pair highlight together
                        isLinkedHighlight: root.selectedChannel >= 0 && bridge.linkedPartner(root.selectedChannel) === appId

                        onClicked: root.selectChannel(appId)

                        Connections {
                            target: bridge
                            function onStatusChanged() {
                                inputRow.meterLevel = bridge.peakLevel(inputRow.appId)
                                inputRow.isClipping = bridge.isClipping(inputRow.appId)
                            }
                            function onStateChanged() {
                                inputRow.channelName = bridge.channelName(inputRow.appId)
                            }
                        }
                    }
                }

                SectionHeader { text: "OUTPUTS"; leftPadding: 8; topPadding: 14 }

                // Enabled outputs only (outputs are enabled in the Matrix Mixer)
                Repeater {
                    model: bridge.connected ? bridge.numOutputChannels : 0

                    ChannelRow {
                        id: outputRow
                        width: channelColumn.width
                        visible: bridge.outputEnabled(index)
                        height: visible ? 30 : 0
                        channelIndex: index + 2
                        channelName: bridge.channelName(index + 2)
                        channelColor: bridge.channelColor(index + 2)
                        descriptor: bridge.channelDescriptor(index + 2)
                        isMuted: bridge.outputMuted(index)
                        isSelected: root.selection === "output:" + index

                        onClicked: root.selectOutput(index)

                        Connections {
                            target: bridge
                            function onStatusChanged() {
                                outputRow.meterLevel = bridge.peakLevel(index + 2)
                                outputRow.isClipping = bridge.isClipping(index + 2)
                            }
                            function onStateChanged() {
                                outputRow.visible = bridge.outputEnabled(index)
                                outputRow.isMuted = bridge.outputMuted(index)
                                outputRow.channelName = bridge.channelName(index + 2)
                            }
                        }
                    }
                }
            }
        }

        // ── Bottom panel ───────────────────────────────────────────
        Column {
            id: bottomPanel
            width: parent.width

            // Quick-access buttons, spread evenly across the sidebar
            Row {
                id: quickRow
                x: 14
                width: parent.width - 28
                height: 40
                spacing: (width - children.length * 24) / Math.max(1, children.length - 1)

                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "sliders"; tip: "Matrix Mixer"
                    lit: matrixWindow.visible
                    onClicked: matrixWindow.visible = !matrixWindow.visible
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "headphones"; tip: "Headphone Crossfeed (right-click for settings)"
                    lit: bridge.crossfeedEnabled
                    onClicked: bridge.setCrossfeed(!bridge.crossfeedEnabled)
                    onRightClicked: crossfeedWindow.visible = true
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "loudness"; tip: "Loudness Compensation (right-click for settings)"
                    lit: bridge.loudnessEnabled
                    onClicked: bridge.setLoudness(!bridge.loudnessEnabled)
                    onRightClicked: loudnessWindow.visible = true
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "waveform"; tip: "Volume Leveller (right-click for settings)"
                    lit: bridge.levellerEnabled
                    onClicked: bridge.setLevellerEnabled(!bridge.levellerEnabled)
                    onRightClicked: levellerWindow.visible = true
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "bassclef"; tip: "Psychoacoustic Bass (right-click for settings)"
                    lit: bridge.psybassEnabled
                    onClicked: bridge.setPsybassEnabled(!bridge.psybassEnabled)
                    onRightClicked: psybassWindow.visible = true
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "info"; tip: "Stats for Nerds"
                    lit: statsWindow.visible
                    onClicked: statsWindow.visible = !statsWindow.visible
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "gear"; tip: "Settings"
                    lit: settingsWindow.visible
                    onClicked: settingsWindow.visible = !settingsWindow.visible
                }
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "xmark"; tip: "Bypass Master EQ"
                    lit: bridge.bypass
                    litColor: "#ff9f0a"
                    onClicked: bridge.setBypass(!bridge.bypass)
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

            // Preset / Source / Volume
            Column {
                x: 16
                width: parent.width - 32
                topPadding: 12
                bottomPadding: 12
                spacing: 8

                SidebarPicker {
                    width: parent.width
                    label: "Preset"
                    enabled: bridge.connected
                    readonly property var slots: {
                        bridge.presetOccupied; bridge.activePresetSlot
                        var o = []
                        for (var i = 0; i < 10; i++) {
                            var name = bridge.presetName(i)
                            var occupied = bridge.isPresetOccupied(i)
                            o.push({ value: i, prefix: String(i + 1),
                                     text: occupied ? (name === "" ? "Preset " + (i + 1) : name) : "Empty",
                                     enabled: occupied })
                        }
                        return o
                    }
                    options: slots
                    currentValue: bridge.activePresetSlot
                    valueText: bridge.connected && slots[bridge.activePresetSlot] ? slots[bridge.activePresetSlot].text : "—"
                    onChosen: if (value !== bridge.activePresetSlot) bridge.loadPreset(value)
                }

                SidebarPicker {
                    width: parent.width
                    label: "Source"
                    enabled: bridge.connected
                    readonly property var sources: bridge.inputSources.map(function (src) { return { value: src.id, text: src.name } })
                    options: sources
                    currentValue: bridge.inputSource
                    valueText: {
                        if (!bridge.connected) return "—"
                        for (var i = 0; i < sources.length; i++) if (sources[i].value === bridge.inputSource) return sources[i].text
                        return "USB"
                    }
                    onChosen: bridge.setInputSource(value)
                }

                // Volume: the heading picks User or Master volume
                Item {
                    width: parent.width
                    height: 24

                    // Heading doubles as the User / Master selector
                    Item {
                        id: volumeHeading
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: headingRow.width
                        height: headingRow.height
                        Row {
                            id: headingRow
                            spacing: 4
                            GlobalLabel {
                                text: volumeSettings.showMaster ? "Master Volume" : "User Volume"
                                color: volHeadMouse.containsMouse || volumeMenu.visible ? "white" : Qt.rgba(1, 1, 1, 0.6)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Icon {
                                name: "chev-down"
                                size: 12
                                color: volHeadMouse.containsMouse || volumeMenu.visible ? "white" : Qt.rgba(1, 1, 1, 0.5)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: volHeadMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: volumeMenu.toggleAt(volumeHeading)
                        }
                    }
                    ChoiceMenu {
                        id: volumeMenu
                        parent: Overlay.overlay
                        currentValue: volumeSettings.showMaster ? "master" : "user"
                        options: [
                            { value: "user", text: "User Volume", icon: "speaker" },
                            { value: "master", text: "Master Volume", icon: "gauge" }
                        ]
                        onChosen: volumeSettings.showMaster = (value === "master")
                    }
                    ValueField {
                        fieldWidth: 64
                        value: volumeSettings.showMaster ? bridge.masterVolumeDB : bridge.userVolumeDB
                        suffix: "dB"
                        decimals: 1
                        minValue: volumeSettings.showMaster ? -128 : -60
                        maxValue: 0
                        infinityAt: volumeSettings.showMaster ? -128 : -1e9   // master mute sentinel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        onValueEdited: {
                            if (volumeSettings.showMaster) bridge.setMasterVolume(newValue)
                            else bridge.setUserVolume(newValue)
                        }
                    }
                }

                // Volume slider (master volume is red); right-click resets to 0 dB
                Slider {
                    id: volumeSlider
                    width: parent.width
                    height: 20
                    topPadding: 0
                    bottomPadding: 0
                    from: volumeSettings.showMaster ? -128 : -60
                    to: 0
                    stepSize: 0.5
                    enabled: bridge.connected
                    value: volumeSettings.showMaster ? bridge.masterVolumeDB : bridge.userVolumeDB
                    onPressedChanged: {
                        if (pressed) return
                        if (volumeSettings.showMaster) bridge.setMasterVolume(value)
                        else bridge.setUserVolume(value)
                    }
                    function refresh() {
                        if (!pressed) value = volumeSettings.showMaster ? bridge.masterVolumeDB : bridge.userVolumeDB
                    }
                    Connections { target: bridge; function onStateChanged() { volumeSlider.refresh() } }
                    Connections { target: volumeSettings; function onShowMasterChanged() { volumeSlider.refresh() } }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: volumeSettings.showMaster ? bridge.setMasterVolume(0) : bridge.setUserVolume(0)
                    }

                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: (volumeSlider.height - height) / 2
                        width: volumeSlider.availableWidth
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: volumeSettings.showMaster ? "#E04848" : "#3A79DE"
                        }
                    }
                    handle: Rectangle {
                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: (volumeSlider.height - height) / 2
                        width: 18
                        height: 18
                        radius: 9
                        color: "#d8d8d8"
                        border.color: Qt.rgba(0, 0, 0, 0.3)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

            CpuSection {
                width: parent.width
                cpu0: bridge.cpu0
                cpu1: bridge.cpu1
            }
        }
    }
}
