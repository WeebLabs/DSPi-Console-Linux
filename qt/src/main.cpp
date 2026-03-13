#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QPalette>
#include <QFont>

#ifdef Q_OS_MACOS
#include <objc/runtime.h>
#include <objc/message.h>
#endif

#include <QWindow>
#include <QQuickWindow>

#include "DSPiBridge.h"
#include "BodePlotItem.h"
#include "MeterItem.h"

static void setMacOSDarkMode()
{
#ifdef Q_OS_MACOS
    // Force dark appearance via NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
    id nsApp = reinterpret_cast<id (*)(Class, SEL)>(objc_msgSend)(
        objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    id darkName = reinterpret_cast<id (*)(Class, SEL, const char *)>(objc_msgSend)(
        objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), "NSAppearanceNameDarkAqua");
    id appearance = reinterpret_cast<id (*)(Class, SEL, id)>(objc_msgSend)(
        objc_getClass("NSAppearance"), sel_registerName("appearanceNamed:"), darkName);
    reinterpret_cast<void (*)(id, SEL, id)>(objc_msgSend)(nsApp, sel_registerName("setAppearance:"), appearance);
#endif
}

int main(int argc, char *argv[])
{
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QApplication app(argc, argv);
    app.setApplicationName("DSPi Console");
    app.setOrganizationName("DSPi");

    setMacOSDarkMode();

    // Fusion style — but native titlebar/menubar comes from QApplication
    QQuickStyle::setStyle("Fusion");

    // Dark palette
    QPalette darkPalette;
    darkPalette.setColor(QPalette::Window, QColor(48, 48, 48));
    darkPalette.setColor(QPalette::WindowText, Qt::white);
    darkPalette.setColor(QPalette::Base, QColor(42, 42, 42));
    darkPalette.setColor(QPalette::AlternateBase, QColor(53, 53, 53));
    darkPalette.setColor(QPalette::ToolTipBase, QColor(42, 42, 42));
    darkPalette.setColor(QPalette::ToolTipText, Qt::white);
    darkPalette.setColor(QPalette::Text, Qt::white);
    darkPalette.setColor(QPalette::Button, QColor(53, 53, 53));
    darkPalette.setColor(QPalette::ButtonText, Qt::white);
    darkPalette.setColor(QPalette::BrightText, Qt::white);
    darkPalette.setColor(QPalette::Link, QColor(0, 120, 212));
    darkPalette.setColor(QPalette::Highlight, QColor(0, 120, 212));
    darkPalette.setColor(QPalette::HighlightedText, Qt::white);
    darkPalette.setColor(QPalette::Disabled, QPalette::Text, QColor(128, 128, 128));
    darkPalette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(128, 128, 128));
    app.setPalette(darkPalette);

    // Default font
    QFont defaultFont(".AppleSystemUIFont", 13);
    defaultFont.setStyleStrategy(QFont::PreferAntialias);
    app.setFont(defaultFont);

    // Register QML types
    qmlRegisterType<BodePlotItem>("DSPi", 1, 0, "BodePlotItem");
    qmlRegisterType<MeterItem>("DSPi", 1, 0, "MeterItem");

    // Create bridge
    DSPiBridge bridge;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);

    // Add QML import path for our custom module
    engine.addImportPath("qrc:/");

    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

#ifdef Q_OS_MACOS
    QQuickWindow *qw = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (qw) {
        // Make Qt scene graph clear to transparent so vibrancy shows through
        qw->setColor(Qt::transparent);

        auto nsView = reinterpret_cast<id>(qw->winId());
        id nsWindow = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(
            nsView, sel_registerName("window"));

        // --- Integrated titlebar ---
        reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(
            nsWindow, sel_registerName("setTitlebarAppearsTransparent:"), YES);
        reinterpret_cast<void (*)(id, SEL, long)>(objc_msgSend)(
            nsWindow, sel_registerName("setTitleVisibility:"), 1);
        long styleMask = reinterpret_cast<long (*)(id, SEL)>(objc_msgSend)(
            nsWindow, sel_registerName("styleMask"));
        styleMask |= (1 << 15); // NSWindowStyleMaskFullSizeContentView
        reinterpret_cast<void (*)(id, SEL, long)>(objc_msgSend)(
            nsWindow, sel_registerName("setStyleMask:"), styleMask);

        // --- Translucent sidebar via NSVisualEffectView ---
        // Make window non-opaque
        reinterpret_cast<void (*)(id, SEL, BOOL)>(objc_msgSend)(
            nsWindow, sel_registerName("setOpaque:"), NO);
        id clearColor = reinterpret_cast<id (*)(Class, SEL)>(objc_msgSend)(
            objc_getClass("NSColor"), sel_registerName("clearColor"));
        reinterpret_cast<void (*)(id, SEL, id)>(objc_msgSend)(
            nsWindow, sel_registerName("setBackgroundColor:"), clearColor);

        // Get contentView and its superview (the window's frame view)
        id contentView = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(
            nsWindow, sel_registerName("contentView"));
        id frameView = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(
            contentView, sel_registerName("superview"));

        // Create NSVisualEffectView sized to the sidebar
        typedef struct { double x, y, w, h; } NSRect;
        NSRect sidebarFrame = {0, 0, 260, 900}; // tall enough, autoresizes
        id veView = reinterpret_cast<id (*)(Class, SEL)>(objc_msgSend)(
            objc_getClass("NSVisualEffectView"), sel_registerName("alloc"));
        veView = reinterpret_cast<id (*)(id, SEL, NSRect)>(objc_msgSend)(
            veView, sel_registerName("initWithFrame:"), sidebarFrame);

        // material = NSVisualEffectMaterialSidebar (7)
        reinterpret_cast<void (*)(id, SEL, long)>(objc_msgSend)(
            veView, sel_registerName("setMaterial:"), 7);
        // blendingMode = NSVisualEffectBlendingModeBehindWindow (0)
        reinterpret_cast<void (*)(id, SEL, long)>(objc_msgSend)(
            veView, sel_registerName("setBlendingMode:"), 0);
        // state = NSVisualEffectStateActive (1)
        reinterpret_cast<void (*)(id, SEL, long)>(objc_msgSend)(
            veView, sel_registerName("setState:"), 1);
        // autoresizingMask = NSViewHeightSizable (16)
        reinterpret_cast<void (*)(id, SEL, unsigned long)>(objc_msgSend)(
            veView, sel_registerName("setAutoresizingMask:"), 16);

        // Insert VE view as sibling of contentView, below it in z-order
        // NSWindowBelow = -1
        reinterpret_cast<void (*)(id, SEL, id, long, id)>(objc_msgSend)(
            frameView, sel_registerName("addSubview:positioned:relativeTo:"),
            veView, (long)-1, contentView);

    }
#endif

    return app.exec();
}
