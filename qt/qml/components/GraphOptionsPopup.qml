import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// The response graph's gear popover, after the macOS Console: a window of
// its own, so it opens centred under the gear even at the window's edge.
// The main page picks which channels the spectrum analyser shows on this
// page (inputs or outputs, never both) and where; Graph Setup slides in the
// graph's scale, grid and curve options.
PopoverWindow {
    id: pop
    property var app                      // main window: spectrum selection and settings
    property bool inPopOut: false         // opened from the pop-out graph window
    signal popOutRequested()

    readonly property var sel: app ? app.rtaSelection : ({ tap: 1, channels: [] })
    readonly property var available: app ? (app.rtaAvailable, app.rtaAvailableAt(sel.tap)) : []
    property int page: 0                  // 0 main, 1 graph setup

    contentWidth: 280
    contentHeight: page === 0 ? mainPage.implicitHeight : setupPage.implicitHeight
    onAboutToOpen: page = 0

    component SectionLabel: Text {
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
    }

    component Divider: Rectangle { width: parent ? parent.width : 0; height: 1; color: isMacOS ? MacColors.separator : MenuStyle.separator }

    // A switch row; `icon` is optional
    component SwitchRow: Item {
        id: sr
        property string text: ""
        property string icon: ""
        property bool checked: false
        signal toggled(bool checked)
        width: parent ? parent.width : 0
        height: 28
        opacity: enabled ? 1 : 0.4
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Icon { visible: sr.icon !== ""; name: sr.icon; size: 15; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.65); anchors.verticalCenter: parent.verticalCenter }
            Text { text: sr.text; font.pixelSize: 13; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9); anchors.verticalCenter: parent.verticalCenter }
        }
        ToggleSwitch {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            checked: sr.checked
            onToggled: sr.toggled(checked)
        }
    }

    // An action row: icon, title, optional chevron
    component ActionRow: Rectangle {
        id: ar
        property string text: ""
        property string icon: ""
        property bool chevron: false
        signal clicked()
        x: 6
        width: (parent ? parent.width : 0) - 12
        height: 28
        radius: 6
        color: isMacOS ? (arMouse.containsMouse ? MacColors.accent : "transparent") : arMouse.containsMouse ? MenuStyle.highlight : "transparent"
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Icon { name: ar.icon; size: 15; color: isMacOS ? (arMouse.containsMouse ? "white" : MacColors.label) : arMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.65); anchors.verticalCenter: parent.verticalCenter }
            Text { text: ar.text; font.pixelSize: 13; color: isMacOS ? (arMouse.containsMouse ? "white" : MacColors.label) : arMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.9); anchors.verticalCenter: parent.verticalCenter }
        }
        Icon {
            visible: ar.chevron
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            name: "chev-right"
            size: 11
            color: isMacOS ? (arMouse.containsMouse ? "white" : MacColors.opacity(MacColors.label, 0.5)) : arMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.4)
        }
        MouseArea { id: arMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ar.clicked() }
    }

    // Label, slider, value: label and value fixed so rows line up
    component SliderRow: Item {
        id: slr
        property string text: ""
        property string valueText: ""
        property alias from: slider.from
        property alias to: slider.to
        property alias stepSize: slider.stepSize
        property real value: 0
        signal moved(real value)
        x: 12
        width: (parent ? parent.width : 0) - 24
        height: 26
        opacity: enabled ? 1 : 0.4
        Text { id: slLabel; width: 70; text: slr.text; font.pixelSize: 12; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9); anchors.verticalCenter: parent.verticalCenter }
        StyledSlider {
            id: slider
            anchors.left: slLabel.right
            anchors.right: slValue.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            value: slr.value
            onMoved: slr.moved(value)
        }
        Text {
            id: slValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            horizontalAlignment: Text.AlignRight
            text: slr.valueText
            font.pixelSize: 11
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55)
        }
    }

    Item {
        anchors.fill: parent
        clip: true

        // ── Main page ──
        Column {
            id: mainPage
            width: parent.width
            x: pop.page === 0 ? 0 : -width
            opacity: pop.page === 0 ? 1 : 0
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Column {
                x: 12
                width: parent.width - 24
                topPadding: 12
                bottomPadding: 12
                spacing: 10

                RowLayout {
                    width: parent.width
                    visible: rta.supported && bridge.connected
                    SectionLabel { text: "SPECTRUM" }
                    Item { Layout.fillWidth: true }
                    SegmentedControl {
                        Layout.preferredWidth: 150
                        model: ["Inputs", "Outputs"]
                        currentIndex: pop.sel.tap
                        onActivated: pop.app.rtaSwitchSide(index)
                    }
                }

                Text {
                    visible: !rta.supported || !bridge.connected
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.55)
                    text: bridge.connected ? "This firmware has no spectrum analyser." : "Connect a DSPi to show its spectrum."
                }

                // Channel chips, two to a row
                Grid {
                    visible: rta.supported && bridge.connected
                    width: parent.width
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: pop.available
                        Rectangle {
                            id: chip
                            readonly property int app: rta.appChannel(pop.sel.tap, modelData)
                            readonly property color tint: bridge.channelColor(app)
                            readonly property bool on: pop.sel.channels.indexOf(modelData) >= 0
                            width: (parent.width - 6) / 2
                            height: 24
                            radius: 6
                            color: isMacOS ? (on ? Qt.rgba(tint.r, tint.g, tint.b, 0.22) : MacColors.opacity(MacColors.label, 0.05)) : on ? Qt.rgba(tint.r, tint.g, tint.b, 0.22)
                                 : chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.05)
                            border.color: isMacOS ? (on ? Qt.rgba(tint.r, tint.g, tint.b, 0.75) : MacColors.opacity(MacColors.label, 0.08)) : on ? Qt.rgba(tint.r, tint.g, tint.b, 0.75) : Qt.rgba(1, 1, 1, 0.08)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Rectangle { width: 7; height: 7; radius: 3.5; color: isMacOS ? MacColors.opacity(chip.tint, chip.on ? 1.0 : 0.4) : chip.tint; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width - 13
                                    elide: Text.ElideRight
                                    text: bridge.channelName(chip.app)
                                    font.pixelSize: 11
                                    font.weight: chip.on ? Font.DemiBold : Font.Normal
                                    color: isMacOS ? (chip.on ? MacColors.label : MacColors.secondaryLabel) : Qt.rgba(1, 1, 1, chip.on ? 0.95 : 0.7)
                                }
                            }
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.app.rtaToggle(modelData)
                            }
                        }
                    }
                }

                RowLayout {
                    visible: rta.supported && bridge.connected
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                        text: pop.sel.channels.length === 0 ? "Spectrum hidden"
                            : pop.sel.channels.length === 1 ? "1 channel" : pop.sel.channels.length + " channels"
                    }
                    Text {
                        visible: pop.sel.channels.length > 0
                        text: "Clear"
                        font.pixelSize: 11
                        color: isMacOS ? MacColors.accent : clearMouse.containsMouse ? "white" : "#3a96ff"
                        MouseArea { id: clearMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pop.app.rtaClear() }
                    }
                }
            }

            Divider { visible: rta.supported && bridge.connected }
            Column {
                visible: rta.supported && bridge.connected
                width: parent.width
                topPadding: 6
                bottomPadding: 6
                SwitchRow {
                    icon: "waveform"
                    text: "FFT Graph"
                    checked: pop.app ? pop.app.rtaShowGraph : false
                    onToggled: pop.app.rtaSetShowGraph(checked)
                }
                SwitchRow {
                    icon: "spectrum"
                    text: "RTA Bars"
                    checked: pop.app ? pop.app.rtaShowBars : false
                    onToggled: pop.app.rtaSetShowBars(checked)
                }
            }
            Divider {}
            Column {
                width: parent.width
                topPadding: 6
                bottomPadding: 6
                ActionRow { icon: "sliders"; text: "Graph Setup"; chevron: true; onClicked: pop.page = 1 }
                ActionRow {
                    visible: !pop.inPopOut
                    icon: "external"
                    text: "Pop Out Graph"
                    onClicked: { pop.close(); pop.popOutRequested() }
                }
            }
        }

        // ── Graph Setup ──
        Column {
            id: setupPage
            width: parent.width
            x: pop.page === 1 ? 0 : width
            opacity: pop.page === 1 ? 1 : 0
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            bottomPadding: 8

            Item {
                width: parent.width
                height: 32
                Text {
                    anchors.centerIn: parent
                    text: "Graph Setup"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9)
                }
                Row {
                    id: backRow
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Icon { name: "chev-left"; size: 12; color: isMacOS ? MacColors.accent : backMouse.containsMouse ? "white" : "#3a96ff"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Back"; font.pixelSize: 12; color: isMacOS ? MacColors.accent : backMouse.containsMouse ? "white" : "#3a96ff"; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: backMouse; anchors.fill: backRow; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pop.page = 0 }
            }
            Divider {}

            // SCALE
            Item {
                width: parent.width
                height: 32
                SectionLabel { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; text: "SCALE" }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: "Reset"
                    font.pixelSize: 11
                    color: isMacOS ? MacColors.accent : resetMouse.containsMouse ? "white" : "#3a96ff"
                    MouseArea {
                        id: resetMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pop.app.graphMinFreq = 15
                            pop.app.graphMaxFreq = 20000
                            pop.app.graphDbRange = 50
                            pop.app.graphDbCenter = 0
                        }
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 600
                        ToolTip.text: "Restore the default frequency and dB range"
                    }
                }
            }
            Item {
                x: 12
                width: parent.width - 24
                height: 30
                Text { id: freqLabel; width: 70; text: "Frequency"; font.pixelSize: 12; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9); anchors.verticalCenter: parent.verticalCenter }
                Row {
                    anchors.left: freqLabel.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    StyledComboBox {
                        id: minBox
                        width: 80
                        leftPadding: 0
                        rightPadding: 0
                        readonly property var values: [10, 15, 20, 50, 100]
                        model: ["10 Hz", "15 Hz", "20 Hz", "50 Hz", "100 Hz"]
                        currentIndex: pop.app ? values.indexOf(pop.app.graphMinFreq) : 1
                        onActivated: pop.app.graphMinFreq = values[index]
                    }
                    Text { text: "to"; font.pixelSize: 11; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5); anchors.verticalCenter: parent.verticalCenter }
                    StyledComboBox {
                        width: 80
                        leftPadding: 0
                        rightPadding: 0
                        readonly property var values: [5000, 10000, 20000]
                        model: ["5 kHz", "10 kHz", "20 kHz"]
                        currentIndex: pop.app ? values.indexOf(pop.app.graphMaxFreq) : 2
                        onActivated: pop.app.graphMaxFreq = values[index]
                    }
                }
            }
            SliderRow {
                text: "Range"
                from: 10; to: 100; stepSize: 1
                value: pop.app ? pop.app.graphDbRange : 50
                valueText: Math.round(value) + " dB"
                onMoved: pop.app.graphDbRange = Math.round(value)
            }
            SliderRow {
                text: "Center"
                from: -40; to: 20; stepSize: 1
                value: pop.app ? pop.app.graphDbCenter : 0
                valueText: (value > 0 ? "+" : value < 0 ? "−" : "±") + Math.abs(Math.round(value)) + " dB"
                onMoved: pop.app.graphDbCenter = Math.round(value)
            }

            // GRID & LABELS
            Item { width: parent.width; height: 30; SectionLabel { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; text: "GRID & LABELS" } }
            SwitchRow { text: "Frequency Grid"; checked: pop.app ? pop.app.graphShowFreqGrid : true; onToggled: pop.app.graphShowFreqGrid = checked }
            SwitchRow { text: "Frequency Labels"; checked: pop.app ? pop.app.graphShowFreqLabels : true; onToggled: pop.app.graphShowFreqLabels = checked }
            SwitchRow { text: "dB Grid"; checked: pop.app ? pop.app.graphShowDbGrid : true; onToggled: pop.app.graphShowDbGrid = checked }
            SwitchRow { text: "dB Labels"; checked: pop.app ? pop.app.graphShowDbLabels : true; onToggled: pop.app.graphShowDbLabels = checked }
            SwitchRow { text: "Frequency Readout"; checked: pop.app ? pop.app.graphFreqReadout : true; onToggled: pop.app.graphFreqReadout = checked }
            SwitchRow { text: "Gain Readout"; checked: pop.app ? pop.app.graphLevelReadout : true; onToggled: pop.app.graphLevelReadout = checked }
            SliderRow {
                text: "Grid Opacity"
                enabled: pop.app ? pop.app.graphShowFreqGrid || pop.app.graphShowDbGrid : true
                from: 0; to: 2; stepSize: 0.05
                value: pop.app ? pop.app.graphGridOpacity : 0.5
                valueText: Math.round(value * 100) + "%"
                onMoved: pop.app.graphGridOpacity = value
            }

            // CURVES
            Item { width: parent.width; height: 30; SectionLabel { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; text: "CURVES" } }
            SliderRow {
                text: "Line Width"
                from: 1; to: 4; stepSize: 0.5
                value: pop.app ? pop.app.graphLineWidth : 1.5
                valueText: value.toFixed(1) + " pt"
                onMoved: pop.app.graphLineWidth = value
            }
            SwitchRow { text: "Glow"; checked: pop.app ? pop.app.graphShowGlow : false; onToggled: pop.app.graphShowGlow = checked }
            SwitchRow { text: "Phase Response"; checked: pop.app ? pop.app.graphShowPhase : false; onToggled: pop.app.graphShowPhase = checked }
            SwitchRow {
                text: "Unwrap Phase"
                enabled: pop.app ? pop.app.graphShowPhase : false
                checked: pop.app ? pop.app.graphPhaseUnwrapped : false
                onToggled: pop.app.graphPhaseUnwrapped = checked
            }
            SwitchRow {
                visible: pop.inPopOut
                text: "Follow Channel Selection"
                checked: pop.app ? pop.app.graphPopOutFollows : true
                onToggled: pop.app.graphPopOutFollows = checked
            }
        }
    }
}
