import QtQuick 2.15
import "../"
import "../../components"

SettingsPage {
    title: "About"

    // App identity
    Rectangle {
        width: parent.width
        height: 116
        radius: isMacOS ? 5 : 12
        color: isMacOS ? "#2b2b2b" : Qt.rgba(1, 1, 1, 0.045)
        border.color: isMacOS ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.07)

        Rectangle {
            id: appTile
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 72; height: 72; radius: 18
            gradient: Gradient {
                GradientStop { position: 0; color: "#3a96ff" }
                GradientStop { position: 1; color: "#6b4cf0" }
            }
            Icon { anchors.centerIn: parent; name: "sliders"; size: 38; color: "white" }
        }
        Column {
            anchors.left: appTile.right
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text { text: "DSPi Console"; font.pixelSize: 22; font.weight: Font.Bold; color: isMacOS ? MacColors.label : "white" }
            Text { text: "Version " + Qt.application.version + " for Linux"; font.pixelSize: 13; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.6) }
            Text { text: "by Weeb Labs"; font.pixelSize: 13; color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.45) }
        }
    }

    SettingsSection {
        title: "Links"
        Repeater {
            model: [
                { title: "YouTube", detail: "Builds, demos and how-tos", url: "https://youtube.com/weeblabs" },
                { title: "GitHub", detail: "DSPi firmware and the Consoles", url: "https://github.com/weeblabs" },
                { title: "Discord", detail: "Help and discussion", url: "https://discord.gg/RCyqxAQ5xS" },
                { title: "Patreon", detail: "Support development", url: "https://patreon.com/weeblabs" },
                { title: "Ko-fi", detail: "Buy a coffee", url: "https://ko-fi.com/weeblabs" }
            ]
            SettingsRow {
                title: modelData.title
                titleColor: isMacOS ? Qt.rgba(0.72, 0.72, 0.72, 1) : "white"
                detail: modelData.detail
                clickable: true
                onActivated: Qt.openUrlExternally(modelData.url)
                Icon { name: "external"; size: 16; color: Qt.rgba(1, 1, 1, 0.5) }
            }
        }
    }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        color: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.5)
        text: "DSPi Firmware and Console are free, open-source software developed in spare time. "
            + "Contributions of any kind - code, feedback, funding, or otherwise - are always immensely appreciated."
    }
}
