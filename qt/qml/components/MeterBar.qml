import QtQuick 2.15
import DSPi 1.0

MeterItem {
    id: meterBar

    property alias level: meterBar.level
    property alias clipping: meterBar.clipping
    property alias barColor: meterBar.barColor
}
