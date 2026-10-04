import QtQuick 2.15

// Shared state for the Settings pages: the app and window, navigation, and
// the draft of board-wide settings that are only written on Save.
QtObject {
    id: ctx
    property var app                 // main window (graph preferences live there)
    property var window              // the Settings window
    signal navigateRequested(string pageId)
    function navigate(pageId) { navigateRequested(pageId) }

    // ── Global Parameters draft ──
    // Edited freely; nothing reaches the device until save().
    property int startupMode: 0          // 0 = specified default, 1 = last used
    property int defaultSlot: 0
    property int masterVolumeMode: 0     // 0 = independent, 1 = with preset
    property int outputConfigMode: 1     // 0 = independent, 1 = with preset
    // External DAC mute (Global Parameters), sent on Save as on macOS
    property bool dacEnabled: false
    property bool dacActiveLow: true
    property int dacPin: 0xFF
    property int dacHoldMs: 5
    property int dacReleaseMs: 0
    property bool edited: false

    readonly property bool dacDirty: {
        var h = bridge.hardware
        return dacEnabled !== h.dacMuteEnabled || (dacEnabled && (dacActiveLow !== h.dacMuteActiveLow
            || dacPin !== h.dacMutePin || dacHoldMs !== h.dacMuteHoldMs || dacReleaseMs !== h.dacMuteReleaseMs))
    }
    readonly property bool draftDirty: edited && bridge.connected && (
        startupMode !== bridge.presetStartupMode
        || (startupMode === 0 && defaultSlot !== bridge.presetDefaultSlot)
        || masterVolumeMode !== bridge.masterVolumeMode
        || outputConfigMode !== bridge.outputConfigMode
        || dacDirty)
    // Hardware edits in independent mode are RAM-only until the output
    // config is saved; they share the save bar (but cannot be reverted)
    readonly property bool hardwareDirty: bridge.connected && bridge.hardwareUnsaved
    readonly property bool dirty: draftDirty || hardwareDirty

    function load() {
        startupMode = bridge.presetStartupMode
        defaultSlot = bridge.presetDefaultSlot
        masterVolumeMode = bridge.masterVolumeMode
        outputConfigMode = bridge.outputConfigMode
        var h = bridge.hardware
        dacEnabled = h.dacMuteEnabled
        dacActiveLow = h.dacMuteActiveLow
        dacPin = h.dacMutePin
        dacHoldMs = h.dacMuteHoldMs
        dacReleaseMs = h.dacMuteReleaseMs
        edited = false
    }

    function edit(name, value) {
        ctx[name] = value
        edited = true
    }

    function save() {
        if (startupMode !== bridge.presetStartupMode || defaultSlot !== bridge.presetDefaultSlot)
            bridge.setPresetStartup(startupMode, defaultSlot)
        if (masterVolumeMode !== bridge.masterVolumeMode)
            bridge.setMasterVolumeMode(masterVolumeMode)
        if (outputConfigMode !== bridge.outputConfigMode)
            bridge.setOutputConfigMode(outputConfigMode)
        if (dacDirty)
            bridge.setDacMute(dacEnabled, dacActiveLow, dacPin, dacHoldMs, dacReleaseMs)
        if (hardwareDirty)
            bridge.saveOutputConfig()
        edited = false
    }

    // ── Pins ──

    // Who holds a GPIO ("" = free), as the firmware reserves it
    function ownerOf(pin) {
        var owners = bridge.pinOwners()
        for (var i = 0; i < owners.length; i++)
            if (owners[i].pin === pin) return owners[i].owner
        return ""
    }
    // Picker options for a GPIO: the wirable pins nothing else holds, plus
    // `pin` itself. accept(p) narrows the list; owners named in `sharable`
    // don't count as holding their pin.
    function pinOptions(pin, accept, sharable, allowUnset, unsetText) {
        var owners = bridge.pinOwners(), taken = {}
        for (var i = 0; i < owners.length; i++)
            if (!sharable || sharable.indexOf(owners[i].owner) < 0) taken[owners[i].pin] = true
        var list = []
        if (allowUnset) list.push({ text: unsetText || "Not set", value: 0xFF })
        var pins = bridge.validPins
        for (var k = 0; k < pins.length; k++) {
            var p = pins[k]
            if (p !== pin && (taken[p] || (accept && !accept(p)))) continue
            list.push({ text: "GPIO " + p, value: p })
        }
        if (pin !== 0xFF && pins.indexOf(pin) < 0) list.push({ text: "GPIO " + pin, value: pin })
        return list
    }
    function optionIndex(options, value) {
        for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
        return -1
    }

    // A PIN_CONFIG_* status as a sentence ("" for success)
    function statusText(code, pin) {
        switch (code) {
        case 0: return ""
        case 1: return pin !== undefined ? "GPIO " + pin + " can't be used for this." : "That pin can't be used for this."
        case 2: {
            var who = pin !== undefined ? ownerOf(pin) : ""
            return pin !== undefined ? "GPIO " + pin + " is already assigned" + (who !== "" ? " to " + who : "") + "."
                                     : "That pin is already in use."
        }
        case 3: return "This isn't supported on this device."
        case 4: return "Turn this off before changing it."
        case 5: return "That value is out of range."
        case 255: return "The device did not respond."
        default: return "Error " + code + "."
        }
    }

    function revert() { load() }

    // Follow the device while there is no draft
    property Connections bridgeWatch: Connections {
        target: bridge
        function onStateChanged() { if (!ctx.edited) ctx.load() }
    }
    Component.onCompleted: load()
}
