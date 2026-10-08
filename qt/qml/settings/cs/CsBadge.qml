import QtQuick 2.15
import "../../components"

// A component type's tinted tile with its white glyph (the card's badge).
Rectangle {
    id: badge
    property string icon: ""
    property color tint: "#8354a0"
    property int size: 28
    width: size
    height: size
    radius: Math.round(size * 0.24)
    gradient: Gradient {
        GradientStop { position: 0; color: isMacOS ? Qt.hsla(badge.tint.hslHue, badge.tint.hslSaturation, Math.min(1, badge.tint.hslLightness + 0.145), 1) : Qt.lighter(badge.tint, 1.18) }
        GradientStop { position: 1; color: badge.tint }
    }
    Icon {
        anchors.centerIn: parent
        name: badge.icon
        size: Math.round(badge.size * 0.6)
        color: "white"
    }
}
