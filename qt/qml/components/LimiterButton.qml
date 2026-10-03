import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// Output limiter gauge: click toggles the limiter, right-click opens its
// settings. Grey = off, accent = on, orange = reducing the level now.
Rectangle {
    id: btn
    width: 36
    height: 24
    radius: 6
    color: hover.containsMouse || popup.visible ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

    property int outputIndex: 0
    property bool enabled_: bridge.limiterEnabled(outputIndex)
    property real reduction: bridge.limiterReduction(outputIndex)
    property real threshold: bridge.limiterThreshold(outputIndex)
    property real release: bridge.limiterRelease(outputIndex)
    property int linkGroup: bridge.limiterLinkGroup(outputIndex)
    readonly property bool limiting: enabled_ && reduction > 0.05

    Connections {
        target: bridge
        function onStateChanged() {
            btn.enabled_ = bridge.limiterEnabled(btn.outputIndex)
            btn.threshold = bridge.limiterThreshold(btn.outputIndex)
            btn.release = bridge.limiterRelease(btn.outputIndex)
            btn.linkGroup = bridge.limiterLinkGroup(btn.outputIndex)
        }
        function onStatusChanged() { btn.reduction = bridge.limiterReduction(btn.outputIndex) }
    }

    Icon {
        anchors.centerIn: parent
        name: "gauge"
        size: 18
        color: !btn.enabled_ ? Qt.rgba(1, 1, 1, 0.4) : btn.limiting ? "#ff9f0a" : "#3a96dd"
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            if (mouse.button === Qt.RightButton) btn.openSettings()
            else bridge.setLimiterEnabled(btn.outputIndex, !btn.enabled_)
        }
        ToolTip.visible: containsMouse && !popup.visible
        ToolTip.delay: 600
        ToolTip.text: "Output limiter: click to switch " + (btn.enabled_ ? "off" : "on")
                      + ", right-click for settings"
    }

    // Opens under the button (or above it when there's no room), right-aligned
    function openSettings() {
        var p = btn.mapToItem(popup.parent, 0, 0)
        popup.x = Math.max(6, Math.min(p.x + btn.width - popup.width, popup.parent.width - popup.width - 6))
        var h = popup.implicitHeight
        popup.y = p.y + btn.height + 6 + h > popup.parent.height - 6 ? Math.max(6, p.y - 6 - h) : p.y + btn.height + 6
        popup.open()
    }

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    component OutlineButton: Rectangle {
        id: ob
        property string text: ""
        property bool chevron: false
        signal clicked()
        implicitHeight: 26
        radius: 7
        color: obMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : obMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Row {
            anchors.centerIn: parent
            spacing: 5
            Text { text: ob.text; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
            Icon { visible: ob.chevron; name: "chev-down"; size: 11; color: Qt.rgba(1, 1, 1, 0.6); anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: obMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ob.clicked() }
    }

    Popup {
        id: popup
        parent: Overlay.overlay
        width: 270
        padding: 12
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 130; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }

        background: Item {
            Repeater {
                model: 6
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -(index + 1) * 2
                    anchors.topMargin: -(index + 1) * 2 + 4
                    radius: 12 + (index + 1) * 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: MenuStyle.background
                border.color: MenuStyle.border
            }
        }

        contentItem: Column {
            spacing: 10

            // Header: icon, title + status, on/off
            RowLayout {
                width: parent.width
                spacing: 10
                Rectangle {
                    width: 28; height: 28; radius: 7
                    color: btn.limiting ? Qt.rgba(1, 0.62, 0.04, 0.18) : Qt.rgba(0.04, 0.49, 1, btn.enabled_ ? 0.18 : 0.08)
                    Icon {
                        anchors.centerIn: parent
                        name: "gauge"
                        size: 16
                        color: !btn.enabled_ ? Qt.rgba(1, 1, 1, 0.45) : btn.limiting ? "#ff9f0a" : "#3a96ff"
                    }
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Output Limiter"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: "white"
                    }
                    Text {
                        text: !btn.enabled_ ? "Off"
                            : btn.limiting ? "Reducing by " + btn.reduction.toFixed(1) + " dB"
                            : "On · not limiting"
                        font.pixelSize: 11
                        color: btn.limiting ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.5)
                    }
                }
                ToggleSwitch {
                    checked: btn.enabled_
                    onToggled: bridge.setLimiterEnabled(btn.outputIndex, checked)
                }
            }

            Rectangle { width: parent.width; height: 1; color: MenuStyle.separator }

            // Threshold
            Column {
                width: parent.width
                spacing: 4
                RowLayout {
                    width: parent.width
                    SectionLabel { text: "THRESHOLD" }
                    Item { Layout.fillWidth: true }
                    ValueField {
                        fieldWidth: 56; height: 22; suffix: "dBFS"; decimals: 1; wheelStep: 0.5
                        minValue: -30; maxValue: 0
                        value: btn.threshold
                        onValueEdited: bridge.setLimiterThreshold(btn.outputIndex, newValue)
                    }
                }
                StyledSlider {
                    width: parent.width
                    from: -30; to: 0; stepSize: 0.5
                    value: btn.threshold
                    onMoved: { btn.threshold = value; thresholdLive.push(value) }
                    onPressedChanged: if (!pressed) { thresholdLive.cancel(); bridge.setLimiterThreshold(btn.outputIndex, value) }
                    Throttle { id: thresholdLive; onFire: bridge.setLimiterThreshold(btn.outputIndex, value, true) }
                }
            }

            // Release
            Column {
                width: parent.width
                spacing: 4
                RowLayout {
                    width: parent.width
                    SectionLabel { text: "RELEASE" }
                    Item { Layout.fillWidth: true }
                    ValueField {
                        fieldWidth: 56; height: 22; suffix: "ms"; decimals: 0; wheelStep: 10
                        minValue: 10; maxValue: 1000
                        value: btn.release
                        onValueEdited: bridge.setLimiterRelease(btn.outputIndex, newValue)
                    }
                }
                StyledSlider {
                    width: parent.width
                    from: 10; to: 1000; stepSize: 10
                    value: btn.release
                    onMoved: { btn.release = value; releaseLive.push(value) }
                    onPressedChanged: if (!pressed) { releaseLive.cancel(); bridge.setLimiterRelease(btn.outputIndex, value) }
                    Throttle { id: releaseLive; onFire: bridge.setLimiterRelease(btn.outputIndex, value, true) }
                }
            }

            // Link group: segmented Off | 1 | 2 | 3 | 4
            Column {
                width: parent.width
                spacing: 4
                SectionLabel {
                    text: "LINK GROUP"
                    MouseArea {
                        id: linkHelp
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                    ToolTip.visible: linkHelp.containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: "Outputs in the same group share the deepest gain reduction, so a stereo image doesn't shift."
                }
                Rectangle {
                    width: parent.width
                    height: 26
                    radius: 7
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Row {
                        anchors.fill: parent
                        anchors.margins: 2
                        Repeater {
                            model: ["Off", "1", "2", "3", "4"]
                            Rectangle {
                                readonly property bool isCurrent: btn.linkGroup === index
                                width: parent.width / 5
                                height: parent.height
                                radius: 5
                                color: isCurrent ? MenuStyle.highlight
                                     : segMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 12
                                    font.weight: parent.isCurrent ? Font.DemiBold : Font.Normal
                                    color: parent.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.75)
                                }
                                MouseArea {
                                    id: segMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bridge.setLimiterLinkGroup(btn.outputIndex, index)
                                }
                            }
                        }
                    }
                }

            }

            Rectangle { width: parent.width; height: 1; color: MenuStyle.separator }

            // Actions
            RowLayout {
                width: parent.width
                spacing: 8
                OutlineButton {
                    Layout.fillWidth: true
                    text: "Copy to All Outputs"
                    onClicked: bridge.copyLimiterToAll(btn.outputIndex)
                }
                OutlineButton {
                    id: allButton
                    Layout.preferredWidth: 104
                    text: "All Outputs"
                    chevron: true
                    onClicked: allMenu.openAt(allButton, 0, allButton.height + 4)
                }
            }
        }
    }

    ActionMenu {
        id: allMenu
        parent: Overlay.overlay
        items: [
            { key: "link", text: "Link All Stereo Pairs", icon: "link" },
            { key: "unlink", text: "Unlink All Outputs" },
            { separator: true },
            { key: "off", text: "Switch Every Limiter Off", icon: "power", danger: true }
        ]
        onTriggered: {
            if (key === "link") bridge.linkAllLimiterPairs()
            else if (key === "unlink") bridge.unlinkAllLimiters()
            else if (key === "off") bridge.disableAllLimiters()
        }
    }
}
