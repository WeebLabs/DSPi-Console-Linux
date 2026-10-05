import QtQuick 2.15

// A pulsing dot while the device works (listening for a remote, applying).
Rectangle {
    width: 8
    height: 8
    radius: 4
    color: "#0a7cff"
    SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: visible
        NumberAnimation { from: 1; to: 0.25; duration: 500; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.25; to: 1; duration: 500; easing.type: Easing.InOutQuad }
    }
}
