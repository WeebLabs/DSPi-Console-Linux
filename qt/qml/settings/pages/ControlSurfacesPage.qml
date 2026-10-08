import QtQuick 2.15
import "../"
import "../cs"
import "../../components"

// Control Surfaces: buttons, switches, knobs, encoders, LEDs, an IR remote
// receiver and a display wired to spare GPIOs, each bound to a function.
SettingsPage {
    id: page
    title: "Control Surfaces"
    subtitle: "Wire physical controls to spare GPIOs and bind each to a device function. They work on their own, without Console running."

    CsHelper { id: cs }
    readonly property var csHelper: cs

    CsControlsView { cs: page.csHelper }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        leftPadding: 4
        rightPadding: 4
        text: "Buttons and switches wire between the GPIO and GND (internal pull-up); pots use an ADC pin (GPIO 26, 27, or 28) between 3V3 and GND; encoders use two GPIOs with the common wired to GND. LEDs drive active-high by default. An IR receiver module's OUT pin connects to any GPIO, and its remote buttons are learned by pressing them at the device.\n\nThis wiring is a board-level setting: it is stored on the device, survives preset changes, and survives a factory reset. Applied changes work at once; Save keeps them across a restart."
              + (cs.supported && cs.m.capsVersion ? "\n\nControl-surface capability version " + cs.m.capsVersion + "." : "")
        font.pixelSize: 11
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45)
    }
}
