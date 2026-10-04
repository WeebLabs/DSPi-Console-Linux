import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.0
import "components"

// Stereo Upmixer: derives Centre and Surround from stereo (RP2350 only).
// Basic and Advanced views like the Tube Modeller; the soundstage on the
// left shows the speakers the current engines feed.
AppWindow {
    id: win
    fitHeight: header.height + flick.contentHeight
    title: "Stereo Upmixer"
    visible: false
    width: 840
    height: 600 + titlebarHeight
    minimumWidth: 700
    minimumHeight: 360 + titlebarHeight

    Settings {
        id: prefs
        category: "stereoUpmixer"
        property bool advanced: false
    }

    // Parameter ids (firmware / core UPMIX_PARAM_*)
    readonly property int pEnabled: 0
    readonly property int pCenterMode: 1
    readonly property int pSurroundMode: 2
    readonly property int pStrength: 3
    readonly property int pWidth: 4
    readonly property int pThreshold: 5
    readonly property int pAttack: 6
    readonly property int pRelease: 7
    readonly property int pDetectorHpf: 8
    readonly property int pSurDelay: 9
    readonly property int pSurHpf: 10
    readonly property int pSurLpf: 11
    readonly property int pDecorr: 12
    readonly property int pPresence: 13

    readonly property bool supported: bridge.upmixSupported
    readonly property var params: bridge.upmixParams
    readonly property bool active: params[pEnabled] > 0
    // Centre: 0 passive, 1 adaptive, 2 off. Surround: 0 off, 1 passive, 2 adaptive.
    readonly property int centerMode: params[pCenterMode]
    readonly property int surroundMode: params[pSurroundMode]
    readonly property bool centerOn: centerMode !== 2
    readonly property bool surroundOn: surroundMode !== 0
    // Segments read Off | Sinner | Logician for both
    readonly property var centerWire: [2, 0, 1]
    readonly property var surroundWire: [0, 1, 2]

    readonly property color centerColor: "#32d74b"
    readonly property color lsColor: "#bf5af2"
    readonly property color rsColor: "#ff375f"

    // Live status, polled while the window is open
    property var status: ({})
    Timer {
        interval: 100
        repeat: true
        running: win.visible && win.supported
        triggeredOnStart: true
        onTriggered: win.status = bridge.fetchUpmixStatus()
        onRunningChanged: if (!running) win.status = ({})
    }
    readonly property bool processing: status.active === true

    function statusText() {
        if (!bridge.connected) return "No device connected"
        if (processing) return "Active - processing audio"
        switch (status.parkedReason) {
        case 1: return "Idle: upmixer disabled"
        case 2: return "Idle: input is not stereo"
        case 3: return "Idle: sample rate above 48 kHz"
        default: return "Idle"
        }
    }
    // What the speakers add up to, and which engines drive them
    function layoutName() {
        if (!active || (!centerOn && !surroundOn)) return "Stereo"
        return centerOn && surroundOn ? "5.0 Surround" : centerOn ? "3.0 Front" : "4.0 Quad"
    }
    function layoutCaption() {
        if (!active) return "Upmixer off: L and R pass through untouched."
        if (!centerOn && !surroundOn) return "Both engines are off: L and R pass through untouched."
        var parts = []
        if (centerOn) parts.push((centerMode === 1 ? "Logician" : "Sinner") + " centre")
        if (surroundOn) parts.push((surroundMode === 2 ? "Logician" : "Sinner") + " surround")
        return parts.join(", ") + "."
    }

    component Divider: Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
    component Note: Text {
        width: parent.width
        wrapMode: Text.WordWrap
        font.pixelSize: 11
        color: Qt.rgba(1, 1, 1, 0.5)
    }

    component StatusLine: Row {
        spacing: 8
        Rectangle {
            width: 8; height: 8; radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: !bridge.connected ? Qt.rgba(1, 1, 1, 0.3) : win.processing ? "#32d74b" : "#ff9f0a"
        }
        Text {
            text: win.statusText()
            font.pixelSize: 12
            font.weight: Font.Medium
            color: win.processing ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.6)
        }
    }

    // Live gain bar with its reading (hidden, not removed, so the height holds)
    component Gauge: Item {
        id: gauge
        property string label: ""
        property real fraction: 0
        property string reading: ""
        property color barColor: "#0a7cff"
        width: parent.width
        height: 18
        Text {
            id: gaugeLabel
            width: 84
            anchors.verticalCenter: parent.verticalCenter
            text: gauge.label
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.6)
        }
        Rectangle {
            anchors.left: gaugeLabel.right
            anchors.right: gaugeValue.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.1)
            Rectangle {
                height: parent.height
                radius: 3
                width: parent.width * Math.max(0, Math.min(1, gauge.fraction))
                color: gauge.barColor
                Behavior on width { NumberAnimation { duration: 60 } }
            }
        }
        Text {
            id: gaugeValue
            width: 44
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: gauge.reading
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.8)
        }
    }

    // Centre and Surround engine pickers (both views)
    component Engines: Column {
        spacing: 10
        Repeater {
            model: [
                { label: "Centre", param: win.pCenterMode, wire: win.centerWire, current: win.centerMode },
                { label: "Surround", param: win.pSurroundMode, wire: win.surroundWire, current: win.surroundMode }]
            Item {
                width: parent.width
                height: 26
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pixelSize: 13
                    color: Qt.rgba(1, 1, 1, 0.9)
                }
                SegmentedControl {
                    anchors.right: parent.right
                    width: parent.width - 90
                    model: ["Off", "Sinner", "Logician"]
                    currentIndex: modelData.wire.indexOf(modelData.current)
                    tips: ["", "A fixed passive matrix, Hafler-style: C = 0.7071(L+R), surround = L-R.",
                           modelData.label === "Centre" ? "Gates centre extraction on running L/R correlation."
                                                        : "A Pro Logic II-style matrix decoder."]
                    onActivated: { win.refitAnimated(); bridge.setUpmixParam(modelData.param, modelData.wire[index]) }
                }
            }
        }
    }

    // A parameter row; its macOS help text is the tooltip
    component UpmixRow: ParamRow {
        property int param: 0
        value: win.params[param]
        onLiveChanged: bridge.setUpmixParam(param, v, true)
        onCommitted: bridge.setUpmixParam(param, v)
    }

    readonly property string routingText: "The derived channels appear as matrix source rows: row 2 = Centre, row 3 = Left Surround, row 4 = Right Surround. Open the Matrix Mixer to route them to your output slots (a centre crosspoint gain of -3 dB is a safe start, since the centre row can reach +3 dBFS)."

    ToolHeader {
        id: header
        width: parent.width
        icon: "upmix"
        title: "Stereo Upmixer"
        subtitle: "Derive Centre and Surround from stereo"
        checked: win.active
        enabled: win.supported
        onToggled: bridge.setUpmixParam(win.pEnabled, enable ? 1 : 0)
        accessories: [
            SegmentedControl {
                anchors.verticalCenter: parent.verticalCenter
                width: 150
                visible: win.supported
                model: ["Basic", "Advanced"]
                currentIndex: prefs.advanced ? 1 : 0
                onActivated: { win.refitAnimated(); prefs.advanced = (index === 1) }
            }
        ]
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: (!win.supported ? unsupported.height : prefs.advanced ? advanced.height : basic.height) + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        readonly property real colWidth: (win.width - 32 - 2 * 20 - 1) / 2

        Column {
            id: unsupported
            visible: !win.supported
            x: 16
            y: 40
            width: win.width - 32
            spacing: 6
            Icon { name: "warning"; size: 22; color: "#ff9f0a"; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: bridge.connected ? "Requires an RP2350 device with firmware wire format V25 or newer." : "No device connected"
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.85)
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "The upmixer runs on stereo input at 48 kHz or below."
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.5)
            }
        }

        // ── Basic: the soundstage and the main controls ──
        Row {
            id: basic
            visible: win.supported && !prefs.advanced
            x: 16
            y: 16
            spacing: 20
            enabled: bridge.connected

            Rectangle {
                width: flick.colWidth
                height: Math.max(340, basicRight.height)
                radius: 10
                color: Qt.rgba(0, 0, 0, 0.2)
                border.color: Qt.rgba(1, 1, 1, 0.1)
                clip: true

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 8

                    SoundstageIllustration {
                        width: parent.width
                        height: width * 220 / 300
                        active: win.active
                        centerOn: win.centerOn
                        surroundOn: win.surroundOn
                        live: win.processing
                        centerGain: win.status.centerGain || 0
                        lsGain: win.status.lsGain || 0
                        rsGain: win.status.rsGain || 0
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.layoutName()
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: "white"
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: win.layoutCaption()
                        font.pixelSize: 11
                        color: Qt.rgba(1, 1, 1, 0.55)
                    }
                    Item { width: 1; height: 4 }
                    StatusLine { anchors.horizontalCenter: parent.horizontalCenter }
                }
            }

            Rectangle { width: 1; height: basic.height; color: Qt.rgba(1, 1, 1, 0.08) }

            Column {
                id: basicRight
                width: flick.colWidth
                spacing: 12

                SectionLabel { text: "ENGINES" }
                Engines { width: parent.width }
                Note {
                    text: "Sinner is a fixed passive matrix; Logician steers by what the music is doing."
                    MouseArea { id: engineHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    ToolTip.visible: engineHover.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: "Logician centre gates extraction on running L/R correlation; Logician surround uses a Pro Logic II-style matrix decoder. Sinner modes are fixed (C = 0.7071(L+R), surround = L-R) - a Hafler-style passive matrix like the one in the Schiit Syn."
                }

                // Greyed out, not hidden, while an engine is off, so the page keeps its size
                Divider {}
                Column {
                    width: parent.width
                    spacing: 12
                    enabled: win.centerOn
                    opacity: enabled ? 1 : 0.4
                    SectionLabel { text: "CENTRE" }
                    UpmixRow {
                        param: win.pStrength
                        label: "Strength"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 100
                        tip: "Centre extraction strength; scales both the C output and how much centre energy is removed from L/R. In Sinner mode this is the fixed centre gain."
                    }
                    UpmixRow {
                        param: win.pPresence
                        label: "Presence"; unit: "dB"; from: -12; to: 12; stepSize: 0.5; defaultValue: 0
                        leftHint: "Back"; rightHint: "Forward"
                        tip: "Voice presence bell at 3 kHz (Q 0.6). Positive brings voices forward, negative pushes them back (Syn-style). Stored in 0.5 dB steps."
                    }
                }

                Divider {}
                Column {
                    width: parent.width
                    spacing: 12
                    enabled: win.surroundOn
                    opacity: enabled ? 1 : 0.4
                    SectionLabel { text: "SURROUND" }
                    UpmixRow {
                        param: win.pSurDelay
                        label: "Delay"; unit: "ms"; from: 0; to: 20; stepSize: 0.5; defaultValue: 12
                        tip: "Haas delay on Ls/Rs (precedence effect). Rule of thumb ~1 ms per foot of listener distance."
                    }
                }

                Divider {}
                Note {
                    text: "Route Upmix C, Ls and Rs to your outputs in the Matrix Mixer. More settings in Advanced."
                    MouseArea { id: routeHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    ToolTip.visible: routeHover.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: win.routingText
                }
            }
        }

        // ── Advanced: soundstage, live readings and every setting ──
        Row {
            id: advanced
            visible: win.supported && prefs.advanced
            x: 16
            y: 16
            spacing: 20
            enabled: bridge.connected

            Column {
                width: flick.colWidth
                spacing: 12

                SectionLabel { text: "SOUNDSTAGE" }
                Rectangle {
                    width: parent.width
                    height: 200
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.2)
                    border.color: Qt.rgba(1, 1, 1, 0.1)
                    clip: true
                    SoundstageIllustration {
                        anchors.fill: parent
                        anchors.margins: 8
                        active: win.active
                        centerOn: win.centerOn
                        surroundOn: win.surroundOn
                        live: win.processing
                        centerGain: win.status.centerGain || 0
                        lsGain: win.status.lsGain || 0
                        rsGain: win.status.rsGain || 0
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        text: win.layoutName()
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                }

                StatusLine {}
                Column {
                    width: parent.width
                    spacing: 6
                    Gauge {
                        opacity: win.processing ? 1 : 0
                        label: "Correlation"
                        fraction: ((win.status.correlation || 0) + 1) / 2
                        reading: { var c = win.status.correlation || 0; return (c >= 0 ? "+" : "") + c.toFixed(2) }
                    }
                    Gauge {
                        opacity: win.processing && win.centerOn ? 1 : 0
                        label: "Centre gain"
                        barColor: win.centerColor
                        fraction: win.status.centerGain || 0
                        reading: Math.round((win.status.centerGain || 0) * 100) + "%"
                    }
                    Gauge {
                        opacity: win.processing && win.surroundOn ? 1 : 0
                        label: "Ls gain"
                        barColor: win.lsColor
                        fraction: win.status.lsGain || 0
                        reading: Math.round((win.status.lsGain || 0) * 100) + "%"
                    }
                    Gauge {
                        opacity: win.processing && win.surroundOn ? 1 : 0
                        label: "Rs gain"
                        barColor: win.rsColor
                        fraction: win.status.rsGain || 0
                        reading: Math.round((win.status.rsGain || 0) * 100) + "%"
                    }
                }

                Divider {}
                SectionLabel { text: "ENGINES" }
                Engines { width: parent.width }
                Note {
                    text: "Logician centre gates extraction on running L/R correlation; Logician surround uses a Pro Logic II-style matrix decoder. Sinner modes are fixed (C = 0.7071(L+R), surround = L-R) - a Hafler-style passive matrix like the one in the Schiit Syn."
                }

                Divider {}
                SectionLabel { text: "ROUTING" }
                Note { text: win.routingText }
            }

            Rectangle { width: 1; height: advanced.height; color: Qt.rgba(1, 1, 1, 0.08) }

            Column {
                width: flick.colWidth
                spacing: 12

                Text {
                    visible: !win.centerOn && !win.surroundOn
                    width: parent.width
                    topPadding: 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Both engines are off. Choose Sinner or Logician for the centre or the surrounds."
                    font.pixelSize: 12
                    color: Qt.rgba(1, 1, 1, 0.45)
                }

                // Centre (gone while the centre is off)
                Column {
                    visible: win.centerOn
                    width: parent.width
                    spacing: 12
                    SectionLabel { text: "CENTRE" }
                    UpmixRow {
                        param: win.pStrength
                        label: "Strength"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 100
                        tip: "Centre extraction strength; scales both the C output and how much centre energy is removed from L/R. In Sinner mode this is the fixed centre gain."
                    }
                    UpmixRow {
                        param: win.pWidth
                        label: "Centre Width"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 25
                        leftHint: "Discrete"; rightHint: "L/R untouched"
                        tip: "How much extracted centre stays in L/R. 0 = full removal (discrete centre); 100 = L/R untouched (expect combing if a real centre speaker plays)."
                    }
                    UpmixRow {
                        param: win.pPresence
                        label: "Presence"; unit: "dB"; from: -12; to: 12; stepSize: 0.5; defaultValue: 0
                        leftHint: "Back"; rightHint: "Forward"
                        tip: "Voice presence bell at 3 kHz (Q 0.6). Positive brings voices forward, negative pushes them back (Syn-style). Stored in 0.5 dB steps."
                    }
                    // Logician only
                    Column {
                        visible: win.centerMode === 1
                        width: parent.width
                        spacing: 12
                        UpmixRow {
                            param: win.pThreshold
                            label: "Correlation Threshold"; unit: "%"; from: 0; to: 95; stepSize: 1; decimals: 0; defaultValue: 30
                            tip: "Correlation gate. Below this, nothing is extracted; above it, extraction scales up to full. Raise to extract only strongly-correlated content."
                        }
                        UpmixRow {
                            param: win.pAttack
                            label: "Attack"; unit: "ms"; from: 1; to: 500; stepSize: 1; decimals: 0; defaultValue: 10
                            tip: "Centre gain rise time (Logician mode)."
                        }
                        UpmixRow {
                            param: win.pRelease
                            label: "Release"; unit: "ms"; from: 5; to: 2000; stepSize: 5; decimals: 0; defaultValue: 100
                            tip: "Centre gain fall time (Logician mode)."
                        }
                        UpmixRow {
                            param: win.pDetectorHpf
                            label: "Detector HPF"; unit: "Hz"; from: 20; to: 1000; stepSize: 5; decimals: 0; defaultValue: 200
                            tip: "Detector bass-cut corner. Content below this is ignored by the steering detector (the audio itself is not filtered) so bass does not pump the centre."
                        }
                    }
                }

                Divider { visible: win.centerOn && win.surroundOn }

                // Surround (gone while surround is off)
                Column {
                    visible: win.surroundOn
                    width: parent.width
                    spacing: 12
                    SectionLabel { text: "SURROUND" }
                    UpmixRow {
                        param: win.pSurDelay
                        label: "Delay"; unit: "ms"; from: 0; to: 20; stepSize: 0.5; defaultValue: 12
                        tip: "Haas delay on Ls/Rs (precedence effect). Rule of thumb ~1 ms per foot of listener distance."
                    }
                    UpmixRow {
                        param: win.pSurHpf
                        label: "Band-limit HPF"; unit: "Hz"; from: 20; to: 2000; stepSize: 5; decimals: 0; defaultValue: 300
                        tip: "Surround high-pass; keeps rumble out of the rears."
                    }
                    UpmixRow {
                        param: win.pSurLpf
                        label: "Band-limit LPF"; unit: "Hz"; from: 1000; to: 20000; stepSize: 100; decimals: 0; defaultValue: 7000
                        tip: "Surround low-pass. 7 kHz is the classic surround voicing; raise for full-band rears."
                    }
                    UpmixRow {
                        param: win.pDecorr
                        label: "Decorrelation"; unit: "%"; from: 0; to: 100; stepSize: 1; decimals: 0; defaultValue: 90
                        tip: "Schroeder allpass decorrelator amount. 0 disables decorrelation."
                    }
                }
            }
        }
    }
}
