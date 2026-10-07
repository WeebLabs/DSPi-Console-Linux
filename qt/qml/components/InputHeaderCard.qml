import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Header card of an input channel page, laid out as on the macOS Console:
// Link n/n+1 | Preamp slider and value | Clear PEQ, separated by dividers.
Rectangle {
    id: card
    height: 60
    radius: 10
    // Same surface as the band list below it
    color: isMacOS ? Qt.rgba(0.21, 0.21, 0.21, 0.6) : nativeAltBaseColor
    border.color: Qt.rgba(1, 1, 1, 0.1)
    border.width: 1

    property int channelId: 0
    readonly property int inputIndex: inputOfApp(channelId)
    readonly property int partnerId: bridge.pairPartner(channelId)
    // The pair's lower and upper input, as app ids
    readonly property int firstId: inputIndex < inputOfApp(partnerId) ? channelId : partnerId
    readonly property int secondId: firstId === channelId ? partnerId : channelId
    property bool linked: bridge.isInputLinked(channelId)
    property bool pairLive: bridge.pairAvailable(channelId)
    property real preampDB: bridge.inputPreampDB(inputIndex)

    // App id -> input index (0,1 then 11..16 -> 2..7)
    function inputOfApp(id) { return id < 2 ? id : id - 9 }
    function pairLabel() {
        var a = Math.min(inputIndex, inputOfApp(partnerId)) + 1
        return a + "/" + (a + 1)
    }

    // As on Windows: "Link 3/4" on the numbered sources (USB, ADAT), else "Link Pair"
    function linkLabel() {
        var numbered = bridge.inputSource === 0 || bridge.inputSource === 3   // USB, ADAT
        return inputIndex < 2 || !numbered ? "Link Pair" : "Link " + pairLabel()
    }

    function refresh() {
        linked = bridge.isInputLinked(channelId)
        pairLive = bridge.pairAvailable(channelId)
        if (!preampSlider.pressed) preampDB = bridge.inputPreampDB(inputOfApp(channelId))
    }
    // refresh() ends the bindings above, so a switch to another input re-reads
    onChannelIdChanged: refresh()

    Connections {
        target: bridge
        function onStateChanged() { card.refresh() }
        function onStatusChanged() { card.refresh() }
    }

    // Outlined button (Link / Clear PEQ); `active` fills it with the accent
    component CardButton: Rectangle {
        id: cb
        property string text: ""
        property string icon: ""
        property bool active: false
        property int fontSize: 13
        signal clicked()
        implicitWidth: cbRow.implicitWidth + 28
        implicitHeight: 32
        radius: 8
        color: active ? Qt.rgba(0.04, 0.49, 1, cbMouse.containsMouse ? 0.32 : 0.22)
             : cbMouse.pressed ? Qt.rgba(1, 1, 1, 0.12) : cbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
        border.width: 1
        border.color: active ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.18)
        Row {
            id: cbRow
            anchors.centerIn: parent
            spacing: 7
            Icon {
                visible: cb.icon !== ""
                name: cb.icon
                size: 15
                color: cb.active ? "white" : "#cccccc"
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: cb.text
                font.pixelSize: cb.fontSize
                color: cb.active ? "white" : "#cccccc"   // Windows Console secondary text
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: cbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }

    component Divider: Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Link (only while both inputs of the pair are live) ──
        CardButton {
            visible: pairLive
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            icon: "link"
            fontSize: 12
            text: linkLabel()
            active: linked
            onClicked: {
                if (linked) bridge.setInputLinked(channelId, false, -1)
                else if (bridge.inputPairMatches(channelId)) bridge.setInputLinked(channelId, true, -1)
                else linkDialog.open()
            }
        }
        Divider { visible: pairLive }

        // ── Preamp ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 18
            Layout.alignment: Qt.AlignVCenter
            spacing: 16

            Text {
                text: "Preamp"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            StyledSlider {
                id: preampSlider
                Layout.fillWidth: true
                from: -60; to: bridge.preampMaxDB     // +18 dB on RP2040, +24 on RP2350
                stepSize: 0.1
                value: preampDB
                // Value follows the drag; the device gets live updates. A
                // press that didn't move commits nothing, so a value set
                // outside the slider's range elsewhere stays as it is
                property bool dragged: false
                onMoved: { dragged = true; preampDB = value; preampLive.push(value) }
                onPressedChanged: if (!pressed) {
                    preampLive.cancel()
                    if (dragged) bridge.setInputPreamp(inputIndex, value)
                    dragged = false
                }
                Throttle { id: preampLive; onFire: bridge.setInputPreamp(inputIndex, value, true) }
                // Right-click resets to 0 dB
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: bridge.setInputPreamp(inputIndex, 0)
                }
            }
            ValueField {
                fieldWidth: 58
                height: 24
                value: preampDB
                suffix: "dB"
                decimals: 1
                minValue: -60
                maxValue: bridge.preampMaxDB
                onValueEdited: bridge.setInputPreamp(inputIndex, newValue)
            }
        }

        Divider {}

        // ── Clear PEQ (both inputs while linked) ──
        CardButton {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            fontSize: 14
            text: linked ? "Clear " + pairLabel() + " PEQ" : "Clear PEQ"
            onClicked: bridge.clearPeq(channelId)
        }
    }

    // One line describing an input's settings, for the link prompt
    function settingsSummary(appId) {
        var n = 0
        for (var b = 0; b < 10; b++) if (bridge.filterType(appId, b) !== 0) n++
        var p = bridge.inputPreampDB(inputOfApp(appId))
        return {
            text: bridge.channelName(appId) + ":  " + n + (n === 1 ? " filter" : " filters")
                  + "  \u00b7  preamp " + (p > 0 ? "+" : "") + p.toFixed(1) + " dB",
            color: bridge.channelColor(appId)
        }
    }

    // Linking inputs whose filters or preamp differ: choose which to keep.
    // The input whose page this is is the default.
    AppDialog {
        id: linkDialog
        icon: "link"
        title: "Link " + bridge.channelName(card.firstId) + " and " + bridge.channelName(card.secondId) + "?"
        message: "Their filters or preamp differ. Which settings should both use?"
        onAboutToShow: details = [card.settingsSummary(card.firstId), card.settingsSummary(card.secondId)]
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "other", text: "Keep " + bridge.channelName(card.partnerId) },
            { key: "this", text: "Keep " + bridge.channelName(card.channelId), role: "primary" }
        ]
        onChosen: {
            if (key === "this") bridge.setInputLinked(card.channelId, true, card.channelId)
            else if (key === "other") bridge.setInputLinked(card.channelId, true, card.partnerId)
        }
    }
}
