import QtQuick 2.15
import QtQuick.Controls 2.15

Slider {
    id: sliderRoot
    height: 12

    property color trackColor: Qt.rgba(0.5, 0.5, 0.5, 0.2)
    property color activeColor: "#0078d4"

    background: Rectangle {
        x: sliderRoot.leftPadding
        y: sliderRoot.topPadding + sliderRoot.availableHeight / 2 - height / 2
        width: sliderRoot.availableWidth
        height: 3
        radius: 2
        color: trackColor

        Rectangle {
            width: sliderRoot.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: sliderRoot.enabled ? activeColor : Qt.rgba(0.5, 0.5, 0.5, 0.3)
        }
    }

    handle: Rectangle {
        x: sliderRoot.leftPadding + sliderRoot.visualPosition * (sliderRoot.availableWidth - width)
        y: sliderRoot.topPadding + sliderRoot.availableHeight / 2 - height / 2
        width: 12
        height: 12
        radius: 6
        color: sliderRoot.enabled ? "white" : Qt.rgba(0.7, 0.7, 0.7, 1.0)
    }
}
