import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"
import "../../components"

// I2S clocking: bit clock pins, master clock and the master-mode sample rate.
SettingsPage {
    id: page
    title: "I2S Configuration"
    subtitle: "Clock pins and the master clock for I2S outputs and the I2S input. Changes apply at once."

    readonly property var hw: bridge.hardware
    readonly property bool rp2350: hw.rp2350 === true
    readonly property bool anyI2sOutput: {
        var t = hw.outputTypes || []
        for (var i = 0; i < t.length; i++) if (t[i] === 1) return true
        return false
    }
    readonly property bool slaveMode: hw.i2sClockMode === 1
    readonly property var mckPins: rp2350 ? [13, 15, 21] : [21]

    property string status: ""
    property bool statusError: false
    function report(code, pin, okText) {
        statusError = code !== 0
        status = code === 0 ? (okText || "") : ctx.statusText(code, pin)
    }
    // A BCK candidate needs its LRCLK neighbour free, or held by the same
    // clock pair that is moving
    function pairFree(p, own) {
        if (bridge.validPins.indexOf(p + 1) < 0) return false
        var who = ctx.ownerOf(p + 1)
        return who === "" || own.indexOf(who) >= 0
    }
    readonly property var masterPair: ["I2S BCK", "I2S LRCLK"]
    readonly property var slavePair: ["I2S Slave BCK", "I2S Slave LRCLK"]

    SettingsSection {
        title: "Bit Clock"
        enabled: bridge.connected
        footnote: page.anyI2sOutput ? "Set every output to S/PDIF (Outputs) before moving the bit clock pins." : ""

        SettingsPinRow {
            title: "BCK Pin"
            detail: "LRCLK: GPIO " + (page.hw.bckPin + 1) + " (BCK + 1)"
            enabled: !page.anyI2sOutput
            pin: page.hw.bckPin
            accept: function(p) { return page.pairFree(p, page.masterPair) }
            onChosen: page.report(bridge.setI2sBckPin(0, pin), pin, "BCK now on GPIO " + pin + ", LRCLK on GPIO " + (pin + 1) + ".")
        }
        SettingsSegmentedRow {
            title: "Clock Pins"
            detail: page.hw.clockPinMode === 1 ? "Split: separate pins for Master and Slave modes."
                                               : "Unified: Master and Slave modes share pins."
            options: ["Unified", "Split"]
            value: page.hw.clockPinMode === 1 ? 1 : 0
            controlWidth: 168
            onChosen: page.report(bridge.setI2sClockPinMode(index), page.hw.bckPinSlave,
                                  index === 1 ? "Slave mode uses its own clock pins." : "Master and Slave share the clock pins.")
        }
        SettingsPinRow {
            title: "Slave BCK Pin"
            detail: page.hw.clockPinMode === 1 ? "LRCLK: GPIO " + (page.hw.bckPinSlave + 1) + " (BCK + 1)"
                                               : "Stored but inactive while clock pins are shared."
            enabled: page.hw.clockPinMode === 1
            pin: page.hw.bckPinSlave
            accept: function(p) { return page.pairFree(p, page.slavePair) }
            onChosen: page.report(bridge.setI2sBckPin(1, pin), pin, "Slave BCK now on GPIO " + pin + ".")
        }
    }

    SettingsSection {
        title: "Master Clock"
        enabled: bridge.connected

        SettingsSwitchRow {
            title: "Master Clock (MCK)"
            detail: page.slaveMode ? "Forced off in I2S slave mode: the external master supplies the clocks."
                                   : "Clock reference for external DACs."
            enabled: !page.slaveMode
            checked: page.hw.mckEnabled === true && !page.slaveMode
            onToggled: page.report(bridge.setMckEnabled(checked), page.hw.mckPin, checked ? "MCK on GPIO " + page.hw.mckPin + "." : "MCK off.")
        }
        SettingsPinRow {
            title: "MCK Pin"
            detail: page.hw.mckEnabled ? "Turn MCK off to change its pin." : "Pin on which MCK is generated."
            enabled: !page.hw.mckEnabled && !page.slaveMode
            pin: page.hw.mckPin
            accept: function(p) { return page.mckPins.indexOf(p) >= 0 }
            onChosen: page.report(bridge.setMckPin(pin), pin, "MCK pin is now GPIO " + pin + ".")
        }
        SettingsChoiceRow {
            title: "MCK Multiplier"
            detail: page.hw.inputRate === 2 ? "Locked to 128x at 96 kHz." : "Use 256x for DACs that need a higher MCK rate."
            enabled: !page.slaveMode && page.hw.inputRate !== 2
            options: [{ text: "128x", value: 0 }, { text: "256x", value: 1 }]
            value: page.hw.mckMultiplier
            onChosen: page.report(bridge.setMckMultiplier(value), undefined, "")
        }
    }

    SettingsSection {
        title: "Input Sample Rate"
        enabled: bridge.connected
        footnote: "Used when DSPi is the clock master for the I2S or ADAT input."
        SettingsChoiceRow {
            title: "Sample Rate"
            detail: page.slaveMode ? "Rate used in master mode; in slave mode it follows the external clock." : ""
            enabled: !page.slaveMode
            options: [{ text: "44.1 kHz", value: 0 }, { text: "48 kHz", value: 1 }, { text: "96 kHz", value: 2 }]
            value: page.hw.inputRate
            onChosen: bridge.setInputRate(value)
        }
    }

    SettingsStatusLine { text: page.status; error: page.statusError }
}
