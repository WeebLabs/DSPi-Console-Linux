import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"

SettingsPage {
    id: page
    title: "Outputs"
    subtitle: "Which GPIO pin each physical output uses. Changes apply immediately."

    property int rev: 0
    Connections { target: bridge; function onStateChanged() { page.rev++ } }

    property string status: ""
    property bool statusError: false
    readonly property var pinMessages: ["", "That GPIO can't be used for this output.",
        "That GPIO is already in use.", "Unknown output.", "Disable the output in the Matrix Mixer before changing its pin.",
        "Invalid setting."]

    // GPIOs a user can wire (23-25 are internal on a Pico)
    readonly property var gpioOptions: {
        var o = []
        for (var g = 0; g <= 28; g++)
            if (g < 23 || g > 25) o.push({ text: "GPIO " + g, value: g })
        return o
    }

    function slotName(i, n) {
        return i === n - 1 ? "Sub" : "OUT " + (2 * i + 1) + "/" + (2 * i + 2)
    }
    function report(code, what) {
        statusError = code !== 0
        status = code === 0 ? what : code === 255 ? "The device did not respond." : (pinMessages[code] || "Error " + code)
    }

    SettingsSection {
        title: "Output Pins"
        footnote: page.status
        enabled: bridge.connected

        Repeater {
            model: bridge.connected ? bridge.numPinOutputs() : 0
            SettingsChoiceRow {
                title: page.slotName(index, bridge.numPinOutputs())
                detail: index === bridge.numPinOutputs() - 1 ? "PDM subwoofer output" : "Stereo output pair"
                options: page.gpioOptions
                value: { page.rev; return bridge.outputPin(index) }
                onChosen: page.report(bridge.setOutputPin(index, value),
                                      title + " now uses GPIO " + value + ".")
            }
        }

        SettingsButtonRow {
            title: "Reset Pins"
            detail: "Sets every output pin back to its default. Output types are unchanged."
            buttonText: "Reset"
            onClicked: {
                var worst = 0
                for (var i = 0; i < bridge.numPinOutputs(); i++) {
                    var code = bridge.setOutputPin(i, 255)
                    if (code !== 0) worst = code
                }
                page.report(worst, "Output pins reset to their defaults.")
            }
        }
    }

    SettingsSection {
        title: "Storage"
        enabled: bridge.connected
        SettingsRow {
            title: bridge.outputConfigMode === 1 ? "Saved with each preset" : "Stored once for the board"
            detail: bridge.outputConfigMode === 1
                    ? "Pins and output limiters change when you load a preset. Save the preset to keep these changes."
                    : "Loading a preset never changes your wiring. Save the output config to keep these changes."
            Button {
                visible: bridge.outputConfigMode === 0
                text: "Save Output Config"
                onClicked: bridge.saveOutputConfig()
            }
        }
        SettingsButtonRow {
            title: "Change where this is stored"
            buttonText: "Global Parameters…"
            onClicked: page.ctx.navigate("global")
        }
    }
}
