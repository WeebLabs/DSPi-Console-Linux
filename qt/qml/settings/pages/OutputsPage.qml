import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"
import "../../components"

// Output hardware: each slot's type and pin, and the ADAT optical output.
SettingsPage {
    id: page
    title: "Outputs"
    subtitle: "The type and GPIO pin of each physical output. Changes apply at once."

    readonly property var hw: bridge.hardware
    readonly property bool rp2350: hw.rp2350 === true
    readonly property int slots: hw.numPinOutputs || 0

    property string status: ""
    property bool statusError: false
    function report(code, pin, okText) {
        statusError = code !== 0
        status = code === 0 ? (okText || "")
               : code === 4 ? "Disable this output in the Matrix Mixer before changing its pin."
               : ctx.statusText(code, pin)
    }
    function slotName(i) {
        return i === slots - 1 ? "Sub" : "OUT " + (2 * i + 1) + "/" + (2 * i + 2)
    }

    // ADAT output state while the page shows it
    property var adatStatus: ({})
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: page.visible && bridge.connected && page.rp2350 && page.hw.adatOutEnabled === true
        onTriggered: page.adatStatus = bridge.fetchAdatOutStatus()
    }

    SettingsSection {
        visible: !isMacOS
        title: "Slots"
        enabled: bridge.connected

        Repeater {
            model: page.slots
            SettingsRow {
                id: slotRow
                readonly property bool isSub: index === page.slots - 1
                readonly property int kind: !isSub && page.hw.outputTypes ? page.hw.outputTypes[index] : 0
                title: page.slotName(index)
                detail: isSub ? "PDM subwoofer output" : kind === 1 ? "I2S stereo pair (clocks in I2S Configuration)" : "S/PDIF stereo pair"

                readonly property int slot: index
                readonly property int pin: page.hw.outputPins ? page.hw.outputPins[index] : 0xFF
                readonly property var pinChoices: { bridge.hardware; return page.ctx ? page.ctx.pinOptions(pin) : [] }

                Row {
                    spacing: 8
                    StyledComboBox {
                        width: 92
                        enabled: !slotRow.isSub
                        model: slotRow.isSub ? ["PDM"] : ["S/PDIF", "I2S"]
                        currentIndex: slotRow.isSub ? 0 : slotRow.kind
                        onActivated: if (!slotRow.isSub && index !== slotRow.kind)
                            page.report(bridge.setOutputType(slotRow.slot, index), undefined,
                                        slotRow.title + " is now " + (index === 1 ? "I2S." : "S/PDIF."))
                    }
                    StyledComboBox {
                        width: 108
                        model: slotRow.pinChoices.map(function(o) { return o.text })
                        currentIndex: page.ctx ? page.ctx.optionIndex(slotRow.pinChoices, slotRow.pin) : -1
                        onActivated: {
                            var p = slotRow.pinChoices[index].value
                            if (p !== slotRow.pin)
                                page.report(bridge.setOutputPin(slotRow.slot, p), p, slotRow.title + " now uses GPIO " + p + ".")
                        }
                    }
                }
            }
        }

        SettingsButtonRow {
            title: "Reset Pins"
            detail: "Sets every output pin back to its default. Output types are unchanged."
            buttonText: "Reset"
            onClicked: {
                var worst = 0
                for (var i = 0; i < page.slots; i++) {
                    var code = bridge.setOutputPin(i, 255)
                    if (code !== 0) worst = code
                }
                page.report(worst, undefined, "Output pins reset to their defaults.")
            }
        }
    }

    SettingsSection {
        visible: !isMacOS && page.rp2350
        title: "ADAT Output"
        enabled: bridge.connected
        footnote: "ADAT runs at 44.1 and 48 kHz and pauses above that."

        SettingsSwitchRow {
            title: "Enable ADAT"
            detail: "Stream all 8 output channels as one optical ADAT lightpipe (44.1/48 kHz, 24-bit). Runs alongside the existing outputs; drive a TOSLINK transmitter from the data pin."
            checked: page.hw.adatOutEnabled === true
            onToggled: page.report(bridge.setAdatOutEnabled(checked), page.hw.adatOutPin, checked ? "ADAT output enabled." : "ADAT output disabled.")
        }
        SettingsPinRow {
            title: "Serial Data"
            detail: "GPIO driving the ADAT optical output. Default GPIO 12."
            pin: page.hw.adatOutPin
            onChosen: page.report(bridge.setAdatOutPin(pin), pin, "ADAT output now uses GPIO " + pin + ".")
        }
        SettingsValueRow {
            visible: page.hw.adatOutEnabled === true
            title: "State"
            value: page.adatStatus.active ? "Streaming"
                 : page.adatStatus.rateOk === false ? "Suspended (rate above 48 kHz)" : "Enabled"
        }
    }

    SettingsSection {
        visible: !isMacOS
        title: "Storage"
        enabled: bridge.connected
        SettingsRow {
            title: bridge.outputConfigMode === 1 ? "Saved with each preset" : "Stored once for the board"
            detail: bridge.outputConfigMode === 1
                    ? "Pins, types, clocks and output limiters change when you load a preset. Save the preset to keep these changes."
                    : "Loading a preset never changes your wiring. Save in the bar below to keep these changes."
        }
        SettingsButtonRow {
            title: "Change where this is stored"
            buttonText: "Global Parameters…"
            onClicked: page.ctx.navigate("global")
        }
    }

    SettingsStatusLine { visible: !isMacOS && page.status !== ""; text: page.status; error: page.statusError }

    // ── macOS: the native Outputs page (DSPi_ConsoleApp.swift:8868) ──
    function resetPins() {
        var worst = 0
        for (var i = 0; i < page.slots; i++) {
            var code = bridge.setOutputPin(i, 255)
            if (code !== 0) worst = code
        }
        page.report(worst, undefined, "Output pins reset to their defaults.")
    }
    Loader {
        active: isMacOS
        visible: isMacOS
        width: parent.width
        sourceComponent: Column {
            spacing: 11

            SettingsSection {
                title: "Slots"
                icon: "grid-2x2"
                enabled: bridge.connected
                Repeater {
                    model: page.slots
                    MacSlotRow {}
                }
            }

            SettingsSection {
                visible: page.rp2350
                title: "Bulk Output"
                icon: "fibre"
                iconSize: 24
                enabled: bridge.connected
                SettingsSwitchRow {
                    icon: "fibre"
                    extraPadding: 4
                    title: "Enable ADAT"
                    detail: "Stream all 8 output channels as one optical ADAT lightpipe (44.1/48 kHz, 24-bit). Runs alongside the existing outputs; drive a TOSLINK transmitter from the data pin."
                    checked: page.hw.adatOutEnabled === true
                    onToggled: page.report(bridge.setAdatOutEnabled(checked), page.hw.adatOutPin, checked ? "ADAT output enabled." : "ADAT output disabled.")
                }
                SettingsPinRow {
                    icon: "connector"
                    title: "Serial Data"
                    detail: "GPIO driving the ADAT optical output. Default GPIO 12."
                    pin: page.hw.adatOutPin
                    onChosen: page.report(bridge.setAdatOutPin(pin), pin, "ADAT output now uses GPIO " + pin + ".")
                }
            }

            // Status on the left, Reset Pins on the right, in a card of its own
            SettingsSection {
                Item {
                    width: parent.width
                    height: 35
                    Row {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        visible: page.status !== ""
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: page.statusError ? "warning" : "check-circle"
                            size: 12
                            color: page.statusError ? MacColors.orange : MacColors.green
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.parent.width - resetText.width - 46)
                            elide: Text.ElideRight
                            text: page.status
                            font.pixelSize: 10
                            color: page.statusError ? MacColors.orange : MacColors.secondaryLabel
                        }
                    }
                    Text {
                        id: resetText
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Reset Pins"
                        font.pixelSize: 13
                        color: bridge.connected ? MacColors.accent : MacColors.opacity(MacColors.secondaryLabel, 0.5)
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            enabled: bridge.connected
                            onClicked: page.resetPins()
                        }
                    }
                }
            }
        }
    }

    // A slot row as the native assignmentRow: the output pair's colour dot,
    // its name in a 56 pt column, a "Default" capsule while type and pin are
    // the factory ones, and the type and pin menus on the right
    component MacSlotRow: SettingsRow {
        id: slotRow
        readonly property bool isSub: index === page.slots - 1
        readonly property int slot: index
        readonly property int kind: !isSub && page.hw.outputTypes ? page.hw.outputTypes[index] : 0
        readonly property int pin: page.hw.outputPins ? page.hw.outputPins[index] : 0xFF
        readonly property int defaultPin: isSub ? 10 : [6, 7, 8, 9][index]
        readonly property bool isDefault: kind === 0 && pin === defaultPin
        readonly property var pinChoices: { bridge.hardware; return page.ctx ? page.ctx.pinOptions(pin) : [] }
        // The R channel colour of the pair (ChannelPalette.outputs), the PDM purple
        readonly property color dotColor: isSub ? "#BA87F2" : ["#59D180", "#F2A64D", "#8CB3F2", "#F299A6"][index % 4]
        title: ""
        height: 41

        // On the row itself, not in its trailing area
        Row {
            parent: slotRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: slotRow.dotColor
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                text: page.slotName(slotRow.slot)
                font.pixelSize: 13
                color: MacColors.label
            }
            Rectangle {
                visible: slotRow.isDefault
                anchors.verticalCenter: parent.verticalCenter
                width: defaultText.implicitWidth + 14
                height: defaultText.implicitHeight + 4
                radius: height / 2
                color: MacColors.opacity(MacColors.secondaryLabel, 0.15)
                Text {
                    id: defaultText
                    anchors.centerIn: parent
                    text: "Default"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: MacColors.secondaryLabel
                }
            }
        }

        Row {
            spacing: 8
            StyledComboBox {
                macForm: true
                anchors.verticalCenter: parent.verticalCenter
                enabled: !slotRow.isSub
                model: slotRow.isSub ? ["PDM"] : ["S/PDIF", "I2S"]
                currentIndex: slotRow.isSub ? 0 : slotRow.kind
                onActivated: if (!slotRow.isSub && index !== slotRow.kind)
                    page.report(bridge.setOutputType(slotRow.slot, index), undefined,
                                (slotRow.isSub ? "Sub" : page.slotName(slotRow.slot)) + " is now " + (index === 1 ? "I2S." : "S/PDIF."))
            }
            StyledComboBox {
                macForm: true
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(92, implicitWidth)
                model: slotRow.pinChoices.map(function(o) { return o.text })
                currentIndex: page.ctx ? page.ctx.optionIndex(slotRow.pinChoices, slotRow.pin) : -1
                onActivated: {
                    var p = slotRow.pinChoices[index].value
                    if (p !== slotRow.pin)
                        page.report(bridge.setOutputPin(slotRow.slot, p), p, page.slotName(slotRow.slot) + " now uses GPIO " + p + ".")
                }
            }
        }
    }
}
