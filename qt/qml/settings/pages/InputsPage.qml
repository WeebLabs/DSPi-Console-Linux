import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"
import "../../components"

// Input hardware: S/PDIF receivers, the I2S input and the ADAT input.
// Changes apply at once; in independent mode Save keeps them on the board.
SettingsPage {
    id: page
    title: "Inputs"
    subtitle: "Receivers, pins and clocking for the digital inputs. Select which one plays in the sidebar's Source menu."

    readonly property var hw: bridge.hardware
    readonly property bool rp2350: hw.rp2350 === true
    readonly property int spdifCount: {
        var n = 0
        for (var k = 0; k < 4; k++) if ((hw.spdifMask >> k) & 1) n = k + 1
        return Math.max(1, n)
    }
    readonly property int i2sPairs: Math.max(1, Math.min(4, (hw.i2sChannels || 2) / 2))
    readonly property bool anyI2sOutput: {
        var t = hw.outputTypes || []
        for (var i = 0; i < t.length; i++) if (t[i] === 1) return true
        return false
    }

    // Last outcome, shown under the sections
    property string status: ""
    property bool statusError: false
    function report(code, pin, okText) {
        statusError = code !== 0
        status = code === 0 ? (okText || "") : ctx.statusText(code, pin)
    }

    // Live lock state of the clocked inputs while they're the source
    readonly property bool watchI2s: hw.i2sClockMode === 1 && hw.inputSource === 2
    readonly property bool watchAdat: rp2350 && hw.inputSource === 3
    property var i2sLock: ({})
    property var adatLock: ({})
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: page.visible && bridge.connected && (page.watchI2s || page.watchAdat)
        onTriggered: {
            if (page.watchI2s) page.i2sLock = bridge.fetchInputLock(0)
            if (page.watchAdat) page.adatLock = bridge.fetchInputLock(1)
        }
    }
    function lockText(st, adat) {
        var names = adat ? ["Inactive", "Acquiring", "Syncing", "Locked", "Relocking"]
                         : ["Inactive", "Acquiring", "Relocking", "Locked"]
        return names[st.state] || "Inactive"
    }
    function lockColor(st, adat) {
        var locked = st.state === 3
        var hunting = adat ? (st.state === 1 || st.state === 2 || st.state === 4) : (st.state === 1 || st.state === 2)
        return isMacOS ? (locked ? MacColors.green : adat ? (st.state === 4 ? MacColors.orange : hunting ? MacColors.yellow : MacColors.gray)
                                           : (st.state === 2 ? MacColors.orange : hunting ? MacColors.yellow : MacColors.gray))
                       : locked ? "#32d74b" : hunting ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.35)
    }
    function lockDetail(st) {
        if (st.state === 3 && st.detectedRate > 0) return "Locked to the external clock at " + (st.detectedRate / 1000).toFixed(1) + " kHz."
        if (st.measuredHz > 0) return "Waiting for the external clock (measured " + (st.measuredHz / 1000).toFixed(1) + " kHz)."
        return "Waiting for the external clock."
    }

    // Instances: enable upwards / disable downwards, stopping at the first refusal
    function setSpdifCount(n) {
        var code = 0, failed = -1
        if (n > spdifCount) {
            for (var k = spdifCount; k < n && code === 0; k++) { code = bridge.setSpdifInputEnabled(k, true); failed = k }
        } else {
            for (var j = spdifCount - 1; j >= n && code === 0; j--) { code = bridge.setSpdifInputEnabled(j, false); failed = j }
        }
        if (code === 0) { report(0, undefined, n + (n === 1 ? " S/PDIF input." : " S/PDIF inputs.")); return }
        statusError = true
        if (n > spdifCount && code === 2)
            status = "Can't enable S/PDIF " + (failed + 1) + ": " + ctx.statusText(2, hw.spdifRxPins[failed])
        else if (code === 2)
            status = "Switch the input source away from S/PDIF " + (failed + 1) + " before reducing the input count."
        else
            status = ctx.statusText(code)
    }

    component LockRow: SettingsRow {
        id: lockRow
        property var lockState: ({})
        property bool adat: false
        title: "Lock Status"
        detail: page.lockDetail(lockState)
        Row {
            spacing: 6
            Rectangle {
                width: 8; height: 8; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: page.lockColor(lockRow.lockState, lockRow.adat)
            }
            Text {
                text: page.lockText(lockRow.lockState, lockRow.adat)
                font.pixelSize: 13
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.75)
            }
        }
    }

    // ── S/PDIF ──
    SettingsSection {
        title: "S/PDIF Input"
        enabled: bridge.connected
        footnote: "Up to four S/PDIF inputs share one receiver; the Source menu picks which one plays."

        SettingsSegmentedRow {
            title: "Inputs"
            detail: page.spdifCount + (page.spdifCount === 1 ? " selectable input" : " selectable inputs") + " sharing one receiver"
            options: ["1", "2", "3", "4"]
            value: page.spdifCount - 1
            controlWidth: 200
            onChosen: page.setSpdifCount(index + 1)
        }
        Repeater {
            model: page.spdifCount
            SettingsPinRow {
                title: page.spdifCount > 1 ? "S/PDIF " + (index + 1) : "S/PDIF RX"
                detail: "GPIO pin for S/PDIF input " + (index + 1) + " (TOSLINK RX module or comparator)."
                pin: page.hw.spdifRxPins ? page.hw.spdifRxPins[index] : 0xFF
                onChosen: page.report(bridge.setSpdifRxPin(index, pin), pin, title + " now uses GPIO " + pin + ".")
            }
        }
        SettingsSwitchRow {
            title: "LG Sound Sync"
            detail: "Decode an LG TV's TOSLINK volume and mute and apply them as the user volume, so the TV remote controls the volume. Saved with the active preset."
            checked: page.hw.lgEnabled === true
            onToggled: bridge.setLgSoundSync(checked)
        }
    }

    // ── I2S ──
    SettingsSection {
        title: "I2S Input"
        enabled: bridge.connected
        footnote: "The bit clock pins and the master-mode sample rate are set in I2S Configuration."

        SettingsSegmentedRow {
            title: "Clock Mode"
            detail: "Master: DSPi drives BCK/LRCLK. Slave: an external master drives the clocks and the rate is auto-detected."
            options: ["Master", "Slave"]
            value: page.hw.i2sClockMode === 1 ? 1 : 0
            controlWidth: 168
            onChosen: {
                if (index === page.hw.i2sClockMode) return
                if (page.anyI2sOutput) { clockModeDialog.pending = index; clockModeDialog.open() }
                else bridge.setI2sClockMode(index)
            }
        }
        LockRow {
            visible: page.watchI2s
            lockState: page.i2sLock
        }
        SettingsSegmentedRow {
            visible: page.rp2350
            title: "Channels"
            detail: page.i2sPairs + (page.i2sPairs === 1 ? " stereo pair" : " stereo pairs") + " of 24-bit audio, sample-aligned"
            options: ["2", "4", "6", "8"]
            value: page.i2sPairs - 1
            controlWidth: 200
            onChosen: {
                var n = (index + 1) * 2, code = bridge.setI2sInputChannels(n)
                if (code === 2) {
                    page.statusError = true
                    page.status = "Can't switch to " + n + " channels: a data pin is already in use. Reassign it first."
                } else page.report(code, undefined, "I2S input set to " + n + " channels.")
            }
        }
        SettingsValueRow {
            visible: !page.rp2350
            title: "Channels"
            detail: "One stereo pair of 24-bit audio"
            value: "2"
        }
        Repeater {
            model: page.i2sPairs
            SettingsPinRow {
                title: page.i2sPairs > 1 ? "Serial Data " + (index + 1) : "Serial Data"
                detail: "GPIO data pin for input channels " + (index * 2 + 1) + "-" + (index * 2 + 2) + "."
                pin: page.hw.i2sRxPins ? page.hw.i2sRxPins[index] : 0xFF
                onChosen: page.report(bridge.setI2sRxPin(index, pin), pin, title + " now uses GPIO " + pin + ".")
            }
        }
    }

    // ── ADAT (RP2350) ──
    SettingsSection {
        visible: page.rp2350
        title: "ADAT Input"
        enabled: bridge.connected
        footnote: "Wire an optical receiver's data output to the pin above (an ADA8200 or similar sends 8 channels). Save a preset to keep this wiring."

        SettingsSwitchRow {
            title: "Enable ADAT Input"
            detail: "Receive 8 channels of 24-bit audio (44.1/48 kHz). Assign a data pin below, then select ADAT as the input source."
            enabled: page.hw.adatInPin !== 0xFF || page.hw.adatInEnabled
            checked: page.hw.adatInEnabled === true
            onToggled: {
                var code = bridge.setAdatInputEnabled(checked)
                if (code === 1) { page.statusError = true; page.status = "Assign a valid data pin before enabling ADAT input." }
                else page.report(code, page.hw.adatInPin, checked ? "ADAT input enabled." : "ADAT input disabled.")
            }
        }
        SettingsPinRow {
            title: "Serial Data"
            detail: "No default: assign a spare pin. It may match the ADAT output pin for a loopback self-test."
            pin: page.hw.adatInPin
            allowUnset: !page.hw.adatInEnabled
            sharable: ["ADAT Output"]
            onChosen: page.report(bridge.setAdatInputPin(pin), pin, pin === 0xFF ? "ADAT input pin cleared." : "ADAT input now uses GPIO " + pin + ".")
        }
        SettingsSegmentedRow {
            title: "Clock Mode"
            detail: "Master runs the input at the rate set in I2S Configuration; Slave follows the ADAT stream's clock."
            options: ["Master", "Slave"]
            value: page.hw.adatInClockMode === 1 ? 1 : 0
            controlWidth: 168
            onChosen: page.report(bridge.setAdatInputClockMode(index), undefined, "")
        }
        // A master-mode ADAT input with nothing driving the far end's clock
        SettingsButtonRow {
            visible: page.hw.adatInEnabled && page.hw.adatInClockMode === 0 && !page.hw.adatOutEnabled
            title: "Clock is free-running"
            titleColor: isMacOS ? MacColors.label : "#ff9f0a"
            detail: "In master mode the device sending ADAT must lock to DSPi's clock, which only the ADAT output provides. Turn it on, or switch to Slave above."
            buttonText: "Enable ADAT Output"
            onClicked: page.report(bridge.setAdatOutEnabled(true), page.hw.adatOutPin, "ADAT output enabled.")
        }
        LockRow {
            visible: page.watchAdat
            lockState: page.adatLock
            adat: true
        }
    }

    // Outcome of the last change
    SettingsStatusLine { text: page.status; error: page.statusError }

    AppDialog {
        id: clockModeDialog
        property int pending: 0
        icon: "warning"
        iconTint: isMacOS ? MacColors.yellow : "#ff453a"
        title: "Change I2S clock mode?"
        message: "One or more I2S outputs are active. Switching between Master and Slave modes may cause sustained loud noises to be emitted by the connected I2S DAC if wiring has not been adjusted."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "change", text: "Change Clock Mode", role: "destructive" }
        ]
        onChosen: if (key === "change") bridge.setI2sClockMode(pending)
    }
}
