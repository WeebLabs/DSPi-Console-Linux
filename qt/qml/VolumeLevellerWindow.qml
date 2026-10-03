import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Volume Leveller: upward dynamic range compression.
AppWindow {
    id: win
    title: "Volume Leveller"
    visible: false
    width: 460
    height: 660 + titlebarHeight
    minimumWidth: 400
    minimumHeight: 360 + titlebarHeight

    readonly property int inputCount: Math.min(bridge.numInputChannels, Math.max(2, bridge.activeInputChannels))
    readonly property var speedCaptions: [
        "Slow — Gentle response for music and wide dynamic range content.",
        "Medium — Balanced response for general purpose use.",
        "Fast — Tight response for speech, dialogue, and podcasts."]

    function inputNames() {
        var n = []
        for (var i = 0; i < inputCount; i++) n.push(bridge.channelName(bridge.inputAppId(i)))
        return n
    }

    component SectionLabel: Text {
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: Qt.rgba(1, 1, 1, 0.5)
    }
    component Divider: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    ToolHeader {
        id: header
        width: parent.width
        icon: "waveform"
        title: "Volume Leveller"
        subtitle: "Upward Dynamic Range Compression"
        checked: bridge.levellerEnabled
        onToggled: bridge.setLevellerEnabled(enable)
    }

    Flickable {
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: body.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: body
            x: 28
            y: 20
            width: win.width - 56
            spacing: 18
            enabled: bridge.connected

            // ── Channels (multichannel inputs only) ──
            Column {
                visible: inputCount > 2
                width: parent.width
                spacing: 12

                Item {
                    width: parent.width
                    height: 22
                    SectionLabel { text: "CHANNELS"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        id: presetsLink
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Presets ▾"
                        font.pixelSize: 14
                        color: presetMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.8)
                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: presetMenu.popup(presetsLink, 0, presetsLink.height)
                        }
                        Menu {
                            id: presetMenu
                            MenuItem { text: "All channels (Night mode)"; onTriggered: bridge.setLevellerMasks(0xFF, 0xFF) }
                            MenuItem { text: "Center only (Dialog boost)"; onTriggered: bridge.setLevellerMasks(0x04, 0x04) }
                            MenuItem { text: "Front L / R only"; onTriggered: bridge.setLevellerMasks(0x03, 0x03) }
                        }
                    }
                }

                Row {
                    spacing: 8
                    Text { text: "Detector"; font.pixelSize: 15; font.weight: Font.Medium; color: "white" }
                    Text { text: "sets the shared gain"; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.55); anchors.baseline: parent.children[0].baseline }
                }
                ChannelChips {
                    width: parent.width
                    count: inputCount
                    mask: bridge.levellerDetectorMask
                    names: inputNames()
                    onMaskEdited: bridge.setLevellerMasks(mask, bridge.levellerApplyMask)
                }

                Row {
                    spacing: 8
                    Text { text: "Apply"; font.pixelSize: 15; font.weight: Font.Medium; color: "white" }
                    Text { text: "receives the gain"; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.55); anchors.baseline: parent.children[0].baseline }
                }
                ChannelChips {
                    width: parent.width
                    count: inputCount
                    mask: bridge.levellerApplyMask
                    names: inputNames()
                    onMaskEdited: bridge.setLevellerMasks(bridge.levellerDetectorMask, mask)
                }

                Divider {}
            }

            SectionLabel { text: "PARAMETERS" }

            ParamRow {
                label: "Amount"; unit: "%"; from: 0; to: 100; stepSize: 0.5
                value: bridge.levellerAmount
                caption: "Compression strength. Higher values reduce dynamic range more aggressively."
                onLiveChanged: bridge.setLevellerAmount(v, true)
                onCommitted: bridge.setLevellerAmount(v)
            }
            Divider {}

            // Speed: segmented Slow / Medium / Fast
            Column {
                width: parent.width
                spacing: 8
                Text { text: "Speed"; font.pixelSize: 15; font.weight: Font.Medium; color: "white" }
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 7
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: Qt.rgba(1, 1, 1, 0.1)
                    Row {
                        anchors.fill: parent
                        anchors.margins: 2
                        Repeater {
                            model: ["Slow", "Medium", "Fast"]
                            Rectangle {
                                width: (parent.width) / 3
                                height: parent.height
                                radius: 6
                                color: bridge.levellerSpeed === index ? Qt.rgba(1, 1, 1, 0.22) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 14
                                    color: "white"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bridge.setLevellerSpeed(index)
                                }
                            }
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: speedCaptions[Math.max(0, Math.min(2, bridge.levellerSpeed))]
                    font.pixelSize: 12
                    color: Qt.rgba(1, 1, 1, 0.55)
                }
            }
            Divider {}

            ParamRow {
                label: "Max Gain"; unit: "dB"; from: 0; to: 35; stepSize: 0.5
                value: bridge.levellerMaxGain
                caption: "Maximum boost for quiet passages. Higher values risk amplifying noise."
                onLiveChanged: bridge.setLevellerMaxGain(v, true)
                onCommitted: bridge.setLevellerMaxGain(v)
            }
            Divider {}

            ParamRow {
                label: "Gate Threshold"; unit: "dB"; from: -96; to: 0; stepSize: 1; decimals: 1
                value: bridge.levellerGate
                caption: "Silence gate. Signals below this level are not boosted, preventing noise amplification."
                onLiveChanged: bridge.setLevellerGate(v, true)
                onCommitted: bridge.setLevellerGate(v)
            }
            Divider {}

            Item {
                width: parent.width
                height: 44
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text { text: "Lookahead"; font.pixelSize: 15; font.weight: Font.Medium; color: "white" }
                    Text { text: "Adds 5ms latency. Improves transient handling."; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.55) }
                }
                Switch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: bridge.levellerLookahead
                    onToggled: bridge.setLevellerLookahead(checked)
                }
            }
        }
    }
}
