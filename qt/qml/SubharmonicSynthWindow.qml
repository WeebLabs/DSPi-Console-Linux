import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Subharmonic Synthesizer: a sub an octave below the source's bass, in three
// bands. Layout after the macOS Console.
AppWindow {
    id: win
    fitHeight: header.height + flick.contentHeight
    title: "Subharmonic Synthesizer"
    visible: false
    width: 760
    height: 600 + titlebarHeight
    minimumWidth: 700
    minimumHeight: 380 + titlebarHeight

    // Parameter ids (core SUBHARM_PARAM_*)
    readonly property int pEnabled: 0
    readonly property int pMask: 1
    readonly property int pLow: 2
    readonly property int pHigh: 3
    readonly property int pTop: 4
    readonly property int pBoost: 5
    readonly property int pSelect: 6
    readonly property int pDepth: 7
    readonly property int pHold: 8
    readonly property int pCeiling: 9
    readonly property int pLink: 10

    readonly property var params: bridge.subharmParams
    readonly property bool active: params[pEnabled] > 0
    readonly property int numOut: bridge.numOutputChannels
    readonly property int pdm: numOut - 1
    readonly property int mask: params[pMask]
    readonly property int selectMode: params[pSelect]

    // Headroom cost (re-read after every change) and the live sub meters
    property real headroom: 0
    property var meter: []

    function refreshHeadroom() {
        var h = bridge.fetchSubharmHeadroom()
        headroom = (h === undefined) ? 0 : h
    }
    onParamsChanged: if (visible) refreshHeadroom()
    onVisibleChanged: {
        if (visible) refreshHeadroom()
        // Solo mutes the program: never leave it on behind a closed window
        else if (bridge.subharmSolo) bridge.setSubharmSolo(false)
        if (!visible) meter = []
    }
    Timer {
        interval: 100
        repeat: true
        running: win.visible && bridge.connected && win.active
        onTriggered: win.meter = bridge.fetchSubharmMeter()
        onRunningChanged: if (!running) win.meter = []
    }

    // low, high, boost (top band off), as on macOS
    readonly property var presets: [
        { name: "Subwoofer feed",   detail: "Subtle added weight",      v: [-6, -6, 0] },
        { name: "Club / large PA",  detail: "Lower two bands, full",    v: [0, 0, 3] },
        { name: "Thin recordings",  detail: "Add a missing bottom",     v: [0, -6, 3] },
        { name: "Cinema LFE",       detail: "Lowest octave only",       v: [3, -12, 0] }]

    function applyPreset(p) {
        bridge.setSubharmParam(pLow, p.v[0])
        bridge.setSubharmParam(pHigh, p.v[1])
        bridge.setSubharmParam(pBoost, p.v[2])
        bridge.setSubharmParam(pTop, -30)
    }
    function outputNames() {
        var n = []
        for (var o = 0; o < numOut; o++) n.push(bridge.channelName(o + 2))
        return n
    }

    component Divider: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    ToolHeader {
        id: header
        width: parent.width
        icon: "subwave"
        title: "Subharmonic Synthesizer"
        subtitle: "Generates a subharmonic at half the frequency of the source's bass"
        checked: win.active
        onToggled: bridge.setSubharmParam(win.pEnabled, enable ? 1 : 0)
        accessories: [
            // SOLO latch: the program is muted on the selected outputs
            Rectangle {
                id: solo
                readonly property bool isOn: bridge.subharmSolo
                anchors.verticalCenter: parent.verticalCenter
                width: soloText.implicitWidth + 18
                height: 22
                radius: 6
                enabled: bridge.connected && win.active
                opacity: enabled ? 1 : 0.4
                color: isOn ? "#ff9f0a" : soloMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.1)
                Text {
                    id: soloText
                    anchors.centerIn: parent
                    text: "SOLO"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 0.4
                    color: solo.isOn ? "white" : Qt.rgba(1, 1, 1, 0.7)
                }
                MouseArea {
                    id: soloMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bridge.setSubharmSolo(!solo.isOn)
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: solo.isOn
                        ? "The selected outputs are carrying the synthesized sub only - the program signal is muted on them. Closing this window switches it off."
                        : "Mute the program signal on the selected outputs so the synthesized sub can be heard or measured on its own. Never saved to a preset."
                }
            }
        ]
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: columns.height + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Row {
            id: columns
            x: 16
            y: 16
            spacing: 20
            enabled: bridge.connected
            readonly property real colWidth: (win.width - 32 - 2 * 20 - 1) / 2

            // ── Left: graph, headroom, levels ──
            Column {
                width: columns.colWidth
                spacing: 12

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "BANDS"; anchors.verticalCenter: parent.verticalCenter }
                    MenuLink {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Apply preset"
                        menu: presetMenu
                    }
                }

                // Where each sub comes from and how loud it is (a diagram, not a measurement)
                Rectangle {
                    width: parent.width
                    height: 188
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.2)
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    Canvas {
                        id: graph
                        anchors.fill: parent
                        anchors.margins: 10
                        // Follow the sliders during a drag
                        property real lvLow: lowRow.displayValue
                        property real lvHigh: highRow.displayValue
                        property real lvTop: topRow.displayValue
                        property real boost: boostRow.displayValue
                        property real ceiling: ceilingRow.displayValue
                        property bool shown: win.active
                        onLvLowChanged: requestPaint()
                        onLvHighChanged: requestPaint()
                        onLvTopChanged: requestPaint()
                        onBoostChanged: requestPaint()
                        onCeilingChanged: requestPaint()
                        onShownChanged: requestPaint()
                        onWidthChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var left = 24, w = width - left, h = height - 16
                            var lo = Math.log(16), hi = Math.log(250)
                            var dbTop = 18, dbBottom = -42
                            function xOf(f) { return left + (Math.log(f) - lo) / (hi - lo) * w }
                            function yOf(db) { return (dbTop - Math.max(dbBottom, Math.min(dbTop, db))) / (dbTop - dbBottom) * h }

                            // Grid
                            ctx.lineWidth = 1
                            ctx.strokeStyle = "rgba(255,255,255,0.07)"
                            ctx.fillStyle = "rgba(255,255,255,0.4)"
                            ctx.font = "9px sans-serif"
                            ctx.textAlign = "center"
                            var fm = [20, 50, 100, 200]
                            for (var i = 0; i < fm.length; i++) {
                                var x = xOf(fm[i])
                                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke()
                                ctx.fillText(String(fm[i]), x, h + 12)
                            }
                            ctx.textAlign = "right"
                            var dm = [12, 0, -12, -24, -36]
                            for (i = 0; i < dm.length; i++) {
                                var y = yOf(dm[i])
                                ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(left + w, y); ctx.stroke()
                                ctx.fillText((dm[i] > 0 ? "+" : "") + dm[i], left - 4, y + 3)
                            }

                            if (!shown) {
                                ctx.textAlign = "center"
                                ctx.fillStyle = "rgba(255,255,255,0.35)"
                                ctx.font = "12px sans-serif"
                                ctx.fillText("Disabled", left + w / 2, h / 2)
                                return
                            }

                            // Each band: its source range, the sub block an octave down
                            var bands = [
                                { lvl: lvLow,  src: [48, 72],   sub: [24, 36], col: "10,124,255",  from: 60,  to: 30 },
                                { lvl: lvHigh, src: [72, 112],  sub: [36, 56], col: "255,159,10",  from: 92,  to: 46 },
                                { lvl: lvTop, src: [112, 160], sub: [56, 80], col: "191,90,242",  from: 136, to: 68 }]
                            var anyOn = false
                            for (i = 0; i < bands.length; i++) {
                                var b = bands[i], isOn = b.lvl > -30
                                anyOn = anyOn || isOn
                                ctx.fillStyle = "rgba(255,255,255," + (isOn ? 0.06 : 0.025) + ")"
                                ctx.fillRect(xOf(b.src[0]), 0, xOf(b.src[1]) - xOf(b.src[0]), h)
                                if (!isOn) continue
                                // The divider's own gain: 0 dB comes out 1.4 dB down
                                var yTop = yOf(b.lvl + 20 * Math.log(0.849) / Math.LN10)
                                ctx.fillStyle = "rgba(" + b.col + ",0.45)"
                                ctx.strokeStyle = "rgba(" + b.col + ",0.95)"
                                ctx.fillRect(xOf(b.sub[0]), yTop, xOf(b.sub[1]) - xOf(b.sub[0]), h - yTop)
                                ctx.strokeRect(xOf(b.sub[0]) + 0.5, yTop + 0.5, xOf(b.sub[1]) - xOf(b.sub[0]) - 1, h - yTop - 1)
                                // ÷2 arrow from source to sub
                                var ya = 8 + i * 11
                                ctx.setLineDash([2, 2])
                                ctx.strokeStyle = "rgba(255,255,255,0.4)"
                                ctx.beginPath(); ctx.moveTo(xOf(b.from), ya); ctx.lineTo(xOf(b.to), ya); ctx.stroke()
                                ctx.setLineDash([])
                                ctx.beginPath(); ctx.moveTo(xOf(b.to) + 4, ya - 3); ctx.lineTo(xOf(b.to), ya); ctx.lineTo(xOf(b.to) + 4, ya + 3); ctx.stroke()
                                ctx.textAlign = "center"
                                ctx.fillStyle = "rgba(255,255,255,0.55)"
                                ctx.fillText("÷2", (xOf(b.from) + xOf(b.to)) / 2, ya - 2)
                            }

                            // LF boost: a 70 Hz bell, Q 0.9, on the whole output
                            if (boost > 0) {
                                var A = Math.pow(10, boost / 40), Q = 0.9
                                ctx.strokeStyle = "#32d74b"
                                ctx.lineWidth = 1.5
                                ctx.beginPath()
                                for (var px = 0; px <= w; px += 2) {
                                    var f = Math.exp(lo + px / w * (hi - lo)), r = f / 70, k = 1 - r * r
                                    var num = k * k + Math.pow(A * r / Q, 2), den = k * k + Math.pow(r / (A * Q), 2)
                                    var g = 10 * Math.log(num / den) / Math.LN10
                                    if (px === 0) ctx.moveTo(left + px, yOf(g)); else ctx.lineTo(left + px, yOf(g))
                                }
                                ctx.stroke()
                                ctx.lineWidth = 1
                            }

                            // Sub ceiling (0 dBFS = off)
                            if (ceiling < 0) {
                                var yc = yOf(ceiling)
                                ctx.setLineDash([4, 3])
                                ctx.strokeStyle = "#ff453a"
                                ctx.beginPath(); ctx.moveTo(left, yc); ctx.lineTo(xOf(80), yc); ctx.stroke()
                                ctx.setLineDash([])
                                ctx.textAlign = "left"
                                ctx.fillStyle = "#ff6961"
                                ctx.fillText("ceiling", xOf(80) + 4, yc + 3)
                            }

                            if (!anyOn) {
                                ctx.textAlign = "center"
                                ctx.fillStyle = "rgba(255,255,255,0.35)"
                                ctx.font = "12px sans-serif"
                                ctx.fillText("All bands off", left + w / 2, h / 2)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "HEADROOM COST"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.headroom > 0 ? "+" + win.headroom.toFixed(1) + " dB" : "none"
                        font.pixelSize: 13
                        color: win.headroom > 0 ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.45)
                        MouseArea { id: headroomHover; anchors.fill: parent; hoverEnabled: true }
                        ToolTip.visible: headroomHover.containsMouse
                        ToolTip.delay: 500
                        ToolTip.text: win.headroom > 0
                            ? "This setting can add up to " + win.headroom.toFixed(1) + " dB. Lower the preamp on the inputs feeding the selected outputs by that much, or a loud passage will clip."
                            : "This setting cannot push the signal past full scale."
                    }
                }

                Divider {}
                SectionLabel { text: "LEVELS" }

                ParamRow {
                    id: lowRow
                    label: "24 - 36 Hz"; subtitle: "Derived from 48 - 72 Hz"
                    unit: "dB"; from: -30; to: 12; stepSize: 0.5; offAt: -30; defaultValue: 0
                    leftHint: "Off"; rightHint: "+12 dB"
                    tip: "Level of the sub synthesized from program content between 48 and 72 Hz. At 0 dB it comes out 1.4 dB below the bass that produced it, which is the divider's own gain."
                    value: win.params[win.pLow]
                    onLiveChanged: bridge.setSubharmParam(win.pLow, v, true)
                    onCommitted: bridge.setSubharmParam(win.pLow, v)
                }
                Divider {}
                ParamRow {
                    id: highRow
                    label: "36 - 56 Hz"; subtitle: "Derived from 72 - 112 Hz"
                    unit: "dB"; from: -30; to: 12; stepSize: 0.5; offAt: -30; defaultValue: 0
                    leftHint: "Off"; rightHint: "+12 dB"
                    tip: "Level of the sub synthesized from program content between 72 and 112 Hz. This band has its own divider, so a bass note here and a kick in the band below are tracked independently."
                    value: win.params[win.pHigh]
                    onLiveChanged: bridge.setSubharmParam(win.pHigh, v, true)
                    onCommitted: bridge.setSubharmParam(win.pHigh, v)
                }
                Divider {}
                ParamRow {
                    id: topRow
                    label: "56 - 80 Hz"; subtitle: "Derived from 112 - 160 Hz"
                    unit: "dB"; from: -30; to: 12; stepSize: 0.5; offAt: -30; defaultValue: -30
                    leftHint: "Off"; rightHint: "+12 dB"
                    tip: "Level of the sub synthesized from program content between 112 and 160 Hz. It ships off: this band reaches up into the range where a divided sub starts to compete with the program's own fundamentals. Turn it up for a subwoofer that cannot reach the lowest octave."
                    value: win.params[win.pTop]
                    onLiveChanged: bridge.setSubharmParam(win.pTop, v, true)
                    onCommitted: bridge.setSubharmParam(win.pTop, v)
                }
            }

            Rectangle { width: 1; height: columns.height; color: Qt.rgba(1, 1, 1, 0.08) }

            // ── Right: selectivity, ceiling, boost, outputs ──
            Column {
                width: columns.colWidth
                spacing: 12

                SectionLabel { text: "SELECTIVITY" }
                SegmentedControl {
                    width: parent.width
                    model: ["All material", "Percussive", "Sustained"]
                    currentIndex: win.selectMode
                    tips: [
                        "Every band signal is treated alike. Choose percussive or sustained to weight the synthesized sub toward one kind of bass material; the gate decides per band from time behaviour, so it cannot separate two sources sounding at once in the same band.",
                        "A short sub burst after each attack, so a kick can be extended without extending the bass line under it. The most robust of the three: a held note gets nothing between kicks.",
                        "The sub opens only after a band has been ringing, so bass notes are extended and kicks are not. A kick landing in the same band ducks the held note's sub, which pumps on a four-on-the-floor line - shorten the hold or lower the depth to soften it."]
                    onActivated: bridge.setSubharmParam(win.pSelect, index)
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.5)
                    text: win.selectMode === 1 ? "A short sub burst after each attack - extends kicks, not the bass line."
                        : win.selectMode === 2 ? "The sub opens once a band has been ringing - extends bass notes, not kicks."
                        : "Every band signal is treated alike."
                }
                // Depth and hold do nothing in "All material"
                ParamRow {
                    visible: win.selectMode !== 0
                    label: "Depth"; unit: "%"; from: 0; to: 100; stepSize: 5; decimals: 0; defaultValue: 100
                    tip: "How far the material this mode does not favour is gated down. At 0% the selectivity is inaudible whatever the mode is set to; 100% is full gating."
                    value: win.params[win.pDepth]
                    onLiveChanged: bridge.setSubharmParam(win.pDepth, v, true)
                    onCommitted: bridge.setSubharmParam(win.pDepth, v)
                }
                ParamRow {
                    visible: win.selectMode !== 0
                    label: "Hold"; unit: "ms"; from: 50; to: 400; stepSize: 10; decimals: 0; defaultValue: 150
                    tip: win.selectMode === 1 ? "The length of the sub burst after each attack."
                        : "How long a band must ring before its sub opens. Every note's first hold period has no sub, so staccato bass lines get little."
                    value: win.params[win.pHold]
                    onLiveChanged: bridge.setSubharmParam(win.pHold, v, true)
                    onCommitted: bridge.setSubharmParam(win.pHold, v)
                }

                Divider {}
                SectionLabel { text: "SUB CEILING" }
                ParamRow {
                    id: ceilingRow
                    label: "Threshold"; unit: "dB"; from: -40; to: 0; stepSize: 1; decimals: 0; offAt: 0; defaultValue: 0
                    leftHint: "-40 dBFS"; rightHint: "Off"
                    tip: "A soft limit on the synthesized sub just before it is mixed back in, capping how far it can push a driver without touching the program signal. It is an absolute level, so a ceiling at full scale limits nothing and means the stage is off. With it on, the headroom cost is only the ceiling's worth. A loud onset overshoots it by a few dB for the first few milliseconds while the limiter's 3 ms attack catches up."
                    value: win.params[win.pCeiling]
                    onLiveChanged: bridge.setSubharmParam(win.pCeiling, v, true)
                    onCommitted: bridge.setSubharmParam(win.pCeiling, v)
                }

                Divider {}
                SectionLabel { text: "LF BOOST" }
                ParamRow {
                    id: boostRow
                    label: "70 Hz bell"; unit: "dB"; from: 0; to: 6; stepSize: 0.5; offAt: 0; defaultValue: 0
                    leftHint: "Off"; rightHint: "+6 dB"
                    tip: "A gentle bell at 70 Hz, Q 0.9, applied to the whole output after the subs are summed. It fills the gap between the synthesized sub and the program's own mid-bass. Meant to stay gentle, as on the dbx."
                    value: win.params[win.pBoost]
                    onLiveChanged: bridge.setSubharmParam(win.pBoost, v, true)
                    onCommitted: bridge.setSubharmParam(win.pBoost, v)
                }

                Divider {}
                Item {
                    width: parent.width
                    height: 20
                    SectionLabel {
                        text: "OUTPUTS"
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { id: outputsHover; anchors.fill: parent; hoverEnabled: true }
                        ToolTip.visible: outputsHover.containsMouse
                        ToolTip.delay: 500
                        ToolTip.text: "Select the outputs that can actually play 24 to 80 Hz. Subharm runs before the crossover, so a satellite with a highpass loses the sub again - mask it off and save the CPU instead."
                    }
                    MenuLink {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Presets"
                        menu: outputPresetMenu
                    }
                }

                Column {
                    width: parent.width
                    spacing: 4
                    ChannelChips {
                        id: chips
                        width: parent.width
                        count: win.numOut
                        mask: win.mask
                        names: win.outputNames()
                        onMaskEdited: bridge.setSubharmParam(win.pMask, mask)
                    }
                    // The synthesized sub on each output
                    Row {
                        spacing: chips.spacing
                        Repeater {
                            model: win.numOut
                            Rectangle {
                                width: Math.max(28, (chips.width - (win.numOut - 1) * chips.spacing) / win.numOut)
                                height: 3
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.08)
                                Rectangle {
                                    readonly property bool isOn: (win.mask >> index) & 1
                                    height: parent.height
                                    radius: 1.5
                                    width: parent.width * (isOn && win.meter.length > index ? Math.min(1, win.meter[index]) : 0)
                                    color: "#0a7cff"
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 34
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: "Link output pairs"; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.9) }
                        Text { text: "One sub per pair, from its mono sum."; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
                    }
                    ToggleSwitch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: win.params[win.pLink] > 0
                        onToggled: bridge.setSubharmParam(win.pLink, checked ? 1 : 0)
                    }
                    MouseArea {
                        id: linkHover
                        anchors.fill: parent
                        anchors.rightMargin: 50
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                    ToolTip.visible: linkHover.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: "Synthesize one sub per output pair from its mono sum and feed it to both channels, as the dbx does. Bass is near-mono in most material, and two independent dividers can land on opposite polarities, which cancels a centred note's sub between the speakers."
                }
            }
        }
    }

    ActionMenu {
        id: presetMenu
        parent: Overlay.overlay
        items: win.presets.map(function(p, i) { return { key: String(i), text: p.name, shortcut: p.detail } })
        onTriggered: win.applyPreset(win.presets[Number(key)])
    }

    ActionMenu {
        id: outputPresetMenu
        parent: Overlay.overlay
        items: [
            { key: "sub", text: "Sub only (Recommended)" },
            { key: "all", text: "All Outputs" },
            { key: "none", text: "None" }
        ]
        onTriggered: {
            if (key === "sub") bridge.setSubharmParam(win.pMask, 1 << win.pdm)
            else if (key === "all") bridge.setSubharmParam(win.pMask, (1 << win.numOut) - 1)
            else if (key === "none") bridge.setSubharmParam(win.pMask, 0)
        }
    }
}
