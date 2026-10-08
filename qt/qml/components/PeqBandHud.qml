import QtQuick 2.15
import QtQuick.Controls 2.15

// The on-graph band panel: shape button (opens the shape card), bypass, and
// the band's values, editable by typing or the wheel. Placed above a boost
// or below a cut, kept inside the graph; held open while the pointer is on it.
Rectangle {
    id: hud
    property var editor                  // PeqEditorItem
    // The shape page replaces the values while choosing a shape
    property bool shapePage: false
    onBandChanged: { shapePage = false; shapeChooser.reset() }
    // Held open while the pointer is on it, a shape is being picked, or a value typed
    readonly property bool held: shapePage || hoverHandler.hovered || freqField.editing || gainField.editing || qField.editing
    onHeldChanged: if (editor) editor.hudHold = held
    Connections {
        target: hud.editor
        function onEditFrequencyRequested() { if (!hud.linkwitz) freqField.beginEdit() }
    }

    readonly property var v: editor ? editor.hudValues : ({})
    readonly property int band: v.band !== undefined ? v.band : -1
    readonly property int type: v.type || 0
    readonly property bool bypass: v.bypass === true
    readonly property color tint: v.color || "white"
    readonly property var codes: ({ 1: "PK", 2: "LS", 9: "LS", 3: "HS", 10: "HS", 4: "HC", 12: "HC",
                                    5: "LC", 13: "LC", 6: "NT", 7: "AP", 8: "AP", 11: "LT" })
    readonly property bool firstOrderCut: type === 12 || type === 13
    readonly property bool linkwitz: type === 11

    width: 110
    // The shape page needs room for two rows of shapes
    height: shapePage ? Math.max(valuesHeight, 64) : valuesHeight
    readonly property real valuesHeight: header.height + rows.height + 6
    radius: 8
    color: "#1e1e21"
    border.color: Qt.rgba(1, 1, 1, 0.10)
    visible: opacity > 0
    opacity: editor && editor.active && band >= 0 ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: hud.opacity > 0 ? 150 : 120 } }

    // Position by the dot: above a boost, below a cut, then the sides
    readonly property point dot: editor ? editor.hudPoint : Qt.point(0, 0)
    readonly property real gap: 16
    x: {
        if (!editor) return 0
        var fits = dot.y - gap - height >= 4 && dot.y + gap + height <= editor.height - 4
        var px = fits || (editor.hudBoost ? dot.y - gap - height >= 4 : dot.y + gap + height <= editor.height - 4)
                 ? dot.x - width / 2
                 : (dot.x + gap + width < editor.width ? dot.x + gap : dot.x - gap - width)
        return Math.max(4, Math.min(px, editor.width - width - 4))
    }
    y: {
        if (!editor) return 0
        var above = dot.y - gap - height, below = dot.y + gap
        var py = editor.hudBoost ? (above >= 4 ? above : below) : (below + height <= editor.height - 4 ? below : above)
        if (py < 4 || py + height > editor.height - 4) py = dot.y - height / 2
        return Math.max(4, Math.min(py, editor.height - height - 4))
    }

    // Soft shadow
    Repeater {
        model: 3
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -(index + 1)
            anchors.topMargin: -(index + 1) + 2
            radius: hud.radius + index + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.18 - index * 0.05)
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    PeqShapeChooser {
        id: shapeChooser
        visible: hud.shapePage
        anchors.fill: parent
        ownType: hud.type
        markColor: isMacOS ? (hud.bypass ? Qt.rgba(1, 1, 1, 0.4) : hud.tint) : hud.tint
        backTip: "Back to the band"
        onBack: hud.shapePage = false
        onPicked: { hud.editor.setBandType(hud.band, type); hud.shapePage = false }
    }

    // Header: shape button and bypass
    Item {
        id: header
        visible: !hud.shapePage
        width: parent.width
        height: 22
        Rectangle {
            id: shapeButton
            x: 3
            anchors.verticalCenter: parent.verticalCenter
            width: shapeRow.width + 10
            height: 18
            radius: 5
            color: isMacOS ? (shapeMouse.containsMouse && !hud.linkwitz ? Qt.rgba(1, 1, 1, 0.09) : "transparent") : shapeMouse.containsMouse && !hud.linkwitz ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            Row {
                id: shapeRow
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                PeqShapeGlyph { type: hud.type; color: isMacOS ? (hud.bypass ? Qt.rgba(1, 1, 1, 0.4) : hud.tint) : hud.tint; width: 16; height: 10; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: hud.codes[hud.type] || "?"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: isMacOS ? Qt.rgba(1, 1, 1, hud.linkwitz ? 0.7 : hud.bypass ? 0.5 : 0.85) : hud.tint
                    anchors.verticalCenter: parent.verticalCenter
                }
                Icon { visible: !hud.linkwitz; name: "chev-down"; size: 9; color: isMacOS ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(1, 1, 1, 0.5); anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: shapeMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !hud.linkwitz
                cursorShape: Qt.PointingHandCursor
                onClicked: { shapeChooser.reset(); hud.shapePage = true }
            }
            ToolTip.visible: shapeMouse.containsMouse
            ToolTip.delay: 600
            ToolTip.text: "Change the filter shape"
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 5
            color: isMacOS ? (powerMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent") : powerMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            Icon {
                anchors.centerIn: parent
                name: "power"
                size: 11
                color: isMacOS ? (hud.bypass ? Qt.rgba(1, 1, 1, 0.4) : hud.tint) : hud.bypass ? Qt.rgba(1, 1, 1, 0.35) : hud.tint
            }
            MouseArea {
                id: powerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: hud.editor.toggleBypass(hud.band)
            }
            ToolTip.visible: powerMouse.containsMouse
            ToolTip.delay: 600
            ToolTip.text: hud.bypass ? "Enable this band" : "Bypass this band"
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: isMacOS ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.08) }
    }

    component Label: Text {
        font.pixelSize: 9
        color: isMacOS ? Qt.rgba(1, 1, 1, hud.bypass ? 0.28 / 0.6 : 0.45) : Qt.rgba(1, 1, 1, hud.bypass ? 0.3 : 0.45)
        anchors.verticalCenter: parent.verticalCenter
    }
    component ReadRow: Item {
        property string label: ""
        property string value: ""
        width: rows.width
        height: 16
        Label { text: parent.label }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            font.pixelSize: 10
            color: isMacOS ? Qt.rgba(1, 1, 1, hud.bypass ? 0.45 / 0.6 : 0.45) : Qt.rgba(1, 1, 1, hud.bypass ? 0.45 : 0.88)
        }
    }

    Column {
        id: rows
        visible: !hud.shapePage
        x: 7
        y: header.height + 2
        width: parent.width - 9
        opacity: hud.bypass ? 0.6 : 1

        // Frequency in Hz below 1 kHz, kHz above
        Item {
            visible: !hud.linkwitz
            width: rows.width
            height: 16
            readonly property bool khz: (hud.v.freq || 0) >= 1000
            Label { text: "Freq" }
            ValueField {
                id: freqField
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                fieldWidth: 44
                height: 18
                fontSize: 10
                plainWheel: true
                suffix: parent.khz ? "kHz" : "Hz"
                decimals: parent.khz ? 2 : 1
                wheelStep: parent.khz ? 0.05 : 1
                minValue: parent.khz ? 1 : 10
                maxValue: parent.khz ? 21.6 : 21600
                value: parent.khz ? hud.v.freq / 1000 : (hud.v.freq || 0)
                onValueEdited: hud.editor.setBandValue(hud.band, "freq", parent.khz && newValue < 1000 ? newValue * 1000 : newValue)
            }
        }
        Item {
            visible: hud.v.usesGain === true
            width: rows.width
            height: 16
            Label { text: "Gain" }
            ValueField {
                id: gainField
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                fieldWidth: 44
                height: 18
                fontSize: 10
                plainWheel: true
                suffix: "dB"
                decimals: 1
                wheelStep: 0.5
                minValue: -30
                maxValue: 30
                value: hud.v.gain || 0
                onValueEdited: hud.editor.setBandValue(hud.band, "gain", newValue)
            }
        }
        Item {
            visible: hud.v.usesQ === true
            width: rows.width
            height: 16
            Label { text: "Width" }
            ValueField {
                id: qField
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                fieldWidth: 44
                height: 18
                fontSize: 10
                plainWheel: true
                suffix: "Q"
                decimals: 2
                wheelStep: 0.05
                minValue: 0.1
                maxValue: 20
                value: hud.v.q || 0.707
                onValueEdited: hud.editor.setBandValue(hud.band, "q", newValue)
            }
        }
        ReadRow { visible: hud.firstOrderCut; label: "Slope"; value: "6 dB/oct" }
        ReadRow { visible: hud.type === 8; label: "Order"; value: "1st" }
        ReadRow { visible: hud.linkwitz; label: "f0"; value: (hud.v.freq || 0).toFixed(0) + " Hz" }
        ReadRow { visible: hud.linkwitz; label: "fp"; value: (hud.v.gain || 0).toFixed(0) + " Hz" }
    }
}
