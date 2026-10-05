import QtQuick 2.15

// A signal type's waveform as a tiny line drawing (the signal generator's
// tiles), after the macOS Console's hand-drawn glyphs. Painted once per
// type and colour.
Canvas {
    id: glyph
    property int type: 0
    property color color: "white"
    property real lineWidth: 1.4
    implicitWidth: 44
    implicitHeight: 22
    onTypeChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width, h = height, mid = h / 2
        function px(t) { return t * w }
        function py(v) { return mid - v * h * 0.42 }
        function mv(t, v) { ctx.moveTo(px(t), py(v)) }
        function ln(t, v) { ctx.lineTo(px(t), py(v)) }
        function sampled(f, points) {
            points = points || 64
            mv(0, f(0))
            for (var i = 1; i <= points; i++) { var t = i / points; ln(t, f(t)) }
        }
        // Deterministic "random" for the noise glyphs
        function jitter(t, s) { return Math.sin(t * 91.7 + 1.3) * 0.5 + Math.sin(t * 173.3) * 0.35 + Math.sin(t * 47.9 + 4.1) * 0.15 * s }
        var PI = Math.PI

        ctx.strokeStyle = color
        ctx.lineWidth = lineWidth
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        switch (type) {
        case 0: sampled(function (t) { return Math.sin(t * 2 * PI * 2) }); break           // sine
        case 1: {                                                                           // square
            var t = 0, high = true
            mv(0, 1)
            while (t < 1) {
                var next = Math.min(t + 0.25, 1)
                ln(next, high ? 1 : -1)
                if (next < 1) ln(next, high ? -1 : 1)
                high = !high
                t = next
            }
            break
        }
        case 2: sampled(function (t) { return jitter(t, 1) * 1.5 }, 40); break             // white
        case 3: sampled(function (t) { return Math.sin(t * 2 * PI * 1.3) * 0.7 + jitter(t, 1) * 0.5 }, 40); break
        case 4: sampled(function (t) { return Math.sin(2 * PI * 1.2 * (Math.pow(6, t) - 1)) }); break
        case 5: sampled(function (t) { return Math.sin(2 * PI * (1 + 4 * t) * t) }); break
        case 6:                                                                             // stepped sweep
            for (var i = 0; i < 4; i++) {
                var v = i / 3 * 1.6 - 0.8
                mv(i / 4, v)
                ln((i + 1) / 4 - 0.04, v)
            }
            break
        case 7:                                                                             // impulse
            mv(0, 0); ln(0.45, 0); ln(0.48, 1); ln(0.51, 0); ln(1, 0)
            break
        case 8:                                                                             // alternating clicks
            mv(0, 0); ln(0.28, 0); ln(0.31, 1); ln(0.34, 0); ln(0.64, 0); ln(0.67, -1); ln(0.70, 0); ln(1, 0)
            break
        case 9: sampled(function (t) { return (t > 0.3 && t < 0.7) ? Math.sin((t - 0.3) / 0.4 * PI) : 0 }); break
        case 10: sampled(function (t) {                                                     // tone burst
            var win = (t > 0.15 && t < 0.55) ? Math.sin((t - 0.15) / 0.4 * PI) : 0
            return Math.sin(t * 2 * PI * 6) * win
        }); break
        case 11: sampled(function (t) { return Math.sin(t * 2 * PI * 1.5) * 0.72 + Math.sin(t * 2 * PI * 11) * 0.28 }); break
        case 12: sampled(function (t) {
            return (Math.sin(t * 2 * PI * 1.5) + Math.sin(t * 2 * PI * 3.7 + 1) + Math.sin(t * 2 * PI * 7.3 + 2)) / 2.6
        }); break
        case 13:                                                                            // ISP: staircase and its over-peak arc
            mv(0.05, 0.7); ln(0.45, 0.7)
            mv(0.55, -0.7); ln(0.95, -0.7)
            mv(0.05, 0.7)
            ctx.quadraticCurveTo(px(0.25), py(1.15), px(0.45), py(0.7))
            break
        case 14: {                                                                          // channel ID: counted blips
            var centres = [0.18, 0.5, 0.82]
            for (var k = 0; k < 3; k++) {
                var c = centres[k], wd = 0.11, amp = 0.45 + k * 0.27
                mv(c - wd, 0)
                for (var s = 1; s <= 12; s++) {
                    var tt = c - wd + s / 12 * wd * 2
                    var ph = (tt - (c - wd)) / (wd * 2)
                    ln(tt, Math.sin(ph * PI) * amp * Math.sin(ph * PI * 6))
                }
            }
            break
        }
        default: sampled(function (t) { return Math.sin(t * 2 * PI * 2) })
        }
        ctx.stroke()
    }
}
