import QtQuick 2.15
import QtQuick.Controls 2.15

// A pick-one menu in families: each row names a family and opens its choices
// in a submenu beside it (hover, click, or Right / Enter).
// categories: [{ text, options: [ChoiceMenu options] }]. Emits chosen(value).
Popup {
    id: menu
    property var categories: []
    property var currentValue
    signal chosen(var value)

    width: Math.max(150, widest.advanceWidth + 64)
    padding: MenuStyle.padding
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property int current: -1
    property int openIndex: -1

    TextMetrics {
        id: widest
        font.pixelSize: MenuStyle.fontSize
        text: {
            var t = ""
            for (var i = 0; i < menu.categories.length; i++)
                if (menu.categories[i].text.length > t.length) t = menu.categories[i].text
            return t
        }
    }

    // The anchor's own click would reopen a menu its press just closed
    property real closedAt: 0
    onClosed: { closedAt = Date.now(); sub.close(); openIndex = -1 }

    function containsCurrent(i) {
        var o = categories[i].options
        for (var k = 0; k < o.length; k++) if (o[k].value === currentValue) return true
        return false
    }

    function openAt(anchorItem) {
        var p = anchorItem.mapToItem(parent, 0, 0)
        x = Math.max(6, p.x - 4)
        var fullHeight = list.implicitHeight + topPadding + bottomPadding
        var below = parent.height - (p.y + anchorItem.height + 6) - 8
        var above = p.y - 6 - 8
        var openUp = fullHeight > below && above > below
        height = Math.min(fullHeight, openUp ? above : below)
        y = openUp ? p.y - 6 - height : p.y + anchorItem.height + 6
        transformOrigin = openUp ? Popup.BottomLeft : Popup.TopLeft
        current = -1
        for (var i = 0; i < categories.length; i++) if (containsCurrent(i)) current = i
        open()
    }
    function toggleAt(anchorItem) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        openAt(anchorItem)
    }

    function openSub(i, focusIt) {
        if (i < 0 || i >= categories.length) return
        current = i
        if (openIndex === i && sub.visible) { if (focusIt) sub.contentItem.forceActiveFocus(); return }
        // An open submenu is refilled and moved rather than closed and reopened
        openIndex = i
        sub.options = categories[i].options
        sub.openBeside(rows.itemAt(i))
        if (focusIt) {
            sub.contentItem.forceActiveFocus()
            if (sub.current < 0) sub.step(1)
        }
    }

    property ChoiceMenu sub: ChoiceMenu {
        parent: menu.parent
        currentValue: menu.currentValue
        onChosen: { menu.close(); menu.chosen(value) }
        onClosed: menu.openIndex = -1
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 140; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }
    transformOrigin: Popup.TopLeft

    background: Item {
        Repeater {
            model: 6
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1) * 2
                anchors.topMargin: -(index + 1) * 2 + 4
                radius: MenuStyle.radius + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: MenuStyle.radius
            color: MenuStyle.background
            border.color: MenuStyle.border
        }
    }

    contentItem: Flickable {
        id: scroller
        focus: true
        clip: true
        contentHeight: list.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        ScrollIndicator.vertical: ScrollIndicator {}
        Keys.onUpPressed: menu.current = (menu.current <= 0 ? menu.categories.length : menu.current) - 1
        Keys.onDownPressed: menu.current = (menu.current + 1) % menu.categories.length
        Keys.onRightPressed: menu.openSub(menu.current, true)
        Keys.onReturnPressed: menu.openSub(menu.current, true)
        Keys.onEnterPressed: menu.openSub(menu.current, true)

        Column {
            id: list
            width: scroller.width
            Repeater {
                id: rows
                model: menu.categories
                Item {
                    id: row
                    width: parent.width
                    height: MenuStyle.rowHeight
                    readonly property bool hot: menu.current === index || menu.openIndex === index
                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        radius: MenuStyle.rowRadius
                        color: row.hot ? MenuStyle.highlight : "transparent"
                    }
                    Text {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        font.pixelSize: MenuStyle.fontSize
                        font.weight: menu.containsCurrent(index) ? Font.DemiBold : Font.Normal
                        color: "white"
                    }
                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chev-right"
                        size: 12
                        color: row.hot ? "white" : Qt.rgba(1, 1, 1, 0.5)
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: menu.openSub(index, false)
                        onClicked: menu.openSub(index, true)
                    }
                }
            }
        }
    }
}
