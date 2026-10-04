import QtQuick 2.15

// The Tube Modeller's showcase: the selected tube, its heater glow while the
// stage is on, and a bloom that follows the signal. Port of the Windows
// Console's TubeIllustration (itself after the macOS TubeRenderer). Each
// layer is painted once per tube family and size; afterwards only the
// opacities move, so following the audio costs no drawing.
Item {
    id: art
    property int tubeType: 1
    property bool lit: false
    property real bloom: 0          // 0..1

    // Tube type -> drawn family
    readonly property string family: {
        switch (tubeType) {
        case 6: case 7: return "octalGlass"
        case 9: return "novalPentode"
        case 10: return "octalMetal"
        case 11: return "novalPower"
        case 12: return "octalPowerLarge"
        case 13: return "shoulderedPower"
        case 14: return "octalPowerSmall"
        case 15: return "beamBottle"
        case 16: return "directlyHeated"
        default: return "novalTriode"
        }
    }

    // Every family on a 120 x 200 grid (x -60..60 about the axis, y 0 at the
    // top to 200 at the pin tips). profile: left edge as [half-width, y],
    // bottom to top; a dome closes it at `top`.
    readonly property var shapes: ({
        novalTriode: {
            profile: [[28, 166], [28, 72]], top: 52,
            pins: [-20, -10, 0, 10, 20], pinTop: 166, pinBottom: 190, pinWidth: 1.6,
            getter: [52, 67], micas: [[80, 25], [142, 25]],
            rods: [[-25, 76, 164], [0, 76, 164], [25, 76, 164]],
            plates: [{ r: [-23, 84, 20, 54], ribs: [-13] }, { r: [3, 84, 20, 54], ribs: [13] }],
            glows: [[-13, 80, 12], [13, 80, 12], [-13, 142, 11], [13, 142, 11]] },
        novalPentode: {
            profile: [[28, 166], [28, 72]], top: 52,
            pins: [-20, -10, 0, 10, 20], pinTop: 166, pinBottom: 190, pinWidth: 1.6,
            getter: [52, 67], micas: [[80, 25], [142, 25]],
            rods: [[-22, 76, 164], [22, 76, 164]],
            plates: [{ r: [-17, 86, 34, 52], ribs: [-6, 6] }],
            glows: [[0, 81, 14], [0, 143, 12]] },
        novalPower: {
            profile: [[32, 168], [32, 58]], top: 34,
            pins: [-22, -11, 0, 11, 22], pinTop: 168, pinBottom: 192, pinWidth: 1.6,
            getter: [34, 50], micas: [[60, 29], [144, 29]],
            rods: [[-29, 56, 166], [29, 56, 166]],
            plates: [{ r: [-20, 66, 40, 72], fins: 5, ribs: [-7, 7] }],
            glows: [[0, 61, 16], [0, 144, 14]] },
        octalGlass: {
            profile: [[30, 148], [30, 50]], top: 26,
            base: [146, 176, 33, 31, true],
            pins: [-21, -7, 7, 21], pinTop: 176, pinBottom: 196, pinWidth: 2.6,
            getter: [26, 41], micas: [[58, 27], [128, 27]],
            rods: [[-26, 54, 146], [0, 54, 146], [26, 54, 146]],
            plates: [{ r: [-22, 62, 19, 62], ribs: [-12.5] }, { r: [3, 62, 19, 62], ribs: [12.5] }],
            glows: [[-12.5, 58, 12], [12.5, 58, 12], [-12.5, 128, 11], [12.5, 128, 11]] },
        // A metal tube shows no glow; its one light is a faint warmth at the base
        octalMetal: {
            profile: [[27, 150], [27, 60]], top: 52, metal: true,
            base: [148, 176, 30, 28, true],
            pins: [-19, -6.5, 6.5, 19], pinTop: 176, pinBottom: 196, pinWidth: 2.6,
            glows: [[0, 149, 9]], ring: [126, 132] },
        octalPowerLarge: {
            profile: [[34, 152], [34, 44]], top: 14,
            base: [150, 180, 37, 35, true],
            pins: [-24, -8, 8, 24], pinTop: 180, pinBottom: 199, pinWidth: 2.8,
            getter: [14, 31], micas: [[46, 31], [134, 31]],
            rods: [[-30, 42, 150], [30, 42, 150]],
            plates: [{ r: [-23, 52, 46, 78], fins: 6, ribs: [0] }],
            glows: [[0, 47, 18], [0, 135, 16]] },
        octalPowerSmall: {
            profile: [[27, 152], [27, 66]], top: 44,
            base: [150, 178, 31, 29, true],
            pins: [-20, -7, 7, 20], pinTop: 178, pinBottom: 197, pinWidth: 2.6,
            getter: [44, 59], micas: [[68, 24], [136, 24]],
            rods: [[-24, 64, 150], [24, 64, 150]],
            plates: [{ r: [-17, 74, 34, 58], fins: 5, ribs: [0] }],
            glows: [[0, 69, 14], [0, 137, 12]] },
        shoulderedPower: {
            profile: [[26, 152], [30, 140], [36, 116], [36, 104], [27, 76], [26, 60]], top: 24,
            base: [150, 180, 34, 32, true],
            pins: [-22, -7, 7, 22], pinTop: 180, pinBottom: 199, pinWidth: 2.8,
            getter: [24, 40], micas: [[66, 22], [136, 30]],
            rods: [[-24, 62, 150], [24, 62, 150]],
            plates: [{ r: [-20, 72, 40, 60], fins: 7, ribs: [0] }],
            glows: [[0, 68, 16], [0, 137, 14]] },
        beamBottle: {
            profile: [[30, 156], [32, 144], [42, 108], [42, 40]], top: 8,
            base: [154, 184, 36, 34, true],
            pins: [-24, -8, 8, 24], pinTop: 184, pinBottom: 200, pinWidth: 2.8,
            getter: [8, 25], micas: [[46, 39], [138, 36]],
            rods: [[-34, 42, 154], [34, 42, 154]],
            plates: [{ r: [-26, 54, 52, 80], fins: 7, ribs: [-9, 9] }],
            glows: [[0, 49, 20], [0, 139, 16]] },
        // The filament is the cathode, strung above the plate, so it is what glows
        directlyHeated: {
            profile: [[22, 162], [25, 152], [42, 118], [43, 98], [34, 56], [23, 36]], top: 10,
            base: [160, 188, 36, 34, false],
            pins: [-13, 13], pinTop: 188, pinBottom: 200, pinWidth: 4.5,
            getter: [10, 22], micas: [[50, 24], [140, 27]],
            rods: [[-24, 48, 160], [24, 48, 160], [-7, 50, 57], [7, 50, 57]],
            plates: [{ r: [-19, 74, 38, 62], mesh: true }],
            filament: [[-15, 74], [-7, 57], [0, 74], [7, 57], [15, 74]],
            glows: [[0, 66, 34]] }
    })
    readonly property var shape: shapes[family]

    // ── Shared drawing helpers ──

    function white(a) { return "rgba(255,255,255," + a + ")" }
    function black(a) { return "rgba(0,0,0," + a + ")" }
    function grey(v, a) { var c = Math.round(v * 255); return "rgba(" + c + "," + c + "," + c + "," + (a === undefined ? 1 : a) + ")" }
    function heater(a) { return "rgba(255,133,41," + a + ")" }
    function core(a) { return "rgba(255,199,115," + a + ")" }

    // Centre the 120 x 200 grid, keeping its aspect
    function place(ctx, w, h) {
        var s = Math.min(h / 200, w / 120)
        ctx.translate(w / 2, (h - 200 * s) / 2)
        ctx.scale(s, s)
    }

    // Catmull-Rom through pts, from the current point
    function smooth(ctx, pts) {
        for (var i = 0; i < pts.length - 1; i++) {
            var p0 = pts[Math.max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(i + 2, pts.length - 1)]
            ctx.bezierCurveTo(p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6,
                              p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6, p2[0], p2[1])
        }
    }

    function envelope(ctx, g) {
        var left = g.profile.map(function(v) { return [-v[0], v[1]] })
        var right = g.profile.slice().reverse()
        var last = g.profile[g.profile.length - 1], k = 0.5523, rise = last[1] - g.top
        ctx.beginPath()
        ctx.moveTo(left[0][0], left[0][1])
        smooth(ctx, left)
        // An elliptical dome, a quarter each side of the crown
        ctx.bezierCurveTo(-last[0], last[1] - rise * k, -last[0] * k, g.top, 0, g.top)
        ctx.bezierCurveTo(last[0] * k, g.top, last[0], last[1] - rise * k, last[0], last[1])
        smooth(ctx, right)
        // The pressed glass button at the bottom bulges slightly
        ctx.quadraticCurveTo(0, g.profile[0][1] + 5, left[0][0], left[0][1])
        ctx.closePath()
    }

    function halfWidth(g, y) {
        var p = g.profile
        for (var i = 0; i < p.length - 1; i++)
            if (y <= p[i][1] && y >= p[i + 1][1]) {
                var t = (p[i][1] - y) / Math.max(p[i][1] - p[i + 1][1], 0.001)
                return p[i][0] + (p[i + 1][0] - p[i][0]) * t
            }
        return p[p.length - 1][0]
    }
    function widest(g) { return Math.max.apply(null, g.profile.map(function(v) { return v[0] })) }

    function hGradient(ctx, x0, x1, stops) {
        var gr = ctx.createLinearGradient(x0, 0, x1, 0)
        for (var i = 0; i < stops.length; i++) gr.addColorStop(stops[i][0], stops[i][1])
        return gr
    }
    function even(ctx, x0, x1, colors) {
        return hGradient(ctx, x0, x1, colors.map(function(c, i) { return [i / (colors.length - 1), c] }))
    }
    function line(ctx, x0, y0, x1, y1, color, width) {
        ctx.strokeStyle = color
        ctx.lineWidth = width
        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
    }
    // A soft round spot: stands in for the Windows Gaussian blur
    function spot(ctx, x, y, r, inner, outer) {
        var gr = ctx.createRadialGradient(x, y, 0, x, y, r)
        gr.addColorStop(0, inner)
        gr.addColorStop(1, outer)
        ctx.fillStyle = gr
        ctx.beginPath(); ctx.arc(x, y, r, 0, 2 * Math.PI); ctx.fill()
    }

    // ── Tube ──

    function drawTube(ctx, g) {
        var w = widest(g)

        // Contact shadow on the shelf (a squashed soft spot)
        ctx.save()
        ctx.translate(0, g.pinBottom + 0.5)
        ctx.scale(1, 4.5 / (w * 0.9 + 3))
        spot(ctx, 0, 0, w * 0.9 + 3, black(0.45), black(0))
        ctx.restore()

        // Pins
        for (var i = 0; i < g.pins.length; i++) {
            var x = g.pins[i], pw = g.pinWidth
            ctx.fillStyle = even(ctx, x - pw / 2, x + pw / 2, [grey(0.45), grey(0.85), grey(0.50)])
            ctx.beginPath(); ctx.roundedRect(x - pw / 2, g.pinTop - 2, pw, g.pinBottom - g.pinTop + 2, pw / 2, pw / 2); ctx.fill()
        }

        // Bakelite base (octal and DHT)
        if (g.base) {
            var b = g.base, r = 3.5
            if (b[4]) {
                ctx.fillStyle = "rgb(41,31,26)"
                ctx.beginPath(); ctx.roundedRect(-2.8, b[1] - 2, 5.6, 9, 1.5, 1.5); ctx.fill()
            }
            ctx.beginPath()
            ctx.moveTo(-b[2], b[0]); ctx.lineTo(b[2], b[0]); ctx.lineTo(b[3], b[1] - r)
            ctx.quadraticCurveTo(b[3], b[1], b[3] - r, b[1]); ctx.lineTo(-b[3] + r, b[1])
            ctx.quadraticCurveTo(-b[3], b[1], -b[3], b[1] - r); ctx.closePath()
            ctx.fillStyle = even(ctx, -b[2], b[2], ["rgb(23,18,15)", "rgb(64,48,38)", "rgb(28,20,18)"])
            ctx.fill()
            ctx.strokeStyle = white(0.14); ctx.lineWidth = 0.7; ctx.stroke()
            line(ctx, -b[2] + 1, b[0] + 1.2, b[2] - 1, b[0] + 1.2, white(0.18), 0.6)
        }

        if (g.metal) {
            // Steel can, its pressed ring and the sealing cap
            function steel(half) { return hGradient(ctx, -half, half, [[0, grey(0.30)], [0.28, grey(0.66)], [0.6, grey(0.48)], [1, grey(0.26)]]) }
            envelope(ctx, g); ctx.fillStyle = steel(w); ctx.fill()
            if (g.ring) {
                ctx.beginPath(); ctx.roundedRect(-w - 3, g.ring[0], (w + 3) * 2, g.ring[1] - g.ring[0], 2, 2)
                ctx.fillStyle = steel(w + 3); ctx.fill()
                ctx.strokeStyle = black(0.35); ctx.lineWidth = 0.6; ctx.stroke()
            }
            envelope(ctx, g); ctx.strokeStyle = white(0.25); ctx.lineWidth = 0.8; ctx.stroke()
            ctx.beginPath(); ctx.roundedRect(-7, g.top - 3, 14, 4, 1.5, 1.5)
            ctx.fillStyle = grey(0.55); ctx.fill()
            ctx.strokeStyle = black(0.3); ctx.lineWidth = 0.5; ctx.stroke()
            return
        }

        // Glass body: a faint cylinder shade, lighter at the rims
        envelope(ctx, g)
        ctx.fillStyle = black(0.22); ctx.fill()
        ctx.fillStyle = hGradient(ctx, -w, w, [[0, white(0.16)], [0.2, white(0.04)], [0.65, white(0.02)], [0.92, white(0.10)], [1, white(0.14)]])
        ctx.fill()

        // Inside the glass
        ctx.save()
        envelope(ctx, g)
        ctx.clip()
        for (i = 0; i < (g.rods || []).length; i++) {
            var rod = g.rods[i]
            line(ctx, rod[0], rod[1], rod[0], rod[2], white(0.32), 0.8)
        }
        for (i = 0; i < (g.plates || []).length; i++) drawPlate(ctx, g.plates[i])
        for (i = 0; i < (g.micas || []).length; i++) {
            var m = g.micas[i]
            ctx.fillStyle = white(0.38)
            ctx.beginPath(); ctx.roundedRect(-m[1], m[0] - 0.9, m[1] * 2, 1.8, 0.9, 0.9); ctx.fill()
        }
        if (g.filament) {
            // The unlit filament: a dull wire (the glow layer lights it)
            ctx.strokeStyle = white(0.45); ctx.lineWidth = 0.9; ctx.lineJoin = "round"
            ctx.beginPath(); ctx.moveTo(g.filament[0][0], g.filament[0][1])
            for (i = 1; i < g.filament.length; i++) ctx.lineTo(g.filament[i][0], g.filament[i][1])
            ctx.stroke()
        }
        if (g.getter) {
            // Getter flash: the silvered patch inside the crown
            var gf = ctx.createLinearGradient(0, g.getter[0], 0, g.getter[1])
            gf.addColorStop(0, grey(0.88)); gf.addColorStop(0.45, grey(0.62, 0.95)); gf.addColorStop(1, grey(0.40, 0))
            ctx.fillStyle = gf
            ctx.fillRect(-60, g.getter[0] - 2, 120, g.getter[1] - g.getter[0] + 2)
        }
        // Reflection down the left flank
        var reflTop = g.profile[g.profile.length - 1][1] - 2, reflBottom = g.profile[0][1] - 10
        var rf = ctx.createLinearGradient(0, reflTop, 0, reflBottom)
        rf.addColorStop(0, white(0.20)); rf.addColorStop(1, white(0.02))
        ctx.strokeStyle = rf; ctx.lineWidth = 2.5; ctx.lineCap = "round"
        ctx.beginPath()
        for (i = 0; i <= 12; i++) {
            var y = reflTop + (reflBottom - reflTop) * i / 12
            if (i === 0) ctx.moveTo(-halfWidth(g, y) + 5, y); else ctx.lineTo(-halfWidth(g, y) + 5, y)
        }
        ctx.stroke()
        ctx.restore()

        envelope(ctx, g)
        ctx.strokeStyle = white(0.5); ctx.lineWidth = 1.0; ctx.stroke()

        // Exhaust tip, where the glass was sealed off
        ctx.beginPath(); ctx.roundedRect(-2.6, g.top - 6, 5.2, 7.5, 2.6, 2.6)
        ctx.fillStyle = white(0.12); ctx.fill()
        ctx.strokeStyle = white(0.5); ctx.lineWidth = 0.9; ctx.stroke()
    }

    function drawPlate(ctx, p) {
        var r = p.r
        if (p.fins) {
            var sides = [r[0] - p.fins, r[0] + r[2]]
            for (var s = 0; s < 2; s++) {
                ctx.fillStyle = grey(0.30); ctx.fillRect(sides[s], r[1] + 4, p.fins, r[3] - 8)
                ctx.strokeStyle = white(0.18); ctx.lineWidth = 0.5; ctx.strokeRect(sides[s], r[1] + 4, p.fins, r[3] - 8)
            }
        }
        ctx.beginPath(); ctx.roundedRect(r[0], r[1], r[2], r[3], 1.2, 1.2)
        ctx.fillStyle = even(ctx, r[0], r[0] + r[2], [grey(0.20), grey(0.36), grey(0.24), grey(0.16)])
        ctx.fill()
        if (p.mesh) {
            ctx.save()
            ctx.beginPath(); ctx.roundedRect(r[0], r[1], r[2], r[3], 1.2, 1.2); ctx.clip()
            for (var x = r[0] - r[3]; x < r[0] + r[2]; x += 3.2) {
                line(ctx, x, r[1] + r[3], x + r[3], r[1], white(0.13), 0.45)
                line(ctx, x, r[1], x + r[3], r[1] + r[3], white(0.13), 0.45)
            }
            ctx.restore()
        }
        var ribs = p.ribs || []
        for (var i = 0; i < ribs.length; i++) {
            line(ctx, ribs[i], r[1] + 2, ribs[i], r[1] + r[3] - 2, black(0.45), 1.0)
            line(ctx, ribs[i] + 0.9, r[1] + 2, ribs[i] + 0.9, r[1] + r[3] - 2, white(0.14), 0.6)
        }
        ctx.beginPath(); ctx.roundedRect(r[0], r[1], r[2], r[3], 1.2, 1.2)
        ctx.strokeStyle = white(0.22); ctx.lineWidth = 0.6; ctx.stroke()
    }

    // ── Glow: the heater, or with `flare` the bloom laid over it ──

    function drawGlow(ctx, g, flare) {
        var colour = g.filament ? core : heater
        if (!g.metal && !flare) {
            envelope(ctx, g)
            ctx.fillStyle = heater(0.05)
            ctx.fill()
        }
        for (var i = 0; i < g.glows.length; i++) {
            var gl = g.glows[i], r = flare ? gl[2] * 1.7 : gl[2]
            var gr = ctx.createRadialGradient(gl[0], gl[1], 0, gl[0], gl[1], r)
            gr.addColorStop(0, colour((flare ? 0.35 : 0.55) * (g.metal ? 0.45 : 1)))
            gr.addColorStop(0.45, heater(flare ? 0.12 : 0.2))
            gr.addColorStop(1, heater(0))
            ctx.fillStyle = gr
            ctx.beginPath(); ctx.arc(gl[0], gl[1], r, 0, 2 * Math.PI); ctx.fill()
            if (flare || g.filament || g.metal) continue
            // The visible end of the heater: a hot streak with a soft edge
            spot(ctx, gl[0], gl[1], 4.5, heater(0.8), heater(0))
            ctx.fillStyle = core(1)
            ctx.beginPath(); ctx.roundedRect(gl[0] - 1.1, gl[1] - 2.6, 2.2, 5.2, 1.1, 1.1); ctx.fill()
        }
        if (g.filament) {
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            function wire(color, width) {
                ctx.strokeStyle = color; ctx.lineWidth = width
                ctx.beginPath(); ctx.moveTo(g.filament[0][0], g.filament[0][1])
                for (var j = 1; j < g.filament.length; j++) ctx.lineTo(g.filament[j][0], g.filament[j][1])
                ctx.stroke()
            }
            // Layered strokes for the blurred halo, then the hot wire
            var widths = flare ? [9, 6, 3.5] : [6, 4, 2.4]
            for (var k = 0; k < widths.length; k++) wire(heater(flare ? 0.18 : 0.22), widths[k])
            if (!flare) wire("rgb(255,230,179)", 1.0)
        }
    }

    component Layer: Canvas {
        anchors.fill: parent
        property string fam: art.family
        onFamChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Layer {
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width < 4 || height < 4) return
            art.place(ctx, width, height)
            art.drawTube(ctx, art.shape)
        }
    }
    // Heater: warms over 0.9 s, cools over 0.6 s
    Layer {
        opacity: art.lit ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: art.lit ? 900 : 600; easing.type: Easing.InOutSine } }
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width < 4 || height < 4) return
            art.place(ctx, width, height)
            art.drawGlow(ctx, art.shape, false)
        }
    }
    // Bloom: follows the loudest output the stage processes
    Layer {
        opacity: art.lit ? Math.max(0, Math.min(1, art.bloom)) : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width < 4 || height < 4) return
            art.place(ctx, width, height)
            art.drawGlow(ctx, art.shape, true)
        }
    }
}
