import QtQuick 2.15
import QtQuick.Controls 2.15

// Ctrl-click on empty graph: the shape chooser on a card the size of a band
// chip, for a band not made yet. The back arrow cancels.
Popup {
    id: card
    property var editor
    property real createFreq: 1000
    property real createGain: 0

    // Placed as the new band's chip will be: above a boost (below a cut),
    // else to the right, the left, the other side; kept inside the graph
    function openBeside(px, py, boost) {
        var gap = 16, w = width, h = height, area = { x: 4, y: 4, w: parent.width - 8, h: parent.height - 8 }
        function cx(x) { return Math.min(Math.max(x, area.x), Math.max(area.x + area.w - w, area.x)) }
        function cy(y) { return Math.min(Math.max(y, area.y), Math.max(area.y + area.h - h, area.y)) }
        function inside(r) { return r.x >= area.x && r.y >= area.y && r.x + w <= area.x + area.w && r.y + h <= area.y + area.h }
        var above = { x: cx(px - w / 2), y: py - gap - h }, below = { x: cx(px - w / 2), y: py + gap }
        var right = { x: px + gap, y: cy(py - h / 2) }, left = { x: px - gap - w, y: cy(py - h / 2) }
        var order = boost ? [above, right, left, below] : [below, right, left, above], pick = order[0]
        for (var i = 0; i < order.length; i++) if (inside(order[i])) { pick = order[i]; break }
        x = cx(pick.x)
        y = cy(pick.y)
        chooser.reset()
        open()
    }

    width: 110
    height: 78
    padding: 0
    focus: true
    // A click elsewhere only dismisses the card; it doesn't reach the graph
    modal: true
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: if (editor) editor.cardClosed()
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 120; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 } }

    background: Rectangle {
        radius: 8
        color: "#1e1e21"
        border.color: Qt.rgba(1, 1, 1, 0.10)
        Repeater {
            model: 3
            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.margins: -(index + 1)
                anchors.topMargin: -(index + 1) + 2
                radius: 8 + index + 1
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.18 - index * 0.05)
            }
        }
    }

    contentItem: PeqShapeChooser {
        id: chooser
        backTip: "Cancel"
        onBack: card.close()
        onPicked: { card.editor.createShape(type, card.createFreq, card.createGain); card.close() }
    }
}
