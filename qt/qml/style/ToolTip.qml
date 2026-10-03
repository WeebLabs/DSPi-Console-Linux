import QtQuick 2.15
import QtQuick.Templates 2.15 as T

// App-wide tooltip (the custom style only overrides this control; the rest
// falls back to Fusion): a small dark card in the menu style, 12 px text,
// wrapping past 280 px, fading in.
T.ToolTip {
    id: control

    x: parent ? (parent.width - implicitWidth) / 2 : 0
    y: -implicitHeight - 4

    readonly property int maxTextWidth: 280
    implicitWidth: Math.min(metrics.advanceWidth + 1, maxTextWidth) + leftPadding + rightPadding
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding

    margins: 6
    leftPadding: 8
    rightPadding: 8
    topPadding: 4
    bottomPadding: 5
    font.pixelSize: 12

    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    TextMetrics { id: metrics; font: control.font; text: control.text }

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 100; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 80 } }

    contentItem: Text {
        text: control.text
        font: control.font
        wrapMode: Text.Wrap
        color: Qt.rgba(1, 1, 1, 0.9)
    }

    background: Item {
        // Soft layered shadow, as on menus
        Repeater {
            model: 3
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(index + 1)
                anchors.topMargin: -(index + 1) + 2
                radius: 6 + index + 1
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.16 - index * 0.04)
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 6
            color: "#2a2a2c"
            border.color: Qt.rgba(1, 1, 1, 0.1)
        }
    }
}
