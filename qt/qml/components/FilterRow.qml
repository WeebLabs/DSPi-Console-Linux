import QtQuick 2.15
import QtQuick.Controls 2.15

// One PEQ band in the band list: bypass dot, #, TYPE, FREQ, GAIN, WIDTH.
Rectangle {
    id: filterRowRoot
    height: 36
    color: bandIndex % 2 === 0 ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

    property int channelId: 0
    property int bandIndex: 0
    property bool isOutput: false
    property int filterType: 0
    property real filterFreq: 1000
    property real filterGain: 0
    property real filterQ: 0.707
    property bool filterBypass: false

    // Full names by firmware type (PEQ types 0..13), as on the macOS Console
    readonly property var typeNames: ["Off", "Peaking", "Low Shelf (12dB)", "High Shelf (12dB)",
        "High Cut (12dB)", "Low Cut (12dB)", "Notch", "All Pass (360°)", "All Pass (180°)",
        "Low Shelf (6dB)", "High Shelf (6dB)", "Linkwitz Transform",
        "High Cut (6dB)", "Low Cut (6dB)"]
    // Each band has its own colour (bypass dot and number)
    readonly property var bandColors: ["#4A8FE3", "#F57373", "#73C78C", "#EDB34D", "#998CEB",
        "#E68CC7", "#66C7D1", "#CCB86B", "#F2A64D", "#8CB3F2"]
    readonly property bool isActive: filterType !== 0
    readonly property bool isLinkwitz: filterType === 11
    readonly property bool hasGain: [1, 2, 3, 9, 10].indexOf(filterType) >= 0
    readonly property bool hasQ: [1, 2, 3, 4, 5, 6, 7].indexOf(filterType) >= 0

    property real savedPeakingQ: filterType === 1 ? filterQ : 1.0

    signal filterChanged(int type, real freq, real gain, real q)
    signal bypassToggled(bool bypass)

    opacity: filterBypass ? 0.45 : 1.0

    function chooseType(t) {
        if (t === filterType) return
        var q = filterQ
        if (filterType === 1) savedPeakingQ = filterQ
        if (t === 1) q = savedPeakingQ
        else if (t !== 0) q = 0.707
        // Gain carries fp for the Linkwitz Transform, so never carry it across.
        var keepsGain = [1, 2, 3, 9, 10].indexOf(t) >= 0 && filterType !== 11
        filterRowRoot.filterChanged(t, filterFreq, keepsGain ? filterGain : 0, q)
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        BypassDot {
            active: isActive
            bypassed: filterBypass
            dotColor: bandColors[bandIndex % bandColors.length]
            anchors.verticalCenter: parent.verticalCenter
            onToggled: filterRowRoot.bypassToggled(!filterBypass)
        }

        Text {
            width: 24
            text: (bandIndex + 1).toString()
            font.pixelSize: 12
            font.family: root.monoFont
            color: isActive ? bandColors[bandIndex % bandColors.length] : Qt.rgba(1, 1, 1, 0.4)
            anchors.verticalCenter: parent.verticalCenter
        }

        // Type button + menu (types with more than one slope open a submenu)
        Rectangle {
            id: typeBtn
            width: 150
            height: 30
            radius: 3
            color: "transparent"
            border.color: typeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.fill: parent
                leftPadding: 4
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: typeNames[filterType] || "Unknown"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: isActive ? "white" : Qt.rgba(1, 1, 1, 0.4)
            }
            MouseArea {
                id: typeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: typeMenu.popup(typeBtn, 0, typeBtn.height)
            }

            Menu {
                id: typeMenu
                MenuItem { text: "Off"; onTriggered: chooseType(0) }
                MenuItem { text: "Peaking"; onTriggered: chooseType(1) }
                Menu {
                    title: "Low Shelf"
                    MenuItem { text: "6 dB/oct"; onTriggered: chooseType(9) }
                    MenuItem { text: "12 dB/oct"; onTriggered: chooseType(2) }
                }
                Menu {
                    title: "High Shelf"
                    MenuItem { text: "6 dB/oct"; onTriggered: chooseType(10) }
                    MenuItem { text: "12 dB/oct"; onTriggered: chooseType(3) }
                }
                Menu {
                    title: "High Cut"
                    MenuItem { text: "6 dB/oct"; onTriggered: chooseType(12) }
                    MenuItem { text: "12 dB/oct"; onTriggered: chooseType(4) }
                }
                Menu {
                    title: "Low Cut"
                    MenuItem { text: "6 dB/oct"; onTriggered: chooseType(13) }
                    MenuItem { text: "12 dB/oct"; onTriggered: chooseType(5) }
                }
                MenuItem { text: "Notch"; onTriggered: chooseType(6) }
                Menu {
                    title: "All Pass"
                    MenuItem { text: "180°"; onTriggered: chooseType(8) }
                    MenuItem { text: "360°"; onTriggered: chooseType(7) }
                }
                MenuSeparator { visible: isOutput; height: isOutput ? implicitHeight : 0 }
                MenuItem {
                    text: "Linkwitz Transform"
                    visible: isOutput
                    height: isOutput ? implicitHeight : 0
                    onTriggered: chooseType(11)
                }
            }
        }

        Text {
            visible: !isActive
            text: "Filter Disabled"
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.25)
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 8
        }

        // Linkwitz Transform: one button standing in for FREQ/GAIN/WIDTH
        Rectangle {
            visible: isLinkwitz
            width: 270
            height: 28
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: ltMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
            Text {
                anchors.fill: parent
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 12
                font.family: root.monoFont
                color: "white"
                text: "⚙  f0 " + filterFreq.toFixed(0) + " Hz → fp " + filterGain.toFixed(0) + " Hz"
            }
            MouseArea {
                id: ltMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ltEditor.openFor(filterRowRoot.channelId, filterRowRoot.bandIndex)
            }
            LinkwitzEditor { id: ltEditor; y: parent.height + 4 }
        }

        // Frequency
        Item {
            visible: isActive && !isLinkwitz
            width: 100
            height: parent.height
            ValueField {
                anchors.verticalCenter: parent.verticalCenter
                fieldWidth: 70; height: 28; suffix: "Hz"; decimals: 1; wheelStep: 10; minValue: 10; maxValue: 20000
                value: filterFreq
                onValueEdited: filterRowRoot.filterChanged(filterType, newValue, filterGain, filterQ)
            }
        }

        // Gain (peaking and shelves only)
        Item {
            visible: isActive && !isLinkwitz
            width: 90
            height: parent.height
            ValueField {
                visible: hasGain
                anchors.verticalCenter: parent.verticalCenter
                fieldWidth: 60; height: 28; suffix: "dB"; decimals: 1; minValue: -30; maxValue: 30
                value: filterGain
                onValueEdited: filterRowRoot.filterChanged(filterType, filterFreq, newValue, filterQ)
            }
        }

        // Q (hidden for first-order types)
        Item {
            visible: isActive && !isLinkwitz
            width: 80
            height: parent.height
            ValueField {
                visible: hasQ
                anchors.verticalCenter: parent.verticalCenter
                fieldWidth: 56; height: 28; suffix: "Q"; decimals: 3; wheelStep: 0.1; minValue: 0.1; maxValue: 20
                value: filterQ
                onValueEdited: filterRowRoot.filterChanged(filterType, filterFreq, filterGain, newValue)
            }
        }
    }
}
