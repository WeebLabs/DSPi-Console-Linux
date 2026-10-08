pragma Singleton
import QtQuick 2.15

// The colours of the native macOS Console, for the macOS build only: every use
// sits behind `isMacOS ? MacColors.x : <Linux colour>`. System colours come
// from AppKit at launch (macSystemColors, set in main.cpp), so the accent
// follows System Settings; the fallbacks are their dark-mode values with the
// blue accent.
QtObject {
    readonly property var sys: typeof macSystemColors !== "undefined" ? macSystemColors : ({})
    function pick(name, fallback) { return sys[name] !== undefined ? sys[name] : fallback }

    // Text (SwiftUI .primary / .secondary and the AppKit label colours)
    readonly property color label: pick("label", Qt.rgba(1, 1, 1, 0.847))
    readonly property color secondaryLabel: pick("secondaryLabel", Qt.rgba(1, 1, 1, 0.549))
    readonly property color tertiaryLabel: pick("tertiaryLabel", Qt.rgba(1, 1, 1, 0.247))
    readonly property color quaternaryLabel: pick("quaternaryLabel", Qt.rgba(1, 1, 1, 0.098))
    readonly property color placeholderText: pick("placeholderText", Qt.rgba(1, 1, 1, 0.247))

    // Backgrounds
    readonly property color windowBackground: pick("windowBackground", "#323232")
    readonly property color controlBackground: pick("controlBackground", "#1e1e1e")
    readonly property color textBackground: pick("textBackground", "#1e1e1e")
    readonly property color underPageBackground: pick("underPageBackground", "#282828")
    readonly property color control: pick("control", Qt.rgba(1, 1, 1, 0.247))
    readonly property color separator: pick("separator", Qt.rgba(1, 1, 1, 0.098))
    readonly property color grid: pick("grid", "#1a1a1a")
    readonly property color alternatingRow: pick("alternatingRow", Qt.rgba(1, 1, 1, 0.047))

    // Accent and selection (SwiftUI .accentColor = controlAccentColor)
    readonly property color accent: pick("accent", "#007aff")
    readonly property color selectedContentBackground: pick("selectedContentBackground", "#0059d1")
    readonly property color unemphasizedSelectedContentBackground: pick("unemphasizedSelectedContentBackground", "#464646")
    readonly property color selectedControl: pick("selectedControl", "#3f638b")
    readonly property color keyboardFocusIndicator: pick("keyboardFocusIndicator", Qt.rgba(0.102, 0.663, 1, 0.5))
    readonly property color link: pick("link", "#419cff")

    // The shades system controls fill their accent parts with (measured per
    // accent in MacSystemColors.mm; the accent itself when not known)
    readonly property color switchOn: pick("switchOn", accent)
    readonly property color checkboxOn: pick("checkboxOn", accent)
    readonly property color sliderFill: pick("sliderFill", accent)
    readonly property color defaultButton: pick("defaultButton", accent)              // NSAlert / AppKit default button
    readonly property color defaultButtonPressed: pick("defaultButtonPressed", accent)
    readonly property color prominentButton: pick("prominentButton", accent)          // SwiftUI .borderedProminent
    readonly property color sidebarSelection: pick("sidebarSelection", selectedContentBackground)
    readonly property color redSliderFill: "#c83f29"                                 // Slider with .tint(.red), any accent

    // The native main window: a material behind the whole window (#282828 at
    // rest, as measured), and the detail column windowBackground at 0.8 over
    // it (ContentView.swift:922), which comes to #303030
    readonly property color windowMaterial: "#282828"
    readonly property color mainContent: opacity(windowBackground, 0.8)
    readonly property color mainContentOpaque: Qt.tint(windowMaterial, mainContent)

    // System colours (SwiftUI Color.blue, .orange, ...)
    readonly property color blue: pick("blue", "#0a84ff")
    readonly property color orange: pick("orange", "#ff9f0a")
    readonly property color red: pick("red", "#ff453a")
    readonly property color green: pick("green", "#32d74b")
    readonly property color gray: pick("gray", "#98989d")
    readonly property color yellow: pick("yellow", "#ffd60a")
    readonly property color purple: pick("purple", "#bf5af2")
    readonly property color pink: pick("pink", "#ff375f")
    readonly property color teal: pick("teal", "#6ac4dc")
    readonly property color indigo: pick("indigo", "#5e5ce6")
    readonly property color mint: pick("mint", "#63e6e2")
    readonly property color cyan: pick("cyan", "#5ac8f5")
    readonly property color brown: pick("brown", "#ac8e68")

    // SwiftUI's `color.opacity(a)`: the colour with its alpha multiplied by a
    function opacity(c, a) { return Qt.rgba(c.r, c.g, c.b, c.a * a) }
}
