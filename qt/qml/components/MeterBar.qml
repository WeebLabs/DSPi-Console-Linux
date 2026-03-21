import QtQuick 2.15
import DSPi 1.0

MeterItem {
    id: meterBar

    property real targetLevel: 0
    property alias clipping: meterBar.clipping
    property alias barColor: meterBar.barColor

    level: smoothedLevel

    property real smoothedLevel: 0

    Behavior on smoothedLevel {
        NumberAnimation {
            duration: 60
            easing.type: Easing.Linear
        }
    }

    onTargetLevelChanged: smoothedLevel = targetLevel
}
