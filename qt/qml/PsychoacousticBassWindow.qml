import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// Psychoacoustic Bass: phantom fundamental bass enhancement.
AppWindow {
    id: win
    fitHeight: header.height + flick.contentHeight
    title: "Psychoacoustic Bass"
    visible: false
    width: 720
    height: 520 + titlebarHeight
    minimumWidth: 640
    minimumHeight: 360 + titlebarHeight

    readonly property int numOut: bridge.numOutputChannels
    readonly property int pdm: numOut - 1

    // Apply preset: cutoff, harmonics, drive, character, original (macOS values)
    readonly property var presets: [
        { name: "Bookshelf Speakers",  detail: "Gentle low-end help",       v: [60, 0, 6, 50, 0] },
        { name: "Small Bluetooth",     detail: "Portable speaker",           v: [100, 3, 9, 40, -12] },
        { name: "Laptop / Tablet",     detail: "Tiny drivers, protect them", v: [180, 6, 12, 50, -24] },
        { name: "Headphone Bass Feel", detail: "Extra sub sensation",        v: [45, -3, 6, 30, 0] }]

    function applyPreset(p) {
        for (var i = 0; i < 5; i++) bridge.setPsybassParam(i, p.v[i])
    }
    function outputNames() {
        var n = []
        for (var o = 0; o < numOut; o++) n.push(bridge.channelName(o + 2))
        return n
    }

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }
    component Divider: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
    // "Presets ⌄" link that opens an ActionMenu under itself
    component MenuLink: Item {
        id: link
        property string text: ""
        property ActionMenu menu
        width: linkRow.width
        height: linkRow.height
        Row {
            id: linkRow
            spacing: 4
            Text {
                text: link.text
                font.pixelSize: 12
                color: linkMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.75)
            }
            Icon { name: "chev-down"; size: 11; color: Qt.rgba(1, 1, 1, 0.6); anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: link.menu.openAt(link, 0, link.height + 4)
        }
    }

    ToolHeader {
        id: header
        width: parent.width
        icon: "loudness"
        title: "Psychoacoustic Bass"
        subtitle: "Phantom fundamental bass enhancement"
        checked: bridge.psybassEnabled
        onToggled: bridge.setPsybassEnabled(enable)
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

            // ── Left: spectrum + harmonics ──
            Column {
                width: columns.colWidth
                spacing: 12

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "SPECTRUM"; anchors.verticalCenter: parent.verticalCenter }
                    MenuLink {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Apply Preset"
                        menu: spectrumPresetMenu
                    }
                }

                // Diagram of the effect (not a measurement)
                Rectangle {
                    width: parent.width
                    height: 190
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.2)
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    Canvas {
                        id: spectrum
                        anchors.fill: parent
                        anchors.margins: 12
                        // Follow the sliders during a drag
                        property real fc: cutoffRow.displayValue
                        property real harm: harmonicsRow.displayValue
                        property real orig: originalRow.displayValue
                        property bool active: bridge.psybassEnabled
                        onFcChanged: requestPaint()
                        onHarmChanged: requestPaint()
                        onOrigChanged: requestPaint()
                        onActiveChanged: requestPaint()
                        onWidthChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var w = width, h = height - 18
                            var lo = Math.log(20), hi = Math.log(20000)
                            function xOf(f) { return (Math.log(f) - lo) / (hi - lo) * w }

                            // Decade grid and labels
                            ctx.strokeStyle = "rgba(255,255,255,0.08)"
                            ctx.fillStyle = "rgba(255,255,255,0.45)"
                            ctx.font = "10px sans-serif"
                            ctx.textAlign = "center"
                            var marks = [[100, "100"], [1000, "1k"], [10000, "10k"]]
                            for (var i = 0; i < marks.length; i++) {
                                var x = xOf(marks[i][0])
                                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke()
                                ctx.fillText(marks[i][1], x, h + 13)
                            }
                            ctx.beginPath(); ctx.moveTo(0, h); ctx.lineTo(w, h); ctx.stroke()

                            if (!active) {
                                ctx.fillStyle = "rgba(255,255,255,0.35)"
                                ctx.font = "12px sans-serif"
                                ctx.fillText("Disabled", w / 2, h / 2)
                                return
                            }

                            // Original bass below fc (0 dB = full height, -60 dB = none)
                            var xfc = xOf(fc), x4 = xOf(Math.min(20000, fc * 4))
                            var oh = Math.max(0, Math.min(1, (orig + 60) / 60)) * h
                            ctx.fillStyle = "#1f4a8c"
                            ctx.fillRect(0, h - oh, xfc, oh)
                            // Harmonics fc..4fc (-24..+12 dB)
                            var hh = Math.max(0, Math.min(1, (harm + 24) / 36)) * h
                            ctx.fillStyle = "#a8691f"
                            ctx.fillRect(xfc, h - hh, x4 - xfc, hh)

                            // fc / 4fc markers
                            ctx.setLineDash([3, 3])
                            ctx.strokeStyle = "rgba(255,255,255,0.45)"
                            ctx.beginPath(); ctx.moveTo(xfc, 0); ctx.lineTo(xfc, h); ctx.stroke()
                            ctx.beginPath(); ctx.moveTo(x4, 0); ctx.lineTo(x4, h); ctx.stroke()
                            ctx.setLineDash([])
                            ctx.fillStyle = "rgba(255,255,255,0.5)"
                            ctx.fillText("fc", xfc, 11)
                            ctx.fillText("4fc", x4, 11)
                        }
                    }

                    // Legend
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 16
                        width: legend.width + 12
                        height: legend.height + 10
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.35)
                        Column {
                            id: legend
                            anchors.centerIn: parent
                            spacing: 4
                            Row { spacing: 6; Rectangle { width: 10; height: 8; radius: 2; color: "#2b6fd6"; anchors.verticalCenter: parent.verticalCenter }
                                  Text { text: "Original"; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.85) } }
                            Row { spacing: 6; Rectangle { width: 10; height: 8; radius: 2; color: "#e8901f"; anchors.verticalCenter: parent.verticalCenter }
                                  Text { text: "Harmonics"; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.85) } }
                        }
                    }
                }

                Divider {}
                SectionLabel { text: "HARMONICS" }

                ParamRow {
                    id: cutoffRow
                    label: "Cutoff Frequency"; unit: "Hz"; from: 30; to: 300; stepSize: 1; decimals: 0
                    value: bridge.psybassCutoff
                    caption: "The speaker's low-frequency limit. Content below this feeds the harmonic generator; generated harmonics span roughly this to 4x."
                    onLiveChanged: bridge.setPsybassParam(0, v, true)
                    onCommitted: bridge.setPsybassParam(0, v)
                }
                Divider {}
                ParamRow {
                    id: harmonicsRow
                    label: "Harmonics"; unit: "dB"; from: -24; to: 12; stepSize: 0.5
                    value: bridge.psybassHarmonics
                    caption: "Level of the synthesized harmonics. The primary amount-of-effect control. Higher = more perceived bass."
                    onLiveChanged: bridge.setPsybassParam(1, v, true)
                    onCommitted: bridge.setPsybassParam(1, v)
                }
            }

            Rectangle { width: 1; height: columns.height; color: Qt.rgba(1, 1, 1, 0.08) }

            // ── Right: outputs + shaping ──
            Column {
                width: columns.colWidth
                spacing: 12

                Item {
                    width: parent.width
                    height: 20
                    SectionLabel { text: "OUTPUTS"; anchors.verticalCenter: parent.verticalCenter }
                    MenuLink {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Presets"
                        menu: outputPresetMenu
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.5)
                    text: "Enhance only the small-speaker outputs. Mask off the sub and any full-range outputs: synthesizing harmonics on a channel that can reproduce real bass is counterproductive."
                }

                ChannelChips {
                    width: parent.width
                    count: win.numOut
                    mask: bridge.psybassOutputMask
                    names: outputNames()
                    onMaskEdited: bridge.setPsybassOutputMask(mask)
                }

                Divider {}
                SectionLabel { text: "SHAPING" }

                ParamRow {
                    label: "Drive"; unit: "dB"; from: 0; to: 18; stepSize: 0.5
                    value: bridge.psybassDrive
                    caption: "Pre-gain into the odd-harmonic soft clipper. Higher makes the effect audible on quieter passages. Mostly affects aggressive character."
                    onLiveChanged: bridge.setPsybassParam(2, v, true)
                    onCommitted: bridge.setPsybassParam(2, v)
                }
                Divider {}
                ParamRow {
                    label: "Character"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0
                    leftHint: "Warm"; rightHint: "Aggressive"
                    value: bridge.psybassCharacter
                    onLiveChanged: bridge.setPsybassParam(3, v, true)
                    onCommitted: bridge.setPsybassParam(3, v)
                }
                Divider {}
                ParamRow {
                    id: originalRow
                    label: "Original Bass"; unit: "dB"; from: -60; to: 0; stepSize: 0.5
                    value: bridge.psybassOriginal
                    caption: "Level of the un-reproducible fundamental below the cutoff. Lower attenuates it, freeing driver excursion and headroom. -60 dB is full removal. Speaker protection."
                    onLiveChanged: bridge.setPsybassParam(4, v, true)
                    onCommitted: bridge.setPsybassParam(4, v)
                }
            }
        }
    }

    ActionMenu {
        id: spectrumPresetMenu
        parent: Overlay.overlay
        items: win.presets.map(function(p, i) { return { key: String(i), text: p.name, shortcut: p.detail } })
        onTriggered: win.applyPreset(win.presets[Number(key)])
    }

    ActionMenu {
        id: outputPresetMenu
        parent: Overlay.overlay
        items: [
            { key: "all", text: "All Outputs" },
            { key: "nosub", text: "Exclude Sub (Recommended)" },
            { key: "none", text: "None" }
        ]
        onTriggered: {
            var all = (1 << win.numOut) - 1
            if (key === "all") bridge.setPsybassOutputMask(all)
            else if (key === "nosub") bridge.setPsybassOutputMask(all & ~(1 << win.pdm))
            else if (key === "none") bridge.setPsybassOutputMask(0)
        }
    }
}
