import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import "components"

// Interrupt Monitor: the device's notifications as they arrive, one decoded
// line each (parameter changes named by field, with their source), after
// the macOS Console. The log keeps the last 2000 even while the window is
// closed; Pause stops new lines (they are skipped, not held back).
AppWindow {
    id: win
    title: "Interrupt Monitor"
    visible: false
    width: 900
    height: 480 + titlebarHeight
    minimumWidth: 720
    minimumHeight: 320 + titlebarHeight

    readonly property bool shown: visible && visibility !== Window.Minimized
    onShownChanged: monitor.watching = shown
    readonly property bool listening: bridge.connected && bridge.compat === 1     // COMPAT_OK

    component ToolButton: Rectangle {
        id: tb
        property string text: ""
        property string icon: ""
        property string tip: ""
        signal clicked()
        implicitWidth: tbRow.width + 20
        height: 26
        radius: 8
        color: tbMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : tbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Row {
            id: tbRow
            anchors.centerIn: parent
            spacing: 6
            Icon { visible: tb.icon !== ""; name: tb.icon; size: 13; color: Qt.rgba(1, 1, 1, 0.8); anchors.verticalCenter: parent.verticalCenter }
            Text { text: tb.text; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: tbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
        ToolTip.visible: tbMouse.containsMouse && tip !== ""
        ToolTip.delay: 600
        ToolTip.text: tip
    }

    Shortcut { sequence: "Ctrl+P"; enabled: win.active; onActivated: monitor.paused = !monitor.paused }
    Shortcut { sequence: "Ctrl+K"; enabled: win.active; onActivated: monitor.clear() }

    // Toolbar
    Item {
        id: toolbar
        width: parent.width
        height: 46
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            spacing: 8
            ToolButton {
                text: monitor.paused ? "Resume" : "Pause"
                icon: monitor.paused ? "play" : "pause"
                tip: (monitor.paused ? "Show new events again" : "Stop showing new events (they are not kept)") + "  (Ctrl+P)"
                onClicked: monitor.paused = !monitor.paused
            }
            ToolButton { text: "Clear"; tip: "Empty the log  (Ctrl+K)"; onClicked: monitor.clear() }
            ToolButton { text: "Copy"; tip: "Copy every line to the clipboard"; onClicked: { clip.text = monitor.allText(); clip.selectAll(); clip.copy() } }
            Item { Layout.fillWidth: true }
            Row {
                spacing: 6
                Rectangle {
                    width: 6; height: 6; radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: !win.listening ? Qt.rgba(1, 1, 1, 0.35) : monitor.paused ? "#ff9f0a" : "#32d74b"
                }
                Text {
                    text: !win.listening ? "Inactive" : monitor.paused ? "Paused" : "Listening"
                    font.pixelSize: 11
                    color: !win.listening ? Qt.rgba(1, 1, 1, 0.5) : monitor.paused ? "#ff9f0a" : "#32d74b"
                }
            }
            Text {
                text: monitor.count + (monitor.count === 1 ? " event" : " events")
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.5)
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
    }

    // Hidden helper for the clipboard
    TextEdit { id: clip; visible: false }

    ListView {
        id: list
        anchors.top: toolbar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: monitor
        boundsBehavior: Flickable.StopAtBounds
        topMargin: 8
        bottomMargin: 8
        ScrollBar.vertical: ScrollBar {}
        // Follow the newest line unless scrolled up to read
        property bool following: true
        onMovementEnded: following = atYEnd
        Connections {
            target: monitor
            function onAppended() { if (list.following && !monitor.paused) list.positionViewAtEnd() }
        }
        onVisibleChanged: if (visible) positionViewAtEnd()

        delegate: Row {
            x: 10
            spacing: 14
            height: 17
            Text {
                text: model.time
                font.family: "monospace"
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.45)
            }
            TextEdit {
                text: model.text
                readOnly: true
                selectByMouse: true
                font.family: "monospace"
                font.pixelSize: 11
                color: Qt.rgba(1, 1, 1, 0.88)
                selectionColor: "#0a7cff"
            }
        }

        Text {
            anchors.centerIn: parent
            visible: monitor.count === 0
            text: win.listening ? "Waiting for the device to report a change" : "Connect a DSPi to see its notifications"
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.4)
        }
    }
}
