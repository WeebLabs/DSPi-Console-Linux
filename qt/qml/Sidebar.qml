import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "components"

Rectangle {
    id: sidebarRoot
    color: hasBlurBehind ? Qt.rgba(0.15, 0.15, 0.15, 0.30) : "#2a2a2a"

    // Right edge separator (matches native macOS sidebar)
    Rectangle {
        width: 1
        height: parent.height
        anchors.right: parent.right
        color: "black"
        z: 1
    }

    Column {
        anchors.fill: parent

        // Titlebar spacer for integrated window frame
        Item {
            width: parent.width
            height: root.titlebarHeight + 10
        }

        // Scrollable channel list
        Flickable {
            id: channelList
            width: parent.width
            height: parent.height - root.titlebarHeight - 10 - globalSection.height - cpuSection.height - 40
            clip: true
            contentHeight: channelColumn.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: channelColumn
                width: parent.width

                // INPUTS section header
                Rectangle {
                    width: parent.width
                    height: 24
                    color: Qt.rgba(0, 0, 0, 0.02)
                    Text {
                        text: "INPUTS"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.3)
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Master L/R
                Repeater {
                    model: 2
                    ChannelRow {
                        id: inputRow
                        width: channelColumn.width
                        channelIndex: index
                        channelName: bridge.channelName(index)
                        channelColor: bridge.channelColor(index)
                        descriptor: bridge.channelDescriptor(index)
                        meterLevel: bridge.peakLevel(index)
                        isClipping: bridge.isClipping(index)
                        isSelected: root.selection === "channel:" + index

                        onClicked: root.selectChannel(index)

                        Connections {
                            target: bridge
                            function onStatusChanged() {
                                inputRow.meterLevel = bridge.peakLevel(index)
                                inputRow.isClipping = bridge.isClipping(index)
                            }
                        }
                    }
                }

                // Section gap
                Item { width: 1; height: 10 }

                // OUTPUTS section header
                Rectangle {
                    width: parent.width
                    height: 24
                    color: Qt.rgba(0, 0, 0, 0.02)
                    Text {
                        text: "OUTPUTS"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.3)
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Output channels (only enabled ones)
                Repeater {
                    id: outputRepeater
                    model: bridge.numOutputChannels

                    ChannelRow {
                        id: outputRow
                        width: channelColumn.width
                        visible: bridge.outputEnabled(index)
                        channelIndex: index + 2
                        channelName: bridge.channelName(index + 2)
                        channelColor: bridge.channelColor(index + 2)
                        descriptor: bridge.channelDescriptor(index + 2)
                        meterLevel: bridge.peakLevel(index + 2)
                        isClipping: bridge.isClipping(index + 2)
                        isMuted: bridge.outputMuted(index)
                        isSelected: root.selection === "output:" + index

                        onClicked: root.selectOutput(index)

                        Connections {
                            target: bridge
                            function onStatusChanged() {
                                outputRow.meterLevel = bridge.peakLevel(index + 2)
                                outputRow.isClipping = bridge.isClipping(index + 2)
                            }
                        }
                    }
                }
            }
        }

        // Divider
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

        // GLOBAL section
        Rectangle {
            id: globalSection
            width: parent.width
            height: globalContent.height + 32
            color: Qt.rgba(0, 0, 0, 0.02)

            Column {
                id: globalContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "GLOBAL"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.5)
                }

                // Preset picker
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Preset"
                        font.pixelSize: 9
                        color: Qt.rgba(1, 1, 1, 0.5)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 1; height: 1 }

                    BorderlessComboBox {
                        id: presetCombo
                        width: 140
                        model: {
                            var items = []
                            for (var i = 0; i < 10; i++) {
                                var name = bridge.presetName(i)
                                items.push(name === "" ? "Empty" : name)
                            }
                            return items
                        }
                        currentIndex: bridge.activePresetSlot
                        enabled: bridge.connected
                        onActivated: {
                            if (index !== bridge.activePresetSlot) {
                                bridge.loadPreset(index)
                            }
                        }
                    }
                }

                // Preamp label + value
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        id: preampLabel
                        text: "Preamp"
                        font.pixelSize: 9
                        color: Qt.rgba(1, 1, 1, 0.5)
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ValueField {
                        id: preampField
                        fieldWidth: 60
                        value: bridge.preampDB
                        suffix: "dB"
                        decimals: 1
                        minValue: -60
                        maxValue: 10
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        onValueEdited: bridge.setPreamp(newValue)
                    }
                }

                // Preamp slider
                Slider {
                    id: preampSlider
                    width: parent.width
                    height: 20
                    topPadding: 0
                    bottomPadding: 0
                    from: -60
                    to: 10
                    value: bridge.preampDB
                    onMoved: bridge.sendPreampToDevice(value)
                    onPressedChanged: {
                        if (!pressed) bridge.setPreamp(value)
                    }
                    Connections {
                        target: bridge
                        function onStateChanged() {
                            if (!preampSlider.pressed)
                                preampSlider.value = bridge.preampDB
                        }
                    }

                    background: Rectangle {
                        x: preampSlider.leftPadding
                        y: (preampSlider.height - height) / 2
                        width: preampSlider.availableWidth
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Rectangle {
                            width: preampSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 2
                            color: "#3A79DE"
                        }
                    }

                    handle: Rectangle {
                        x: preampSlider.leftPadding + preampSlider.visualPosition * (preampSlider.availableWidth - width)
                        y: (preampSlider.height - height) / 2
                        implicitWidth: 14
                        implicitHeight: 14
                        width: 14
                        height: 14
                        radius: 7
                        color: "white"
                    }
                }

                // Bypass button
                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 5
                    color: bridge.bypass ? Qt.rgba(0.4, 0.12, 0.12, 1.0) : Qt.rgba(1, 1, 1, 0.08)
                    border.color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Bypass Master EQ"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: bridge.bypass ? "white" : Qt.rgba(1, 1, 1, 0.5)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bridge.setBypass(!bridge.bypass)
                    }
                }
            }
        }

        // Divider
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

        // CPU section
        Rectangle {
            width: parent.width
            height: cpuSection.height
            color: Qt.rgba(0, 0, 0, 0.02)

            CpuSection {
                id: cpuSection
                width: parent.width
                cpu0: bridge.cpu0
                cpu1: bridge.cpu1
            }
        }

        // Divider
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

        // Menu button
        Rectangle {
            width: parent.width
            height: 36
            color: menuArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "\u2630"
                    font.pixelSize: 14
                    color: Qt.rgba(1, 1, 1, 0.5)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Menu"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: Qt.rgba(1, 1, 1, 0.5)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: menuArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: appMenu.open()
            }

            Popup {
                id: appMenu
                x: 0
                y: -appMenu.height
                width: 220
                padding: 4

                background: Rectangle {
                    color: isMacOS ? "#353535" : nativeAltBaseColor
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    radius: 8
                }

                Column {
                    width: parent.width
                    spacing: 0

                    // Section: File
                    Text {
                        text: "FILE"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.3)
                        leftPadding: 12
                        topPadding: 8
                        bottomPadding: 4
                    }

                    MenuItem {
                        text: "Commit Parameters"
                        width: parent.width
                        height: 30
                        onTriggered: { bridge.saveParams(); appMenu.close() }
                    }
                    MenuItem {
                        text: "Revert to Saved"
                        width: parent.width
                        height: 30
                        onTriggered: { bridge.loadParams(); appMenu.close() }
                    }
                    MenuItem {
                        text: "Factory Reset"
                        width: parent.width
                        height: 30
                        onTriggered: { bridge.factoryReset(); appMenu.close() }
                    }

                    // Separator
                    Rectangle { width: parent.width - 16; height: 1; color: Qt.rgba(1, 1, 1, 0.1); anchors.horizontalCenter: parent.horizontalCenter }

                    // Section: Tools
                    Text {
                        text: "TOOLS"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.3)
                        leftPadding: 12
                        topPadding: 8
                        bottomPadding: 4
                    }

                    MenuItem {
                        text: "Matrix Mixer"
                        width: parent.width
                        height: 30
                        onTriggered: { matrixWindow.visible = true; appMenu.close() }
                    }
                    MenuItem {
                        text: "Loudness Compensation"
                        width: parent.width
                        height: 30
                        onTriggered: { loudnessWindow.visible = true; appMenu.close() }
                    }
                    MenuItem {
                        text: "Headphone Crossfeed"
                        width: parent.width
                        height: 30
                        onTriggered: { crossfeedWindow.visible = true; appMenu.close() }
                    }
                    MenuItem {
                        text: "Stats"
                        width: parent.width
                        height: 30
                        onTriggered: { statsWindow.visible = true; appMenu.close() }
                    }

                    // Separator
                    Rectangle { width: parent.width - 16; height: 1; color: Qt.rgba(1, 1, 1, 0.1); anchors.horizontalCenter: parent.horizontalCenter }

                    MenuItem {
                        text: "Settings"
                        width: parent.width
                        height: 30
                        onTriggered: { settingsWindow.visible = true; appMenu.close() }
                    }
                }
            }
        }
    }
}
