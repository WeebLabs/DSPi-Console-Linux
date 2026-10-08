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

    // The graph editor: PEQ rows share its selection and hover
    property var editor: null
    readonly property bool linked: editor !== null && editor.active && !xo && editor.channel === channelId
    readonly property var selectedBands: linked ? editor.selectedBands : []
    readonly property int graphHovered: linked ? editor.hoveredBand : -1
    property var previousSelection: []
    property string madeByList: ""      // the selection the list last made; it doesn't scroll for it

    onChannelIdChanged: showCrossover = false
    // While the XO tab is open the graph can't add or edit PEQ bands (as on macOS)
    onXoChanged: root.crossoverTabOpen = xo
    Component.onCompleted: root.crossoverTabOpen = xo
    Component.onDestruction: root.crossoverTabOpen = false
    onLinkedChanged: {
        previousSelection = linked ? editor.selectedBands : []
        if (!linked && editor && editor.listHovered >= 0) editor.listHovered = -1
    }
    Connections { target: bridge; function onStateChanged() { filterListRoot.rev++ } }

    // A band newly selected on the graph, or one the pointer rests on there,
    // scrolls its row into view; a row already in view does not move
    Connections {
        target: filterListRoot.linked ? filterListRoot.editor : null
        function onSelectionChanged() {
            var now = filterListRoot.editor.selectedBands
            var added = now.filter(function (b) { return filterListRoot.previousSelection.indexOf(b) < 0 })
            filterListRoot.previousSelection = now
            if (now.join(",") === filterListRoot.madeByList) return
            filterListRoot.madeByList = ""
            if (added.length) filterListRoot.reveal(Math.min.apply(null, added))
        }
        function onRevealRow(band) { filterListRoot.reveal(band) }
    }

    function reveal(band) {
        var top = band * 36, bottom = top + 36
        var to = bandList.contentY
        if (top < to) to = top
        else if (bottom > to + bandList.height) to = bottom - bandList.height
        if (to === bandList.contentY) return
        revealAnim.to = Math.max(0, Math.min(to, bandList.contentHeight - bandList.height))
        revealAnim.restart()
    }

    function listClick(band, modifiers) {
        editor.listClick(band, (modifiers & Qt.ControlModifier) !== 0, (modifiers & Qt.ShiftModifier) !== 0)
        madeByList = editor.selectedBands.join(",")
    }

    component HeaderText: Text {
        font.pixelSize: 10
        font.weight: Font.Bold
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
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
        color: isMacOS ? (active || ma.containsMouse && !dim ? MacColors.opacity(MacColors.gray, 0.22) : "transparent") : active ? "#0078d4" : (ma.containsMouse && !dim ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05))
        Text {
            id: lbl
            anchors.centerIn: parent
            font.pixelSize: 11
            color: isMacOS ? (parent.active ? MacColors.label : MacColors.opacity(MacColors.secondaryLabel, parent.dim ? 0.4 : 1.0)) : parent.active ? "white" : Qt.rgba(1, 1, 1, parent.dim ? 0.3 : 0.75)
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

    // ── macOS footer (Components.swift:1590-1665) ──
    // Outlined caption pills on the list's material: Enable All | Bypass All
    // on the left; Clear All and PEQ | XO on the right (outputs).
    // The footer's .ultraThinMaterial over the rows, as measured
    readonly property color macFooterColor: "#292929"

    // One segment of a pill: caption text, grey fill when hovered or selected.
    // `first` / `last` round the fill into the pill's corners.
    component MacSegment: Item {
        id: seg
        property alias label: segText.text
        property real minWidth: 0
        property bool selected: false
        property bool dim: false
        property bool hoverFill: true
        property bool first: true
        property bool last: true
        signal clicked()
        width: Math.max(minWidth, segText.implicitWidth + 16)
        height: parent ? parent.height : 20
        readonly property bool lit: selected || (hoverFill && segMouse.containsMouse && !dim)
        // gray 0.22 over the footer, made opaque so the pieces below can overlap
        readonly property color fill: Qt.tint(filterListRoot.macFooterColor, MacColors.opacity(MacColors.gray, 0.22))
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1          // inside the pill's outline
            radius: 5
            visible: seg.lit
            color: seg.fill
        }
        // Square the inner side of the fill where it meets the next segment
        Rectangle {
            visible: seg.lit && !seg.first
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: 6; height: parent.height - 2
            color: seg.fill
        }
        Rectangle {
            visible: seg.lit && !seg.last
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 6; height: parent.height - 2
            color: seg.fill
        }
        Text {
            id: segText
            anchors.centerIn: parent
            font.pixelSize: 10
            font.weight: Font.Medium
            color: seg.selected ? MacColors.label : MacColors.secondaryLabel
            opacity: seg.dim ? 0.4 : 1
        }
        MouseArea {
            id: segMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !seg.dim
            onClicked: seg.clicked()
        }
    }

    // The 1 pt rule between segments
    component MacSegmentRule: Rectangle {
        width: 1; height: 16
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: MacColors.opacity(MacColors.gray, 0.3)
    }

    // The pill: the segments in a row inside a grey 0.3 outline
    component MacPill: Item {
        default property alias segments: pillRow.data
        width: pillRow.implicitWidth
        height: 20
        Row { id: pillRow; height: parent.height }
        Rectangle {
            anchors.fill: parent
            radius: 6
            color: "transparent"
            border.color: MacColors.opacity(MacColors.gray, 0.3)
            border.width: 1
        }
    }

    Component {
        id: macFooter
        Item {
            // .ultraThinMaterial over the rows, inside the card's border and
            // rounded bottom corners
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 1; anchors.rightMargin: 1; anchors.bottomMargin: 1
                radius: 9
                color: filterListRoot.macFooterColor
                Rectangle { width: parent.width; height: parent.radius; color: parent.color }
            }

            MacPill {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                MacSegment {
                    label: "Enable All"
                    last: false
                    dim: { filterListRoot.rev; return !bridge.canSetAllBypass(filterListRoot.channelId, false, xo) }
                    onClicked: bridge.setAllBandsBypass(filterListRoot.channelId, false, xo)
                }
                MacSegmentRule {}
                MacSegment {
                    label: "Bypass All"
                    first: false
                    dim: { filterListRoot.rev; return !bridge.canSetAllBypass(filterListRoot.channelId, true, xo) }
                    onClicked: {
                        if (xo) xoBypassDialog.open()
                        else bridge.setAllBandsBypass(filterListRoot.channelId, true, false)
                    }
                }
            }

            Row {
                visible: isOutput
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                MacPill {
                    MacSegment { label: "Clear All"; hoverFill: false; onClicked: clearDialog.open() }
                }
                MacPill {
                    // Both segments as wide as the wider title
                    TextMetrics { id: tabTitle; font.pixelSize: 10; font.weight: Font.Medium; text: "PEQ" }
                    MacSegment { label: "PEQ"; last: false; minWidth: tabTitle.width + 16; selected: !showCrossover; hoverFill: false; onClicked: showCrossover = false }
                    MacSegmentRule {}
                    MacSegment { label: "XO"; first: false; minWidth: tabTitle.width + 16; selected: showCrossover; hoverFill: false; onClicked: showCrossover = true }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        radius: 10
        color: isMacOS ? MacColors.opacity(MacColors.controlBackground, 0.6) : nativeAltBaseColor
        border.color: isMacOS ? MacColors.opacity(MacColors.gray, 0.2) : Qt.rgba(1, 1, 1, 0.1)
        border.width: 1
        clip: true

        // Header row
        Item {
            id: header
            width: parent.width
            height: isMacOS ? 32 : 36

            // macOS: the native header is an opaque controlBackground bar
            // (Components.swift:1581), inside the card's border
            Rectangle {
                visible: isMacOS
                anchors.fill: parent
                anchors.leftMargin: 1; anchors.rightMargin: 1; anchors.topMargin: 1
                radius: 9
                color: MacColors.controlBackground
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.radius; color: parent.color }
            }

            Row {
                visible: !xo
                anchors.fill: parent
                anchors.leftMargin: 16
                spacing: 0
                HeaderText { width: 42; text: "#"; leftPadding: isMacOS ? 30 : 18 }
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
                HeaderText { width: 42; text: "#"; leftPadding: isMacOS ? 30 : 18 }
                HeaderText { width: 140; text: "FAMILY"; leftPadding: 4 }
                HeaderText { width: 110; text: "TYPE"; leftPadding: 4 }
                HeaderText { width: 110; text: "SLOPE"; leftPadding: 4 }
                HeaderText { width: 100; text: "FREQ" }
            }
        }

        Rectangle { id: sep; anchors.top: header.bottom; width: parent.width; height: isMacOS ? 0 : 1; color: Qt.rgba(1, 1, 1, 0.1) }

        Flickable {
            id: bandList
            anchors.top: sep.bottom
            anchors.bottom: footer.top
            width: parent.width
            clip: true
            contentHeight: bands.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            NumberAnimation { id: revealAnim; target: bandList; property: "contentY"; duration: 250; easing.type: Easing.InOutQuad }

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
                        linked: filterListRoot.linked
                        selected: filterListRoot.selectedBands.indexOf(index) >= 0
                        graphHovered: filterListRoot.graphHovered === index

                        onNumberClicked: filterListRoot.listClick(bandIndex, modifiers)
                        onPointerOver: function (over) {
                            if (over) filterListRoot.editor.listHovered = bandIndex
                            else if (filterListRoot.editor.listHovered === bandIndex) filterListRoot.editor.listHovered = -1
                        }
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
            height: isMacOS ? 36 : 40

            Rectangle { visible: !isMacOS; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

            Row {
                visible: !isMacOS
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
                visible: !isMacOS && isOutput
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                FooterButton { label: "PEQ"; active: !showCrossover; onClicked: showCrossover = false }
                FooterButton { label: "XO"; active: showCrossover; onClicked: showCrossover = true }
            }

            Loader {
                anchors.fill: parent
                active: isMacOS
                sourceComponent: macFooter
            }
        }
    }

    AppDialog {
        id: clearDialog
        icon: "warning"
        iconTint: "#ff6961"
        title: "Clear All Bands?"
        message: "Every " + (xo ? "crossover" : "PEQ") + " band on " + bridge.channelName(filterListRoot.channelId)
                 + " will be set to Off."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "clear", text: "Clear All", role: "destructive" }
        ]
        onChosen: if (key === "clear") bridge.clearAllBands(filterListRoot.channelId, xo)
    }

    AppDialog {
        id: xoBypassDialog
        icon: "warning"
        iconTint: "#ff9f0a"
        title: "Bypass All Crossovers?"
        message: "Bypassing the crossovers sends full-range audio to this output, which can damage "
                 + "a tweeter or other driver that relies on them for protection."
        buttons: [
            { key: "cancel", text: "Cancel" },
            { key: "bypass", text: "Bypass All", role: "destructive" }
        ]
        onChosen: if (key === "bypass") bridge.setAllBandsBypass(filterListRoot.channelId, true, true)
    }
}
