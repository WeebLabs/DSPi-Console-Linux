import QtQuick 2.15

// The Stereo Upmixer's soundstage: a listening room seen from above, with
// the speakers the current engines feed. L and R are always there; a centre
// engine adds C, a surround engine adds Ls and Rs (an engine that is off
// leaves a dashed outline). Each channel's waves glow with its live gain.
// The room is painted once per configuration and size; only the wave
// opacities follow the audio.
Item {
    id: stage
    property bool active: false        // upmixer enabled
    property bool centerOn: false
    property bool surroundOn: false
    property bool live: false          // processing audio
    property real centerGain: 0        // 0..1, live
    property real lsGain: 0
    property real rsGain: 0

    readonly property color lColor: "#4A8FE3"
    readonly property color rColor: "#F57373"
    readonly property color cColor: "#32d74b"
    readonly property color lsColor: "#bf5af2"
    readonly property color rsColor: "#ff375f"

    // Design grid: 300 x 220, scaled to fit and centred
    readonly property real scaleFactor: Math.min(width / 300, height / 220)
    readonly property real originX: (width - 300 * scaleFactor) / 2
    readonly property real originY: (height - 220 * scaleFactor) / 2

    // Speakers on a circle around the listener at the usual surround angles
    // (C ahead, L/R at 30 degrees, Ls/Rs at 110 degrees)
    readonly property var listener: [150, 116]
    readonly property real ringRadius: 84
    readonly property var angles: ({ C: 0, L: -30, R: 30, Ls: -110, Rs: 110 })
    function spot(name) {
        var a = angles[name] * Math.PI / 180
        return [listener[0] + ringRadius * Math.sin(a), listener[1] - ringRadius * Math.cos(a)]
    }

    function place(ctx) {
        ctx.translate(originX, originY)
        ctx.scale(scaleFactor, scaleFactor)
    }
    function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }

    // ── Room, listener, speakers ──

    function drawRoom(ctx) {
        // The circle the speakers sit on
        ctx.strokeStyle = "rgba(255,255,255,0.08)"
        ctx.lineWidth = 1
        ctx.beginPath(); ctx.arc(listener[0], listener[1], ringRadius, 0, 2 * Math.PI); ctx.stroke()
        // and a smaller one for the sweet spot
        ctx.setLineDash([2, 4])
        ctx.strokeStyle = "rgba(255,255,255,0.10)"
        ctx.beginPath(); ctx.arc(listener[0], listener[1], 26, 0, 2 * Math.PI); ctx.stroke()
        ctx.setLineDash([])
    }

    function drawListener(ctx) {
        var x = listener[0], y = listener[1]
        ctx.fillStyle = "rgba(255,255,255,0.10)"
        ctx.strokeStyle = "rgba(255,255,255,0.45)"
        ctx.lineWidth = 1
        ctx.beginPath(); ctx.arc(x, y, 9, 0, 2 * Math.PI); ctx.fill(); ctx.stroke()
        // Facing the front
        ctx.fillStyle = "rgba(255,255,255,0.6)"
        ctx.beginPath(); ctx.moveTo(x - 3.5, y - 11); ctx.lineTo(x, y - 16); ctx.lineTo(x + 3.5, y - 11); ctx.closePath(); ctx.fill()
    }

    // A speaker: a rounded block turned to face the listener, its front edge lit
    function drawSpeaker(ctx, name, tint, present) {
        var p = spot(name)
        var w = name === "C" ? 30 : 20, h = name === "C" ? 11 : 13
        ctx.save()
        ctx.translate(p[0], p[1])
        ctx.rotate(angles[name] * Math.PI / 180)
        if (present) {
            ctx.fillStyle = rgba(tint, 0.9)
            ctx.beginPath(); ctx.roundedRect(-w / 2, -h / 2, w, h, 3.5, 3.5); ctx.fill()
            // Front edge, toward the listener
            ctx.strokeStyle = "rgba(255,255,255,0.75)"
            ctx.lineWidth = 1.4
            ctx.lineCap = "round"
            ctx.beginPath(); ctx.moveTo(-w / 2 + 4, h / 2 - 1.6); ctx.lineTo(w / 2 - 4, h / 2 - 1.6); ctx.stroke()
        } else {
            // An engine that is off: just where its speaker would be
            ctx.setLineDash([2.5, 2.5])
            ctx.strokeStyle = "rgba(255,255,255,0.22)"
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.roundedRect(-w / 2, -h / 2, w, h, 3.5, 3.5); ctx.stroke()
            ctx.setLineDash([])
        }
        ctx.restore()
        // Label just outside the circle
        var a = angles[name] * Math.PI / 180, r = ringRadius + 20
        label(ctx, listener[0] + r * Math.sin(a), listener[1] - r * Math.cos(a) + 3.5, name,
              present ? rgba(tint, 0.95) : "rgba(255,255,255,0.28)")
    }

    function label(ctx, x, y, text, color) {
        ctx.fillStyle = color
        ctx.font = "bold 10px sans-serif"
        ctx.textAlign = "center"
        ctx.fillText(text, x, y)
    }

    // ── Waves: three arcs from the speaker toward the listener ──

    function drawWaves(ctx, name, tint) {
        var p = spot(name)
        var dir = Math.atan2(listener[1] - p[1], listener[0] - p[0])
        ctx.lineCap = "round"
        for (var i = 0; i < 3; i++) {
            ctx.strokeStyle = rgba(tint, 0.85 - i * 0.25)
            ctx.lineWidth = 1.4
            ctx.beginPath()
            ctx.arc(p[0], p[1], 16 + i * 12, dir - 0.38, dir + 0.38)
            ctx.stroke()
        }
        // A soft halo around the speaker
        var g = ctx.createRadialGradient(p[0], p[1], 0, p[0], p[1], 26)
        g.addColorStop(0, rgba(tint, 0.28))
        g.addColorStop(1, rgba(tint, 0))
        ctx.fillStyle = g
        ctx.beginPath(); ctx.arc(p[0], p[1], 26, 0, 2 * Math.PI); ctx.fill()
    }

    component WaveLayer: Canvas {
        property string channel: ""
        property color tint: "white"
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width < 4 || height < 4) return
            stage.place(ctx)
            stage.drawWaves(ctx, channel, tint)
        }
    }

    // Waves under the room's speakers. L and R carry the program while the
    // upmixer runs; the derived channels follow their live gains.
    WaveLayer {
        channel: "L"; tint: stage.lColor
        opacity: stage.live ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
    WaveLayer {
        channel: "R"; tint: stage.rColor
        opacity: stage.live ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
    WaveLayer {
        channel: "C"; tint: stage.cColor
        opacity: stage.live && stage.centerOn ? Math.min(1, stage.centerGain * 1.3) : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }
    WaveLayer {
        channel: "Ls"; tint: stage.lsColor
        opacity: stage.live && stage.surroundOn ? Math.min(1, stage.lsGain * 1.6) : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }
    WaveLayer {
        channel: "Rs"; tint: stage.rsColor
        opacity: stage.live && stage.surroundOn ? Math.min(1, stage.rsGain * 1.6) : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    // The room: repainted only when the configuration or size changes
    Canvas {
        anchors.fill: parent
        property string config: [stage.active, stage.centerOn, stage.surroundOn].join()
        onConfigChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width < 4 || height < 4) return
            stage.place(ctx)
            stage.drawRoom(ctx)
            var c = stage.active && stage.centerOn, s = stage.active && stage.surroundOn
            stage.drawSpeaker(ctx, "Ls", stage.lsColor, s)
            stage.drawSpeaker(ctx, "Rs", stage.rsColor, s)
            stage.drawSpeaker(ctx, "L", stage.lColor, true)
            stage.drawSpeaker(ctx, "R", stage.rColor, true)
            stage.drawSpeaker(ctx, "C", stage.cColor, c)
            stage.drawListener(ctx)
        }
    }
}
