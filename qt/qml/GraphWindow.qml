import QtQuick 2.15
import QtQuick.Controls 2.15
import "components"

// Pop Out Graph: the response graph in its own window. It shows what the
// main window shows, or (Follow Channel Selection off, in its gear's Graph
// Setup) its own channels, picked with the pills under it.
AppWindow {
    id: win
    title: "Filter Response"
    visible: false
    width: 800
    height: 400 + titlebarHeight
    minimumWidth: 500
    minimumHeight: 250 + titlebarHeight

    // Built while open only, so a closed window costs nothing
    Loader {
        anchors.fill: parent
        active: win.visible
        sourceComponent: FilterResponseView { popOut: true }
    }
}
