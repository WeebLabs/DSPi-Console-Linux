import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

Window {
    id: siggenWindow
    title: "Test Signals"
    visible: false
    width: 420
    height: 640
    minimumWidth: 420
    minimumHeight: 640
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    // Per-type parameter metadata: labels and defaults (spec §2).
    // Empty label = parameter unused for that type.
    readonly property var typeNames: [
        "Sine", "Square", "White Noise", "Pink Noise",
        "Sweep (Log)", "Sweep (Linear)", "Sweep (Stepped)",
        "Impulse", "Clicks (Alt. Polarity)", "Polarity Pulse",
        "Tone Burst", "Tone Pair (IMD)", "Multitone",
        "Inter-Sample Peaks", "Channel ID"
    ]
    readonly property var typeParams: [
        { labels: ["Frequency (Hz)"],                                     defs: [1000] },
        { labels: ["Frequency (Hz)"],                                     defs: [100] },
        { labels: [],                                                     defs: [] },
        { labels: [],                                                     defs: [] },
        { labels: ["From (Hz)", "To (Hz)"],                               defs: [20, 20000] },
        { labels: ["From (Hz)", "To (Hz)"],                               defs: [20, 20000] },
        { labels: ["From (Hz)", "To (Hz)", "Steps/octave", "Dwell (ms)"], defs: [20, 20000, 3, 250] },
        { labels: ["Period (ms)"],                                        defs: [500] },
        { labels: ["Period (ms)"],                                        defs: [500] },
        { labels: ["Pulse width (ms)", "Period (ms)"],                    defs: [5, 500] },
        { labels: ["Frequency (Hz)", "On cycles", "Off cycles", "Edge cycles"], defs: [1000, 8, 8, 2] },
        { labels: ["f1 (Hz)", "f2 (Hz)", "Ratio A1/A2"],                  defs: [60, 7000, 4] },
        { labels: ["Tone count", "From (Hz)", "To (Hz)"],                 defs: [10, 20, 20000] },
        { labels: ["Pattern (0/1)"],                                      defs: [0] },
        { labels: ["Blip (ms)"],                                          defs: [120] }
    ]
    readonly property bool isSweep: typeCombo.currentIndex >= 4 && typeCombo.currentIndex <= 6
    property var pValues: [1000, 0, 0, 0]
    property bool running: false

    function applyTypeDefaults() {
        var defs = typeParams[typeCombo.currentIndex].defs
        var vals = [0, 0, 0, 0]
        for (var i = 0; i < defs.length; i++) vals[i] = defs[i]
        pValues = vals
        durationField.value = isSweep ? 5000 : 0
    }

    function channelMask() {
        var mask = 0
        for (var i = 0; i < outputRepeater.count; i++) {
            var item = outputRepeater.itemAt(i)
            if (item && item.checked) mask |= (1 << i)
        }
        return mask
    }

    onVisibleChanged: if (visible) statusTimer.restart()

    Timer {
        id: statusTimer
        interval: 500
        repeat: true
        running: siggenWindow.visible && bridge.connected && bridge.siggenSupported()
        onTriggered: {
            var st = bridge.siggenStatus()
            if (!st.ok) { statusText.text = "status unavailable"; return }
            siggenWindow.running = st.state !== 0
            var states = ["idle", "fade in", "running", "gap", "fade out"]
            var line = states[st.state] || ("state " + st.state)
            if (st.state !== 0) {
                line += " · " + (st.elapsedMs / 1000).toFixed(1) + " s"
                if (st.currentFreq > 0) line += " · " + st.currentFreq.toFixed(0) + " Hz"
                if (st.activeChannel !== 255) line += " · walking ch " + (st.activeChannel + 1)
            }
            statusText.text = line
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: parent.width - 32
            x: 16; y: 16
            spacing: 14

            Text {
                text: "Generates measurement signals inside the DSPi output pipeline. No host audio stream is required; masked outputs replace program audio."
                font.pixelSize: 10; color: Qt.rgba(1,1,1,0.5)
                wrapMode: Text.WordWrap; width: parent.width
            }

            // Signal type
            Column {
                width: parent.width; spacing: 6
                Text { text: "Signal"; font.pixelSize: 12; font.weight: Font.Bold; color: "white" }
                BorderlessComboBox {
                    id: typeCombo
                    width: 200
                    model: siggenWindow.typeNames
                    onActivated: siggenWindow.applyTypeDefaults()
                }
            }

            // Per-type parameters
            Column {
                width: parent.width; spacing: 6
                visible: typeParams[typeCombo.currentIndex].labels.length > 0
                Repeater {
                    model: typeParams[typeCombo.currentIndex].labels
                    Row {
                        spacing: 8; height: 26
                        Text {
                            text: modelData
                            font.pixelSize: 11; color: Qt.rgba(1,1,1,0.7)
                            width: 130; anchors.verticalCenter: parent.verticalCenter
                        }
                        ValueField {
                            value: siggenWindow.pValues[index]
                            decimals: 0; minValue: 0; maxValue: 100000
                            anchors.verticalCenter: parent.verticalCenter
                            onValueEdited: {
                                var vals = siggenWindow.pValues.slice()
                                vals[index] = newValue
                                siggenWindow.pValues = vals
                            }
                        }
                    }
                }
            }

            // Level
            Column {
                width: parent.width; spacing: 6
                Row {
                    spacing: 8
                    Text { text: "Level"; font.pixelSize: 12; font.weight: Font.Bold; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    ValueField {
                        id: levelField
                        value: -20; suffix: " dBFS"; decimals: 1
                        minValue: -120; maxValue: 0
                        anchors.verticalCenter: parent.verticalCenter
                        onValueEdited: { value = newValue; levelSlider.value = newValue }
                    }
                }
                CustomSlider {
                    id: levelSlider
                    width: parent.width
                    from: -60; to: 0; value: -20
                    onMoved: levelField.value = value
                }
            }

            // Outputs
            Column {
                width: parent.width; spacing: 6
                Text { text: "Outputs"; font.pixelSize: 12; font.weight: Font.Bold; color: "white" }
                Flow {
                    width: parent.width; spacing: 4
                    Repeater {
                        id: outputRepeater
                        model: bridge.numOutputChannels
                        CheckBox {
                            required property int index
                            property bool valid: (bridge.siggenValidChannelMask() & (1 << index)) !== 0
                            checked: index === 0
                            enabled: valid
                            text: bridge.channelName(index + 2) !== "" ? bridge.channelName(index + 2) : "Out " + (index + 1)
                            font.pixelSize: 10
                        }
                    }
                }
                Text {
                    text: "Only outputs enabled in the matrix mixer emit signal."
                    font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4)
                    wrapMode: Text.WordWrap; width: parent.width
                }
            }

            // Timing (sweeps and finite runs)
            Column {
                width: parent.width; spacing: 6
                Text { text: "Timing"; font.pixelSize: 12; font.weight: Font.Bold; color: "white" }
                Row {
                    spacing: 8; height: 26
                    Text {
                        text: siggenWindow.isSweep ? "Sweep length (ms)" : "Duration (ms, 0 = until stopped)"
                        font.pixelSize: 11; color: Qt.rgba(1,1,1,0.7)
                        width: 180; anchors.verticalCenter: parent.verticalCenter
                    }
                    ValueField {
                        id: durationField
                        value: 0; decimals: 0; minValue: 0; maxValue: 600000
                        anchors.verticalCenter: parent.verticalCenter
                        onValueEdited: value = newValue
                    }
                }
                Row {
                    spacing: 8; height: 26
                    Text {
                        text: "Repeat (0 = infinite)"
                        font.pixelSize: 11; color: Qt.rgba(1,1,1,0.7)
                        width: 180; anchors.verticalCenter: parent.verticalCenter
                    }
                    ValueField {
                        id: repeatField
                        value: 0; decimals: 0; minValue: 0; maxValue: 65535
                        anchors.verticalCenter: parent.verticalCenter
                        onValueEdited: value = newValue
                    }
                }
                Row {
                    spacing: 8; height: 26
                    Text {
                        text: "Gap between cycles (ms)"
                        font.pixelSize: 11; color: Qt.rgba(1,1,1,0.7)
                        width: 180; anchors.verticalCenter: parent.verticalCenter
                    }
                    ValueField {
                        id: gapField
                        value: 0; decimals: 0; minValue: 0; maxValue: 65535
                        anchors.verticalCenter: parent.verticalCenter
                        onValueEdited: value = newValue
                    }
                }
            }

            // Flags
            Column {
                width: parent.width; spacing: 2
                Text { text: "Options"; font.pixelSize: 12; font.weight: Font.Bold; color: "white" }
                CheckBox { id: rawFlag; text: "Raw (bypass crossover + PEQ on generator channels)"; font.pixelSize: 10 }
                CheckBox { id: decorrFlag; text: "Decorrelated noise per channel"; font.pixelSize: 10 }
                CheckBox { id: walkFlag; text: "Walk outputs one at a time"; font.pixelSize: 10 }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

            // Transport
            Row {
                spacing: 12
                Button {
                    text: siggenWindow.running ? "Restart" : "Start"
                    enabled: bridge.connected
                    onClicked: {
                        var flags = (rawFlag.checked ? 1 : 0)
                                  | (decorrFlag.checked ? 2 : 0)
                                  | (walkFlag.checked ? 4 : 0)
                        var ok = bridge.siggenStart(
                            typeCombo.currentIndex, levelField.value,
                            siggenWindow.channelMask(), 0, flags,
                            durationField.value, repeatField.value, gapField.value,
                            siggenWindow.pValues[0], siggenWindow.pValues[1],
                            siggenWindow.pValues[2], siggenWindow.pValues[3])
                        statusText.text = ok ? "started" : "rejected by device"
                    }
                }
                Button {
                    text: "Stop"
                    enabled: bridge.connected
                    onClicked: bridge.siggenStop(false)
                }
                Text {
                    id: statusText
                    text: "idle"
                    font.pixelSize: 11; font.family: root.monoFont
                    color: Qt.rgba(1,1,1,0.6)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                text: "The generator is transient: it never persists to flash and stops on preset load."
                font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4)
                wrapMode: Text.WordWrap; width: parent.width
            }
        }
    }

    Component.onCompleted: applyTypeDefaults()
}
