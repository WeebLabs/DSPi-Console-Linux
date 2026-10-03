import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

// Client-side titlebar (Linux): menu button over the sidebar, centred title,
// minimise / maximise / close. Moving and resizing go through the window
// manager (startSystemMove / startSystemResize), so snapping still works.
Item {
    id: bar
    property var window
    property int sidebarWidth: 260
    property bool showMenuButton: true
    property bool showMinMax: true
    property string titleText: window ? window.title : ""
    // Back / Forward arrows just right of the sidebar (Settings)
    property bool showNav: false
    property bool canGoBack: false
    property bool canGoForward: false
    signal menuRequested(Item anchorItem)
    signal goBack()
    signal goForward()

    readonly property bool maximized: window && window.visibility === Window.Maximized

    function toggleMaximized() {
        if (maximized) window.showNormal()
        else window.showMaximized()
    }

    // Drag to move, double-click to maximise / restore
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: bar.window.startSystemMove()
        onDoubleClicked: bar.toggleMaximized()
    }

    component BarButton: Item {
        id: bb
        property string icon: ""
        property bool danger: false
        property bool lit: false
        property bool active: true
        signal clicked()
        opacity: active ? 1.0 : 0.35
        width: 24
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.centerIn: parent
            width: 22; height: 22; radius: 11
            color: bbMouse.containsMouse ? (bb.danger ? "#e0454a" : Qt.rgba(1, 1, 1, 0.12))
                 : bb.lit ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
        }
        Icon {
            anchors.centerIn: parent
            name: bb.icon
            size: 14
            color: bbMouse.containsMouse && bb.danger ? "white"
                 : bbMouse.containsMouse || bb.lit ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(1, 1, 1, 0.65)
        }
        MouseArea {
            id: bbMouse
            anchors.fill: parent
            hoverEnabled: bb.active
            enabled: bb.active
            onClicked: bb.clicked()
        }
    }

    BarButton {
        id: menuBtn
        visible: bar.showMenuButton
        x: 10
        icon: "menu"
        onClicked: bar.menuRequested(menuBtn)
        ToolTip.visible: false
    }

    Row {
        visible: bar.showNav
        x: bar.sidebarWidth + 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        BarButton { icon: "chev-left"; active: bar.canGoBack; onClicked: bar.goBack() }
        BarButton { icon: "chev-right"; active: bar.canGoForward; onClicked: bar.goForward() }
    }

    Text {
        // Centred over the content area, like the KDE title
        x: bar.sidebarWidth + (bar.width - bar.sidebarWidth - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: bar.titleText
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: bar.window && bar.window.active ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.45)
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        BarButton { visible: bar.showMinMax; icon: "win-min"; onClicked: bar.window.showMinimized() }
        BarButton { visible: bar.showMinMax; icon: bar.maximized ? "win-restore" : "win-max"; onClicked: bar.toggleMaximized() }
        BarButton { icon: "win-close"; danger: true; onClicked: bar.window.close() }
    }
}
