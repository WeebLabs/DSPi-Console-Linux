import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

// The Getting Started wizard: replaces the console inside the main window on
// first launch (and from Help), as on macOS. One objective - a board running
// verified DSPi firmware - in three steps: Welcome, Board, Done. The firmware
// install happens right here, through the same updater as Firmware Update.
Rectangle {
    id: wiz
    color: isMacOS ? MacColors.windowMaterial : nativeWindowColor
    signal finished()

    readonly property var stages: ["Welcome", "Board", "Done"]
    property int stage: 0
    property bool confirmed: false
    property bool rebootRequested: false

    readonly property string phase: firmware.state
    readonly property string bundled: firmware.expectedVersion || "unknown"
    readonly property bool installing: phase === "writing" || phase === "waitingForDevice"
    // A running DSPi the board step talks about instead of a bootloader:
    // 1 matches, 2 older, 3 newer (0 = none, or the installer owns the step)
    readonly property int connectedMatch: !confirmed && bridge.connected && (phase === "idle" || phase === "waitingForBoard")
                                          ? firmware.match : 0

    // Detection runs only while the board step is on screen
    onStageChanged: {
        if (stage === 1) { resetRun(); firmware.beginWatching() }
        else firmware.stopWatching()
    }
    Component.onDestruction: firmware.stopWatching()

    function resetRun() {
        confirmed = false
        rebootRequested = false
        firmware.reset()
    }
    // Onto a board already in BOOTSEL
    function beginInstall() {
        confirmed = true
        firmware.installWhenReady()
    }
    // Onto the DSPi already connected: restart it into the bootloader first
    function beginConnectedInstall() {
        confirmed = true
        firmware.installWhenReady()
        if (!rebootRequested) { rebootRequested = true; firmware.enterBootloader() }
    }
    function advance() {
        if (stage < stages.length - 1) stage++
        else finished()
    }

    readonly property string boardTitle: {
        switch (phase) {
        case "verified": return "Your device has been prepared"
        case "failed": return "Something needs attention"
        case "writing": case "waitingForDevice": return "Installing firmware"
        }
        switch (connectedMatch) {
        case 1: return "Your device is ready"
        case 2: return "Update your firmware"
        case 3: return "Your firmware is newer"
        default: return "Prepare your Pico"
        }
    }
    readonly property string boardBlurb: {
        switch (phase) {
        case "writing": case "waitingForDevice":
            return "Console ships the firmware it expects, so nothing needs a download. Keep the Pico plugged in until it checks back in."
        case "verified":
            return "The device has successfully restarted and DSPi Firmware is correctly installed."
        case "failed":
            return "This is almost always fixable. Follow the card below, then try again - nothing has been lost."
        }
        switch (connectedMatch) {
        case 1: return "This step installs the DSPi firmware, and your connected device is already running it. There is nothing to do here."
        case 2: return "Your DSPi is already connected, so no buttons need holding: the app can restart it and install the matching firmware in one step."
        case 3: return "This Console ships an older firmware than your device is running. Updating the app is usually the better fix, but you can also downgrade the device to match."
        default: return "In this step, we are going to install the DSPi firmware on your Pico-compatible device. Follow the directions below."
        }
    }
    // The board step's card: { icon, tint, spin, size, title, text, action, actionPrimary }
    readonly property var card: {
        switch (phase) {
        case "idle": case "waitingForBoard":
            if (confirmed) return { spin: true, title: "Looking for your Pico",
                text: "Waiting for it to appear in bootloader mode. If nothing happens after a few seconds, unplug it, hold BOOTSEL, and plug it back in." }
            if (connectedMatch === 1) return { icon: "check-circle", tint: isMacOS ? MacColors.green : "#32d74b", size: 36, title: "Firmware " + bundled + " already installed",
                text: "Your DSPi is running the firmware this Console ships, so there is nothing to install. Continue to finish setup." }
            if (connectedMatch === 2) return { icon: "arrow-up", title: "Firmware update available",
                text: "Your DSPi is running firmware " + firmware.deviceVersion + "; this Console pairs with " + bundled
                      + ". The device will restart into bootloader mode and come back updated. Audio stops until it finishes.",
                action: "Update DSPi Firmware", actionPrimary: true }
            if (connectedMatch === 3) return { icon: "arrow-down-circle", tint: isMacOS ? MacColors.orange : "#ff9f0a", title: "This would be a downgrade",
                text: "Your DSPi is running firmware " + firmware.deviceVersion + ", which is newer than this Console expects (" + bundled
                      + "). A newer Console is the better fix, but you can downgrade the device to match this one.",
                action: "Downgrade Firmware", actionPrimary: false }
            return { spin: true, title: "Waiting for your Pico",
                text: "Hold the BOOTSEL button while connecting your Pico-compatible device to your computer. Once detected, it will appear here." }
        case "waitingForVolume":
            return { spin: true, title: firmware.chipName + " found",
                text: "The board is in bootloader mode. Waiting for its " + firmware.volumeName + " drive to mount - this usually takes a second or two." }
        case "ready":
            if (confirmed) return { spin: true, title: "Preparing to write",
                text: "Opening the " + firmware.chipName + "'s " + firmware.volumeName + " drive." }
            return { icon: "drive", tint: isMacOS ? MacColors.green : "#32d74b", title: firmware.chipName + " ready",
                text: "The device is now in bootloader mode and ready to receive firmware.",
                action: "Install DSPi Firmware", actionPrimary: true }
        case "waitingForDevice":
            return { spin: true, title: "Firmware written",
                text: "The board is restarting with its new firmware. This can take up to half a minute; leave it plugged in." }
        case "verified":
            return { icon: "check-circle", tint: isMacOS ? MacColors.green : "#32d74b", size: 36, title: "Firmware " + firmware.verifiedVersion + " installed",
                text: "That was the whole job. Continue to finish setup." }
        case "failed":
            return { icon: firmware.failureMundane ? "question-circle" : "warning", tint: isMacOS ? MacColors.orange : "#ff9f0a",
                title: firmware.failureMundane ? "Not quite ready" : "The update did not complete", text: firmware.failure,
                action: "Try Again", actionPrimary: false }
        default:
            return { title: "", text: "" }
        }
    }
    function cardAction() {
        if (phase === "failed") resetRun()
        else if (phase === "ready") beginInstall()
        else beginConnectedInstall()
    }
    // Continue on the board step only once there is nothing left to do there
    readonly property bool showsContinue: stage !== 1 || phase === "verified" || connectedMatch === 1

    component InfoRow: Row {
        property string icon: ""
        property string text: ""
        width: parent ? parent.width : 400
        spacing: 10
        Icon { name: parent.icon; size: 16; color: isMacOS ? MacColors.accent : "#3a96ff" }
        Text {
            width: parent.width - 26
            wrapMode: Text.WordWrap
            text: parent.text
            font.pixelSize: 12
            color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.85)
        }
    }

    // ── Header ──
    Item {
        id: header
        width: parent.width
        height: 104
        Rectangle {
            id: tile
            x: 24
            y: 14
            width: 28; height: 28; radius: 7
            color: isMacOS ? "transparent" : "#0a7cff"
            Icon { anchors.centerIn: parent; name: "cap"; size: 18; color: isMacOS ? MacColors.accent : "white" }
        }
        Column {
            anchors.left: tile.right
            anchors.leftMargin: 10
            anchors.verticalCenter: tile.verticalCenter
            spacing: 1
            Text { text: "Getting Started"; font.pixelSize: 14; font.weight: Font.DemiBold; color: isMacOS ? MacColors.label : "white" }
            Text { text: "Step " + (wiz.stage + 1) + " of " + wiz.stages.length; font.pixelSize: 11; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5) }
        }
        StepStrip {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 56
            width: Math.min(420, parent.width - 48)
            labels: wiz.stages
            current: wiz.stage
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }
    }

    // ── Content ──
    Flickable {
        id: scroller
        anchors.top: header.bottom
        anchors.bottom: footer.top
        width: parent.width
        contentHeight: content.height + 56
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: content
            y: 28
            width: Math.min(560, scroller.width - 56)
            x: (scroller.width - width) / 2
            spacing: 16

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: wiz.stage === 0 ? "Welcome to DSPi Console" : wiz.stage === 1 ? wiz.boardTitle : "You are set up"
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: isMacOS ? MacColors.label : "white"
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: wiz.stage === 0
                      ? "DSPi turns a Raspberry Pi Pico into a remarkably capable audio processor: equalisation, crossovers, upmixing, loudness compensation and more, applied live to whatever you play.\n\nSetup is short and has one job: getting the DSPi firmware onto your Pico. Once it is running, everything else is set up in the app as you need it."
                      : wiz.stage === 1 ? wiz.boardBlurb
                      : "Your Pico is running the DSPi firmware, and the console is ready whenever it is plugged in. A few places worth knowing about:"
                font.pixelSize: 13
                lineHeight: 1.15
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.6)
            }

            // Welcome
            Column {
                visible: wiz.stage === 0
                width: parent.width
                spacing: 12
                InfoRow { icon: "plug"; text: "Connect your Pico and install the DSPi firmware, right here." }
                InfoRow { icon: "check-circle"; text: "The board restarts and the app confirms the install worked." }
                InfoRow { icon: "sliders"; text: "Outputs, wiring and audio are then yours to shape in the console." }
            }

            // Board: the install happens in place
            Item {
                visible: wiz.stage === 1
                width: parent.width
                height: 210
                InstallStateCard {
                    anchors.fill: parent
                    visible: wiz.phase !== "writing"
                    icon: wiz.card.icon || ""
                    tint: isMacOS ? wiz.card.tint || MacColors.accent : wiz.card.tint || "#3a96ff"
                    spin: wiz.card.spin === true
                    iconSize: wiz.card.size || 28
                    title: wiz.card.title
                    text: wiz.card.text
                    AppButton {
                        visible: !!wiz.card.action
                        text: wiz.card.action || ""
                        primary: wiz.card.actionPrimary === true
                        onClicked: wiz.cardAction()
                    }
                }
                InstallWritingCard {
                    anchors.fill: parent
                    visible: wiz.phase === "writing"
                    progress: firmware.progress
                    boardName: firmware.chipName
                    version: wiz.bundled
                }
            }

            // Done
            Column {
                visible: wiz.stage === 2
                width: parent.width
                spacing: 12
                InfoRow { icon: "output"; text: "Choose which outputs your build uses, and the pins that carry them, in Settings under Outputs." }
                InfoRow { icon: "speaker"; text: "Pick DSPi as the output device in your desktop's sound settings to hear your computer through it." }
                InfoRow { icon: "sliders"; text: "Click an input or output in the sidebar to edit its filters." }
                InfoRow { icon: "question-circle"; text: "Help in the app menu holds release notes and links, and this wizard can be run again." }
            }
        }
    }

    // ── Footer ──
    Item {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: 56
        Rectangle { width: parent.width; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }
        // Always there, one click, and it never comes back
        AppButton {
            x: 24
            anchors.verticalCenter: parent.verticalCenter
            text: "Skip Setup"
            onClicked: wiz.finished()
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            AppButton {
                visible: wiz.stage > 0 && !wiz.installing
                text: "Back"
                onClicked: wiz.stage--
            }
            AppButton {
                visible: wiz.showsContinue
                text: wiz.stage === wiz.stages.length - 1 ? "Start Using DSPi Console" : "Continue"
                // The install button owns the emphasis while it is on screen
                primary: !(wiz.stage === 1 && !!wiz.card.action && wiz.card.actionPrimary)
                onClicked: wiz.advance()
            }
        }
    }
}
