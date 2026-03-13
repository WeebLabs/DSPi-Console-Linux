import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

Window {
    id: crossfeedWindow
    title: "Crossfeed"
    visible: false
    width: 380
    height: 560
    minimumWidth: 380
    minimumHeight: 300
    maximumWidth: 380
    maximumHeight: 560
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMaximizeButtonHint

    readonly property var presets: [
        { name: "Default", desc: "700 Hz / 4.5 dB — Balanced, most popular", freq: 700, feed: 4.5 },
        { name: "Chu Moy", desc: "700 Hz / 6.0 dB — Stronger spatial effect", freq: 700, feed: 6.0 },
        { name: "Jan Meier", desc: "650 Hz / 9.5 dB — Natural speaker-like", freq: 650, feed: 9.5 },
        { name: "Custom", desc: "User-defined parameters", freq: -1, feed: -1 }
    ]

    Flickable {
        anchors.fill: parent
        contentHeight: crossfeedContent.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: crossfeedContent
            width: parent.width
            spacing: 0

            // Header
            Rectangle {
                width: parent.width; height: 60; color: "transparent"
                Row {
                    anchors.fill: parent; anchors.margins: 16; spacing: 12
                    Text {
                        text: "\uD83C\uDFA7" // headphones
                        font.pixelSize: 22; color: "#0078d4"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "Crossfeed"; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
                        Text { text: "BS2B Bauer Stereophonic-to-Binaural"; font.pixelSize: 10; color: Qt.rgba(1,1,1,0.5) }
                    }
                    Item { width: 1; height: 1 }
                    Switch {
                        checked: bridge.crossfeedEnabled
                        anchors.verticalCenter: parent.verticalCenter
                        onToggled: bridge.setCrossfeed(checked)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

            // Graph placeholder
            Item {
                width: parent.width; height: 180
                Column {
                    anchors.fill: parent; anchors.margins: 16; spacing: 8
                    Text { text: "FREQUENCY RESPONSE"; font.pixelSize: 10; font.weight: Font.Bold; color: Qt.rgba(1,1,1,0.5) }
                    Rectangle {
                        width: parent.width; height: 140; radius: 8
                        color: Qt.rgba(0.21, 0.21, 0.21, 0.6)
                        border.color: Qt.rgba(1,1,1,0.1); border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "Crossfeed response visualization"
                            font.pixelSize: 11; color: Qt.rgba(1,1,1,0.3)
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

            // Presets
            Column {
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                topPadding: 12

                Text { text: "PRESETS"; font.pixelSize: 10; font.weight: Font.Bold; color: Qt.rgba(1,1,1,0.5) }

                Repeater {
                    model: presets
                    Rectangle {
                        width: parent.width; height: 44; radius: 6
                        color: bridge.crossfeedPreset === index ? Qt.rgba(1,1,1,0.05) : "transparent"

                        Row {
                            anchors.fill: parent; anchors.margins: 8; spacing: 8

                            Text {
                                text: bridge.crossfeedPreset === index ? "\u25C9" : "\u25CB"
                                font.pixelSize: 14
                                color: bridge.crossfeedPreset === index ? "#0078d4" : Qt.rgba(1,1,1,0.5)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text { text: modelData.name; font.pixelSize: 12; font.weight: Font.Medium; color: "white" }
                                Text { text: modelData.desc; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4) }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: bridge.setCrossfeedPreset(index)
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08); }

            // Custom parameters
            Column {
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                topPadding: 12
                opacity: bridge.crossfeedPreset === 3 ? 1.0 : 0.5

                Text { text: "PARAMETERS"; font.pixelSize: 10; font.weight: Font.Bold; color: Qt.rgba(1,1,1,0.5) }

                // Cutoff Frequency
                Column {
                    width: parent.width; spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "Cutoff Frequency"; font.pixelSize: 12; font.weight: Font.Medium; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 1; height: 1 }
                        ValueField {
                            fieldWidth: 60; value: bridge.crossfeedFreq; suffix: "Hz"; decimals: 0
                            minValue: 500; maxValue: 2000
                            onValueEdited: bridge.setCrossfeedFreq(newValue)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    CustomSlider {
                        width: parent.width; from: 500; to: 2000
                        value: bridge.crossfeedFreq
                        enabled: bridge.crossfeedPreset === 3
                        onMoved: bridge.setCrossfeedFreq(value)
                    }
                    Text {
                        text: "Simulates head shadow lowpass cutoff. Lower = more bass crossfeed."
                        font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4); wrapMode: Text.WordWrap; width: parent.width
                    }
                }

                Item { width: 1; height: 8 }

                // Feed Level
                Column {
                    width: parent.width; spacing: 4
                    Row {
                        width: parent.width
                        Text { text: "Feed Level"; font.pixelSize: 12; font.weight: Font.Medium; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                        Item { width: 1; height: 1 }
                        ValueField {
                            fieldWidth: 60; value: bridge.crossfeedFeed; suffix: "dB"; decimals: 1
                            minValue: 0; maxValue: 15
                            onValueEdited: bridge.setCrossfeedFeed(newValue)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    CustomSlider {
                        width: parent.width; from: 0; to: 15
                        value: bridge.crossfeedFeed
                        enabled: bridge.crossfeedPreset === 3
                        onMoved: bridge.setCrossfeedFeed(value)
                    }
                    Text {
                        text: "Crossfeed attenuation. Higher = more crossfeed."
                        font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4); wrapMode: Text.WordWrap; width: parent.width
                    }
                }

                Item { width: 1; height: 12 }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

            // ITD section
            Rectangle {
                width: parent.width; height: 60; color: "transparent"
                Row {
                    anchors.fill: parent; anchors.margins: 16; spacing: 12
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text { text: "Interaural Time Delay"; font.pixelSize: 12; font.weight: Font.Medium; color: "white" }
                        Text { text: "Simulates ~220 \u00B5s path difference via all-pass filter"; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4) }
                    }
                    Item { width: 1; height: 1 }
                    Switch {
                        checked: bridge.crossfeedITD
                        anchors.verticalCenter: parent.verticalCenter
                        onToggled: bridge.setCrossfeedITD(checked)
                    }
                }
            }
        }
    }
}
