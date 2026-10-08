import QtQuick 2.15
import QtQuick.Controls 2.15

// Chooses a filter shape and its order, as a page of the band chip (or on
// the Ctrl-click card): a header with a back arrow and the shape's name, a
// grid of shapes, then for a shape with two orders its two slopes (or
// all-pass phases). Only the last click reports; after the macOS Console.
Item {
    id: chooser
    property int ownType: -1              // the band's type, marked; -1 = none
    property color markColor: "white"
    property string backTip: "Back"
    signal picked(int type)
    signal back()

    // name, 2nd-order type, 1st-order type (0 = none)
    readonly property var shapes: [
        { name: "Bell", t2: 1, t1: 0 }, { name: "Low Shelf", t2: 2, t1: 9 },
        { name: "Low Cut", t2: 5, t1: 13 }, { name: "High Shelf", t2: 3, t1: 10 },
        { name: "High Cut", t2: 4, t1: 12 }, { name: "Notch", t2: 6, t1: 0 },
        { name: "All Pass", t2: 7, t1: 8 }]
    function indexOfType(t) {
        for (var i = 0; i < shapes.length; i++) if (shapes[i].t2 === t || shapes[i].t1 === t) return i
        return -1
    }
    readonly property int ownShape: indexOfType(ownType)
    readonly property int ownOrder: ownShape >= 0 && shapes[ownShape].t1 === ownType ? 1 : 2
    property int pending: -1              // shape awaiting its order
    property int hovered: -1
    function reset() { pending = -1; hovered = -1 }

    readonly property string title: {
        var i = pending >= 0 ? pending : hovered >= 0 ? hovered : ownShape
        return i >= 0 ? shapes[i].name : "Add Band"
    }

    // Header: back arrow and the shape's name
    Item {
        id: header
        width: parent.width
        height: 22
        Rectangle {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 16; radius: 4
            color: isMacOS ? (backMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent") : backMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
            Icon { anchors.centerIn: parent; name: "chev-left"; size: 10; color: isMacOS ? Qt.rgba(1, 1, 1, 0.82) : Qt.rgba(1, 1, 1, 0.75) }
            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { if (chooser.pending >= 0) chooser.pending = -1; else chooser.back() }
            }
            ToolTip.visible: backMouse.containsMouse
            ToolTip.delay: 600
            ToolTip.text: chooser.pending >= 0 ? "Back to shapes" : chooser.backTip
        }
        Text {
            x: 19
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 25
            elide: Text.ElideRight
            text: chooser.title
            font.pixelSize: 10
            color: Qt.rgba(1, 1, 1, 0.85)
        }
        Rectangle { anchors.bottom: parent.bottom; x: 8; width: parent.width - 16; height: 1; color: Qt.rgba(1, 1, 1, 0.09) }
    }

    // Step one: the shapes fill the body, a short last row centred
    Item {
        id: body
        visible: chooser.pending < 0
        x: 5
        y: header.height + 2
        width: parent.width - 10
        height: parent.height - header.height - 5
        readonly property int columns: 4
        readonly property int rows: Math.ceil(chooser.shapes.length / columns)
        readonly property real cellW: width / columns
        readonly property real cellH: height / rows
        Repeater {
            model: chooser.shapes
            Rectangle {
                readonly property int row: Math.floor(index / body.columns)
                readonly property int inRow: Math.min(body.columns, chooser.shapes.length - row * body.columns)
                readonly property bool marked: index === chooser.ownShape
                x: (body.columns - inRow) * body.cellW / 2 + (index % body.columns) * body.cellW + 1
                y: row * body.cellH + 1
                width: body.cellW - 2
                height: body.cellH - 2
                radius: 5
                color: isMacOS ? (marked ? Qt.rgba(1, 1, 1, 0.16) : cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent") : marked ? Qt.rgba(chooser.markColor.r, chooser.markColor.g, chooser.markColor.b, 0.18)
                     : cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                PeqShapeGlyph {
                    anchors.centerIn: parent
                    type: modelData.t2
                    color: parent.marked ? chooser.markColor : Qt.rgba(1, 1, 1, 0.7)
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (containsMouse) chooser.hovered = index
                        else if (chooser.hovered === index) chooser.hovered = -1
                    }
                    // Two orders: ask which; one: done
                    onClicked: { if (modelData.t1 !== 0) chooser.pending = index; else chooser.picked(modelData.t2) }
                }
            }
        }
    }

    // Step two: the picked shape's two orders
    Row {
        visible: chooser.pending >= 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: header.height + (parent.height - header.height - height) / 2
        spacing: 5
        Repeater {
            model: 2
            Rectangle {
                readonly property int order: index + 1
                readonly property var shape: chooser.pending >= 0 ? chooser.shapes[chooser.pending] : null
                readonly property bool marked: chooser.pending === chooser.ownShape && order === chooser.ownOrder
                width: 40; height: 18; radius: 5
                color: isMacOS ? (marked ? Qt.rgba(1, 1, 1, 0.16) : orderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)) : marked ? Qt.rgba(chooser.markColor.r, chooser.markColor.g, chooser.markColor.b, 0.22)
                     : orderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.07)
                Text {
                    anchors.centerIn: parent
                    text: parent.shape && parent.shape.t2 === 7 ? (parent.order === 1 ? "180°" : "360°") : (parent.order === 1 ? "6 dB" : "12 dB")
                    font.pixelSize: 10
                    color: parent.marked ? chooser.markColor : Qt.rgba(1, 1, 1, 0.85)
                }
                MouseArea {
                    id: orderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chooser.picked(parent.order === 1 ? parent.shape.t1 : parent.shape.t2)
                }
                ToolTip.visible: orderMouse.containsMouse
                ToolTip.delay: 600
                ToolTip.text: shape && shape.t2 === 7 ? (order === 1 ? "First order, 180° of phase" : "Second order, 360° of phase")
                                                      : (order === 1 ? "6 dB per octave" : "12 dB per octave")
            }
        }
    }
}
