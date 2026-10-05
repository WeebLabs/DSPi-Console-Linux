import QtQuick 2.15
import "../"
import "../cs"

// Auxiliary outputs: GPIOs the device switches or dims for external
// equipment. They share the binding slots with the controls.
SettingsPage {
    id: page
    title: "Auxiliary Outputs"
    subtitle: "Pins that switch or dim external equipment: an amplifier trigger, a speaker relay, a panel lamp, a fan."

    CsHelper { id: cs }
    readonly property var csHelper: cs

    CsControlsView { cs: page.csHelper; auxPage: true }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        leftPadding: 4
        rightPadding: 4
        text: "An on/off output follows its switch. A dimmable output follows its switch and its level, so one button and one knob can share a lamp. Turn on \"Active-Low Output\" for the relay and opto-isolator boards that switch when the pin goes low.\n\nA GPIO is a 3.3 V pin good for a few milliamps. Anything real needs a MOSFET, a transistor with a flyback diode, or an opto-isolated relay module in between, and a dimmed load should have its own supply so its switching noise stays out of the DAC.\n\nSwitching an output is instant and never writes to flash. The pin, name and power-on behaviour are stored on the device alongside the controls and share their Save and Revert."
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.45)
    }
}
