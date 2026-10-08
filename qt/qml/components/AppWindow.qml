import QtQuick 2.15
import QtQuick.Window 2.15

// Base for the app's secondary windows (tool windows, Matrix Mixer,
// Settings). On Linux it draws the shared titlebar, resize edges and outline,
// and asks WindowEffects for a shadow (and a blurred strip of `blurWidth`
// for a translucent sidebar). Declare the window's content as children.
Window {
    id: appWindow
    default property alias content: contentArea.data

    // macOS: the width of a sidebar under a unified, transparent titlebar
    // (Settings). The window then gets the sidebar material behind that strip
    // and a compact toolbar-height titlebar over its content (MacSystemColors.mm).
    property int macUnifiedSidebar: 0
    // Titlebar height on Linux (macOS keeps its native titlebar, unless unified)
    readonly property int titlebarHeight: isMacOS ? (macUnifiedSidebar > 0 ? 38 : 0) : 30
    // Content starts under the titlebar (Settings: sidebar runs to the top)
    property bool contentUnderTitlebar: false
    // Width of a translucent, blurred sidebar strip on the left (0 = none)
    property int blurWidth: 0
    // Show minimise / maximise next to close
    property bool showMinMax: false
    // Fixed-size windows (minimum == maximum) get no resize edges
    readonly property bool resizable: minimumWidth !== maximumWidth || minimumHeight !== maximumHeight
    // Height the content would like (titlebar excluded); when set, the
    // window opens tall enough to show all of it (at most 960 px, and never
    // taller than the screen allows)
    property real fitHeight: 0
    // The titlebar, for Back/Forward and title overrides
    property alias titleBar: bar

    color: isMacOS ? (macUnifiedSidebar > 0 ? "transparent" : MacColors.windowBackground) : "#1e1e20"
    flags: isMacOS ? (Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint)
                   : (Qt.Window | Qt.FramelessWindowHint)

    Component.onCompleted: if (!isMacOS) windowEffects.decorate(appWindow, blurWidth, true)

    // Fit once, on first show; later opens keep the user's size
    property bool fitted: false
    function fittedHeight() {
        var avail = Screen.desktopAvailableHeight > 0 ? Screen.desktopAvailableHeight : 900
        return Math.round(Math.max(minimumHeight, Math.min(fitHeight + titlebarHeight, avail - 80, 960)))
    }
    function fitToContent() {
        if (fitHeight <= 0) return
        height = fittedHeight()
    }
    onVisibleChanged: if (visible && !fitted) { fitted = true; fitToContent() }

    // Refit smoothly once the content's height settles (e.g. after switching
    // a window between views): call refitAnimated() before the change
    property bool refitPending: false
    function refitAnimated() {
        refitPending = true
        refitSettle.restart()
    }
    onFitHeightChanged: if (refitPending) refitSettle.restart()
    Timer {
        id: refitSettle
        interval: 30   // the new layout lands over a frame or two
        onTriggered: {
            appWindow.refitPending = false
            if (appWindow.fitHeight <= 0 || !appWindow.visible) return
            var target = appWindow.fittedHeight()
            if (Math.abs(target - appWindow.height) < 1) return
            refitAnim.stop()
            refitAnim.from = appWindow.height
            refitAnim.to = target
            refitAnim.start()
        }
    }
    NumberAnimation {
        id: refitAnim
        target: appWindow
        property: "height"
        duration: 240
        easing.type: Easing.InOutCubic
    }

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

    // macOS, unified windows: the edge AppKit draws on an opaque window and
    // leaves off a transparent one (measured from the native Settings): a
    // 0.5 pt dark outline, then a 1 pt light rim, brighter along the top
    Loader {
        active: isMacOS && appWindow.macUnifiedSidebar > 0
        visible: appWindow.visibility !== Window.FullScreen
        anchors.fill: parent
        z: 1000
        sourceComponent: Item {
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.color: Qt.rgba(0, 0, 0, 0.9)
                border.width: 0.5
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 0.5
                radius: 9.5
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.2)
                border.width: 1
            }
            // The top rim, per device pixel (measured: white at 0.36, then 0.29)
            Rectangle {
                x: 10; y: 0.5
                width: parent.width - 20
                height: 0.5
                color: Qt.rgba(1, 1, 1, 0.31)
            }
            Rectangle {
                x: 10; y: 1
                width: parent.width - 20
                height: 0.5
                color: Qt.rgba(1, 1, 1, 0.11)
            }
            // Around the two top corners the brighter rim fades into the sides
            // over the first 8 pt (measured): the rim again, in bands
            Repeater {
                model: [ { y: 0, h: 5, a: 0.2 }, { y: 5, h: 2, a: 0.1 }, { y: 7, h: 2, a: 0.05 } ]
                Item {
                    id: band
                    readonly property var spec: modelData
                    anchors.fill: parent
                    Repeater {
                        model: 2      // left and right corner
                        Item {
                            x: index === 0 ? 0 : parent.width - 10
                            y: band.spec.y
                            width: 10
                            height: band.spec.h
                            clip: true
                            Rectangle {
                                x: index === 0 ? 0.5 : -(parent.parent.width - 10) + 0.5
                                y: 0.5 - band.spec.y
                                width: parent.parent.width - 1
                                height: parent.parent.height - 1
                                radius: 9.5
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, band.spec.a)
                                border.width: 1
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: !isMacOS && appWindow.visibility !== Window.Maximized
        anchors.fill: parent
        z: 1000
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
}
