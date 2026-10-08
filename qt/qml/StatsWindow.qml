import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import DSPi 1.0
import "components"

// System Statistics, after the macOS Console: device and system figures,
// audio output and PDM over/underrun counters, S/PDIF DMA starvation, live
// buffer fill levels with a 15 s trace, and (when they apply) the S/PDIF
// input, LG Sound Sync, ADAT output and I2S slave clock. Polled only while
// the window is open: counters every 2 s, buffers every 60 ms.
AppWindow {
    id: win
    title: "System Statistics"
    visible: false
    width: 960
    height: 660 + titlebarHeight
    minimumWidth: 900
    minimumHeight: 480 + titlebarHeight

    readonly property bool shown: visible && visibility !== Window.Minimized
    onShownChanged: stats.watching = shown

    readonly property string dash: "-"
    readonly property var info: stats.info
    readonly property var buf: stats.buffers
    readonly property bool live: bridge.connected && info.clockMHz !== undefined
    readonly property real columnWidth: (width - 2) / 3
    readonly property var outputTypes: bridge.hardware.outputTypes || []

    // A clock for the "time since" rows, only while they show something
    property real now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: win.shown && (win.info.lastEventMs || 0) > 0
        onTriggered: win.now = Date.now()
    }
    function span(ms) {
        if (ms <= 0) return dash
        var s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
        function two(n) { return (n < 10 ? "0" : "") + n }
        return h > 0 ? h + "h " + two(m) + "m " + two(r) + "s" : m + "m " + two(r) + "s"
    }
    function num(v) { return v === undefined || v === null ? dash : String(v) }

    // Colours: macOS dark system colours
    readonly property color green: isMacOS ? MacColors.green : "#32d74b"
    readonly property color yellow: isMacOS ? MacColors.yellow : "#ffd60a"
    readonly property color orange: isMacOS ? MacColors.orange : "#ff9f0a"
    readonly property color red: isMacOS ? MacColors.red : "#ff453a"
    readonly property color grey: isMacOS ? MacColors.gray : "#8e8e93"

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
        topPadding: 4
        bottomPadding: 2
    }
    component Divider: Rectangle { width: parent ? parent.width : 0; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }

    // Title left, value right
    component InfoRow: Item {
        property string title: ""
        property string value: ""
        property color valueColor: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9)
        width: parent ? parent.width : 0
        height: 22
        // macOS: the starvation section's per-output and timer rows have secondary titles
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.title; font.pixelSize: 11; font.weight: Font.Medium; color: isMacOS ? (/^(Out \d|Time )/.test(parent.title) ? MacColors.secondaryLabel : MacColors.label) : Qt.rgba(1, 1, 1, 0.75) }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            font.pixelSize: 12
            font.weight: Font.Bold
            color: isMacOS ? (/^Time /.test(parent.title) ? MacColors.secondaryLabel : parent.valueColor) : parent.valueColor
        }
    }
    // Title left, a state dot and its name right
    component StateRow: Item {
        property string title: ""
        property string text: ""
        property color dot: win.grey
        width: parent ? parent.width : 0
        height: 22
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.title; font.pixelSize: 11; font.weight: Font.Medium; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.75) }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle { width: 6; height: 6; radius: 3; color: parent.parent.dot; anchors.verticalCenter: parent.verticalCenter }
            Text { text: parent.parent.text; font.pixelSize: 11; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.6) }
        }
    }
    // Over / underrun counters: orange overruns, red underruns when non-zero
    component CounterRow: Item {
        property string title: ""
        property string subtitle: ""
        property var over
        property var under
        property bool hasUnder: true
        width: parent ? parent.width : 0
        height: Math.max(34, counterTitle.height + 8)
        Column {
            id: counterTitle
            anchors.verticalCenter: parent.verticalCenter
            Text { text: parent.parent.title; font.pixelSize: 11; font.weight: Font.Medium; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.85) }
            Text { text: parent.parent.subtitle; font.pixelSize: 10; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45) }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Column {
                Text {
                    anchors.right: parent.right
                    text: win.num(parent.parent.parent.over)
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: isMacOS ? ((parent.parent.parent.over || 0) > 0 ? win.orange : MacColors.label) : (parent.parent.parent.over || 0) > 0 ? win.orange : Qt.rgba(1, 1, 1, 0.9)
                }
                Text { anchors.right: parent.right; text: "over"; font.pixelSize: 9; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45) }
            }
            Column {
                visible: parent.parent.hasUnder
                Text {
                    anchors.right: parent.right
                    text: win.num(parent.parent.parent.under)
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: isMacOS ? ((parent.parent.parent.under || 0) > 0 ? win.red : MacColors.label) : (parent.parent.parent.under || 0) > 0 ? win.red : Qt.rgba(1, 1, 1, 0.9)
                }
                Text { anchors.right: parent.right; text: "under"; font.pixelSize: 9; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45) }
            }
        }
    }
    // A buffer's fill now, its watermarks, and the last 15 s
    component BufferRow: Rectangle {
        id: br
        property string title: ""
        property color tint: "white"
        property bool hollow: false
        property int series: 0
        property var levels: ({})        // {fill, min, max}
        property int kind: 0             // 0 S/PDIF, 1 PDM DMA, 2 PDM ring
        readonly property int fill: levels.fill !== undefined ? levels.fill : 0
        readonly property color fillColor: kind === 0 ? (fill === 0 || fill === 100 ? win.red : fill < 25 || fill > 75 ? win.yellow : win.green)
                                         : kind === 1 ? (fill > 50 ? win.red : fill < 5 || fill > 30 ? win.yellow : win.green)
                                         : (fill > 50 ? win.red : fill > 20 ? win.yellow : win.green)
        width: parent ? parent.width : 0
        height: 48
        radius: 5
        color: isMacOS ? MacColors.opacity(MacColors.secondaryLabel, 0.07) : Qt.rgba(1, 1, 1, 0.05)
        Row {
            x: 8
            y: 3
            spacing: 6
            height: 14
            Rectangle {
                width: 7; height: 7; radius: 3.5
                anchors.verticalCenter: parent.verticalCenter
                color: br.hollow ? "transparent" : br.tint
                border.width: 1.5
                border.color: br.tint
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: br.title; font.pixelSize: 10; font.weight: Font.Medium; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.85) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: br.levels.min !== undefined && br.levels.max >= br.levels.min ? br.levels.min + "–" + br.levels.max + "%" : ""
                font.pixelSize: 9
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45)
                MouseArea { id: wmHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                ToolTip.visible: wmHover.containsMouse
                ToolTip.delay: 600
                ToolTip.text: "Lowest and highest fill since the watermarks were reset"
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 2
            width: 36
            horizontalAlignment: Text.AlignRight
            text: br.fill + "%"
            font.pixelSize: 11
            font.weight: Font.Bold
            color: br.fillColor
        }
        BufferTraceItem {
            x: 4
            y: 17
            width: parent.width - 8
            height: parent.height - 19
            controller: stats
            series: br.series
            color: br.tint
            dashed: br.hollow
            bandMin: br.levels.min !== undefined ? br.levels.min : 100
            bandMax: br.levels.max !== undefined ? br.levels.max : 0
        }
        MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton; z: -1 }
        ToolTip.visible: rowHover.containsMouse
        ToolTip.delay: 800
        ToolTip.text: br.title + " fill level over the last 15 seconds"
    }

    Flickable {
        anchors.fill: parent
        anchors.bottomMargin: footer.height
        contentHeight: columns.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Row {
            id: columns
            y: 16

            // ── Column 1: device, system, output counters ──
            Column {
                width: win.columnWidth
                leftPadding: 16
                rightPadding: 16
                spacing: 4
                readonly property real inner: width - 32

                SectionLabel { text: "DEVICE INFORMATION" }
                Column {
                    width: parent.inner
                    InfoRow { title: "Platform"; value: bridge.connected ? bridge.platformName : win.dash }
                    InfoRow { title: "Firmware"; value: bridge.connected ? bridge.firmwareVersion : win.dash }
                    InfoRow { title: "Serial"; value: bridge.selectedSerial || win.dash }
                    InfoRow { title: "Reconnects"; value: String(stats.reconnects) }
                }
                Item { width: 1; height: 8 }
                SectionLabel { text: "SYSTEM INFORMATION" }
                Column {
                    width: parent.inner
                    InfoRow { title: "Clock Frequency"; value: win.live ? win.info.clockMHz.toFixed(1) + " MHz" : win.dash }
                    InfoRow { title: "Core Voltage"; value: win.live && win.info.coreVolts !== undefined ? win.info.coreVolts.toFixed(2) + " V" : win.dash }
                    InfoRow { title: "Sample Rate"; value: win.live && win.info.sampleKHz !== undefined ? win.info.sampleKHz.toFixed(1) + " kHz" : win.dash }
                    InfoRow { title: "Temperature"; value: win.live && win.info.tempC !== undefined ? win.info.tempC.toFixed(1) + " °C" : win.dash }
                    InfoRow { title: "Core 0 Load"; value: bridge.connected ? bridge.cpu0 + " %" : win.dash; valueColor: bridge.cpu0 > 80 ? win.orange : Qt.rgba(1, 1, 1, 0.9) }
                    InfoRow { title: "Core 1 Load"; value: bridge.connected ? bridge.cpu1 + " %" : win.dash; valueColor: bridge.cpu1 > 80 ? win.orange : Qt.rgba(1, 1, 1, 0.9) }
                    InfoRow { title: "Core 1 Mode"; value: !bridge.connected ? win.dash : ["Idle", "PDM", "EQ Worker"][bridge.core1Mode] || "Unknown" }
                }
                Item { width: 1; height: 8 }
                SectionLabel { text: "AUDIO OUTPUT" }
                Column {
                    width: parent.inner
                    CounterRow { title: "USB Ring"; subtitle: "ISR → Main Loop"; over: win.info.usbRingOver; hasUnder: false }
                    CounterRow { title: "Buffer Pool"; subtitle: "USB → DMA"; over: win.info.spdifOver; under: win.info.spdifUnder }
                }
                Item { width: 1; height: 8 }
                SectionLabel { text: "PDM (SUBWOOFER)" }
                Column {
                    width: parent.inner
                    CounterRow { title: "Ring Buffer"; subtitle: "Core 0 → Core 1"; over: win.info.pdmRingOver; under: win.info.pdmRingUnder }
                    CounterRow { title: "DMA Buffer"; subtitle: "Core 1 → PIO"; over: win.info.pdmDmaOver; under: win.info.pdmDmaUnder }
                }
            }

            Rectangle { width: 1; height: columns.height; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }

            // ── Column 2: starvation and buffer fill ──
            Column {
                width: win.columnWidth
                leftPadding: 16
                rightPadding: 16
                spacing: 4
                readonly property real inner: width - 32

                SectionLabel { text: "SPDIF DMA STARVATION" }
                Column {
                    width: parent.inner
                    Item {
                        width: parent.width
                        height: 26
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Total"; font.pixelSize: 11; font.weight: Font.Medium; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.75) }
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Rectangle {
                                visible: (win.info.starvationDelta || 0) > 0
                                width: deltaText.width + 10
                                height: 16
                                radius: 3
                                color: isMacOS ? MacColors.opacity(MacColors.red, 0.15) : Qt.rgba(1, 0.27, 0.23, 0.15)
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: deltaText; anchors.centerIn: parent; text: "+" + win.info.starvationDelta; font.pixelSize: 10; font.weight: Font.Bold; color: win.red }
                            }
                            Text {
                                text: win.num(win.info.starvationTotal)
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: isMacOS ? ((win.info.starvationTotal || 0) > 0 ? win.red : MacColors.label) : (win.info.starvationTotal || 0) > 0 ? win.red : Qt.rgba(1, 1, 1, 0.9)
                            }
                        }
                    }
                    Repeater {
                        model: Math.max(win.buf.numSpdif || 0, 2)
                        InfoRow {
                            readonly property var per: win.info.starvationPer || []
                            title: "Out " + (index * 2 + 1) + "/" + (index * 2 + 2)
                            value: per.length > index ? String(per[index]) : win.dash
                            valueColor: isMacOS ? ((per[index] || 0) > 0 ? win.red : MacColors.label) : (per[index] || 0) > 0 ? win.red : Qt.rgba(1, 1, 1, 0.9)
                        }
                    }
                    InfoRow { title: "Time since last event"; value: (win.info.lastEventMs || 0) > 0 ? win.span(win.now - win.info.lastEventMs) : win.dash }
                    InfoRow {
                        title: "Time between last two"
                        value: (win.info.previousEventMs || 0) > 0 ? win.span(win.info.lastEventMs - win.info.previousEventMs) : win.dash
                    }
                }
                Item { width: 1; height: 8 }
                RowLayout {
                    width: parent.inner
                    SectionLabel { text: "BUFFER FILL LEVELS" }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: resetText.width + 16
                        Layout.preferredHeight: 20
                        radius: 6
                        color: isMacOS ? (resetMouse.pressed ? MacColors.opacity(MacColors.control, 1.6) : MacColors.control) : resetMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : resetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.18)
                        Text { id: resetText; anchors.centerIn: parent; text: "Reset Watermarks"; font.pixelSize: 10; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.85) }
                        MouseArea { id: resetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: stats.resetWatermarks() }
                    }
                }
                Row {
                    spacing: 14
                    Repeater {
                        model: [{ t: "Audio Streaming", on: win.buf.streaming === true }, { t: "PDM Active", on: win.buf.pdmActive === true }]
                        Row {
                            spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: modelData.on ? win.green : win.grey; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.t; font.pixelSize: 10; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55) }
                        }
                    }
                }
                Column {
                    width: parent.inner
                    spacing: 6
                    topPadding: 4
                    // Keyed on the count: the levels change every poll, the rows don't
                    Repeater {
                        model: win.buf.numSpdif || 0
                        BufferRow {
                            title: "Out " + (index * 2 + 1) + "/" + (index * 2 + 2) + " (" + (win.outputTypes[index] === 1 ? "I2S" : "S/PDIF") + ")"
                            tint: bridge.channelColor(2 + index * 2)
                            series: index
                            levels: (win.buf.spdif || [])[index] || ({})
                            kind: 0
                        }
                    }
                    BufferRow {
                        visible: win.buf.pdmActive === true
                        title: "PDM DMA"
                        tint: bridge.channelColor(bridge.numOutputChannels + 1)
                        series: 4
                        levels: win.buf.pdmDma || ({})
                        kind: 1
                    }
                    BufferRow {
                        visible: win.buf.pdmActive === true
                        title: "PDM Ring"
                        tint: bridge.channelColor(bridge.numOutputChannels + 1)
                        hollow: true
                        series: 5
                        levels: win.buf.pdmRing || ({})
                        kind: 2
                    }
                }
            }

            Rectangle { width: 1; height: columns.height; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }

            // ── Column 3: inputs and links, when they apply ──
            Column {
                width: win.columnWidth
                leftPadding: 16
                rightPadding: 16
                spacing: 4
                readonly property real inner: width - 32
                readonly property var rx: win.info.spdifRx
                readonly property var lg: win.info.lg
                readonly property var adat: win.info.adatOut
                readonly property var i2s: win.info.i2sSlave

                Text {
                    visible: !parent.rx && !parent.lg && !parent.adat && !parent.i2s
                    width: parent.inner
                    wrapMode: Text.WordWrap
                    topPadding: 4
                    text: bridge.connected ? "No digital inputs or links to report." : "Connect a DSPi to see its statistics."
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.4)
                }

                // S/PDIF input
                Column {
                    visible: !!parent.rx
                    width: parent.inner
                    spacing: 0
                    readonly property var r: parent.rx || ({})
                    SectionLabel { text: "S/PDIF INPUT" }
                    StateRow {
                        title: "State"
                        text: ["Inactive", "Acquiring", "Locked", "Relocking"][parent.r.state] || "Inactive"
                        dot: [win.grey, win.yellow, win.green, win.orange][parent.r.state] || win.grey
                    }
                    InfoRow { title: "Active Source"; value: parent.r.source || win.dash }
                    InfoRow { title: "Sample Rate"; value: parent.r.locked ? parent.r.rateKHz.toFixed(1) + " kHz" : win.dash }
                    InfoRow { title: "Lock Count"; value: win.num(parent.r.lockCount) }
                    InfoRow { title: "Loss Count"; value: win.num(parent.r.lossCount) }
                    InfoRow { title: "Parity Errors"; value: parent.r.locked ? win.num(parent.r.parityErrors) : win.dash }
                    InfoRow { title: "FIFO Fill"; value: parent.r.locked ? parent.r.fifoPct + "%" : win.dash }
                    InfoRow { title: "RX Pin"; value: parent.r.pin !== undefined ? "GPIO " + parent.r.pin : win.dash }
                    Column {
                        visible: parent.r.locked === true && parent.r.category !== undefined
                        width: parent.width
                        Item { width: 1; height: 6 }
                        SectionLabel { text: "CHANNEL STATUS" }
                        InfoRow { title: "Format"; value: parent.parent.r.consumer ? "Consumer" : "Professional" }
                        InfoRow { title: "Audio"; value: parent.parent.r.pcm ? "PCM" : "Non-PCM" }
                        InfoRow { title: "Category"; value: parent.parent.r.category || win.dash }
                        InfoRow { title: "Word Length"; value: parent.parent.r.wordLength || win.dash }
                        InfoRow { title: "Copy"; value: parent.parent.r.copyPermitted ? "Permitted" : "Prohibited" }
                    }
                    Column {
                        visible: (parent.r.state || 0) !== 0
                        width: parent.width
                        Item { width: 1; height: 6 }
                        SectionLabel { text: "DEBUG" }
                        InfoRow { title: "Library State"; value: ["No Signal", "Waiting Stable", "Stable"][parent.parent.r.libState] || win.dash }
                        InfoRow { title: "Stable Callbacks"; value: win.num(parent.parent.r.stableCallbacks) }
                        InfoRow { title: "Lost Callbacks"; value: win.num(parent.parent.r.lostCallbacks) }
                    }
                    Item { width: 1; height: 8 }
                }

                // LG Sound Sync
                Column {
                    visible: !!parent.lg
                    width: parent.inner
                    readonly property var l: parent.lg || ({})
                    SectionLabel { text: "LG SOUND SYNC" }
                    InfoRow { title: "Enabled"; value: parent.l.enabled ? "Yes" : "No" }
                    StateRow { title: "Present"; text: parent.l.present ? "Yes" : "No"; dot: parent.l.present ? win.green : win.grey }
                    InfoRow { title: "TV Volume"; value: parent.l.volume === undefined || parent.l.volume === 255 ? win.dash : parent.l.volume + " / 100" }
                    InfoRow { title: "TV Mute"; value: parent.l.muted ? "On" : "Off" }
                    Item { width: 1; height: 8 }
                }

                // ADAT bulk output
                Column {
                    visible: !!parent.adat
                    width: parent.inner
                    readonly property var a: parent.adat || ({})
                    SectionLabel { text: "ADAT BULK OUTPUT" }
                    StateRow {
                        title: "State"
                        text: !parent.a.enabled ? "Disabled" : parent.a.active ? "Streaming" : !parent.a.rateOk ? "Suspended (rate above 48 kHz)" : "Enabled"
                        dot: !parent.a.enabled ? win.grey : parent.a.active ? win.green : !parent.a.rateOk ? win.orange : win.yellow
                    }
                    InfoRow { title: "Streaming"; value: parent.a.active ? "Yes" : "No" }
                    InfoRow { title: "Rate Supported"; value: parent.a.rateOk ? "Yes" : "No" }
                    InfoRow { title: "Data Pin"; value: parent.a.pin !== undefined ? "GPIO " + parent.a.pin : win.dash }
                    InfoRow { title: "Resync Count"; value: win.num(parent.a.resyncCount) }
                    InfoRow { title: "Slip Count"; value: win.num(parent.a.slipCount) }
                    Item { width: 1; height: 8 }
                }

                // I2S input as clock slave
                Column {
                    visible: !!parent.i2s
                    width: parent.inner
                    readonly property var s: parent.i2s || ({})
                    SectionLabel { text: "I2S INPUT (SLAVE CLOCK)" }
                    StateRow {
                        title: "State"
                        text: ["Inactive", "Acquiring", "Relocking", "Locked"][parent.s.state] || "Inactive"
                        dot: [win.grey, win.yellow, win.orange, win.green][parent.s.state] || win.grey
                    }
                    InfoRow { title: "Detected Rate"; value: (parent.s.detectedKHz || 0) > 0 ? parent.s.detectedKHz.toFixed(1) + " kHz" : win.dash }
                    InfoRow { title: "Measured Rate"; value: (parent.s.measuredKHz || 0) > 0 ? parent.s.measuredKHz.toFixed(1) + " kHz" : win.dash }
                    InfoRow { title: "Lock Count"; value: win.num(parent.s.lockCount) }
                    InfoRow { title: "Loss Count"; value: win.num(parent.s.lossCount) }
                }
            }
        }
    }

    // Footer: connection state
    Rectangle {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: 30
        color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.03)
        Rectangle { width: parent.width; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.08) }
        Row {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            Rectangle { width: 6; height: 6; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: bridge.connected ? win.green : win.red }
            Text { text: bridge.connected ? "Connected" : "Disconnected"; font.pixelSize: 11; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55) }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Updated every 2 seconds"
            font.pixelSize: 11
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.4)
        }
    }
}
