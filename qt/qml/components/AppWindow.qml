import QtQuick 2.15
import QtQuick.Window 2.15

// Base for the app's secondary windows (tool windows, Matrix Mixer,
// Settings). On Linux it draws the shared titlebar, resize edges and outline,
// and asks WindowEffects for a shadow (and a blurred strip of `blurWidth`
// for a translucent sidebar). Declare the window's content as children.
Window {
    id: appWindow
    default property alias content: contentArea.data

    // Titlebar height on Linux (macOS keeps its native titlebar)
    readonly property int titlebarHeight: isMacOS ? 0 : 40
    // Content starts under the titlebar (Settings: sidebar runs to the top)
    property bool contentUnderTitlebar: false
    // Width of a translucent, blurred sidebar strip on the left (0 = none)
    property int blurWidth: 0
    // Show minimise / maximise next to close
    property bool showMinMax: false
    // Fixed-size windows (minimum == maximum) get no resize edges
    readonly property bool resizable: minimumWidth !== maximumWidth || minimumHeight !== maximumHeight
    // The titlebar, for Back/Forward and title overrides
    property alias titleBar: bar

    color: "#1e1e20"
    flags: isMacOS ? (Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
                   : (Qt.Window | Qt.FramelessWindowHint)

    Component.onCompleted: if (!isMacOS) windowEffects.decorate(appWindow, blurWidth, true)

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.topMargin: appWindow.contentUnderTitlebar ? 0 : appWindow.titlebarHeight
    }

    WindowTitleBar {
        id: bar
        visible: !isMacOS
        z: 900
        width: parent.width
        height: appWindow.titlebarHeight
        window: appWindow
        sidebarWidth: appWindow.blurWidth
        showMenuButton: false
        showMinMax: appWindow.showMinMax
    }

    WindowResizeEdges {
        visible: !isMacOS && appWindow.resizable && appWindow.visibility !== Window.Maximized
        window: appWindow
        z: 950
    }

    Rectangle {
        visible: !isMacOS && appWindow.visibility !== Window.Maximized
        anchors.fill: parent
        z: 1000
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
}
