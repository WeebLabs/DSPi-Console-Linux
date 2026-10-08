#include "MacSystemColors.h"

#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QWindow>

#import <AppKit/AppKit.h>

// The shades AppKit and SwiftUI fill a control's accent parts with. AppKit
// derives them from the accent its own way (the switch is #1769e5 for the
// #007aff accent), and draws them only for an active app, so they were
// measured once per accent (controls drawn in an sRGB window, dark
// appearance, macOS 15) rather than computed. Keyed by the accent; an accent
// not listed (graphite) falls back to the accent itself in MacColors.
static void addControlAccents(QVariantMap &colors, const QColor &accent)
{
    struct Shades {
        QRgb accent, switchOn, checkboxOn, sliderFill, defaultButton, defaultButtonPressed, prominentButton;
    };
    static const Shades table[] = {
        // accent    switch    checkbox  slider    default   pressed   prominent
        { 0x007aff, 0x1769e5, 0x155fd0, 0x177be5, 0x1560d2, 0x2096e8, 0x1664dd },  // blue (and multicolour)
        { 0xff5257, 0xed4044, 0xd73a3e, 0xee4044, 0xda3a3e, 0xfc4e55, 0xb9362e },  // red
        { 0xf7821b, 0xf37200, 0xdd6800, 0xf47300, 0xdf6900, 0xff7b00, 0xc1791f },  // orange
        { 0xffc600, 0xe9af04, 0xd39f04, 0xeab004, 0xd5a004, 0xf7b911, 0xe0c416 },  // yellow
        { 0x62ba46, 0x44a029, 0x44a029, 0x4cb12d, 0x44a029, 0x5bbf3a, 0x367d29 },  // green
        { 0xa550a7, 0xcb2dca, 0xb829b8, 0xcc2ecb, 0xba2aba, 0xcc36ce, 0x843f80 },  // purple
        { 0xf74f9e, 0xe54a91, 0xd04483, 0xe64b91, 0xd24485, 0xf458a2, 0xbb3468 },  // pink
    };
    for (const Shades &t : table) {
        if (accent.rgb() != (0xff000000 | t.accent)) continue;
        colors.insert("switchOn", QColor(t.switchOn));
        colors.insert("checkboxOn", QColor(t.checkboxOn));
        colors.insert("sliderFill", QColor(t.sliderFill));
        colors.insert("defaultButton", QColor(t.defaultButton));
        colors.insert("defaultButtonPressed", QColor(t.defaultButtonPressed));
        colors.insert("prominentButton", QColor(t.prominentButton));
        // The selected row of a sidebar List over its material, measured on
        // screen for blue only
        if (t.accent == 0x007aff) colors.insert("sidebarSelection", QColor(0x276cd9));
        return;
    }
}

// The system colours the native macOS Console draws with, resolved in the dark
// appearance it runs in. Read once at launch; the accent follows the user's
// choice in System Settings.
QVariantMap macSystemColors()
{
    QVariantMap colors;
    @autoreleasepool {
        NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        struct Entry { const char *name; NSColor *color; };
        const Entry table[] = {
            { "label", NSColor.labelColor },
            { "secondaryLabel", NSColor.secondaryLabelColor },
            { "tertiaryLabel", NSColor.tertiaryLabelColor },
            { "quaternaryLabel", NSColor.quaternaryLabelColor },
            { "placeholderText", NSColor.placeholderTextColor },
            { "windowBackground", NSColor.windowBackgroundColor },
            { "controlBackground", NSColor.controlBackgroundColor },
            { "textBackground", NSColor.textBackgroundColor },
            { "underPageBackground", NSColor.underPageBackgroundColor },
            { "control", NSColor.controlColor },
            { "separator", NSColor.separatorColor },
            { "grid", NSColor.gridColor },
            { "accent", NSColor.controlAccentColor },
            { "selectedContentBackground", NSColor.selectedContentBackgroundColor },
            { "unemphasizedSelectedContentBackground", NSColor.unemphasizedSelectedContentBackgroundColor },
            { "selectedControl", NSColor.selectedControlColor },
            { "keyboardFocusIndicator", NSColor.keyboardFocusIndicatorColor },
            { "alternatingRow", NSColor.alternatingContentBackgroundColors.lastObject },
            { "link", NSColor.linkColor },
            { "blue", NSColor.systemBlueColor },
            { "orange", NSColor.systemOrangeColor },
            { "red", NSColor.systemRedColor },
            { "green", NSColor.systemGreenColor },
            { "gray", NSColor.systemGrayColor },
            { "yellow", NSColor.systemYellowColor },
            { "purple", NSColor.systemPurpleColor },
            { "pink", NSColor.systemPinkColor },
            { "teal", NSColor.systemTealColor },
            { "indigo", NSColor.systemIndigoColor },
            { "mint", NSColor.systemMintColor },
            { "cyan", NSColor.systemCyanColor },
            { "brown", NSColor.systemBrownColor },
        };
        const Entry *entries = table;
        const size_t count = sizeof(table) / sizeof(table[0]);
        QVariantMap *out = &colors;
        [dark performAsCurrentDrawingAppearance:^{
            for (size_t i = 0; i < count; ++i) {
                const Entry &entry = entries[i];
                NSColor *c = [entry.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                if (!c) continue;
                out->insert(QString::fromUtf8(entry.name),
                              QColor::fromRgbF(c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent));
            }
        }];
        addControlAccents(colors, colors.value("accent").value<QColor>());
    }
    return colors;
}

// Qt 5 hands its pixels to the display unconverted; the native app's colours
// are sRGB, converted for the display by AppKit. Tag every window as sRGB, as
// it is shown, so its colours are converted the same way.
namespace {
class SrgbWindows : public QObject
{
public:
    using QObject::QObject;
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() == QEvent::Show && object->isWindowType()) {
            NSView *view = reinterpret_cast<NSView *>(static_cast<QWindow *>(object)->winId());
            if (view.window && view.window.colorSpace != NSColorSpace.sRGBColorSpace)
                view.window.colorSpace = NSColorSpace.sRGBColorSpace;
        }
        return false;
    }
};
}

void macUseSrgbWindows(QCoreApplication *app)
{
    app->installEventFilter(new SrgbWindows(app));
}
