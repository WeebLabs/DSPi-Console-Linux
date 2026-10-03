import QtQuick 2.15
import "../"

SettingsPage {
    title: "Advanced"

    SettingsSection {
        title: "Device"
        enabled: bridge.connected
        SettingsValueRow { title: "Platform"; value: bridge.connected ? bridge.platformName : "—" }
        SettingsValueRow { title: "Firmware"; value: bridge.firmwareVersion || "—" }
        SettingsValueRow { title: "Serial Number"; value: bridge.selectedSerial || "—"; mono: true }
        SettingsValueRow {
            title: "Channels"
            value: bridge.connected ? bridge.numInputChannels + " inputs, " + bridge.numOutputChannels + " outputs" : "—"
        }
    }

    SettingsSection {
        title: "Channel Names"
        footnote: "Renames every channel back to its default (USB L, SPDIF 1 L and so on). Takes effect immediately."
        SettingsButtonRow {
            title: "Reset Channel Names"
            buttonText: "Reset"
            enabled: bridge.connected
            onClicked: bridge.resetChannelNames()
        }
    }
}
