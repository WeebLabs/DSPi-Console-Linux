import QtQuick 2.15
import QtQuick.Controls 2.15

// A modal prompt in the app's menu style: icon tile, title, message and a
// row of buttons. buttons: [{ key, text, role }] with role "primary",
// "destructive" or "secondary" (the default). Emits chosen(key); Esc or a
// click outside cancels (chosen("cancel")), Enter picks the primary button.
// hasInput adds a text field under the message (inputText), focused and
// selected on open (e.g. Rename). checks adds tick boxes under that:
// [{ key, text, checked, detail? }]; checkedKeys has the ticked keys.
Popup {
    id: dlg
    property string title: ""
    property string message: ""
    property string icon: ""
    property color iconTint: "#0a7cff"
    property var buttons: []
    // Optional lines in a box under the message: [{ text, color? }]; a
    // colour draws a dot (e.g. a channel's colour)
    property var details: []
    property var checks: []
    property var checkedKeys: []
    onChecksChanged: checkedKeys = checks.filter(function (c) { return c.checked }).map(function (c) { return c.key })
    function toggleCheck(key) {
        var k = checkedKeys.slice(), i = k.indexOf(key)
        if (i >= 0) k.splice(i, 1); else k.push(key)
        checkedKeys = k
    }
    property bool hasInput: false
    property alias inputText: input.text
    property string placeholder: ""
    property int maxLength: 31
    signal chosen(string key)

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, parent ? parent.width - 48 : 420)
    padding: 22
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property bool answered: false
    onAboutToShow: answered = false
    onOpened: if (hasInput) { input.forceActiveFocus(); input.selectAll() }
    onClosed: if (!answered) chosen("cancel")
    function choose(key) { if (answered) return; answered = true; close(); chosen(key) }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.45) }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 130; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 150; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }

    background: Item {
        Repeater {
            model: 8
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1) * 2
                anchors.topMargin: -(index + 1) * 2 + 6
                radius: 14 + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.12 - index * 0.013)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: MenuStyle.background
            border.color: MenuStyle.border
        }
    }

    contentItem: Column {
        spacing: 18
        focus: true
        Keys.onReturnPressed: dlg.choosePrimary()
        Keys.onEnterPressed: dlg.choosePrimary()

        Row {
            width: parent.width
            spacing: 14

            Rectangle {
                visible: dlg.icon !== ""
                width: 38; height: 38; radius: 10
                color: Qt.rgba(dlg.iconTint.r, dlg.iconTint.g, dlg.iconTint.b, 0.18)
                Icon {
                    anchors.centerIn: parent
                    name: dlg.icon
                    size: 20
                    color: dlg.iconTint
                }
            }
            Column {
                width: parent.width - (dlg.icon !== "" ? 52 : 0)
                spacing: 6
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: dlg.title
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: isMacOS ? MacColors.label : "white"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: dlg.message !== ""
                    text: dlg.message
                    font.pixelSize: 13
                    color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.65)
                }
                TextField {
                    id: input
                    visible: dlg.hasInput
                    width: parent.width
                    height: 30
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 10
                    rightPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 13
                    color: isMacOS ? MacColors.label : "white"
                    selectionColor: isMacOS ? MacColors.selectedControl : "#0a7cff"
                    selectedTextColor: "white"
                    selectByMouse: true
                    maximumLength: dlg.maxLength
                    placeholderText: dlg.placeholder
                    placeholderTextColor: isMacOS ? Qt.rgba(1, 1, 1, 0.47) : Qt.rgba(1, 1, 1, 0.35)
                    onAccepted: dlg.choosePrimary()
                    background: Rectangle {
                        radius: 7
                        color: isMacOS ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: input.activeFocus ? 1.5 : 1
                        border.color: isMacOS ? (input.activeFocus ? MacColors.keyboardFocusIndicator : Qt.rgba(1, 1, 1, 0.11)) : input.activeFocus ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.12)
                    }
                }
                Rectangle {
                    visible: dlg.details.length > 0
                    width: parent.width
                    height: detailColumn.implicitHeight + 16
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(1, 1, 1, 0.07)
                    Column {
                        id: detailColumn
                        x: 12
                        y: 8
                        width: parent.width - 24
                        spacing: 4
                        Repeater {
                            model: dlg.details
                            Row {
                                spacing: 8
                                Rectangle {
                                    visible: !!modelData.color
                                    width: 8; height: 8; radius: 4
                                    color: modelData.color || "transparent"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.text
                                    font.pixelSize: 12
                                    color: Qt.rgba(1, 1, 1, 0.8)
                                }
                            }
                        }
                    }
                }
                // Tick boxes (scrolls when there are many)
                Flickable {
                    visible: dlg.checks.length > 0
                    width: parent.width
                    height: Math.min(checkColumn.implicitHeight, 300)
                    contentHeight: checkColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    ScrollBar.vertical: ScrollBar { policy: checkColumn.implicitHeight > 300 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }
                    Column {
                        id: checkColumn
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: dlg.checks
                            Item {
                                readonly property bool ticked: dlg.checkedKeys.indexOf(modelData.key) >= 0
                                width: checkColumn.width
                                height: Math.max(26, checkText.implicitHeight + 8)
                                Rectangle {
                                    id: box
                                    y: 5
                                    width: 16; height: 16; radius: 4
                                    color: isMacOS ? (parent.ticked ? MacColors.checkboxOn : Qt.rgba(1, 1, 1, 0.21)) : parent.ticked ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: isMacOS ? (parent.ticked ? MacColors.checkboxOn : Qt.rgba(1, 1, 1, 0.21)) : parent.ticked ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.25)
                                    Icon { anchors.centerIn: parent; visible: parent.parent.ticked; name: "check"; size: 13; color: isMacOS ? Qt.rgba(1, 1, 1, 0.85) : "white" }
                                }
                                Column {
                                    id: checkText
                                    anchors.left: box.right
                                    anchors.leftMargin: 9
                                    anchors.right: parent.right
                                    y: 4
                                    Text { width: parent.width; wrapMode: Text.WordWrap; text: modelData.text; font.pixelSize: 13; color: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9) }
                                    Text { visible: !!modelData.detail; width: parent.width; wrapMode: Text.WordWrap; text: modelData.detail || ""; font.pixelSize: 11; color: Qt.rgba(1, 1, 1, 0.5) }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dlg.toggleCheck(modelData.key) }
                            }
                        }
                    }
                }
            }
        }

        // Buttons share the full width equally, or stack full width when a
        // label wouldn't fit (as a macOS alert with many buttons does)
        TextMetrics {
            id: widestButton
            font.pixelSize: 13
            font.weight: Font.DemiBold
            text: {
                var t = ""
                for (var i = 0; i < dlg.buttons.length; i++) if (dlg.buttons[i].text.length > t.length) t = dlg.buttons[i].text
                return t
            }
        }
        Grid {
            id: buttonRow
            readonly property real share: (width - columnSpacing * (dlg.buttons.length - 1)) / Math.max(1, dlg.buttons.length)
            readonly property bool stacked: widestButton.advanceWidth + 24 > share
            width: parent.width
            columns: stacked ? 1 : Math.max(1, dlg.buttons.length)
            columnSpacing: 8
            rowSpacing: 6
            Repeater {
                model: dlg.buttons
                Rectangle {
                    id: btn
                    readonly property string role: modelData.role || "secondary"
                    readonly property bool filled: role === "primary" || role === "destructive"
                    width: buttonRow.stacked ? buttonRow.width : buttonRow.share
                    height: 32
                    radius: 8
                    color: isMacOS ? (filled ? (btnMouse.pressed ? MacColors.defaultButtonPressed : MacColors.defaultButton) : btnMouse.pressed ? Qt.rgba(1, 1, 1, 0.36) : Qt.rgba(1, 1, 1, 0.25)) : filled ? (role === "destructive" ? (btnMouse.pressed ? "#b52a31" : "#d9363e")
                                                            : (btnMouse.pressed ? "#0062cc" : "#0a7cff"))
                         : btnMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : btnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                    border.width: filled ? 0 : 1
                    border.color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.18)
                    opacity: isMacOS ? 1.0 : filled && btnMouse.containsMouse && !btnMouse.pressed ? 0.9 : 1.0
                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.text
                        font.pixelSize: 13
                        font.weight: btn.filled ? Font.DemiBold : Font.Normal
                        color: isMacOS ? (btn.filled ? Qt.rgba(1, 1, 1, 0.86) : Qt.rgba(1, 1, 1, 0.89)) : "white"
                    }
                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dlg.choose(modelData.key)
                    }
                }
            }
        }
    }

    function choosePrimary() {
        for (var i = 0; i < buttons.length; i++)
            if (buttons[i].role === "primary" || buttons[i].role === "destructive") { choose(buttons[i].key); return }
    }
}
