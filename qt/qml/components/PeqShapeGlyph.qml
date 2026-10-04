import QtQuick 2.15

// A filter's shape as a tiny line drawing (the band HUD and shape card).
// type: firmware filter type. Painted once per type and colour.
Canvas {
    id: glyph
    property int type: 1
    property color color: "white"
    property real lineWidth: 1.4
    implicitWidth: 18
    implicitHeight: 12
    onTypeChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width, h = height, m = lineWidth
        function P(x, y) { return [m + x * (w - 2 * m), m + y * (h - 2 * m)] }
        function mv(x, y) { var p = P(x, y); ctx.moveTo(p[0], p[1]) }
        function ln(x, y) { var p = P(x, y); ctx.lineTo(p[0], p[1]) }
        function cv(a, b, c, d, e, f) { var p = P(a, b), q = P(c, d), r = P(e, f); ctx.bezierCurveTo(p[0], p[1], q[0], q[1], r[0], r[1]) }
        ctx.strokeStyle = color
        ctx.lineWidth = lineWidth
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        switch (type) {
        case 1: mv(0, 0.85); cv(0.35, 0.85, 0.38, 0.05, 0.5, 0.05); cv(0.62, 0.05, 0.65, 0.85, 1, 0.85); break    // bell
        case 6: mv(0, 0.15); cv(0.4, 0.15, 0.45, 1, 0.5, 1); cv(0.55, 1, 0.6, 0.15, 1, 0.15); break                // notch
        case 2: case 9: mv(0, 0.15); ln(0.3, 0.15); cv(0.5, 0.15, 0.5, 0.85, 0.7, 0.85); ln(1, 0.85); break        // low shelf
        case 3: case 10: mv(0, 0.85); ln(0.3, 0.85); cv(0.5, 0.85, 0.5, 0.15, 0.7, 0.15); ln(1, 0.15); break       // high shelf
        case 5: case 13: mv(0.05, 1); cv(0.3, 0.3, 0.45, 0.2, 0.6, 0.2); ln(1, 0.2); break                         // low cut
        case 4: case 12: mv(0, 0.2); ln(0.4, 0.2); cv(0.55, 0.2, 0.7, 0.3, 0.95, 1); break                         // high cut
        case 7: case 8: mv(0, 0.5); cv(0.25, 0, 0.25, 0, 0.5, 0.5); cv(0.75, 1, 0.75, 1, 1, 0.5); break             // all-pass
        default: mv(0, 0.85); cv(0.3, 0.85, 0.6, 0.15, 1, 0.15)                                                       // Linkwitz
        }
        ctx.stroke()
    }
}
