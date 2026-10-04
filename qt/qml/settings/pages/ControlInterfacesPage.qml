import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"
import "../../components"

// UART and I2C control interfaces: an external controller drives DSPi over
// a serial link. Each is edited as a draft and applied; the device checks the
// pins and saves the result to flash.
SettingsPage {
    id: page
    title: "Control Interfaces"
    subtitle: "Let an external microcontroller control DSPi over UART or I2C. Set up over USB only; the configuration survives a factory reset."

    readonly property var hw: bridge.hardware
    readonly property var bauds: [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600, 1000000]
    // Which UART block a pin's UART function belongs to (UART1 on 4-11 and
    // 20-27, UART0 elsewhere); TX and RX must share one
    function uartBlock(p) { var m = p % 16; return m >= 4 && m <= 11 ? 1 : 0 }

    Component.onCompleted: bridge.refreshCtrlIfaces()

    // Drafts, reloaded from the device while not edited
    property bool uartEdited: false
    property bool uartEnabled: false
    property int uartTx: 16
    property int uartRx: 17
    property bool uartNotify: false
    property int uartBaud: 115200
    property bool i2cEdited: false
    property bool i2cEnabled: false
    property int i2cSda: 18
    property int i2cScl: 19
    property int i2cAddress: 0x42

    function loadUart() {
        uartEnabled = hw.uartEnabled === true; uartTx = hw.uartTx; uartRx = hw.uartRx
        uartNotify = hw.uartNotify === true; uartBaud = hw.uartBaud; uartEdited = false
    }
    function loadI2c() {
        i2cEnabled = hw.i2cEnabled === true; i2cSda = hw.i2cSda; i2cScl = hw.i2cScl
        i2cAddress = hw.i2cAddress; i2cEdited = false
    }
    onHwChanged: { if (!uartEdited) loadUart(); if (!i2cEdited) loadI2c() }

    // Outcome of the last Apply, per interface
    property string uartResult: ""
    property bool uartResultError: false
    property string i2cResult: ""
    property bool i2cResultError: false
    function resultText(which, code) {
        var name = which === 0 ? "UART" : "I2C"
        switch (code) {
        case 0: return name + " configuration applied and saved."
        case 1: return "A pin is out of range or lacks the required " + name + " function."
        case 2: return "A pin is already claimed by another output or interface."
        case 5: return which === 0 ? "Baud rate is out of range (9600 - 1000000)." : "Address is out of range (0x08 - 0x77)."
        default: return "Failed to apply the " + name + " configuration."
        }
    }
    Connections {
        target: bridge
        function onCtrlIfaceApplied(which, status) {
            if (which === 0) { page.uartResult = page.resultText(0, status); page.uartResultError = status !== 0; page.loadUart() }
            else { page.i2cResult = page.resultText(1, status); page.i2cResultError = status !== 0; page.loadI2c() }
        }
    }

    // Enable row with the live state as a pill
    component StatePill: Rectangle {
        property bool enabledInFlash: false
        property bool live: false
        readonly property string label: !enabledInFlash ? "Disabled" : live ? "Active" : "Inactive"
        readonly property color tint: !enabledInFlash ? Qt.rgba(1, 1, 1, 0.4) : live ? "#32d74b" : "#ff9f0a"
        width: pillText.implicitWidth + 16
        height: 20
        radius: 10
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.15)
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.5)
        Text {
            id: pillText
            anchors.centerIn: parent
            text: parent.label
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: parent.tint
        }
    }

    // Revert / Apply for a draft
    component ApplyRow: SettingsRow {
        id: applyRow
        property bool edited: false
        property string result: ""
        property bool resultError: false
        signal apply()
        signal revert()
        title: edited ? "Unapplied changes" : result !== "" ? result : "Applied"
        titleColor: edited ? "white" : resultError ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.7)
        Row {
            spacing: 8
            Rectangle {
                visible: applyRow.edited
                width: 80; height: 28; radius: 8
                color: revertMouse.pressed ? Qt.rgba(1, 1, 1, 0.12) : revertMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.18)
                Text { anchors.centerIn: parent; text: "Revert"; font.pixelSize: 13; color: "white" }
                MouseArea { id: revertMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: applyRow.revert() }
            }
            Rectangle {
                width: 80; height: 28; radius: 8
                opacity: applyRow.edited ? 1 : 0.4
                color: applyMouse.pressed ? "#0060cc" : "#0a7cff"
                Text { anchors.centerIn: parent; text: "Apply"; font.pixelSize: 13; font.weight: Font.DemiBold; color: "white" }
                MouseArea { id: applyMouse; anchors.fill: parent; enabled: applyRow.edited; cursorShape: Qt.PointingHandCursor; onClicked: applyRow.apply() }
            }
        }
    }

    Text {
        visible: !page.hw.ctrlSupported
        width: parent.width
        wrapMode: Text.WordWrap
        text: bridge.connected ? "The connected firmware has no UART or I2C control interface." : "Connect a DSPi to set up its control interfaces."
        font.pixelSize: 13
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    // ── UART ──
    SettingsSection {
        visible: page.hw.ctrlSupported === true
        title: "UART"
        enabled: bridge.connected
        footnote: page.hw.uartEnabled && !page.hw.uartLive
                  ? "Enabled in flash but not running: its pins likely collide with the current wiring. Reassign the conflicting pin or move this interface, then apply."
                  : ""

        SettingsRow {
            title: "Enable UART"
            detail: "Asynchronous 3.3 V serial link, fixed 8N1 framing."
            Row {
                spacing: 12
                StatePill {
                    anchors.verticalCenter: parent.verticalCenter
                    enabledInFlash: page.hw.uartEnabled === true
                    live: page.hw.uartLive === true
                }
                ToggleSwitch {
                    checked: page.uartEnabled
                    onToggled: { page.uartEnabled = checked; page.uartEdited = true }
                }
            }
        }
        SettingsPinRow {
            visible: page.uartEnabled
            title: "TX Pin"
            detail: "GPIO transmitting to the controller's RX (a UART TX pin: GPIO number divisible by 4)."
            pin: page.uartTx
            alsoTaken: [page.uartRx]
            sharable: ["UART TX", "UART RX"]
            accept: function(p) { return p % 4 === 0 }
            onChosen: { page.uartTx = pin; page.uartEdited = true }
        }
        SettingsPinRow {
            visible: page.uartEnabled
            title: "RX Pin"
            detail: "GPIO receiving from the controller's TX (a UART RX pin: one above a TX pin)."
            pin: page.uartRx
            alsoTaken: [page.uartTx]
            sharable: ["UART TX", "UART RX"]
            accept: function(p) { return p % 4 === 1 && page.uartBlock(p) === page.uartBlock(page.uartTx) }
            onChosen: { page.uartRx = pin; page.uartEdited = true }
        }
        SettingsChoiceRow {
            visible: page.uartEnabled
            title: "Baud Rate"
            detail: "Must match the controller."
            options: page.bauds.map(function(b) { return { text: b >= 1000 ? (b / 1000) + "k" : String(b), value: b } })
            value: page.uartBaud
            onChosen: { page.uartBaud = value; page.uartEdited = true }
        }
        SettingsSwitchRow {
            visible: page.uartEnabled
            title: "Push Notifications"
            detail: "Stream live parameter, preset and format changes to the controller instead of having it poll."
            checked: page.uartNotify
            onToggled: { page.uartNotify = checked; page.uartEdited = true }
        }
        ApplyRow {
            edited: page.uartEdited
            result: page.uartResult
            resultError: page.uartResultError
            onRevert: page.loadUart()
            onApply: bridge.setUart(page.uartEnabled, page.uartTx, page.uartRx, page.uartNotify, page.uartBaud)
        }
    }

    // ── I2C ──
    SettingsSection {
        visible: page.hw.ctrlSupported === true
        title: "I2C"
        enabled: bridge.connected
        footnote: page.hw.i2cEnabled && !page.hw.i2cLive
                  ? "Enabled in flash but not running: its pins likely collide with the current wiring. Reassign the conflicting pin or move this interface, then apply."
                  : "The controller is the bus master; fit 2.2k to 4.7k pull-ups on SDA and SCL. External control protocol version " + (page.hw.ctrlProtocol || 1) + "."

        SettingsRow {
            title: "Enable I2C Target"
            detail: "DSPi answers as an I2C target; the controller polls it (no notifications)."
            Row {
                spacing: 12
                StatePill {
                    anchors.verticalCenter: parent.verticalCenter
                    enabledInFlash: page.hw.i2cEnabled === true
                    live: page.hw.i2cLive === true
                }
                ToggleSwitch {
                    checked: page.i2cEnabled
                    onToggled: { page.i2cEnabled = checked; page.i2cEdited = true }
                }
            }
        }
        SettingsPinRow {
            visible: page.i2cEnabled
            title: "SDA Pin"
            detail: "Serial data line (even GPIO). SCL is the next pin up."
            pin: page.i2cSda
            sharable: ["I2C SDA", "I2C SCL"]
            accept: function(p) {
                if (p % 2 !== 0 || bridge.validPins.indexOf(p + 1) < 0) return false
                var who = page.ctx.ownerOf(p + 1)       // SCL rides on the next pin
                return who === "" || who === "I2C SDA" || who === "I2C SCL"
            }
            onChosen: { page.i2cSda = pin; page.i2cScl = pin + 1; page.i2cEdited = true }
        }
        SettingsValueRow {
            visible: page.i2cEnabled
            title: "SCL Pin"
            detail: "Serial clock line (next odd GPIO, same I2C block)."
            value: "GPIO " + page.i2cScl
        }
        SettingsRow {
            visible: page.i2cEnabled
            title: "Target Address"
            detail: "7-bit address, 0x08 - 0x77."
            ValueField {
                fieldWidth: 56
                height: 24
                decimals: 0
                minValue: 8
                maxValue: 119
                value: page.i2cAddress
                suffix: "0x" + ("0" + page.i2cAddress.toString(16).toUpperCase()).slice(-2)
                onValueEdited: { page.i2cAddress = Math.round(newValue); page.i2cEdited = true }
            }
        }
        ApplyRow {
            edited: page.i2cEdited
            result: page.i2cResult
            resultError: page.i2cResultError
            onRevert: page.loadI2c()
            onApply: bridge.setI2c(page.i2cEnabled, page.i2cSda, page.i2cScl, page.i2cAddress)
        }
    }
}
