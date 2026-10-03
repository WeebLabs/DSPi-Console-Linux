import QtQuick 2.15
import QtQuick.Controls 2.15

// Header card of an input channel page: Link, Preamp, Clear PEQ.
Rectangle {
    id: card
    height: 60
    radius: 10
    color: Qt.rgba(0.21, 0.21, 0.21, 0.6)
    border.color: Qt.rgba(0.5, 0.5, 0.5, 0.2)
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

    function refresh() {
        linked = bridge.isInputLinked(channelId)
        pairLive = bridge.pairAvailable(channelId)
        if (!preampSlider.pressed) preampDB = bridge.inputPreampDB(inputIndex)
    }

    Connections {
        target: bridge
        function onStateChanged() { card.refresh() }
        function onStatusChanged() { card.refresh() }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 14

        // Link toggle
        Button {
            id: linkBtn
            visible: pairLive
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            checkable: false
            text: "Link " + pairLabel()
            font.pixelSize: 11
            palette.buttonText: linked ? "white" : Qt.rgba(1, 1, 1, 0.7)
            background: Rectangle {
                radius: 5
                color: linked ? "#0078d4" : Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.12)
            }
            onClicked: {
                if (linked) bridge.setInputLinked(channelId, false, -1)
                else if (bridge.inputPairMatches(channelId)) bridge.setInputLinked(channelId, true, -1)
                else linkDialog.open()
            }
        }

        // Preamp
        Text {
            text: "PREAMP"
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Qt.rgba(1, 1, 1, 0.5)
            anchors.verticalCenter: parent.verticalCenter
        }

        ValueField {
            fieldWidth: 60
            value: preampDB
            suffix: "dB"
            decimals: 1
            minValue: -60
            maxValue: 10
            anchors.verticalCenter: parent.verticalCenter
            onValueEdited: bridge.setInputPreamp(inputIndex, newValue)
        }

        Slider {
            id: preampSlider
            width: Math.max(120, card.width - linkBtn.width * (linkBtn.visible ? 1 : 0) - clearBtn.width - 230)
            height: 20
            topPadding: 0
            bottomPadding: 0
            from: -60; to: 10
            stepSize: 0.1
            value: preampDB
            anchors.verticalCenter: parent.verticalCenter
            onMoved: preampDB = value
            onPressedChanged: if (!pressed) bridge.setInputPreamp(inputIndex, value)

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: bridge.setInputPreamp(inputIndex, 0)
            }

            background: Rectangle {
                x: preampSlider.leftPadding
                y: (preampSlider.height - height) / 2
                width: preampSlider.availableWidth
                height: 3; radius: 2
                color: Qt.rgba(1, 1, 1, 0.15)
                Rectangle {
                    width: preampSlider.visualPosition * parent.width
                    height: parent.height; radius: 2
                    color: "#0078d4"
                }
            }
            handle: Rectangle {
                x: preampSlider.leftPadding + preampSlider.visualPosition * (preampSlider.availableWidth - width)
                y: (preampSlider.height - height) / 2
                width: 12; height: 12; radius: 6; color: "white"
            }
        }

        Button {
            id: clearBtn
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            text: linked ? "Clear " + pairLabel() + " PEQ" : "Clear PEQ"
            font.pixelSize: 11
            onClicked: bridge.clearPeq(channelId)
        }
    }

    Dialog {
        id: linkDialog
        title: "Link " + pairLabel() + "?"
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380

        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "These inputs have different filters or preamp. Choose which input's settings to keep; they will be copied onto the other."
        }

        footer: DialogButtonBox {
            Button {
                text: "Keep " + bridge.channelDescriptor(card.firstId)
                onClicked: { bridge.setInputLinked(card.channelId, true, card.firstId); linkDialog.close() }
            }
            Button {
                text: "Keep " + bridge.channelDescriptor(card.secondId)
                onClicked: { bridge.setInputLinked(card.channelId, true, card.secondId); linkDialog.close() }
            }
            Button {
                text: "Cancel"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: linkDialog.close()
            }
        }
    }
}
