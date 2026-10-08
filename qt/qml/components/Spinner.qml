import QtQuick 2.15

// Work in progress: an arc turning while the app or the hardware is busy.
Icon {
    id: spin
    name: "spinner"
    size: 24
    color: isMacOS ? MacColors.secondaryLabel : "#3a96ff"
    RotationAnimator on rotation {
        from: 0; to: 360
        duration: 900
        loops: Animation.Infinite
        running: spin.visible
    }
}
