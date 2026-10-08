import QtQuick 2.15
import QtQuick.Controls 2.15

// Thin-track slider with a round knob.
Slider {
    id: sl
    property color accent: isMacOS ? MacColors.sliderFill : "#0a7cff"
    implicitHeight: 22
    topPadding: 0
    bottomPadding: 0

    background: Rectangle {
        x: sl.leftPadding
        y: (sl.height - height) / 2
        width: sl.availableWidth
        height: 4
        radius: 2
        color: isMacOS ? (sl.enabled ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)) : Qt.rgba(1, 1, 1, 0.14)
        Rectangle {
            width: sl.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: isMacOS ? (sl.enabled ? sl.accent : MacColors.opacity(sl.accent, 0.5)) : sl.enabled ? sl.accent : Qt.rgba(1, 1, 1, 0.3)
        }
    }
    handle: Rectangle {
        x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
        y: (sl.height - height) / 2
        width: 18
        height: 18
        radius: 9
        color: isMacOS ? (sl.enabled ? Qt.rgba(0.6, 0.6, 0.6, 1) : Qt.rgba(0.408, 0.408, 0.408, 1)) : sl.pressed ? "#e8e8e8" : "white"
        border.color: Qt.rgba(0, 0, 0, 0.25)
    }
}
