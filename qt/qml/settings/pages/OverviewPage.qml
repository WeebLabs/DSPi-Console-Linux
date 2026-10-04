import QtQuick 2.15
import QtQuick.Controls 2.15
import "../"
import "../../components"

// Which GPIO does what: a map of the wirable pins coloured by role, then a
// list per role. Read-only; change pins on the Inputs, Outputs, I2S and
// Control Interfaces pages.
SettingsPage {
    id: page
    title: "Overview"
    subtitle: "Every GPIO the device has claimed, by what uses it."

    readonly property var roles: [
        { key: "output", title: "Outputs", color: "#0278c7" },
        { key: "clock", title: "Clocks", color: "#ba3822" },
        { key: "input", title: "Inputs", color: "#04856f" },
        { key: "control", title: "Control", color: "#9543a7" },
        { key: "other", title: "Other", color: "#807701" }]
    function roleColor(key) {
        for (var i = 0; i < roles.length; i++) if (roles[i].key === key) return roles[i].color
        return "#807701"
    }

    readonly property var owners: { bridge.hardware; return bridge.connected ? bridge.pinOwners() : [] }
    readonly property var byPin: {
        var m = {}
        for (var i = 0; i < owners.length; i++) if (m[owners[i].pin] === undefined) m[owners[i].pin] = owners[i]
        return m
    }
    readonly property int used: {
        var n = 0, pins = bridge.validPins
        for (var i = 0; i < pins.length; i++) if (byPin[pins[i]] !== undefined) n++
        return n
    }

    // ── Map ──
    SettingsSection {
        title: bridge.connected ? page.used + " of " + bridge.validPins.length + " GPIOs in use" : "Pins"
        footnote: bridge.connected ? (bridge.validPins.length - page.used) + " free. GPIO 23-25 are wired inside the Pico and not offered."
                                   : "Pin assignments live on the device. Connect a DSPi to see which GPIOs are in use."

        Item {
            width: parent.width
            height: map.height + 28
            Flow {
                id: map
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 6
                Repeater {
                    model: bridge.validPins
                    Rectangle {
                        readonly property var owner: page.byPin[modelData]
                        width: 52
                        height: 30
                        radius: 7
                        color: owner ? Qt.darker(page.roleColor(owner.role), 1.15) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: owner ? Qt.lighter(page.roleColor(owner.role), 1.3) : Qt.rgba(1, 1, 1, 0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "GP" + modelData
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: parent.owner ? "white" : Qt.rgba(1, 1, 1, 0.4)
                        }
                        MouseArea {
                            id: chipHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                        ToolTip.visible: chipHover.containsMouse
                        ToolTip.delay: 300
                        ToolTip.text: "GPIO " + modelData + ": " + (owner ? owner.owner : "free")
                    }
                }
            }
        }
        // Legend
        Item {
            width: parent.width
            height: 34
            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Repeater {
                    model: page.roles
                    Row {
                        spacing: 5
                        Rectangle { width: 10; height: 10; radius: 3; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.title; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.6) }
                    }
                }
            }
        }
    }

    // ── Per role ──
    Repeater {
        model: bridge.connected ? page.roles : []
        SettingsSection {
            id: roleSection
            readonly property var members: page.owners.filter(function(o) { return o.role === modelData.key })
                                                      .sort(function(a, b) { return a.pin - b.pin })
            visible: members.length > 0
            title: modelData.title
            Repeater {
                model: roleSection.members
                SettingsValueRow {
                    title: modelData.owner
                    value: "GPIO " + modelData.pin
                }
            }
        }
    }

    Text {
        visible: bridge.connected && page.owners.length === 0
        text: "No GPIOs are currently claimed."
        font.pixelSize: 13
        color: Qt.rgba(1, 1, 1, 0.5)
    }
}
