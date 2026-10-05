import QtQuick 2.15

// A stroke icon drawn in any colour. The SVG is built here with the colour
// baked in (no shader effects, so it also draws under the software renderer).
Item {
    id: icon
    property string name: ""
    property color color: Qt.rgba(1, 1, 1, 0.6)
    property int size: 18
    width: size
    height: size

    readonly property var shapes: ({
        "bassclef": '<path d="M5 9.5a5.5 5.5 0 0 1 11 0c0 5.5-5 9.5-11 11.5"/><circle cx="6.5" cy="9.5" r="1.6" fill="COLOR"/><circle cx="19.5" cy="7.5" r="0.9" fill="COLOR"/><circle cx="19.5" cy="12.5" r="0.9" fill="COLOR"/>',
        "gauge": '<path d="M3.5 17a9 9 0 1 1 17 0"/><line x1="12" y1="14" x2="16.5" y2="8.5"/><circle cx="12" cy="14" r="1.2" fill="COLOR"/>',
        "gear": '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
        "headphones": '<path d="M4 15v-3a8 8 0 0 1 16 0v3"/><rect x="2.5" y="14" width="4.5" height="7" rx="1.5"/><rect x="17" y="14" width="4.5" height="7" rx="1.5"/>',
        "info": '<circle cx="12" cy="12" r="9.5"/><line x1="12" y1="11" x2="12" y2="17"/><circle cx="12" cy="7.5" r="0.6" fill="COLOR"/>',
        "loudness": '<path d="M3 9.5h3.5L11 5.5v13l-4.5-4H3z"/><path d="M15 9.5c.9.7 1.4 1.6 1.4 2.5s-.5 1.8-1.4 2.5"/><path d="M18 7c1.7 1.3 2.6 3 2.6 5s-.9 3.7-2.6 5"/>',
        "win-min": '<line x1="6" y1="12" x2="18" y2="12"/>',
        "win-max": '<rect x="6" y="6" width="12" height="12" rx="1"/>',
        "win-restore": '<rect x="5" y="8.5" width="10.5" height="10.5" rx="1"/><path d="M8.5 8.5V6a1 1 0 0 1 1-1H18a1 1 0 0 1 1 1v8.5a1 1 0 0 1-1 1h-2.5"/>',
        "win-close": '<line x1="7" y1="7" x2="17" y2="17"/><line x1="17" y1="7" x2="7" y2="17"/>',
        "save": '<path d="M12 4v11"/><polyline points="7.5,10.5 12,15 16.5,10.5"/><path d="M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>',
        "revert": '<path d="M4 10a8 8 0 1 1 2.3 6.2"/><polyline points="4,4 4,10 10,10"/>',
        "chip": '<rect x="6" y="6" width="12" height="12" rx="2"/><line x1="9" y1="2.5" x2="9" y2="6"/><line x1="15" y1="2.5" x2="15" y2="6"/><line x1="9" y1="18" x2="9" y2="21.5"/><line x1="15" y1="18" x2="15" y2="21.5"/><line x1="2.5" y1="9" x2="6" y2="9"/><line x1="2.5" y1="15" x2="6" y2="15"/><line x1="18" y1="9" x2="21.5" y2="9"/><line x1="18" y1="15" x2="21.5" y2="15"/>',
        "warning": '<path d="M12 3.5l9 16H3z"/><line x1="12" y1="10" x2="12" y2="14"/><circle cx="12" cy="17" r="0.6" fill="COLOR"/>',
        "chev-up": '<polyline points="6,15 12,9 18,15"/>',
        "chev-down": '<polyline points="6,9 12,15 18,9"/>',
        "chev-left": '<polyline points="15,5 8,12 15,19"/>',
        "chev-right": '<polyline points="9,5 16,12 9,19"/>',
        "search": '<circle cx="10.5" cy="10.5" r="6.5"/><line x1="15.5" y1="15.5" x2="20.5" y2="20.5"/>',
        "spectrum": '<line x1="5" y1="20" x2="5" y2="13"/><line x1="9.67" y1="20" x2="9.67" y2="7"/><line x1="14.33" y1="20" x2="14.33" y2="10.5"/><line x1="19" y1="20" x2="19" y2="4.5"/>',
        "chart": '<polyline points="3,17 8,11 12,14 20,6"/><line x1="3" y1="21" x2="21" y2="21"/>',
        "wrench": '<path d="M14.5 4.5a4.5 4.5 0 0 0-4.3 5.8L4 16.5 7.5 20l6.2-6.2a4.5 4.5 0 0 0 5.8-4.3l-2.6 2.6-2.8-.4-.4-2.8z"/>',
        "globe": '<circle cx="12" cy="12" r="9"/><line x1="3" y1="12" x2="21" y2="12"/><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
        "output": '<rect x="3" y="5" width="11" height="14" rx="2"/><line x1="10" y1="12" x2="21" y2="12"/><polyline points="17.5,8.5 21,12 17.5,15.5"/>',
        "external": '<path d="M14 4h6v6"/><line x1="20" y1="4" x2="11" y2="13"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
        "pencil": '<path d="M4 20l1-4.5L15.5 5a2.1 2.1 0 0 1 3 3L8 18.5z"/><line x1="13.5" y1="7" x2="16.5" y2="10"/>',
        "copy": '<rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2"/><path d="M15.5 8.5V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5"/>',
        "paste": '<rect x="5" y="5" width="14" height="16" rx="2"/><rect x="9" y="3" width="6" height="4" rx="1"/><line x1="9" y1="12" x2="15" y2="12"/><line x1="9" y1="16" x2="13" y2="16"/>',
        "link": '<path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1.2 1.2"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1.2-1.2"/>',
        "menu": '<line x1="4" y1="6.5" x2="20" y2="6.5"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17.5" x2="20" y2="17.5"/>',
        "more": '<circle cx="5" cy="12" r="1.3" fill="COLOR"/><circle cx="12" cy="12" r="1.3" fill="COLOR"/><circle cx="19" cy="12" r="1.3" fill="COLOR"/>',
        "power": '<path d="M7.8 6.3a8 8 0 1 0 8.4 0"/><line x1="12" y1="2.5" x2="12" y2="11.5"/>',
        "sliders": '<line x1="5" y1="3" x2="5" y2="21"/><line x1="12" y1="3" x2="12" y2="21"/><line x1="19" y1="3" x2="19" y2="21"/><line x1="2.5" y1="15" x2="7.5" y2="15"/><line x1="9.5" y1="8" x2="14.5" y2="8"/><line x1="16.5" y1="13" x2="21.5" y2="13"/>',
        "speaker-mute": '<path d="M3 9.5h3.5L11 5.5v13l-4.5-4H3z"/><line x1="15" y1="9" x2="21" y2="15"/><line x1="21" y1="9" x2="15" y2="15"/>',
        "speaker": '<path d="M3 9.5h3.5L11 5.5v13l-4.5-4H3z"/><path d="M15 9.5c.9.7 1.4 1.6 1.4 2.5s-.5 1.8-1.4 2.5"/>',
        "subwave": '<path d="M2 11c2.7-7.5 7.3-7.5 10 0s7.3 7.5 10 0"/><line x1="2" y1="21" x2="22" y2="21"/>',
        "tube": '<path d="M5.5 17V8.5a6.5 6.5 0 0 1 13 0V17"/><line x1="12" y1="2" x2="12" y2="0.8"/><rect x="4.5" y="16.8" width="15" height="3.6" fill="COLOR" stroke="none"/><line x1="8.5" y1="20.4" x2="8.5" y2="23.2"/><line x1="12" y1="20.4" x2="12" y2="23.2"/><line x1="15.5" y1="20.4" x2="15.5" y2="23.2"/><line x1="10.5" y1="16.8" x2="10.5" y2="11"/><line x1="13.5" y1="16.8" x2="13.5" y2="11"/><path d="M10.5 11Q12 6.5 13.5 11"/>',
        "upmix": '<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/><line x1="12" y1="3.5" x2="12" y2="20.5"/><line x1="3.5" y1="12" x2="20.5" y2="12"/>',
        "input": '<path d="M12 3.5v10.5"/><polyline points="7.5,9.5 12,14 16.5,9.5"/><line x1="5" y1="19.5" x2="19" y2="19.5"/>',
        "pins": '<circle cx="6" cy="6" r="1.6" fill="COLOR" stroke="none"/><circle cx="12" cy="6" r="1.6" fill="COLOR" stroke="none"/><circle cx="18" cy="6" r="1.6" fill="COLOR" stroke="none"/><circle cx="6" cy="12" r="1.6" fill="COLOR" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="COLOR" stroke="none"/><circle cx="18" cy="12" r="1.6" fill="COLOR" stroke="none"/><circle cx="6" cy="18" r="1.6" fill="COLOR" stroke="none"/><circle cx="12" cy="18" r="1.6" fill="COLOR" stroke="none"/><circle cx="18" cy="18" r="1.6" fill="COLOR" stroke="none"/>',
        "clock": '<circle cx="12" cy="12" r="8.5"/><polyline points="12,7 12,12 15.5,14"/>',
        "waveform": '<polyline points="2,12 6,12 8.5,6 11,18 13.5,4 16,20 18,12 22,12"/>',
        "xmark": '<line x1="5" y1="5" x2="19" y2="19"/><line x1="19" y1="5" x2="5" y2="19"/>'
    })

    function svgColor(c) {
        function hex(v) { var h = Math.round(v * 255).toString(16); return h.length < 2 ? "0" + h : h }
        return "#" + hex(c.r) + hex(c.g) + hex(c.b)
    }

    Image {
        anchors.fill: parent
        opacity: icon.color.a
        sourceSize: Qt.size(icon.size * 2, icon.size * 2)
        smooth: true
        source: {
            var body = icon.shapes[icon.name]
            if (!body) return ""
            var c = icon.svgColor(icon.color)
            var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
                    + 'stroke="' + c + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
                    + body.replace(/COLOR/g, c) + '</svg>'
            return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
        }
    }
}
