import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: filterRowRoot
    height: 24
    color: bandIndex % 2 === 0 ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

    property int channelId: 0
    property int bandIndex: 0
    property int filterType: 0
    property real filterFreq: 1000
    property real filterGain: 0
    property real filterQ: 0.707

    readonly property var typeNames: ["Off", "Peaking", "Low Shelf", "High Shelf", "Low Pass", "High Pass"]
    readonly property bool isActive: filterType !== 0

    signal filterChanged(int type, real freq, real gain, real q)

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 0

        // Band index
        Text {
            width: 24
            text: (bandIndex + 1).toString()
            font.pixelSize: 11
            font.family: root.monoFont
            color: Qt.rgba(1, 1, 1, 0.5)
            horizontalAlignment: Text.AlignCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        // Type combo
        ComboBox {
            id: typeCombo
            width: 100
            height: 22
            model: typeNames
            currentIndex: filterType
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter

            onActivated: {
                filterRowRoot.filterChanged(index, filterFreq, filterGain, filterQ)
            }

            background: Rectangle {
                color: "transparent"
                border.color: typeCombo.hovered ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                radius: 3
            }

            contentItem: Text {
                text: typeCombo.displayText
                font: typeCombo.font
                color: isActive ? "white" : Qt.rgba(1, 1, 1, 0.4)
                verticalAlignment: Text.AlignVCenter
                leftPadding: 4
            }

            indicator: Item {}

            popup: Popup {
                y: typeCombo.height
                width: typeCombo.width
                implicitHeight: contentItem.implicitHeight + 2
                padding: 1

                background: Rectangle {
                    color: "#353535"
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    radius: 6
                }

                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: typeCombo.popup.visible ? typeCombo.delegateModel : null
                    boundsBehavior: Flickable.StopAtBounds
                }
            }

            delegate: ItemDelegate {
                width: typeCombo.width
                height: 22
                contentItem: Text {
                    text: modelData
                    font.pixelSize: 11
                    color: highlighted ? "white" : Qt.rgba(1, 1, 1, 0.8)
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 4
                }
                highlighted: typeCombo.highlightedIndex === index
                background: Rectangle {
                    color: highlighted ? "#0078d4" : "transparent"
                    radius: 3
                }
            }
        }

        // Frequency
        Item {
            width: 104
            height: parent.height
            visible: isActive
            anchors.verticalCenter: parent.verticalCenter

            TextField {
                id: freqField
                width: 80
                height: 20
                anchors.centerIn: parent
                font.pixelSize: 11
                font.family: root.monoFont
                color: activeFocus ? "#0078d4" : "white"
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                padding: 2

                background: Rectangle {
                    color: "transparent"
                    border.color: freqField.activeFocus ? "#0078d4" : "transparent"
                    radius: 2
                }

                text: filterFreq.toFixed(1)

                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) {
                        v = Math.max(10, Math.min(20000, v))
                        filterRowRoot.filterChanged(filterType, v, filterGain, filterQ)
                    }
                    text = filterFreq.toFixed(1)
                }

                Connections {
                    target: filterRowRoot
                    function onFilterFreqChanged() {
                        if (!freqField.activeFocus)
                            freqField.text = filterRowRoot.filterFreq.toFixed(1)
                    }
                }
            }
        }

        // Gain
        Item {
            width: 84
            height: parent.height
            visible: isActive
            anchors.verticalCenter: parent.verticalCenter

            TextField {
                id: gainField
                width: 60
                height: 20
                anchors.centerIn: parent
                font.pixelSize: 11
                font.family: root.monoFont
                color: activeFocus ? "#0078d4" : "white"
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                padding: 2

                background: Rectangle {
                    color: "transparent"
                    border.color: gainField.activeFocus ? "#0078d4" : "transparent"
                    radius: 2
                }

                text: filterGain.toFixed(1)

                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) {
                        v = Math.max(-30, Math.min(30, v))
                        filterRowRoot.filterChanged(filterType, filterFreq, v, filterQ)
                    }
                    text = filterGain.toFixed(1)
                }

                Connections {
                    target: filterRowRoot
                    function onFilterGainChanged() {
                        if (!gainField.activeFocus)
                            gainField.text = filterRowRoot.filterGain.toFixed(1)
                    }
                }
            }
        }

        // Q/Width
        Item {
            width: 74
            height: parent.height
            visible: isActive
            anchors.verticalCenter: parent.verticalCenter

            TextField {
                id: qField
                width: 50
                height: 20
                anchors.centerIn: parent
                font.pixelSize: 11
                font.family: root.monoFont
                color: activeFocus ? "#0078d4" : "white"
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                padding: 2

                background: Rectangle {
                    color: "transparent"
                    border.color: qField.activeFocus ? "#0078d4" : "transparent"
                    radius: 2
                }

                text: filterQ.toFixed(3)

                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) {
                        v = Math.max(0.01, Math.min(100, v))
                        filterRowRoot.filterChanged(filterType, filterFreq, filterGain, v)
                    }
                    text = filterQ.toFixed(3)
                }

                Connections {
                    target: filterRowRoot
                    function onFilterQChanged() {
                        if (!qField.activeFocus)
                            qField.text = filterRowRoot.filterQ.toFixed(3)
                    }
                }
            }
        }

        // "Filter Disabled" label when inactive
        Text {
            visible: !isActive
            text: "Filter Disabled"
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.3)
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 16
        }
    }
}
