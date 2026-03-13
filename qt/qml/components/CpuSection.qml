import QtQuick 2.15

Item {
    id: cpuRoot
    height: 40

    property int cpu0: 0
    property int cpu1: 0

    Row {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 0

        // Core 0
        Row {
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: "C0:"
                font.pixelSize: 9
                color: Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: 40
                height: 6
                radius: 2
                color: Qt.rgba(0.5, 0.5, 0.5, 0.3)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width * (cpu0 / 100.0)
                    height: parent.height
                    radius: 2
                    color: cpu0 > 90 ? "#f44336" : "#0078d4"
                }
            }

            Text {
                text: cpu0 + "%"
                font.pixelSize: 9
                font.family: "Menlo"
                color: Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
                width: 30
            }
        }

        Item { width: 1; height: 1 }

        // Core 1
        Row {
            spacing: 4
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: "C1:"
                font.pixelSize: 9
                color: Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: 40
                height: 6
                radius: 2
                color: Qt.rgba(0.5, 0.5, 0.5, 0.3)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width * (cpu1 / 100.0)
                    height: parent.height
                    radius: 2
                    color: cpu1 > 90 ? "#f44336" : "#0078d4"
                }
            }

            Text {
                text: cpu1 + "%"
                font.pixelSize: 9
                font.family: "Menlo"
                color: Qt.rgba(1, 1, 1, 0.5)
                anchors.verticalCenter: parent.verticalCenter
                width: 30
            }
        }
    }
}
