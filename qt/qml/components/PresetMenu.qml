import QtQuick 2.15
import QtQuick.Controls 2.15

// Right-click menu of the preset picker (as on the macOS Console): Save,
// Rename, Set as Default, Copy to, Clear the slot, Clear All Slots. Acts on
// the active slot. openAt(item, x, y) opens it at a point in `item`; the
// Copy to slot list opens under `anchorItem`.
Item {
    id: pm
    property Item anchorItem

    readonly property int slot: bridge.activePresetSlot

    function slotName(i) {
        if (!bridge.isPresetOccupied(i)) return "Empty"
        var n = bridge.presetName(i)
        return n === "" ? "Preset " + (i + 1) : n
    }
    function slotLabel(i) { return (i + 1) + ": " + slotName(i) }
    // Saving an unnamed slot gives it its default name, so the picker
    // doesn't keep showing it as "Empty"
    function ensureName(i) {
        if (bridge.presetName(i) === "") bridge.setPresetName(i, "Preset " + (i + 1))
    }
    function report(status, what) {
        if (status === 0) return
        errorDialog.title = what + " Failed"
        errorDialog.message = "The device reported error " + status + "."
        errorDialog.open()
    }

    function openAt(item, x, y) {
        var anyOccupied = bridge.presetOccupied !== 0
        var items = [
            { key: "save", text: "Save", icon: "save" },
            { key: "rename", text: "Rename…", icon: "pencil" },
            { key: "default", text: "Set as Default",
              enabled: !(bridge.presetStartupMode === 0 && bridge.presetDefaultSlot === slot) },
            { key: "copy", text: "Copy to…", icon: "copy" }
        ]
        if (bridge.isPresetOccupied(slot))
            items.push({ separator: true },
                       { key: "clear", text: "Clear “" + slotLabel(slot) + "”…", danger: true })
        if (anyOccupied)
            items.push({ separator: true },
                       { key: "clearAll", text: "Clear All Slots…", danger: true })
        menu.items = items
        menu.openAt(item, x, y)
    }

    ActionMenu {
        id: menu
        parent: Overlay.overlay
        onTriggered: {
            if (key === "save") {
                pm.ensureName(pm.slot)
                pm.report(bridge.savePreset(pm.slot), "Save")
            } else if (key === "rename") {
                renameDialog.renameSlot = pm.slot
                renameDialog.inputText = pm.slotName(pm.slot) === "Empty" ? "" : pm.slotName(pm.slot)
                renameDialog.open()
            } else if (key === "default") {
                bridge.setPresetStartup(0, pm.slot)
            } else if (key === "copy") {
                var o = []
                for (var i = 0; i < 10; i++)
                    if (i !== pm.slot)
                        o.push({ value: i, prefix: String(i + 1), text: pm.slotName(i) })
                copyMenu.options = o
                copyMenu.openAt(pm.anchorItem)
            } else if (key === "clear") {
                clearDialog.clearSlot = pm.slot
                clearDialog.open()
            } else if (key === "clearAll") {
                clearAllDialog.open()
            }
        }
    }

    ChoiceMenu {
        id: copyMenu
        parent: Overlay.overlay
        alignRight: true
        currentValue: -1
        onChosen: {
            if (bridge.isPresetOccupied(value)) {
                replaceDialog.destSlot = value
                replaceDialog.open()
            } else pm.copyTo(value)
        }
    }

    // Copies the current settings (saving them to the active slot as well),
    // after asking about unsaved changes: Save keeps them, Discard reloads
    // the active slot first
    function copyTo(dest) {
        var src = slot
        root.withUnsaved(function (choice) {
            if (choice === "discard") bridge.loadPreset(src)
            ensureName(src)
            ensureName(dest)
            report(bridge.copyPreset(src, dest), "Copy")
        })
    }

    AppDialog {
        id: renameDialog
        property int renameSlot: 0
        icon: "pencil"
        title: "Rename Preset " + (renameSlot + 1)
        hasInput: true
        placeholder: "Preset " + (renameSlot + 1)
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "rename", text: "Rename", role: "primary" }
        ]
        onChosen: {
            var name = inputText.trim()
            if (key === "rename" && name !== "") bridge.setPresetName(renameSlot, name)
        }
    }

    AppDialog {
        id: replaceDialog
        property int destSlot: 0
        icon: "copy"
        title: "Replace “" + pm.slotLabel(destSlot) + "”?"
        message: "Its settings will be replaced with the current ones. Its name stays the same."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "replace", text: "Replace", role: "destructive" }
        ]
        onChosen: if (key === "replace") pm.copyTo(destSlot)
    }

    AppDialog {
        id: clearDialog
        property int clearSlot: 0
        icon: "warning"
        iconTint: "#ff6961"
        title: "Clear Preset?"
        message: "Clear “" + pm.slotLabel(clearSlot) + "” and restore factory defaults? This cannot be undone."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "clear", text: "Clear", role: "destructive" }
        ]
        onChosen: if (key === "clear") pm.report(bridge.deletePreset(clearSlot), "Clear")
    }

    AppDialog {
        id: clearAllDialog
        icon: "warning"
        iconTint: "#ff6961"
        title: "Clear All Presets?"
        message: "This erases all preset data and names, restoring every slot to factory defaults. This cannot be undone."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "clearAll", text: "Clear All", role: "destructive" }
        ]
        onChosen: {
            if (key !== "clearAll") return
            for (var i = 0; i < 10; i++) {
                if (!bridge.isPresetOccupied(i)) continue
                var status = bridge.deletePreset(i)
                if (status !== 0) { pm.report(status, "Clear"); return }
            }
        }
    }

    AppDialog {
        id: errorDialog
        icon: "warning"
        iconTint: "#ff9f0a"
        buttons: [{ key: "ok", text: "OK", role: "primary" }]
    }
}
