import QtQuick 2.15
import "../"

// Spectrum analyser preferences. Display options live on the main window
// (and persist there); the engine options are sent to the device whenever
// the analyser runs and are not stored on it.
SettingsPage {
    id: page
    title: "Spectrum Analyser"
    subtitle: "How the device's spectrum analyser looks and measures. Pick the channels with the gear on the response graph."
    readonly property var app: ctx ? ctx.app : null

    SettingsSection {
        title: "Display"
        SettingsSliderRow {
            title: "Spectrum Strength"
            from: 0.3; to: 1.0; stepSize: 0.05
            value: app ? app.rtaGraphOpacity : 1.0
            format: function (v) { return Math.round(v * 100) + "%" }
            onMoved: app.rtaGraphOpacity = value
            onCommitted: app.rtaGraphOpacity = value
        }
        SettingsSwitchRow {
            title: "Peak Hold"
            detail: "A thin line (or cap on the bars) at each band's recent peak."
            checked: app ? app.rtaShowPeakHold : true
            onToggled: app.rtaShowPeakHold = checked
        }
        SettingsSwitchRow {
            title: "Smoothing"
            detail: "Glide between the device's frames instead of stepping."
            checked: app ? app.rtaSmoothing : true
            onToggled: app.rtaSmoothing = checked
        }
        SettingsChoiceRow {
            title: "Floor"
            options: [{ text: "−60 dBFS", value: -60 }, { text: "−90 dBFS", value: -90 }, { text: "−120 dBFS", value: -120 }]
            value: app ? app.rtaFloorDb : -90
            onChosen: app.rtaFloorDb = value
        }
        SettingsChoiceRow {
            title: "Ceiling"
            options: [{ text: "0 dBFS", value: 0 }, { text: "+6 dBFS", value: 6 }, { text: "+12 dBFS", value: 12 }]
            value: app ? app.rtaCeilingDb : 6
            onChosen: app.rtaCeilingDb = value
        }
    }

    SettingsSection {
        title: "Engine"
        footnote: !rta.supported ? (bridge.connected ? "This firmware has no spectrum analyser." : "Connect a DSPi to see what its analyser can do.")
                  : "This device reports " + rta.dynamicRange + " dB of usable range and transforms up to "
                    + Math.pow(2, rta.orderMax) + " points."
        SettingsSegmentedRow {
            title: "Transform Size"
            detail: "Larger transforms resolve lower bands but refresh each channel less often."
            options: ["256", "512", "1024"]
            controlWidth: 210
            value: app ? app.rtaFftOrder - 8 : 2
            onChosen: app.rtaFftOrder = index + 8
        }
        SettingsChoiceRow {
            title: "Averaging"
            options: [{ text: "Off", value: 0 }, { text: "50 ms", value: 50 }, { text: "125 ms", value: 125 },
                      { text: "300 ms", value: 300 }, { text: "1 s", value: 1000 }, { text: "3 s", value: 3000 }]
            value: app ? app.rtaAvgMs : 300
            onChosen: app.rtaAvgMs = value
        }
        SettingsChoiceRow {
            title: "Peak Decay"
            enabled: app ? app.rtaShowPeakHold : true
            options: [{ text: "Off", value: 0 }, { text: "4 dB/s", value: 4 }, { text: "12 dB/s", value: 12 }, { text: "30 dB/s", value: 30 }]
            value: app ? app.rtaPeakDecay : 12
            onChosen: app.rtaPeakDecay = value
        }
    }
}
