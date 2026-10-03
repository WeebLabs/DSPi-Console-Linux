import QtQuick 2.15
import QtQuick.Controls 2.15

// Output limiter gauge: click toggles the limiter, right-click opens its
// settings. Grey = off, accent = on, orange = reducing the level now.
Rectangle {
    id: btn
    width: 36
    height: 24
    radius: 5
    color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

    property int outputIndex: 0
    property bool enabled_: bridge.limiterEnabled(outputIndex)
    property real reduction: bridge.limiterReduction(outputIndex)

    Connections {
        target: bridge
        function onStateChanged() { btn.enabled_ = bridge.limiterEnabled(btn.outputIndex) }
        function onStatusChanged() { btn.reduction = bridge.limiterReduction(btn.outputIndex) }
    }

    Icon {
        anchors.centerIn: parent
        name: "gauge"
        size: 18
        color: !btn.enabled_ ? Qt.rgba(1, 1, 1, 0.4)
             : btn.reduction > 0.05 ? "#ff9f0a" : "#3a96dd"
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            if (mouse.button === Qt.RightButton) popup.open()
            else bridge.setLimiterEnabled(btn.outputIndex, !btn.enabled_)
        }
        ToolTip.visible: containsMouse && !popup.visible
        ToolTip.delay: 600
        ToolTip.text: "Output limiter: click to switch " + (btn.enabled_ ? "off" : "on")
                      + ", right-click for settings"
    }

    Popup {
        id: popup
        x: btn.width - width
        y: btn.height + 4
        width: 300
        padding: 14
        background: Rectangle {
            color: isMacOS ? "#353535" : nativeAltBaseColor
            border.color: Qt.rgba(1, 1, 1, 0.15)
            radius: 8
        }

        Column {
            width: parent.width
            spacing: 10

            Row {
                width: parent.width
                Text {
                    text: "Output Limiter"
                    font.pixelSize: 13; font.weight: Font.DemiBold; color: "white"
                    width: parent.width - limSwitch.width
                    anchors.verticalCenter: parent.verticalCenter
                }
                Switch {
                    id: limSwitch
                    checked: btn.enabled_
                    onToggled: bridge.setLimiterEnabled(btn.outputIndex, checked)
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                color: Qt.rgba(1, 1, 1, 0.45)
                text: btn.reduction > 0.05
                      ? "Reducing by " + btn.reduction.toFixed(1) + " dB"
                      : "No sample leaves this output above the threshold."
            }

            Row {
                spacing: 8
                Text { text: "Threshold"; width: 80; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                ValueField {
                    fieldWidth: 60; suffix: "dBFS"; decimals: 1; minValue: -30; maxValue: 0
                    value: bridge.limiterThreshold(btn.outputIndex)
                    onValueEdited: bridge.setLimiterThreshold(btn.outputIndex, newValue)
                    Connections {
                        target: bridge
                        function onStateChanged() { parent.value = bridge.limiterThreshold(btn.outputIndex) }
                    }
                }
            }

            Row {
                spacing: 8
                Text { text: "Release"; width: 80; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                ValueField {
                    fieldWidth: 60; suffix: "ms"; decimals: 0; minValue: 10; maxValue: 1000
                    value: bridge.limiterRelease(btn.outputIndex)
                    onValueEdited: bridge.setLimiterRelease(btn.outputIndex, newValue)
                    Connections {
                        target: bridge
                        function onStateChanged() { parent.value = bridge.limiterRelease(btn.outputIndex) }
                    }
                }
            }

            Row {
                spacing: 8
                Text { text: "Link group"; width: 80; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                ComboBox {
                    id: groupCombo
                    width: 90
                    model: ["Off", "1", "2", "3", "4"]
                    currentIndex: bridge.limiterLinkGroup(btn.outputIndex)
                    onActivated: bridge.setLimiterLinkGroup(btn.outputIndex, index)
                    Connections {
                        target: bridge
                        function onStateChanged() { groupCombo.currentIndex = bridge.limiterLinkGroup(btn.outputIndex) }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                color: Qt.rgba(1, 1, 1, 0.45)
                text: "Outputs in the same group share the deepest gain reduction, so a stereo image doesn't shift."
            }

            Row {
                spacing: 8
                Button {
                    text: "Copy to All Outputs"
                    onClicked: bridge.copyLimiterToAll(btn.outputIndex)
                }
                Button {
                    text: "All Outputs ▾"
                    onClicked: allMenu.open()
                    Menu {
                        id: allMenu
                        y: parent.height
                        MenuItem { text: "Link All Stereo Pairs"; onTriggered: bridge.linkAllLimiterPairs() }
                        MenuItem { text: "Unlink All Outputs"; onTriggered: bridge.unlinkAllLimiters() }
                        MenuItem { text: "Switch Every Limiter Off"; onTriggered: bridge.disableAllLimiters() }
                    }
                }
            }
        }
    }
}
