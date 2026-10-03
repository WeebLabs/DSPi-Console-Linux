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
    signal menuRequested(Item anchorItem)

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
        signal clicked()
        width: 28
        height: 28
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.centerIn: parent
            width: 24; height: 24; radius: 12
            color: bbMouse.containsMouse ? (bb.danger ? "#e0454a" : Qt.rgba(1, 1, 1, 0.12))
                 : bb.lit ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
        }
        Icon {
            anchors.centerIn: parent
            name: bb.icon
            size: 16
            color: bbMouse.containsMouse && bb.danger ? "white"
                 : bbMouse.containsMouse || bb.lit ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(1, 1, 1, 0.65)
        }
        MouseArea {
            id: bbMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: bb.clicked()
        }
    }

    BarButton {
        id: menuBtn
        x: 10
        icon: "menu"
        onClicked: bar.menuRequested(menuBtn)
        ToolTip.visible: false
    }

    Text {
        // Centred over the content area, like the KDE title
        x: bar.sidebarWidth + (bar.width - bar.sidebarWidth - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: bar.window ? bar.window.title : ""
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: bar.window && bar.window.active ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.45)
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        BarButton { icon: "win-min"; onClicked: bar.window.showMinimized() }
        BarButton { icon: bar.maximized ? "win-restore" : "win-max"; onClicked: bar.toggleMaximized() }
        BarButton { icon: "win-close"; danger: true; onClicked: bar.window.close() }
    }
}
