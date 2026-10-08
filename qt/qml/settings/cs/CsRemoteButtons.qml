import QtQuick 2.15
import "../../components"

// The IR receiver's learned remote buttons: each a small card with its code,
// a Learn / Re-learn button and, open, what the button does. Edits are
// applied by the receiver card's Apply.
Column {
    id: rb
    property var cs
    property var host                // CsControlsView
    property bool receiverLive: false
    width: parent ? parent.width : 400

    CsRow {
        title: "Remote Buttons"
        detail: "Learn buttons on any remote and bind each to a function."
        Text {
            text: rb.host.visibleSubs.length + "/" + rb.cs.irCount
            font.pixelSize: 12
            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
        }
    }
    CsNote {
        text: rb.receiverLive ? "" : "Apply the receiver above before learning remote buttons."
    }

    Repeater {
        model: rb.host.visibleSubs
        Item {
            id: sub
            readonly property int k: modelData
            readonly property var c: rb.host.irDrafts[k]
            readonly property bool learning: rb.host.learningSub === k
            readonly property bool open: rb.host.expandedSubs[k] === true
            readonly property var msg: rb.host.subMessages[k]
            width: rb.width
            height: box.height + 8

            Rectangle {
                id: box
                x: 14
                y: 4
                width: parent.width - 28
                height: inner.height
                radius: 8
                color: isMacOS ? MacColors.opacity(MacColors.secondaryLabel, 0.06) : Qt.rgba(1, 1, 1, 0.04)
                border.color: isMacOS ? "transparent" : Qt.rgba(1, 1, 1, 0.06)

                Column {
                    id: inner
                    width: parent.width

                    Item {
                        width: parent.width
                        height: 40
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rb.host.setMap("expandedSubs", sub.k, sub.open ? undefined : true)
                        }
                        Icon {
                            id: chev
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chev-right"
                            size: 12
                            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                            rotation: sub.open ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        // The learned code, or a placeholder
                        Row {
                            id: chip
                            anchors.left: chev.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Icon {
                                name: rb.cs.irConfigured(sub.c) ? "check" : "minus-circle"
                                size: 13
                                color: isMacOS ? (rb.cs.irConfigured(sub.c) ? MacColors.green : MacColors.secondaryLabel) : rb.cs.irConfigured(sub.c) ? "#32d74b" : Qt.rgba(1, 1, 1, 0.4)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: rb.cs.irConfigured(sub.c) ? rb.cs.irProtocolName(sub.c.protocol) + " 0x" + rb.cs.hex(sub.c.code, 8) : "Not learned"
                                font.pixelSize: 12
                                font.family: rb.cs.irConfigured(sub.c) ? "monospace" : Qt.application.font.family
                                color: isMacOS ? (rb.cs.irConfigured(sub.c) ? MacColors.label : MacColors.secondaryLabel) : rb.cs.irConfigured(sub.c) ? "white" : Qt.rgba(1, 1, 1, 0.5)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Text {
                            anchors.left: chip.right
                            anchors.leftMargin: 10
                            anchors.right: actions.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !sub.open && rb.cs.irConfigured(sub.c)
                            elide: Text.ElideRight
                            text: rb.cs.irVerbPhrase(sub.c)
                            font.pixelSize: 11
                            color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
                        }
                        Row {
                            id: actions
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            CsBusyDot { visible: sub.learning; anchors.verticalCenter: parent.verticalCenter }
                            CsButton {
                                visible: sub.learning
                                text: "Cancel"
                                onClicked: rb.host.cancelLearn()
                            }
                            CsButton {
                                visible: !sub.learning
                                text: rb.cs.irConfigured(sub.c) ? "Re-learn" : "Learn Button"
                                enabled: rb.receiverLive && rb.cs.connected && rb.host.learningSub < 0
                                onClicked: rb.host.startLearn(sub.k)
                            }
                            CsButton {
                                bare: true
                                icon: "trash"
                                tip: "Remove this remote button"
                                enabled: !sub.learning
                                onClicked: rb.host.removeIrCommand(sub.k)
                            }
                        }
                    }
                    CsNote {
                        text: sub.learning ? rb.host.learnMessage : ""
                    }
                    Loader {
                        width: parent.width
                        active: sub.open
                        visible: active
                        sourceComponent: CsRecordEditor {
                            cs: rb.cs
                            mode: "ir"
                            rec: sub.c
                            onEdited: rb.host.setIrDraft(sub.k, rec)
                        }
                    }
                    CsNote {
                        visible: sub.open && !sub.learning && !!sub.msg
                        warning: !!sub.msg && sub.msg.error
                        text: sub.msg ? sub.msg.text : ""
                    }
                    Item { width: 1; height: sub.open ? 4 : 0 }
                }
            }
        }
    }
    Item { width: 1; height: 6 }
}
