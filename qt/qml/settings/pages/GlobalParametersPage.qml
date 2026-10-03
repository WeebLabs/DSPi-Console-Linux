import QtQuick 2.15
import "../"

// Board-wide settings. Edits are a draft until Save in the save bar.
SettingsPage {
    id: page
    title: "Global Parameters"
    subtitle: "Board-wide settings that don't belong to any preset. Changes are held until you click Save."

    readonly property var presetOptions: {
        bridge.presetOccupied
        var o = []
        for (var i = 0; i < 10; i++) {
            var name = bridge.presetName(i)
            var label = bridge.isPresetOccupied(i) ? (name === "" ? "Preset " + (i + 1) : name) : "Empty"
            o.push({ text: (i + 1) + ". " + label, value: i })
        }
        return o
    }

    SettingsSection {
        title: "Startup Preset"
        enabled: bridge.connected
        SettingsChoiceRow {
            title: "At Power-On"
            options: [{ text: "Specified Default", value: 0 }, { text: "Last Used", value: 1 }]
            value: ctx ? ctx.startupMode : 0
            onChosen: ctx.edit("startupMode", value)
        }
        SettingsChoiceRow {
            title: "Default Preset"
            enabled: ctx ? ctx.startupMode === 0 : true
            options: page.presetOptions
            value: ctx ? ctx.defaultSlot : 0
            onChosen: ctx.edit("defaultSlot", value)
        }
    }

    SettingsSection {
        title: "Master Volume"
        enabled: bridge.connected
        footnote: ctx && ctx.masterVolumeMode === 0
                  ? "Master volume is stored once on the board and applied at power-on. Loading a preset never changes it. Save it from the menu with Save Master Volume."
                  : "Master volume is part of each preset and changes when you load one."
        SettingsChoiceRow {
            title: "Storage"
            options: [{ text: "Independent", value: 0 }, { text: "With Preset", value: 1 }]
            value: ctx ? ctx.masterVolumeMode : 0
            onChosen: ctx.edit("masterVolumeMode", value)
        }
    }

    SettingsSection {
        title: "Hardware Configuration"
        enabled: bridge.connected
        footnote: ctx && ctx.outputConfigMode === 0
                  ? "Pins, output types, clocks, input configuration and output limiters are stored once for the board. Choose this when your hardware is fixed."
                  : "The hardware configuration is part of each preset and changes when you load one."
        SettingsChoiceRow {
            title: "Storage"
            options: [{ text: "Independent", value: 0 }, { text: "With Preset", value: 1 }]
            value: ctx ? ctx.outputConfigMode : 1
            onChosen: ctx.edit("outputConfigMode", value)
        }
    }
}
