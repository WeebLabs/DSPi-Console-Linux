import QtQuick 2.15
import QtQuick.Controls 2.15

// Compact on/off switch: accent pill when on, grey when off.
Switch {
    id: sw
    // macOS: the 26 x 15 pt switch a grouped Form row shows
    property bool mini: false
    readonly property bool macMini: isMacOS && mini
    padding: 0
    implicitWidth: macMini ? 26 : 40
    implicitHeight: macMini ? 15 : 24

    indicator: Rectangle {
        width: sw.macMini ? 26 : 40
        height: sw.macMini ? 15 : 24
        radius: height / 2
        color: isMacOS ? (sw.checked ? MacColors.switchOn : Qt.rgba(1, 1, 1, 0.1)) : sw.checked ? "#0a7cff" : Qt.rgba(1, 1, 1, 0.18)
        opacity: sw.enabled ? 1.0 : 0.5
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            x: sw.checked ? parent.width - width - (sw.macMini ? 1 : 2) : (sw.macMini ? 1 : 2)
            anchors.verticalCenter: parent.verticalCenter
            width: sw.macMini ? 13 : 20
            height: sw.macMini ? 13 : 20
            radius: width / 2
            color: isMacOS ? "#cccccc" : "white"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Item {}
}
