import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import "components"

// AutoEQ > Browse Profiles: search the headphone database, pick a profile
// and apply it to inputs 1 and 2. A heart on hover adds it to the
// favourites in the menu.
AppWindow {
    id: win
    title: "AutoEQ - Browse Profiles"
    visible: false
    width: 600
    height: 500 + titlebarHeight
    minimumWidth: 450
    minimumHeight: 350 + titlebarHeight

    property string selectedId: ""
    readonly property var selected: selectedId !== "" ? autoeq.entry(selectedId) : ({})
    property string message: ""

    onVisibleChanged: if (visible) {
        autoeq.load()
        message = ""
        search.forceActiveFocus()
    }

    function apply() {
        if (selectedId === "") return
        if (!autoeq.apply(selectedId)) {
            message = bridge.connected ? "This profile could not be applied." : "Connect the DSPi before applying a profile."
            return
        }
        close()
    }
    function sourceColor(source) {
        switch (source) {
        case "oratory1990": return isMacOS ? MacColors.orange : "#ff9f0a"
        case "crinacle": return isMacOS ? MacColors.purple : "#bf5af2"
        case "rtings": return isMacOS ? MacColors.blue : "#0a84ff"
        case "innerfidelity": return isMacOS ? MacColors.green : "#32d74b"
        default: return isMacOS ? MacColors.gray : "#8e8e93"
        }
    }

    // ── Search ──
    Rectangle {
        id: searchBar
        width: parent.width
        height: 44
        color: isMacOS ? MacColors.controlBackground : "transparent"
        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            radius: 8
            color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.08)
            border.color: isMacOS ? "transparent" : search.activeFocus ? "#0a7cff" : "transparent"
            Icon {
                id: searchIcon
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: 14
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45)
            }
            TextInput {
                id: search
                anchors.left: searchIcon.right
                anchors.leftMargin: 7
                anchors.right: clear.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 13
                color: isMacOS ? MacColors.label : "white"
                selectByMouse: true
                clip: true
                text: autoeq.query
                onTextChanged: { autoeq.query = text; list.currentIndex = -1 }
                Keys.onDownPressed: { list.forceActiveFocus(); if (list.currentIndex < 0) list.currentIndex = 0 }
                Keys.onReturnPressed: win.apply()
                Text {
                    visible: !search.text
                    text: "Search headphones..."
                    font: search.font
                    color: isMacOS ? MacColors.placeholderText : Qt.rgba(1, 1, 1, 0.4)
                }
            }
            Icon {
                id: clear
                visible: search.text !== ""
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                name: "xmark"
                size: 12
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: search.text = "" }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }
    }

    // ── Results ──
    ListView {
        id: list
        anchors.top: searchBar.bottom
        anchors.bottom: bottomBar.top
        width: parent.width
        clip: true
        model: autoeq.results
        currentIndex: -1
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        onCurrentIndexChanged: if (currentItem) win.selectedId = currentItem.entryId
        Keys.onReturnPressed: win.apply()
        Keys.onEnterPressed: win.apply()

        delegate: Item {
            id: row
            readonly property string entryId: model.entryId
            readonly property bool isSelected: win.selectedId === model.entryId
            width: list.width
            height: 46

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                radius: 6
                color: isMacOS ? (row.isSelected ? MacColors.accent : "transparent") : row.isSelected ? "#0a7cff" : rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            }
            Icon {
                id: kind
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                name: model.formFactor === "over-ear" ? "headphones" : "earbuds"
                size: 20
                color: isMacOS ? (row.isSelected ? "white" : MacColors.accent) : row.isSelected ? "white" : "#3a96ff"
            }
            Column {
                anchors.left: kind.right
                anchors.leftMargin: 12
                anchors.right: heart.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: model.name
                    font.pixelSize: 13
                    color: isMacOS ? (row.isSelected ? "white" : MacColors.label) : "white"
                }
                Row {
                    spacing: 8
                    Item {
                        width: sourceLabel.implicitWidth + 12
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: isMacOS ? win.sourceColor(model.source) : row.isSelected ? Qt.rgba(1, 1, 1, 0.25) : win.sourceColor(model.source)
                            opacity: isMacOS ? (row.isSelected ? 0.3 : 0.15) : row.isSelected ? 1 : 0.18
                        }
                        Text {
                            id: sourceLabel
                            anchors.centerIn: parent
                            text: model.sourceName
                            font.pixelSize: 11
                            color: row.isSelected ? "white" : win.sourceColor(model.source)
                        }
                    }
                    Text {
                        text: model.formFactor
                        font.pixelSize: 11
                        color: isMacOS ? (row.isSelected ? Qt.rgba(1, 1, 1, 0.8) : MacColors.secondaryLabel) : row.isSelected ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(1, 1, 1, 0.5)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { list.currentIndex = index; list.forceActiveFocus() }
                onDoubleClicked: { list.currentIndex = index; win.apply() }
            }
            // On hover, or always once favourited
            Icon {
                id: heart
                visible: rowMouse.containsMouse || heartMouse.containsMouse || model.favorite
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                name: model.favorite ? "heart-fill" : "heart"
                size: 15
                color: isMacOS ? (model.favorite ? MacColors.red : row.isSelected ? Qt.rgba(1, 1, 1, 0.7) : MacColors.secondaryLabel) : model.favorite ? "#ff453a" : row.isSelected ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.5)
                MouseArea {
                    id: heartMouse
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: autoeq.toggleFavorite(model.entryId)
                }
                ToolTip.text: model.favorite ? "Remove from favorites" : "Add to favorites"
                ToolTip.visible: heartMouse.containsMouse
                ToolTip.delay: 600
            }
        }

        Text {
            visible: list.count === 0
            anchors.centerIn: parent
            width: parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: autoeq.loadError !== "" ? autoeq.loadError
                : autoeq.entryCount === 0 ? "Loading headphone database..."
                : "No headphones found matching \"" + search.text + "\""
            font.pixelSize: 13
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // ── Selection and buttons ──
    Item {
        id: bottomBar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 58
        Rectangle { width: parent.width; height: 1; color: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07) }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: buttons.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: win.message !== "" ? win.message
                    : win.selected.name || "Select a headphone to apply its EQ profile"
                font.pixelSize: 13
                font.weight: win.selected.name && win.message === "" ? Font.DemiBold : Font.Normal
                color: isMacOS ? (win.message !== "" ? MacColors.orange : win.selected.name ? MacColors.label : MacColors.secondaryLabel) : win.message !== "" ? "#ff9f0a" : win.selected.name ? "white" : Qt.rgba(1, 1, 1, 0.5)
            }
            Text {
                visible: !!win.selected.name && win.message === ""
                text: (win.selected.source || "") + "  ·  " + (win.selected.formFactor || "")
                font.pixelSize: 11
                color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
            }
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            AppButton { text: "Cancel"; onClicked: win.close() }
            AppButton { text: "Apply"; primary: true; enabled: win.selectedId !== ""; onClicked: win.apply() }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: win.close() }
}
