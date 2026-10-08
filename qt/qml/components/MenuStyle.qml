pragma Singleton
import QtQuick 2.15

// Shared metrics and colours for the app's pop-up menus (AppMenu,
// ChoiceMenu), so they stay the same size as each other.
QtObject {
    readonly property int rowHeight: 28
    readonly property int iconSize: 15
    readonly property int fontSize: 13
    readonly property int smallFontSize: 11
    readonly property int headerFontSize: 10
    readonly property int padding: 4
    readonly property int radius: 9
    readonly property int rowRadius: 6
    readonly property int sideInset: 10       // row content inset from the card edge

    readonly property color background: "#1d1d1f"
    readonly property color border: Qt.rgba(1, 1, 1, 0.08)
    readonly property color highlight: isMacOS ? MacColors.selectedContentBackground : "#0a7cff"
    readonly property color danger: isMacOS ? MacColors.selectedContentBackground : "#d9363e"
    readonly property color dangerText: isMacOS ? MacColors.label : "#ff6961"
    readonly property color separator: isMacOS ? MacColors.separator : Qt.rgba(1, 1, 1, 0.07)
    readonly property color text: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.9)
    readonly property color dimText: isMacOS ? MacColors.secondaryLabel : Qt.rgba(1, 1, 1, 0.35)
    readonly property color iconColor: isMacOS ? MacColors.label : Qt.rgba(1, 1, 1, 0.65)
}
