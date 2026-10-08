import QtQuick 2.15
import QtQuick.Controls 2.15

// Compact on/off switch: accent pill when on, grey when off.
Switch {
    id: sw
    padding: 0
    implicitWidth: 40
    implicitHeight: 24

    indicator: Rectangle {
        width: 40
        height: 24
        radius: 12
        color: isMacOS ? (sw.checked ? MacColors.switchOn : Qt.rgba(1, 1, 1, 0.1)) : sw.checked ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.18)
        opacity: sw.enabled ? 1.0 : 0.5
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            x: sw.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 10
            color: isMacOS ? "#cccccc" : "white"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Item {}
}
