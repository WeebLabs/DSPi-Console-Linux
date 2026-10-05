import QtQuick 2.15

// Resize handles along the edges and corners of a frameless window. Resizing
// goes through the window manager (startSystemResize).
Item {
    id: edges
    property var window
    readonly property int grip: 6
    anchors.fill: parent

    component Edge: MouseArea {
        property int edgeFlags: 0
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onPressed: windowEffects.systemResize(edges.window, edgeFlags)
    }

    Edge { edgeFlags: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor
           x: 0; y: edges.grip; width: edges.grip; height: parent.height - 2 * edges.grip }
    Edge { edgeFlags: Qt.RightEdge; cursorShape: Qt.SizeHorCursor
           x: parent.width - edges.grip; y: edges.grip; width: edges.grip; height: parent.height - 2 * edges.grip }
    Edge { edgeFlags: Qt.TopEdge; cursorShape: Qt.SizeVerCursor
           x: edges.grip; y: 0; width: parent.width - 2 * edges.grip; height: edges.grip }
    Edge { edgeFlags: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor
           x: edges.grip; y: parent.height - edges.grip; width: parent.width - 2 * edges.grip; height: edges.grip }
    Edge { edgeFlags: Qt.TopEdge | Qt.LeftEdge; cursorShape: Qt.SizeFDiagCursor
           x: 0; y: 0; width: edges.grip * 2; height: edges.grip * 2 }
    Edge { edgeFlags: Qt.TopEdge | Qt.RightEdge; cursorShape: Qt.SizeBDiagCursor
           x: parent.width - edges.grip * 2; y: 0; width: edges.grip * 2; height: edges.grip * 2 }
    Edge { edgeFlags: Qt.BottomEdge | Qt.LeftEdge; cursorShape: Qt.SizeBDiagCursor
           x: 0; y: parent.height - edges.grip * 2; width: edges.grip * 2; height: edges.grip * 2 }
    Edge { edgeFlags: Qt.BottomEdge | Qt.RightEdge; cursorShape: Qt.SizeFDiagCursor
           x: parent.width - edges.grip * 2; y: parent.height - edges.grip * 2; width: edges.grip * 2; height: edges.grip * 2 }
}
