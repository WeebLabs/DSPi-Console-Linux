import QtQuick 2.15
import "../"

// Graph preferences live on the main window (and persist there).
SettingsPage {
    id: page
    title: "Graphing"
    subtitle: "How the response graph looks. These are preferences on this computer and take effect immediately."
    readonly property var app: ctx ? ctx.app : null

    SettingsSection {
        title: "Curves"
        SettingsSwitchRow {
            title: "Graph Line Glow"
            detail: "A soft glow behind the response curves."
            checked: app ? app.graphShowGlow : false
            onToggled: app.graphShowGlow = checked
        }
        SettingsSliderRow {
            title: "Line Width"
            from: 1; to: 4; stepSize: 0.5
            value: app ? app.graphLineWidth : 1.5
            format: function (v) { return v.toFixed(1) + " pt" }
            onMoved: app.graphLineWidth = value
            onCommitted: app.graphLineWidth = value
        }
        SettingsSwitchRow {
            title: "Show Phase Response"
            detail: "Overlay the selected channel's phase (degrees) as a dotted line."
            checked: app ? app.graphShowPhase : false
            onToggled: app.graphShowPhase = checked
        }
        SettingsSwitchRow {
            title: "Unwrap Phase"
            detail: "Show continuous phase instead of wrapping at ±180°."
            enabled: app ? app.graphShowPhase : false
            checked: app ? app.graphPhaseUnwrapped : false
            onToggled: app.graphPhaseUnwrapped = checked
        }
    }

    SettingsSection {
        title: "Pop-Out Graph"
        SettingsSwitchRow {
            title: "Follow Channel Selection"
            detail: "The pop-out graph shows the channels the main window shows. Off, it keeps its own, picked with the pills under it."
            checked: app ? app.graphPopOutFollows : true
            onToggled: app.graphPopOutFollows = checked
        }
    }

    SettingsSection {
        title: "Editing"
        footnote: "Drag a band's dot to change it; Shift for fine steps, Alt to keep to one axis, Ctrl-drag or the wheel for its width. Double-click empty graph to add a band."
        SettingsSwitchRow {
            title: "Show Frequency Readout"
            detail: "While editing bands, label the frequency under the pointer along the bottom of the graph."
            checked: app ? app.graphFreqReadout : true
            onToggled: app.graphFreqReadout = checked
        }
        SettingsSwitchRow {
            title: "Show Gain Readout"
            detail: "Label the level under the pointer along the left edge: the gain a new band takes there."
            checked: app ? app.graphLevelReadout : true
            onToggled: app.graphLevelReadout = checked
        }
    }

    SettingsSection {
        title: "Grid and Labels"
        SettingsSwitchRow { title: "Frequency Grid"; checked: app ? app.graphShowFreqGrid : true; onToggled: app.graphShowFreqGrid = checked }
        SettingsSwitchRow { title: "Frequency Labels"; checked: app ? app.graphShowFreqLabels : true; onToggled: app.graphShowFreqLabels = checked }
        SettingsSwitchRow { title: "dB Grid"; checked: app ? app.graphShowDbGrid : true; onToggled: app.graphShowDbGrid = checked }
        SettingsSwitchRow { title: "dB Labels"; checked: app ? app.graphShowDbLabels : true; onToggled: app.graphShowDbLabels = checked }
        SettingsSliderRow {
            title: "Grid Opacity"
            enabled: app ? app.graphShowFreqGrid || app.graphShowDbGrid : true
            from: 0; to: 2; stepSize: 0.05
            value: app ? app.graphGridOpacity : 0.5
            format: function (v) { return Math.round(v * 100) + "%" }
            onMoved: app.graphGridOpacity = value
            onCommitted: app.graphGridOpacity = value
        }
    }

    SettingsSection {
        title: "Range"
        SettingsSliderRow {
            title: "Vertical Range"
            from: 10; to: 100; stepSize: 1
            value: app ? app.graphDbRange : 50
            format: function (v) { return Math.round(v) + " dB" }
            onMoved: app.graphDbRange = Math.round(value)
            onCommitted: app.graphDbRange = Math.round(value)
        }
        SettingsSliderRow {
            title: "Center"
            detail: app ? "Shows +" + (Math.round(app.graphDbCenter) + app.graphDbRange / 2) + " to "
                          + (Math.round(app.graphDbCenter) - app.graphDbRange / 2) + " dB" : ""
            from: -40; to: 20; stepSize: 1
            value: app ? app.graphDbCenter : 0
            format: function (v) { return (v > 0 ? "+" : "") + Math.round(v) + " dB" }
            onMoved: app.graphDbCenter = Math.round(value)
            onCommitted: app.graphDbCenter = Math.round(value)
        }
        SettingsChoiceRow {
            title: "Min Frequency"
            options: [{ text: "10 Hz", value: 10 }, { text: "15 Hz", value: 15 }, { text: "20 Hz", value: 20 },
                      { text: "50 Hz", value: 50 }, { text: "100 Hz", value: 100 }]
            value: app ? app.graphMinFreq : 15
            onChosen: app.graphMinFreq = value
        }
        SettingsChoiceRow {
            title: "Max Frequency"
            options: [{ text: "5 kHz", value: 5000 }, { text: "10 kHz", value: 10000 }, { text: "20 kHz", value: 20000 }]
            value: app ? app.graphMaxFreq : 20000
            onChosen: app.graphMaxFreq = value
        }
    }
}
