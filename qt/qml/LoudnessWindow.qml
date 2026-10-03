import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Loudness Compensation: ISO 226:2003 equal-loudness correction. Laid out as
// on the macOS Console: the compensation curve on the left, parameters and
// output selection on the right.
AppWindow {
    id: win
    fitHeight: header.height + flick.contentHeight
    title: "Loudness Compensation"
    visible: false
    width: 720
    height: 440 + titlebarHeight
    minimumWidth: 640
    minimumHeight: 340 + titlebarHeight

    readonly property int numOut: bridge.numOutputChannels

    function outputNames() {
        var n = []
        for (var o = 0; o < numOut; o++) n.push(bridge.channelName(o + 2))
        return n
    }

    // ISO 226:2003 parameters per frequency: [f, af, Lu, Tf] (macOS values)
    readonly property var isoTable: [
        [20, 0.532, -31.6, 78.5], [25, 0.506, -27.2, 68.7], [31.5, 0.480, -23.0, 59.5],
        [40, 0.455, -19.1, 51.1], [50, 0.432, -15.9, 44.0], [63, 0.409, -13.0, 37.5],
        [80, 0.387, -10.3, 31.5], [100, 0.367, -8.1, 26.5], [125, 0.349, -6.2, 22.1],
        [160, 0.330, -4.5, 17.9], [200, 0.315, -3.1, 14.4], [250, 0.301, -2.0, 11.4],
        [315, 0.288, -1.1, 8.6], [400, 0.276, -0.4, 6.2], [500, 0.267, 0.0, 4.4],
        [630, 0.259, 0.3, 3.0], [800, 0.253, 0.5, 2.2], [1000, 0.250, 0.0, 2.4],
        [1250, 0.246, -2.7, 3.5], [1600, 0.244, -4.1, 1.7], [2000, 0.243, -1.0, -1.3],
        [2500, 0.243, 1.7, -4.2], [3150, 0.243, 2.5, -6.0], [4000, 0.242, 1.2, -5.4],
        [5000, 0.242, -2.1, -1.5], [6300, 0.245, -7.1, 6.0], [8000, 0.254, -11.2, 12.6],
        [10000, 0.271, -10.7, 13.9], [12500, 0.301, -3.1, 12.3], [16000, 0.310, -2.0, 17.0]]
    // The curve is drawn for this volume (as on macOS)
    readonly property real curveVolumeDB: -40

    function isoSPL(tf, af, lu, phon) {
        var threshold = Math.pow(0.4 * Math.pow(10, (tf + lu) / 10 - 9), af)
        var A = Math.max(4.47e-3 * (Math.pow(10, 0.025 * phon) - 1.15) + threshold, 1e-10)
        return (10 / af) * Math.log(A) / Math.LN10 - lu + 94
    }
    // [[f, dB]] for the reference SPL and intensity
    function curve(ref, intensity) {
        var phon = Math.min(Math.max(ref + curveVolumeDB, 20), ref)
        var pts = []
        for (var i = 0; i < isoTable.length; i++) {
            var d = isoTable[i], g = 0
            if (phon < ref) {
                var freq = isoSPL(d[3], d[1], d[2], phon) - isoSPL(d[3], d[1], d[2], ref)
                g = (freq - (phon - ref)) * intensity / 100
            }
            pts.push([d[0], g])
        }
        return pts
    }

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }
    component Divider: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

    ToolHeader {
        id: header
        width: parent.width
        icon: "loudness"
        title: "Loudness Compensation"
        subtitle: "ISO 226:2003 Fletcher-Munson"
        checked: bridge.loudnessEnabled
        onToggled: bridge.setLoudness(enable)
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

            // ── Left: compensation curve ──
            Column {
                width: columns.colWidth
                spacing: 12

                SectionLabel { text: "COMPENSATION CURVE" }

                Rectangle {
                    width: parent.width
                    // As tall as the parameter column, like macOS
                    height: Math.max(200, rightColumn.height - 32)
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.2)
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    Canvas {
                        id: graph
                        anchors.fill: parent
                        anchors.margins: 10
                        // Follow the sliders during a drag
                        property real ref: refRow.displayValue
                        property real intensity: intensityRow.displayValue
                        property bool active: bridge.loudnessEnabled
                        onRefChanged: requestPaint()
                        onIntensityChanged: requestPaint()
                        onActiveChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var left = 24, w = width - left, h = height - 14
                            var lo = Math.log(20), hi = Math.log(20000)
                            function xOf(f) { return left + (Math.log(f) - lo) / (hi - lo) * w }

                            var pts = win.curve(ref, intensity)
                            var mn = 1e9, mx = -1e9
                            for (var i = 0; i < pts.length; i++) {
                                mn = Math.min(mn, pts[i][1]); mx = Math.max(mx, pts[i][1])
                            }
                            var range = Math.max(mx - mn, 10), pad = range * 0.2
                            var dMin = mn - pad, dMax = mx + pad
                            function yOf(g) { return h - (g - dMin) / (dMax - dMin) * h }

                            // Grid: decades and 5 dB lines
                            ctx.lineWidth = 1
                            ctx.strokeStyle = "rgba(255,255,255,0.07)"
                            ctx.fillStyle = "rgba(255,255,255,0.4)"
                            ctx.font = "10px sans-serif"
                            ctx.textAlign = "center"
                            var marks = [[100, "100"], [1000, "1k"], [10000, "10k"]]
                            for (i = 0; i < marks.length; i++) {
                                var gx = xOf(marks[i][0])
                                ctx.beginPath(); ctx.moveTo(gx, 0); ctx.lineTo(gx, h); ctx.stroke()
                                ctx.fillText(marks[i][1], gx, h + 12)
                            }
                            ctx.textAlign = "right"
                            var step = dMax - dMin > 30 ? 10 : 5
                            for (var g = Math.ceil(dMin / step) * step; g <= dMax; g += step) {
                                var gy = yOf(g)
                                ctx.beginPath(); ctx.moveTo(left, gy); ctx.lineTo(left + w, gy); ctx.stroke()
                                ctx.fillText(g, left - 5, gy + 3)
                            }

                            if (!active) {
                                ctx.textAlign = "center"
                                ctx.fillStyle = "rgba(255,255,255,0.35)"
                                ctx.font = "12px sans-serif"
                                ctx.fillText("Disabled", left + w / 2, h / 2)
                                return
                            }

                            ctx.strokeStyle = "#0a7cff"
                            ctx.lineWidth = 2
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            for (i = 0; i < pts.length; i++) {
                                var px = xOf(pts[i][0]), py = yOf(pts[i][1])
                                if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                            }
                            ctx.stroke()
                        }
                    }

                    // Which volume the curve is drawn for
                    Rectangle {
                        visible: bridge.loudnessEnabled
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 14
                        width: curveTag.implicitWidth + 14
                        height: 20
                        radius: 5
                        color: Qt.rgba(0.04, 0.49, 1, 0.85)
                        Text {
                            id: curveTag
                            anchors.centerIn: parent
                            text: "Curve at " + win.curveVolumeDB + " dB"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: "white"
                        }
                    }
                }
            }

            Rectangle { width: 1; height: columns.height; color: Qt.rgba(1, 1, 1, 0.08) }

            // ── Right: parameters and outputs ──
            Column {
                id: rightColumn
                width: columns.colWidth
                spacing: 12

                SectionLabel { text: "PARAMETERS" }

                ParamRow {
                    id: refRow
                    label: "Reference SPL"; unit: "dB"; from: 40; to: 100; stepSize: 0.5; decimals: 1
                    value: bridge.loudnessRefSPL
                    caption: "SPL at 1 kHz when USB volume is 0 dB. Lower = more compensation per dB of volume reduction."
                    onLiveChanged: bridge.setLoudnessRef(v, true)
                    onCommitted: bridge.setLoudnessRef(v)
                }
                Divider {}
                ParamRow {
                    id: intensityRow
                    label: "Intensity"; unit: "%"; from: 0; to: 200; stepSize: 1; decimals: 1
                    value: bridge.loudnessIntensity
                    caption: "Scales the ISO 226 compensation. 100% = standard curve. 0% = bypassed. Over 100% = exaggerated."
                    onLiveChanged: bridge.setLoudnessIntensity(v, true)
                    onCommitted: bridge.setLoudnessIntensity(v)
                }
                Divider {}

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "OUTPUTS"; anchors.verticalCenter: parent.verticalCenter }
                    Item {
                        id: outLink
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: outRow.width
                        height: outRow.height
                        Row {
                            id: outRow
                            spacing: 4
                            Text {
                                text: "Presets"
                                font.pixelSize: 12
                                color: outMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.75)
                            }
                            Icon { name: "chev-down"; size: 11; color: Qt.rgba(1, 1, 1, 0.6); anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: outMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: outMenu.openAt(outLink, 0, outLink.height + 4)
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.5)
                    text: "Compensate only the outputs feeding your low-level listening chain. Keep bass-managed pairs (mains + sub) together so the crossover stays coherent."
                }

                ChannelChips {
                    width: parent.width
                    count: win.numOut
                    mask: bridge.loudnessOutputMask
                    names: win.outputNames()
                    onMaskEdited: bridge.setLoudnessOutputMask(mask)
                }
            }
        }
    }

    ActionMenu {
        id: outMenu
        parent: Overlay.overlay
        items: [
            { key: "all", text: "All Outputs" },
            { key: "first", text: "Outputs 1–2 Only (Headphones)" },
            { key: "none", text: "None" }
        ]
        onTriggered: {
            if (key === "all") bridge.setLoudnessOutputMask(0xFFFF)
            else if (key === "first") bridge.setLoudnessOutputMask(0x0003)
            else if (key === "none") bridge.setLoudnessOutputMask(0)
        }
    }
}
