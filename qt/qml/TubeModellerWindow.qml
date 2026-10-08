import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.0
import "components"

// Tube Modeller: valve-style harmonic colour, supply sag and a tube amplifier's
// output stage. Basic and Advanced views, after the macOS Console.
AppWindow {
    id: win
    fitHeight: header.height + flick.contentHeight
    title: "Tube Modeller"
    visible: false
    width: 840
    height: 600 + titlebarHeight
    minimumWidth: 700
    minimumHeight: 380 + titlebarHeight

    Settings {
        id: prefs
        category: "tubeModeller"
        property bool advanced: false
    }

    // Parameter indices (firmware / core TUBE_PARAM_*)
    readonly property int pEnabled: 0
    readonly property int pMask: 1
    readonly property int pType: 2
    readonly property int pDrive: 3
    readonly property int pBias: 4
    readonly property int pAsym: 5
    readonly property int pHard: 6
    readonly property int pSag: 7
    readonly property int pRect: 8
    readonly property int pXfmr: 9
    readonly property int pDamping: 10
    readonly property int pRes: 11
    readonly property int pMix: 12
    readonly property int pTrim: 13

    readonly property var params: bridge.tubeParams
    readonly property bool active: params[pEnabled] > 0
    readonly property int tubeType: params[pType]
    readonly property int rectifier: params[pRect]
    readonly property bool outputStage: params[pXfmr] > 0
    readonly property int numOut: bridge.numOutputChannels
    readonly property int mask: params[pMask]

    // Types 1..16 (0 = Custom); character rows live in the core
    readonly property var tubeNames: ["Custom", "12AX7 / ECC83", "5751", "12AT7 / ECC81", "12AY7",
        "12AU7 / ECC82", "6SN7", "6SL7", "6DJ8 / ECC88 / 6922", "EF86 / 6267", "6SJ7",
        "EL84 / 6BQ5", "EL34", "6L6 / 5881", "6V6", "KT88 / 6550", "300B / 2A3"]
    readonly property var tubeStyles: ["", "High-gain preamp triode", "Cooler 12AX7",
        "Medium-gain driver, more odd-order", "Tweed front end, gentle", "Clean line stage",
        "Octal hi-fi line stage, sweet", "Octal high-mu, rounder knee", "Clean, hard when pushed",
        "Pentode preamp, symmetric bite", "Octal pentode, softer than EF86", "Push-pull power, chimey",
        "Push-pull power, mid crunch, deep sag", "Push-pull power, tight",
        "Push-pull power, early breakup, heavy sag", "Push-pull hi-fi power, near linear",
        "Single-ended DHT, pure even harmonics"]
    readonly property var groups: [
        { title: "Preamp triodes", types: [1, 2, 3, 4, 5, 6, 7, 8] },
        { title: "Preamp pentodes", types: [9, 10] },
        { title: "Power stages", types: [11, 12, 13, 14, 15, 16] }]
    readonly property var rectifiers: ["Solid state", "GZ34", "5U4", "5Y3"]
    readonly property var rectifierNotes: [
        "No sag: the supply holds up however hard the stage is driven.",
        "Sag depth x0.6, 5 ms attack, 120 ms release.",
        "Sag depth x1.0, 8 ms attack, 200 ms release.",
        "Sag depth x1.3, 10 ms attack, 300 ms release."]

    function shortName(t) { return tubeNames[t].split(" / ")[0] }
    function isPushPull(t) { return t >= 11 && t <= 15 }
    function caption(t) {
        if (t === 0) return "Character set by hand in Advanced."
        var s = tubeStyles[t] + "."
        return isPushPull(t) && !outputStage ? s + " Meant for use with the output stage, in Advanced." : s
    }

    // type, drive, rectifier, damping, resonance (output stage on, mix 100, trim 0)
    readonly property var presets: [
        { name: "Clean default",          v: [1, -12, 1, 2, 95] },
        { name: "Warm hi-fi",             v: [5, -3, 1, 10, 95] },
        { name: "Single-ended sweetness", v: [16, 3, 1, 2, 95] },
        { name: "Guitar-amp style",       v: [1, 15, 2, 2, 100] },
        { name: "Push-pull power",        v: [12, 0, 1, 6, 95] }]
    function applyPreset(p) {
        bridge.setTubeParam(pType, p.v[0])
        bridge.setTubeParam(pDrive, p.v[1])
        bridge.setTubeParam(pRect, p.v[2])
        bridge.setTubeParam(pDamping, p.v[3])
        bridge.setTubeParam(pRes, p.v[4])
        bridge.setTubeParam(pXfmr, 1)
        bridge.setTubeParam(pMix, 100)
        bridge.setTubeParam(pTrim, 0)
    }
    function outputNames() {
        var n = []
        for (var o = 0; o < numOut; o++) n.push(bridge.channelName(o + 2))
        return n
    }

    // Filament glow follows the loudest output the tube runs on (status packets)
    property real bloom: 0
    Connections {
        target: bridge
        enabled: win.visible && win.active && win.mask !== 0 && !prefs.advanced
        function onStatusChanged() {
            var peak = 0
            for (var o = 0; o < win.numOut; o++)
                if ((win.mask >> o) & 1) peak = Math.max(peak, bridge.peakLevel(o + 2))
            win.bloom = Math.sqrt(Math.min(1, peak))
        }
    }

    component Divider: Rectangle { width: parent.width; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.08) }

    // Tube chip in the Basic shelf
    component TubeChip: Rectangle {
        property int type: 0
        readonly property bool isCurrent: win.tubeType === type
        width: (parent.width - 3 * 6) / 4
        height: 26
        radius: 6
        color: isMacOS ? (isCurrent ? MacColors.accent : MacColors.opacity(MacColors.secondaryLabel, 0.12)) : isCurrent ? "#0a7cff" : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        border.color: isMacOS ? (isCurrent ? "transparent" : MacColors.opacity(MacColors.label, 0.08)) : isCurrent ? "transparent" : Qt.rgba(1, 1, 1, 0.12)
        Text {
            anchors.centerIn: parent
            text: win.shortName(parent.type)
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: isMacOS ? (parent.isCurrent ? "white" : MacColors.opacity(MacColors.label, 0.75)) : parent.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.75)
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bridge.setTubeParam(win.pType, parent.type)
            ToolTip.visible: containsMouse
            ToolTip.delay: 500
            ToolTip.text: win.tubeNames[parent.type] + ": " + win.tubeStyles[parent.type]
        }
    }

    // OUTPUTS section (both views)
    component OutputsSection: Column {
        spacing: 12
        Item {
            width: parent.width
            height: 20
            SectionLabel {
                text: "OUTPUTS"
                anchors.verticalCenter: parent.verticalCenter
                MouseArea { id: outHover; anchors.fill: parent; hoverEnabled: true }
                ToolTip.visible: outHover.containsMouse
                ToolTip.delay: 500
                ToolTip.text: "Tube runs before the crossover and the per-output EQ, where a real preamp sits: a sub output saturates the full-band program and then low-passes the result."
            }
            MenuLink {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Presets"
                menu: outputPresetMenu
            }
        }
        ChannelChips {
            width: parent.width
            count: win.numOut
            mask: win.mask
            names: win.outputNames()
            onMaskEdited: bridge.setTubeParam(win.pMask, mask)
        }
    }

    ToolHeader {
        id: header
        width: parent.width
        icon: "tube"
        title: "Tube Modeller"
        subtitle: "Valve-style harmonic colour, supply sag and a tube amplifier's output stage"
        checked: win.active
        onToggled: bridge.setTubeParam(win.pEnabled, enable ? 1 : 0)
        accessories: [
            SegmentedControl {
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                model: ["Basic", "Advanced"]
                currentIndex: prefs.advanced ? 1 : 0
                onActivated: { win.refitAnimated(); prefs.advanced = (index === 1) }
            }
        ]
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: (prefs.advanced ? advanced.height : basic.height) + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        readonly property real colWidth: (win.width - 32 - 2 * 20 - 1) / 2

        // ── Basic: showcase and the tube shelf ──
        Row {
            id: basic
            visible: !prefs.advanced
            x: 16
            y: 16
            spacing: 20
            enabled: bridge.connected

            Rectangle {
                width: flick.colWidth
                height: Math.max(330, basicRight.height)
                radius: 10
                color: isMacOS ? MacColors.opacity(MacColors.controlBackground, 0.6) : Qt.rgba(0, 0, 0, 0.2)
                border.color: isMacOS ? MacColors.opacity(MacColors.gray, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    width: parent.width - 32

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 168
                        height: 280
                        // Warm cast around the tube while the stage is on: a
                        // fixed size about the tube (the card clips it), so
                        // resizing the window leaves it alone. Painted once.
                        Canvas {
                            anchors.centerIn: parent
                            width: 440
                            height: 440
                            opacity: win.active ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: win.active ? 900 : 600; easing.type: Easing.InOutSine } }
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var g = ctx.createRadialGradient(220, 220, 0, 220, 220, 220)
                                g.addColorStop(0, isMacOS ? MacColors.opacity(MacColors.orange, 0.10) : "rgba(255,140,40,0.10)")
                                g.addColorStop(1, isMacOS ? MacColors.opacity(MacColors.orange, 0) : "rgba(255,140,40,0)")
                                ctx.fillStyle = g
                                ctx.fillRect(0, 0, 440, 440)
                            }
                        }
                        TubeIllustration {
                            anchors.fill: parent
                            tubeType: win.tubeType
                            lit: win.active
                            bloom: win.bloom
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.tubeNames[win.tubeType]
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: isMacOS ? MacColors.label : "white"
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: win.caption(win.tubeType)
                        font.pixelSize: 11
                        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55)
                    }
                }
            }

            Rectangle { width: 1; height: basic.height; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.08) }

            Column {
                id: basicRight
                width: flick.colWidth
                spacing: 12

                SectionLabel {
                    text: "TUBE"
                    MouseArea { id: tubeHover; anchors.fill: parent; hoverEnabled: true }
                    ToolTip.visible: tubeHover.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: "Loads the character of a real tube: its bias, asymmetry, knee hardness and sag. Drive, mix and everything in Advanced keep their values."
                }
                Repeater {
                    model: win.groups
                    Column {
                        width: basicRight.width
                        spacing: 6
                        Text { text: modelData.title; font.pixelSize: 11; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5) }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: modelData.types
                                TubeChip { type: modelData }
                            }
                        }
                    }
                }
                Divider {}
                ParamRow {
                    label: "Drive"; unit: "dB"; from: -30; to: 24; stepSize: 0.5; defaultValue: -12
                    leftHint: "Clean"; rightHint: "Overdrive"
                    tip: "How hard the tube is driven. Drive moves the knee, not the level: at the -12 dB default the knee sits 12 dB above full scale and the colour is subtle, the -30 dB floor is close to transparent, and the top of the range is overdrive."
                    value: win.params[win.pDrive]
                    onLiveChanged: bridge.setTubeParam(win.pDrive, v, true)
                    onCommitted: bridge.setTubeParam(win.pDrive, v)
                }
                ParamRow {
                    label: "Mix"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 100
                    leftHint: "Dry"; rightHint: "All tube"
                    tip: "Blends the tube with the untouched signal. Below 100% the original transients stay intact under the colour, which is the easiest way to use heavy drive subtly."
                    value: win.params[win.pMix]
                    onLiveChanged: bridge.setTubeParam(win.pMix, v, true)
                    onCommitted: bridge.setTubeParam(win.pMix, v)
                }
                Divider {}
                OutputsSection { width: parent.width }
            }
        }

        // ── Advanced: transfer curve and every parameter ──
        Row {
            id: advanced
            visible: prefs.advanced
            x: 16
            y: 16
            spacing: 20
            enabled: bridge.connected

            Column {
                id: advLeft
                width: flick.colWidth
                spacing: 12

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "TRANSFER CURVE"; anchors.verticalCenter: parent.verticalCenter }
                    MenuLink {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Apply preset"
                        menu: presetMenu
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 188
                    radius: 10
                    color: isMacOS ? MacColors.opacity(MacColors.controlBackground, 0.6) : Qt.rgba(0, 0, 0, 0.2)
                    border.color: isMacOS ? MacColors.opacity(MacColors.gray, 0.2) : Qt.rgba(1, 1, 1, 0.1)

                    Canvas {
                        id: curve
                        anchors.fill: parent
                        anchors.margins: 8
                        // Follow the sliders during a drag
                        property real drive: driveRow.displayValue
                        property real bias: biasRow.displayValue
                        property real asym: asymRow.displayValue
                        property real hard: hardRow.displayValue
                        property real mix: mixRow.displayValue
                        property real trim: trimRow.displayValue
                        property bool shown: win.active && prefs.advanced
                        onDriveChanged: recompute()
                        onBiasChanged: recompute()
                        onAsymChanged: recompute()
                        onHardChanged: recompute()
                        onMixChanged: recompute()
                        onTrimChanged: recompute()
                        onShownChanged: recompute()
                        onWidthChanged: requestPaint()

                        property real h2: -120
                        property real h3: -120

                        // The firmware's static curve (tube.c), after mix and trim
                        function transfer() {
                            var m = Math.pow(10, drive / 20), b = bias / 200, rn = Math.pow(10, -asym / 20), hh = hard / 100
                            var c1 = 1.5 + 0.375 * hh, c3 = -0.5 - 0.75 * hh, c5 = 0.375 * hh
                            var sP = 1 / (c1 * m), sN = Math.pow(10, asym / 20) / (c1 * m)
                            var mx = mix / 100, g = Math.pow(10, trim / 20)
                            function shape(x) {
                                var t = m * x + b
                                if (t < 0) t *= rn
                                t = Math.max(-1, Math.min(1, t))
                                return t * (c1 + t * t * (c3 + t * t * c5)) * (t >= 0 ? sP : sN)
                            }
                            var s0 = shape(0)
                            return { f: function(x) { return (1 - mx) * x + mx * g * (shape(x) - s0) }, m: m, b: b, rn: rn }
                        }
                        function recompute() {
                            if (!shown) { requestPaint(); return }
                            // 2nd and 3rd harmonic of a full-scale sine, relative to the fundamental
                            var f = transfer().f, N = 256, re = [0, 0, 0, 0], im = [0, 0, 0, 0]
                            for (var n = 0; n < N; n++) {
                                var y = f(Math.sin(2 * Math.PI * n / N))
                                for (var k = 1; k <= 3; k++) {
                                    re[k] += y * Math.cos(2 * Math.PI * k * n / N)
                                    im[k] -= y * Math.sin(2 * Math.PI * k * n / N)
                                }
                            }
                            var a1 = Math.hypot(re[1], im[1])
                            function rel(k) { var a = Math.hypot(re[k], im[k]); return a1 > 0 && a > 0 ? 20 * Math.log(a / a1) / Math.LN10 : -120 }
                            h2 = rel(2)
                            h3 = rel(3)
                            requestPaint()
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var w = width, h = height
                            function xOf(x) { return (x + 1) / 2 * w }
                            function yOf(y) { return h / 2 - y / 1.4 * (h / 2) }

                            ctx.lineWidth = 1
                            ctx.strokeStyle = isMacOS ? MacColors.opacity(MacColors.gray, 0.15) : "rgba(255,255,255,0.07)"
                            var gl = [-1, -0.5, 0.5, 1]
                            for (var i = 0; i < gl.length; i++) {
                                ctx.beginPath(); ctx.moveTo(xOf(gl[i]), 0); ctx.lineTo(xOf(gl[i]), h); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(0, yOf(gl[i])); ctx.lineTo(w, yOf(gl[i])); ctx.stroke()
                            }
                            ctx.strokeStyle = isMacOS ? MacColors.opacity(MacColors.gray, 0.4) : "rgba(255,255,255,0.18)"
                            ctx.beginPath(); ctx.moveTo(xOf(0), 0); ctx.lineTo(xOf(0), h); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(0, yOf(0)); ctx.lineTo(w, yOf(0)); ctx.stroke()
                            ctx.fillStyle = isMacOS ? MacColors.opacity(MacColors.secondaryLabel, 0.6) : "rgba(255,255,255,0.4)"
                            ctx.font = "9px sans-serif"
                            ctx.fillText("out", xOf(0) + 4, 10)
                            ctx.fillText("in", w - 12, yOf(0) - 4)

                            if (!shown) {
                                ctx.textAlign = "center"
                                ctx.fillStyle = isMacOS ? MacColors.opacity(MacColors.secondaryLabel, 0.5) : "rgba(255,255,255,0.35)"
                                ctx.font = "12px sans-serif"
                                ctx.fillText("Disabled", w / 2, h / 2 - 12)
                                return
                            }
                            var t = transfer()
                            // Where the stage runs out of headroom
                            ctx.fillStyle = isMacOS ? MacColors.opacity(MacColors.orange, 0.10) : "rgba(255,159,10,0.10)"
                            var xp = (1 - t.b) / t.m, xn = (-1 / t.rn - t.b) / t.m
                            if (xp < 1) ctx.fillRect(xOf(Math.max(-1, xp)), 0, xOf(1) - xOf(Math.max(-1, xp)), h)
                            if (xn > -1) ctx.fillRect(0, 0, xOf(Math.min(1, xn)), h)
                            // Full scale
                            ctx.setLineDash([3, 3])
                            ctx.strokeStyle = isMacOS ? MacColors.opacity(MacColors.red, 0.3) : "rgba(255,69,58,0.6)"
                            ctx.beginPath(); ctx.moveTo(0, yOf(1)); ctx.lineTo(w, yOf(1)); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(0, yOf(-1)); ctx.lineTo(w, yOf(-1)); ctx.stroke()
                            ctx.fillStyle = isMacOS ? MacColors.opacity(MacColors.red, 0.5) : "rgba(255,105,97,0.8)"
                            ctx.fillText("0 dBFS", 4, yOf(1) - 3)
                            // Unity reference
                            ctx.strokeStyle = isMacOS ? MacColors.opacity(MacColors.label, 0.25) : "rgba(255,255,255,0.25)"
                            ctx.beginPath(); ctx.moveTo(xOf(-1), yOf(-1)); ctx.lineTo(xOf(1), yOf(1)); ctx.stroke()
                            ctx.setLineDash([])
                            // The curve
                            ctx.strokeStyle = isMacOS ? MacColors.accent : "#0a7cff"
                            ctx.lineWidth = 1.6
                            ctx.beginPath()
                            for (var n = 0; n <= 240; n++) {
                                var x = -1 + 2 * n / 240, y = yOf(t.f(x))
                                if (n === 0) ctx.moveTo(xOf(x), y); else ctx.lineTo(xOf(x), y)
                            }
                            ctx.stroke()
                        }
                        Component.onCompleted: recompute()
                    }
                }

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "AT FULL SCALE"; anchors.verticalCenter: parent.verticalCenter }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 16
                        Repeater {
                            model: [["2nd", curve.h2], ["3rd", curve.h3]]
                            Row {
                                spacing: 5
                                Text { text: modelData[0]; font.pixelSize: 12; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5) }
                                Text {
                                    text: !win.active ? "—" : modelData[1] <= -100 ? "none" : modelData[1].toFixed(0) + " dB"
                                    font.pixelSize: 12
                                    color: isMacOS ? (modelData[1] > -100 ? MacColors.label : MacColors.secondaryLabel) : Qt.rgba(1, 1, 1, 0.9)
                                }
                            }
                        }
                    }
                    MouseArea { id: harmHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    ToolTip.visible: harmHover.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: "Level of the second and third harmonic relative to the fundamental, for a full-scale sine through the static curve after mix and trim. Sag lowers the drive on sustained loud passages and the output stage adds its own low-frequency lift, so the running figures sit somewhat lower."
                }

                Divider {}
                SectionLabel { text: "STAGE" }

                Item {
                    width: parent.width
                    height: 28
                    Text { text: "Tube"; font.pixelSize: 13; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9); anchors.verticalCenter: parent.verticalCenter }
                    StyledComboBox {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 190
                        model: win.tubeNames
                        currentIndex: win.tubeType
                        onActivated: bridge.setTubeParam(win.pType, index)
                        ToolTip.visible: hovered && !popup.visible
                        ToolTip.delay: 500
                        ToolTip.text: "Loads the bias, asymmetry, knee hardness and sag of a real tube. Drive, mix, the rectifier and the output stage are left alone. Editing any of the four character controls switches this to Custom."
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: win.caption(win.tubeType)
                    font.pixelSize: 11
                    color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                }
                ParamRow {
                    id: driveRow
                    label: "Drive"; unit: "dB"; from: -30; to: 24; stepSize: 0.5; defaultValue: -12
                    tip: "Gain ahead of the shaper. At 0 dB a full-scale signal just reaches the knee, so this alone sets how hard the stage is driven. The shaper carries matching makeup gain, so clean material keeps its level at every drive; harmonics and sag rise with it."
                    value: win.params[win.pDrive]
                    onLiveChanged: bridge.setTubeParam(win.pDrive, v, true)
                    onCommitted: bridge.setTubeParam(win.pDrive, v)
                }
                ParamRow {
                    id: mixRow
                    label: "Mix"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 100
                    tip: "Blend of the processed signal with the untouched input. The dry path is sample-aligned with the wet one, so blending never combs."
                    value: win.params[win.pMix]
                    onLiveChanged: bridge.setTubeParam(win.pMix, v, true)
                    onCommitted: bridge.setTubeParam(win.pMix, v)
                }
                ParamRow {
                    id: trimRow
                    label: "Output Trim"; unit: "dB"; from: -12; to: 12; stepSize: 0.5; defaultValue: 0
                    tip: "Level of the processed signal only. A hard-driven, strongly asymmetric setting can push the wet path above full scale; watch the output clip indicators and bring it back here."
                    value: win.params[win.pTrim]
                    onLiveChanged: bridge.setTubeParam(win.pTrim, v, true)
                    onCommitted: bridge.setTubeParam(win.pTrim, v)
                }
                Divider {}
                OutputsSection { width: parent.width }
            }

            Rectangle { width: 1; height: advanced.height; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.08) }

            Column {
                width: flick.colWidth
                spacing: 12

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "CHARACTER"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.tubeType > 0 ? "from " + win.tubeNames[win.tubeType] : "custom"
                        font.pixelSize: 11
                        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                    }
                }
                ParamRow {
                    id: biasRow
                    label: "Bias"; unit: "%"; from: -100; to: 100; stepSize: 1; decimals: 0; defaultValue: 10
                    tip: "Shifts the operating point along the curve. Positive values give the classic warm second harmonic that grows with level; negative values give the same amount with the even products inverted, which only matters when mixed with the dry signal."
                    value: win.params[win.pBias]
                    onLiveChanged: bridge.setTubeParam(win.pBias, v, true)
                    onCommitted: bridge.setTubeParam(win.pBias, v)
                }
                ParamRow {
                    id: asymRow
                    label: "Asymmetry"; unit: "dB"; from: -12; to: 12; stepSize: 0.5; defaultValue: 3
                    tip: "How much later the negative half reaches its knee than the positive half. Adds even-order content at heavy drive. Zero is symmetric, as in a push-pull stage."
                    value: win.params[win.pAsym]
                    onLiveChanged: bridge.setTubeParam(win.pAsym, v, true)
                    onCommitted: bridge.setTubeParam(win.pAsym, v)
                }
                ParamRow {
                    id: hardRow
                    label: "Knee Hardness"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 40
                    tip: "Blends from a soft cubic knee (0%) to a harder quintic one (100%). Clean material stays at the same level at every setting; only how abruptly the stage runs out changes."
                    value: win.params[win.pHard]
                    onLiveChanged: bridge.setTubeParam(win.pHard, v, true)
                    onCommitted: bridge.setTubeParam(win.pHard, v)
                }
                ParamRow {
                    label: "Sag"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 15
                    opacity: win.rectifier === 0 ? 0.5 : 1
                    tip: "Supply-sag compression: sustained heavy drive pulls the gain down slowly, then recovers. The rectifier below scales the depth and sets the timing."
                    value: win.params[win.pSag]
                    onLiveChanged: bridge.setTubeParam(win.pSag, v, true)
                    onCommitted: bridge.setTubeParam(win.pSag, v)
                }
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Rectifier"; font.pixelSize: 13; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9) }
                    SegmentedControl {
                        width: parent.width
                        model: win.rectifiers
                        currentIndex: win.rectifier
                        tips: ["The power-supply rectifier sets how deep and how slow the sag is. Solid state switches sag off entirely; the valve rectifiers get progressively softer and slower from GZ34 to 5Y3."]
                        onActivated: bridge.setTubeParam(win.pRect, index)
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: win.rectifierNotes[win.rectifier] || ""
                        font.pixelSize: 11
                        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                    }
                }

                Divider {}
                Item {
                    width: parent.width
                    height: 34
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        SectionLabel { text: "OUTPUT STAGE" }
                        Text { text: "A valve amplifier's loose grip on the speaker."; font.pixelSize: 11; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5) }
                    }
                    MouseArea {
                        id: stageHover
                        anchors.fill: parent
                        anchors.rightMargin: 50
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                    ToolTip.visible: stageHover.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: "A tube amplifier's high source impedance lets the speaker's own impedance curve shape the response: a broad bump at the woofer resonance and a small lift at the top. Nothing here is nonlinear, and the firmware skips the whole stage while it is off."
                    ToggleSwitch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: win.outputStage
                        onToggled: bridge.setTubeParam(win.pXfmr, checked ? 1 : 0)
                    }
                }
                ParamRow {
                    id: dampingRow
                    visible: win.outputStage
                    label: "Damping Factor"; unit: ""; from: 1; to: 20; stepSize: 0.5; defaultValue: 2
                    leftHint: "1 (loose)"; rightHint: "20 (tight)"
                    tip: "The speaker's nominal impedance divided by the amplifier's source impedance. A single-ended triode amplifier without feedback sits around 2 to 3; a push-pull pentode amplifier with feedback around 8 to 15. It sets the size of both the bell and the top lift."
                    caption: {
                        var df = displayValue
                        var bell = 20 * Math.log(4 * (df + 1) / (4 * df + 1)) / Math.LN10
                        var top = 20 * Math.log(2 * (df + 1) / (2 * df + 1)) / Math.LN10
                        return "+" + bell.toFixed(1) + " dB at resonance, +" + top.toFixed(1) + " dB at the top."
                    }
                    value: win.params[win.pDamping]
                    onLiveChanged: bridge.setTubeParam(win.pDamping, v, true)
                    onCommitted: bridge.setTubeParam(win.pDamping, v)
                }
                ParamRow {
                    visible: win.outputStage
                    label: "Speaker Resonance"; unit: "Hz"; from: 30; to: 150; stepSize: 1; decimals: 0; defaultValue: 95
                    leftHint: "30 Hz"; rightHint: "150 Hz"
                    tip: "Where the loudspeaker resonates in its enclosure, which is where the bell sits. Q is fixed at 0.707, so the bump is broad. 95 Hz suits a typical small to medium woofer; larger drivers sit lower."
                    value: win.params[win.pRes]
                    onLiveChanged: bridge.setTubeParam(win.pRes, v, true)
                    onCommitted: bridge.setTubeParam(win.pRes, v)
                }
            }
        }
    }

    ActionMenu {
        id: presetMenu
        parent: Overlay.overlay
        items: win.presets.map(function(p, i) { return { key: String(i), text: p.name } })
        onTriggered: win.applyPreset(win.presets[Number(key)])
    }

    ActionMenu {
        id: outputPresetMenu
        parent: Overlay.overlay
        items: [
            { key: "all", text: "All Outputs" },
            { key: "nosub", text: "Exclude Sub" },
            { key: "none", text: "None" }
        ]
        onTriggered: {
            var all = (1 << win.numOut) - 1
            if (key === "all") bridge.setTubeParam(win.pMask, all)
            else if (key === "nosub") bridge.setTubeParam(win.pMask, all & ~(1 << (win.numOut - 1)))
            else if (key === "none") bridge.setTubeParam(win.pMask, 0)
        }
    }
}
