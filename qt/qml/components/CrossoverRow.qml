import QtQuick 2.15
import QtQuick.Controls 2.15

// One crossover band on an output's XO tab: FAMILY, TYPE, SLOPE, FREQ.
Rectangle {
    id: xoRoot
    height: 36
    color: bandIndex % 2 === 0 ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

    property int channelId: 2
    property int bandIndex: 0
    property int filterType: bridge.crossoverType(channelId, bandIndex)
    property real filterFreq: bridge.crossoverFreq(channelId, bandIndex)
    property bool filterBypass: bridge.crossoverBypass(channelId, bandIndex)

    Connections {
        target: bridge
        function onStateChanged() {
            xoRoot.filterType = bridge.crossoverType(xoRoot.channelId, xoRoot.bandIndex)
            xoRoot.filterFreq = bridge.crossoverFreq(xoRoot.channelId, xoRoot.bandIndex)
            xoRoot.filterBypass = bridge.crossoverBypass(xoRoot.channelId, xoRoot.bandIndex)
        }
    }

    // Family 0 = Off, 1 = Linkwitz-Riley, 2 = Butterworth, 3 = Bessel
    readonly property var familyNames: ["Off", "Linkwitz-Riley", "Butterworth", "Bessel"]
    readonly property var familyOrders: [[], [2, 4, 6, 8], [1, 2, 3, 4, 5, 6, 7, 8], [2, 4, 6, 8]]

    function decode(t) {
        if (t < 32 || t > 63) return { family: 0, order: 4, hp: false }
        var rel = t - 32, hp = (rel & 1) === 1, pair = rel >> 1
        if (pair <= 3) return { family: 1, order: (pair + 1) * 2, hp: hp }
        if (pair <= 11) return { family: 2, order: pair - 3, hp: hp }
        return { family: 3, order: (pair - 11) * 2, hp: hp }
    }
    function encode(family, order, hp) {
        if (family === 0) return 0
        var base = family === 1 ? 32 + (order / 2 - 1) * 2
                 : family === 2 ? 40 + (order - 1) * 2
                 : 56 + (order / 2 - 1) * 2
        return base + (hp ? 1 : 0)
    }
    function nearestOrder(family, order) {
        var opts = familyOrders[family], best = opts[0]
        for (var i = 0; i < opts.length; i++)
            if (Math.abs(opts[i] - order) < Math.abs(best - order)) best = opts[i]
        return best
    }

    readonly property var meta: decode(filterType)
    readonly property bool isActive: meta.family !== 0

    opacity: filterBypass ? 0.45 : 1.0

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        BypassDot {
            active: xoRoot.isActive
            bypassed: xoRoot.filterBypass
            dotColor: isMacOS ? Qt.rgba(0.5, 0.5, 0.5, 1) : "#3a96dd"
            anchors.verticalCenter: parent.verticalCenter
            onToggled: bridge.setCrossoverBypass(xoRoot.channelId, xoRoot.bandIndex, !xoRoot.filterBypass)
        }

        Text {
            width: 24
            leftPadding: isMacOS ? 12 : 0     // macOS: the native 12 pt gap after the dot
            text: (bandIndex + 1).toString()
            font.pixelSize: 12
            font.family: root.monoFont
            color: isMacOS ? (xoRoot.isActive ? MacColors.label : MacColors.opacity(MacColors.secondaryLabel, 0.5)) : Qt.rgba(1, 1, 1, 0.4)
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledComboBox {
            width: 140; height: 30
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 12
            model: familyNames
            currentIndex: meta.family
            onActivated: {
                if (index === 0) {
                    bridge.setCrossover(channelId, bandIndex, 0, filterFreq)
                } else {
                    var order = nearestOrder(index, meta.family === 0 ? 4 : meta.order)
                    bridge.setCrossover(channelId, bandIndex, encode(index, order, meta.hp), filterFreq)
                }
            }
        }

        StyledComboBox {
            visible: isActive
            width: 110; height: 30
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 12
            model: ["Low Pass", "High Pass"]
            currentIndex: meta.hp ? 1 : 0
            onActivated: bridge.setCrossover(channelId, bandIndex, encode(meta.family, meta.order, index === 1), filterFreq)
        }

        StyledComboBox {
            id: slopeCombo
            visible: isActive
            width: 110; height: 30
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 12
            model: isActive ? familyOrders[meta.family].map(function (o) { return (o * 6) + " dB/oct" }) : []
            currentIndex: isActive ? familyOrders[meta.family].indexOf(meta.order) : -1
            onActivated: bridge.setCrossover(channelId, bandIndex,
                                             encode(meta.family, familyOrders[meta.family][index], meta.hp), filterFreq)
        }


        ValueField {
            visible: isActive
            fieldWidth: 70; height: 28; suffix: "Hz"; decimals: 1; wheelStep: 10; minValue: 10; maxValue: 20000
            value: filterFreq
            anchors.verticalCenter: parent.verticalCenter
            onValueEdited: bridge.setCrossover(channelId, bandIndex, filterType, newValue)
        }
    }
}
