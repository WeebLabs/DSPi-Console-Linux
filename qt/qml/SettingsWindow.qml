import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import QtQuick.Layouts 1.15
import "components"

Window {
    id: settingsWindow
    title: "Settings"
    visible: false
    width: 450
    height: 500
    minimumWidth: 450
    minimumHeight: 400
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    // Inline component for toggle settings
    component SettingsToggle: Row {
        property string label: ""
        property alias checked: toggleSwitch.checked
        signal toggled()
        width: parent.width
        spacing: 8
        Text {
            text: label
            font.pixelSize: 12
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: 1; height: 1 }
        Switch {
            id: toggleSwitch
            onToggled: parent.toggled()
        }
    }

    TabBar {
        id: tabBar
        width: parent.width
        z: 1

        TabButton { text: "General" }
        TabButton { text: "Appearance" }
        TabButton { text: "Graphing" }
        TabButton { text: "Hardware" }
        TabButton { text: "Advanced" }
    }

    StackLayout {
        anchors.top: tabBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        currentIndex: tabBar.currentIndex

        // General tab
        Flickable {
            contentHeight: generalCol.height
            clip: true
            Column {
                id: generalCol
                width: parent.width
                spacing: 16

                Text {
                    text: "DSPi Console"
                    font.pixelSize: 32
                    color: "white"
                }

                // Startup Preset section
                Column {
                    width: parent.width; spacing: 8
                    Text { text: "Startup Preset"; font.pixelSize: 12; font.weight: Font.Bold; color: Qt.rgba(1,1,1,0.7) }

                    Row {
                        spacing: 12
                        RadioButton {
                            text: "Specified Default"
                            checked: bridge.presetStartupMode === 0
                            onClicked: bridge.setPresetStartup(0, bridge.presetDefaultSlot)
                        }
                        RadioButton {
                            text: "Last Used"
                            checked: bridge.presetStartupMode === 1
                            onClicked: bridge.setPresetStartup(1, bridge.presetDefaultSlot)
                        }
                    }

                    Row {
                        spacing: 8
                        visible: bridge.presetStartupMode === 0
                        Text { text: "Default Slot:"; font.pixelSize: 11; color: Qt.rgba(1,1,1,0.7); anchors.verticalCenter: parent.verticalCenter }
                        BorderlessComboBox {
                            width: 120
                            model: {
                                var items = []
                                for (var i = 0; i < 10; i++) {
                                    var name = bridge.presetName(i)
                                    items.push((i+1) + ": " + (name === "" ? "Empty" : name))
                                }
                                return items
                            }
                            currentIndex: bridge.presetDefaultSlot
                            onActivated: bridge.setPresetStartup(0, index)
                        }
                    }
                }
            }
        }

        // Appearance tab
        Column {
            width: parent.width; spacing: 16

            Row {
                width: parent.width; spacing: 8
                Text { text: "Graph Line Glow"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                Item { width: 1; height: 1 }
                Switch {
                    checked: root.graphShowGlow
                    onToggled: root.graphShowGlow = checked
                }
            }
            Text {
                text: "Adds a soft glow effect behind frequency response curves."
                font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4); wrapMode: Text.WordWrap; width: parent.width
            }
        }

        // Graphing tab
        Flickable {
            contentHeight: graphCol.height
            clip: true
            Column {
                id: graphCol
                width: parent.width; spacing: 12

                // Line Width
                Column {
                    width: parent.width; spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "Line Width"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 1; height: 1 }
                        Text { text: root.graphLineWidth.toFixed(1) + " pt"; font.pixelSize: 11; font.family: "Menlo"; color: Qt.rgba(1,1,1,0.7); anchors.verticalCenter: parent.verticalCenter }
                    }
                    CustomSlider { width: parent.width; from: 1.0; to: 4.0; stepSize: 0.5; value: root.graphLineWidth; onMoved: root.graphLineWidth = value }
                }

                // Grid toggles
                SettingsToggle { label: "Frequency Grid"; checked: root.graphShowFreqGrid; onToggled: root.graphShowFreqGrid = checked }
                SettingsToggle { label: "Frequency Labels"; checked: root.graphShowFreqLabels; onToggled: root.graphShowFreqLabels = checked }
                SettingsToggle { label: "dB Grid"; checked: root.graphShowDbGrid; onToggled: root.graphShowDbGrid = checked }
                SettingsToggle { label: "dB Labels"; checked: root.graphShowDbLabels; onToggled: root.graphShowDbLabels = checked }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

                // Vertical Range
                Column {
                    width: parent.width; spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "Vertical Range"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 1; height: 1 }
                        Text { text: Math.round(root.graphDbRange) + " dB"; font.pixelSize: 11; font.family: "Menlo"; color: Qt.rgba(1,1,1,0.7); anchors.verticalCenter: parent.verticalCenter }
                    }
                    CustomSlider { width: parent.width; from: 10; to: 100; value: root.graphDbRange; onMoved: root.graphDbRange = Math.round(value) }
                }

                // Center
                Column {
                    width: parent.width; spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "Center"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 1; height: 1 }
                        Text {
                            text: {
                                var c = Math.round(root.graphDbCenter)
                                var h = root.graphDbRange / 2
                                return c + " dB → +" + (c + h) + " to " + (c - h)
                            }
                            font.pixelSize: 11; font.family: "Menlo"; color: Qt.rgba(1,1,1,0.7); anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    CustomSlider { width: parent.width; from: -40; to: 20; value: root.graphDbCenter; onMoved: root.graphDbCenter = Math.round(value) }
                }

                // Min/Max Frequency
                Row {
                    width: parent.width; spacing: 12
                    Text { text: "Min Frequency"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 1; height: 1 }
                    BorderlessComboBox {
                        width: 80
                        model: ["10 Hz", "15 Hz", "20 Hz", "50 Hz", "100 Hz"]
                        property var freqValues: [10, 15, 20, 50, 100]
                        currentIndex: freqValues.indexOf(root.graphMinFreq)
                        onActivated: root.graphMinFreq = freqValues[index]
                    }
                }
                Row {
                    width: parent.width; spacing: 12
                    Text { text: "Max Frequency"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 1; height: 1 }
                    BorderlessComboBox {
                        width: 100
                        model: ["5000 Hz", "10000 Hz", "20000 Hz"]
                        property var freqValues: [5000, 10000, 20000]
                        currentIndex: freqValues.indexOf(root.graphMaxFreq)
                        onActivated: root.graphMaxFreq = freqValues[index]
                    }
                }
            }
        }

        // Hardware tab
        Flickable {
            contentHeight: hwCol.height
            clip: true
            Column {
                id: hwCol
                width: parent.width; spacing: 12

                Text { text: "Pin Configuration"; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }

                Repeater {
                    model: {
                        var pins = []
                        var numPhys = bridge.platformName === "RP2040" ? 3 : 5
                        for (var i = 0; i < numPhys; i++) {
                            var name = i < numPhys - 1 ? "SPDIF " + (i + 1) : "PDM"
                            pins.push({ index: i, name: name })
                        }
                        return pins
                    }

                    Row {
                        width: parent.width; spacing: 8; height: 30

                        Text {
                            text: modelData.name
                            font.pixelSize: 12; font.weight: Font.Medium
                            color: "white"; width: 130
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Pin " + bridge.outputPin(modelData.index)
                            font.pixelSize: 12; font.family: "Menlo"
                            color: Qt.rgba(1,1,1,0.7)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

                Row {
                    width: parent.width; spacing: 8
                    Text { text: "Include Pin Config in Presets"; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    Item { width: 1; height: 1 }
                    Switch {
                        checked: bridge.presetIncludePins
                        onToggled: bridge.setPresetIncludePins(checked)
                    }
                }
            }
        }

        // Advanced tab
        Column {
            width: parent.width; spacing: 16

            Text { text: "Advanced"; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
            Text {
                text: "No advanced settings available at this time."
                font.pixelSize: 11; color: Qt.rgba(1,1,1,0.4)
            }
        }
    }
}
