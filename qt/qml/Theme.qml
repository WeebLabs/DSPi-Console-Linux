pragma Singleton
import QtQuick 2.15

QtObject {
    // Window
    readonly property color windowBg: "#1e1e1e"
    readonly property color baseBg: "#2a2a2a"
    readonly property color controlBg: "#353535"
    readonly property color sidebarBg: "#252525"

    // Text
    readonly property color textPrimary: "#ffffff"
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.7)
    readonly property color textDisabled: Qt.rgba(1, 1, 1, 0.4)

    // Accent
    readonly property color accent: "#0078d4"
    readonly property color accentLight: "#3a96dd"

    // Borders
    readonly property color border: Qt.rgba(1, 1, 1, 0.1)
    readonly property color borderSubtle: Qt.rgba(1, 1, 1, 0.06)

    // Status
    readonly property color success: "#4caf50"
    readonly property color danger: "#f44336"
    readonly property color warning: "#ff9800"

    // Bypass active
    readonly property color bypassBg: Qt.rgba(0.4, 0.12, 0.12, 1.0)

    // Channel colors
    readonly property var channelColors: [
        "#4A8FE3", // 0: Master L
        "#F57373", // 1: Master R
        "#45C2A3", // 2: SPDIF 1 L
        "#59D180", // 3: SPDIF 1 R
        "#F0C459", // 4: SPDIF 2 L
        "#F2A64D", // 5: SPDIF 2 R
        "#598CF2", // 6: SPDIF 3 L
        "#8CB3F2", // 7: SPDIF 3 R
        "#D97390", // 8: SPDIF 4 L
        "#F299A6", // 9: SPDIF 4 R
        "#BA87F2"  // 10: PDM
    ]

    // Filter type names
    readonly property var filterTypeNames: [
        "Off", "Peaking", "Low Shelf", "High Shelf", "Low Pass", "High Pass"
    ]

    // Filter type short names
    readonly property var filterTypeShort: [
        "OFF", "PK", "LS", "HS", "LP", "HP"
    ]

    // Font helpers
    readonly property font monoFont: Qt.font({family: "Menlo", pixelSize: 12})
    readonly property font labelFont: Qt.font({family: ".AppleSystemUIFont", pixelSize: 10, weight: Font.Bold})
    readonly property font captionFont: Qt.font({family: ".AppleSystemUIFont", pixelSize: 10})
    readonly property font bodyFont: Qt.font({family: ".AppleSystemUIFont", pixelSize: 13})
    readonly property font headlineFont: Qt.font({family: ".AppleSystemUIFont", pixelSize: 14, weight: Font.DemiBold})

    // Spacing
    readonly property int spacingSmall: 4
    readonly property int spacingMedium: 8
    readonly property int spacingLarge: 16

    // Sizes
    readonly property int sidebarWidth: 240
    readonly property int graphHeight: 250
    readonly property int channelRowHeight: 28
    readonly property int filterRowHeight: 24
    readonly property int channelSettingsHeight: 60
}
