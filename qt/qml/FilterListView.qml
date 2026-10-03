import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

// The band list of a channel page. Output pages have PEQ and XO tabs.
Item {
    id: filterListRoot
    property int channelId: 0
    readonly property bool isOutput: !bridge.isInputChannel(channelId)
    property bool showCrossover: false
    readonly property bool xo: isOutput && showCrossover
    property int rev: 0

    onChannelIdChanged: showCrossover = false
    Connections { target: bridge; function onStateChanged() { filterListRoot.rev++ } }

    component HeaderText: Text {
        font.pixelSize: 10
        font.weight: Font.Bold
        color: Qt.rgba(1, 1, 1, 0.5)
        anchors.verticalCenter: parent.verticalCenter
    }

    component FooterButton: Rectangle {
        property alias label: lbl.text
        property bool active: false
        property bool dim: false
        signal clicked()
        width: lbl.implicitWidth + 20
        height: 24
        radius: 5
        color: active ? "#0078d4" : (ma.containsMouse && !dim ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05))
        Text {
            id: lbl
            anchors.centerIn: parent
            font.pixelSize: 11
            color: parent.active ? "white" : Qt.rgba(1, 1, 1, parent.dim ? 0.3 : 0.75)
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            enabled: !parent.dim
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        radius: 10
        color: isMacOS ? Qt.rgba(0.21, 0.21, 0.21, 0.6) : nativeAltBaseColor
        border.color: Qt.rgba(1, 1, 1, 0.1)
        border.width: 1
        clip: true

        // Header row
        Item {
            id: header
            width: parent.width
            height: 36

            Row {
                visible: !xo
                anchors.fill: parent
                anchors.leftMargin: 16
                spacing: 0
                HeaderText { width: 42; text: "#"; leftPadding: 18 }
                HeaderText { width: 150; text: "TYPE"; leftPadding: 4 }
                HeaderText { width: 100; text: "FREQ" }
                HeaderText { width: 90; text: "GAIN" }
                HeaderText { width: 80; text: "WIDTH" }
            }
            Row {
                visible: xo
                anchors.fill: parent
                anchors.leftMargin: 16
                spacing: 0
                HeaderText { width: 42; text: "#"; leftPadding: 18 }
                HeaderText { width: 140; text: "FAMILY"; leftPadding: 4 }
                HeaderText { width: 110; text: "TYPE"; leftPadding: 4 }
                HeaderText { width: 110; text: "SLOPE"; leftPadding: 4 }
                HeaderText { width: 100; text: "FREQ" }
            }
        }

        Rectangle { id: sep; anchors.top: header.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

        Flickable {
            anchors.top: sep.bottom
            anchors.bottom: footer.top
            width: parent.width
            clip: true
            contentHeight: bands.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: bands
                width: parent.width

                Repeater {
                    model: xo ? 0 : 10

                    FilterRow {
                        width: parent.width
                        channelId: filterListRoot.channelId
                        bandIndex: index
                        isOutput: filterListRoot.isOutput
                        filterType: { filterListRoot.rev; return bridge.filterType(filterListRoot.channelId, index) }
                        filterFreq: { filterListRoot.rev; return bridge.filterFreq(filterListRoot.channelId, index) }
                        filterGain: { filterListRoot.rev; return bridge.filterGain(filterListRoot.channelId, index) }
                        filterQ: { filterListRoot.rev; return bridge.filterQ(filterListRoot.channelId, index) }
                        filterBypass: { filterListRoot.rev; return bridge.filterBypass(filterListRoot.channelId, index) }

                        onFilterChanged: bridge.setFilter(filterListRoot.channelId, bandIndex, type, freq, gain, q)
                        onBypassToggled: bridge.setBandBypass(filterListRoot.channelId, bandIndex, bypass)
                    }
                }

                Repeater {
                    model: xo ? 4 : 0
                    CrossoverRow {
                        width: parent.width
                        channelId: filterListRoot.channelId
                        bandIndex: index
                    }
                }
            }
        }

        // Footer: Enable All | Bypass All, Clear All, PEQ | XO
        Item {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width
            height: 40

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                FooterButton {
                    label: "Enable All"
                    dim: { filterListRoot.rev; return !bridge.canSetAllBypass(filterListRoot.channelId, false, xo) }
                    onClicked: bridge.setAllBandsBypass(filterListRoot.channelId, false, xo)
                }
                FooterButton {
                    label: "Bypass All"
                    dim: { filterListRoot.rev; return !bridge.canSetAllBypass(filterListRoot.channelId, true, xo) }
                    onClicked: {
                        if (xo) xoBypassDialog.open()
                        else bridge.setAllBandsBypass(filterListRoot.channelId, true, false)
                    }
                }
                FooterButton {
                    visible: isOutput
                    label: "Clear All"
                    onClicked: clearDialog.open()
                }
            }

            Row {
                visible: isOutput
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                FooterButton { label: "PEQ"; active: !showCrossover; onClicked: showCrossover = false }
                FooterButton { label: "XO"; active: showCrossover; onClicked: showCrossover = true }
            }
        }
    }

    Dialog {
        id: clearDialog
        title: "Clear All Bands?"
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 360
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Every " + (xo ? "crossover" : "PEQ") + " band on " + bridge.channelName(filterListRoot.channelId)
                  + " will be set to Off."
        }
        onAccepted: bridge.clearAllBands(filterListRoot.channelId, xo)
    }

    Dialog {
        id: xoBypassDialog
        title: "Bypass All Crossovers?"
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 380
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Bypassing the crossovers sends full-range audio to this output, which can damage a tweeter or other driver that relies on them for protection."
        }
        onAccepted: bridge.setAllBandsBypass(filterListRoot.channelId, true, true)
    }
}
