import QtQuick 2.15
import QtQuick.Window 2.15
import "components"

// Progress while the AutoEQ database is rebuilt from GitHub. Closing it
// cancels the rebuild and leaves the database as it was.
AppWindow {
    id: win
    title: "Rebuilding AutoEQ Database"
    visible: false
    width: 380
    height: 140 + titlebarHeight
    minimumWidth: width
    maximumWidth: width
    minimumHeight: height
    maximumHeight: height

    onVisibleChanged: if (!visible && autoeq.rebuilding) autoeq.cancelRebuild()

    Column {
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 10
        Row {
            spacing: 10
            Spinner { visible: autoeq.rebuilding; size: 18; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: autoeq.rebuildStatus || "Connecting to GitHub..."
                font.pixelSize: 13
                color: "white"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Rectangle {
            width: parent.width
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.14)
            Rectangle { width: parent.width * autoeq.rebuildProgress; height: parent.height; radius: 2; color: "#0a7cff" }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Every profile is downloaded from the AutoEQ project. This can take several minutes."
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }
    AppButton {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        text: "Cancel"
        onClicked: win.close()
    }
}
