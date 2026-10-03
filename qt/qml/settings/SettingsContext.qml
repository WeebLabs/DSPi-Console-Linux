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
    property bool edited: false

    readonly property bool dirty: edited && bridge.connected && (
        startupMode !== bridge.presetStartupMode
        || (startupMode === 0 && defaultSlot !== bridge.presetDefaultSlot)
        || masterVolumeMode !== bridge.masterVolumeMode
        || outputConfigMode !== bridge.outputConfigMode)

    function load() {
        startupMode = bridge.presetStartupMode
        defaultSlot = bridge.presetDefaultSlot
        masterVolumeMode = bridge.masterVolumeMode
        outputConfigMode = bridge.outputConfigMode
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
        edited = false
    }

    function revert() { load() }

    // Follow the device while there is no draft
    property Connections bridgeWatch: Connections {
        target: bridge
        function onStateChanged() { if (!ctx.edited) ctx.load() }
    }
    Component.onCompleted: load()
}
