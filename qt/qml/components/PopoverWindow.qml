import QtQuick 2.15
import QtQuick.Window 2.15

// A popover in a window of its own, so it can reach past the edge of the
// window it opens from, as macOS popovers do: the dark rounded card with a
// soft shadow, opened centred under an anchor (openBelow / toggleBelow),
// with a short fade and scale-in. Esc or a click outside closes it (on
// Wayland the compositor ends the popup; elsewhere a catcher in the parent
// window takes the click). Declare it inside an Item of the parent window,
// so it becomes that window's transient child; put the content in it.
Window {
    id: pw
    default property alias content: card.data
    property real contentWidth: 280
    property real contentHeight: 100
    property int radius: 12
    readonly property int shadow: 14          // room around the card for its shadow
    property real closedAt: 0
    signal aboutToOpen()

    flags: Qt.Popup | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    visible: false
    width: contentWidth + 2 * shadow
    height: contentHeight + 2 * shadow

    // Opens centred under the anchor, kept on its screen where we can tell
    function openBelow(anchor) {
        aboutToOpen()
        var g = anchor.mapToGlobal(anchor.width / 2, anchor.height)
        var px = g.x - width / 2, py = g.y + 4 - shadow
        if (Qt.platform.pluginName !== "wayland") {
            var s = anchor.Window.window ? anchor.Window.window.screen : null
            if (s) px = Math.max(s.virtualX, Math.min(px, s.virtualX + s.width - width))
        }
        x = Math.round(px)
        y = Math.round(py)
        show()
        // A Wayland popup takes the keyboard with its grab
        if (Qt.platform.pluginName !== "wayland") requestActivate()
    }

    // The anchor toggles the popover. A press on the anchor while it is open
    // closes it as an outside click before the anchor's click arrives, so a
    // click right after such a close must not reopen it.
    function toggleBelow(anchor) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        openBelow(anchor)
    }

    onVisibleChanged: {
        if (visible) {
            card.opacity = 0
            card.scale = 0.97
            enter.restart()
            blurCard()
        } else {
            closedAt = Date.now()
        }
    }
    // Translucent over a blurred backdrop where the desktop can blur (KDE),
    // solid elsewhere. The surface is new each time it shows, and the window
    // changes size with its content (Graph Setup is taller).
    readonly property bool translucent: windowEffects.blurAvailable
    function blurCard() {
        if (visible && translucent)
            windowEffects.blurBehind(pw, Qt.rect(shadow, shadow, contentWidth, contentHeight), radius)
    }
    // After the window itself has resized (the blur is clipped to the
    // surface it was set on), and again once the new size has reached KWin
    onWidthChanged: { Qt.callLater(blurCard); blurSettle.restart() }
    onHeightChanged: { Qt.callLater(blurCard); blurSettle.restart() }
    Timer { id: blurSettle; interval: 50; onTriggered: pw.blurCard() }

    // A popover that held the focus and lost it was dismissed elsewhere
    onActiveChanged: if (!active && visible && Qt.platform.pluginName !== "wayland") close()

    ParallelAnimation {
        id: enter
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 130; easing.type: Easing.OutCubic }
    }

    Shortcut { sequence: "Esc"; enabled: pw.visible; onActivated: pw.close() }

    // Without a compositor-ended popup, a press elsewhere in the parent
    // window closes it (and goes no further, as with an in-window popup)
    MouseArea {
        parent: pw.transientParent ? pw.transientParent.contentItem : null
        anchors.fill: parent
        z: 100000
        enabled: pw.visible && Qt.platform.pluginName !== "wayland"
        visible: enabled
        onPressed: pw.close()
    }

    Item {
        anchors.fill: parent
        anchors.margins: pw.shadow

        // Soft shadow: layered outlines, darker near the card
        Repeater {
            model: 6
            Rectangle {
                anchors.fill: parent
                // All outside the card (it can be translucent), deeper below
                anchors.margins: -(index + 1) * 2
                anchors.bottomMargin: -(index + 1) * 2 - 2
                radius: pw.radius + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.10 - index * 0.015)
                opacity: card.opacity
            }
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: pw.radius
            color: pw.translucent ? Qt.rgba(0.11, 0.11, 0.12, 0.62) : MenuStyle.background
            border.color: MenuStyle.border
            transformOrigin: Item.Top
        }
    }
}
