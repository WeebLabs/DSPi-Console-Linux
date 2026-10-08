#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QPalette>
#include <QFont>
#include <QSettings>
#include <QFile>
#include <cstdio>

#ifdef Q_OS_MACOS
#include <objc/runtime.h>
#include <objc/message.h>
#include "MacSystemColors.h"
#endif


#include <QWindow>
#include <QQuickWindow>
#include <QFontDatabase>
#include <QSurfaceFormat>

#include "DSPiBridge.h"
#include "BodePlotItem.h"
#include "PeqEditorItem.h"
#include "RtaController.h"
#include "RtaViews.h"
#include "PointerTracker.h"
#include "SiggenController.h"
#include "CsController.h"
#include "FirmwareUpdater.h"
#include "AutoEqLibrary.h"
#include "StatsController.h"
#include "MonitorModel.h"
#include "ConfigFiles.h"
#include "MeterItem.h"
#include "WindowEffects.h"
#include "TextFocusReleaser.h"

static void setPlatformDarkMode()
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

static void setupPlatformEffects(QQuickWindow *qw)
{
    if (!qw) return;

#ifdef Q_OS_MACOS
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

    // Create the NSVisualEffectView (the window material)
    typedef struct { double x, y, w, h; } NSRect;
    // Behind the whole window, as in the native app: the sidebar shows it
    // through, the content area is drawn translucent over it. It follows the
    // window's size.
    NSRect sidebarFrame = {0, 0, (double)qw->width(), (double)qw->height()};
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
    // state = NSVisualEffectStateFollowsWindowActiveState (0): like the native
    // sidebar list, the material greys out while the window is inactive
    reinterpret_cast<void (*)(id, SEL, long)>(objc_msgSend)(
        veView, sel_registerName("setState:"), 0);
    // autoresizingMask = NSViewWidthSizable (2) | NSViewHeightSizable (16)
    reinterpret_cast<void (*)(id, SEL, unsigned long)>(objc_msgSend)(
        veView, sel_registerName("setAutoresizingMask:"), 2 | 16);

    // Insert VE view as sibling of contentView, below it in z-order
    // NSWindowBelow = -1
    reinterpret_cast<void (*)(id, SEL, id, long, id)>(objc_msgSend)(
        frameView, sel_registerName("addSubview:positioned:relativeTo:"),
        veView, (long)-1, contentView);

#elif defined(HAS_KDE_BLUR)
    // KDE Plasma: blur is requested in enableKdeBlurWhenReady(), once KWin has
    // told us the effect exists.
    Q_UNUSED(qw);
#endif
}

#ifndef Q_OS_MACOS
// Qt 5's Wayland client takes the cursor theme and size only from
// XCURSOR_THEME / XCURSOR_SIZE ("default" at 24 or 32 px without them), and
// Plasma and GNOME on Wayland don't export them. It reads them when it first
// draws a cursor, so setting them once the platform is up still counts. On
// X11 Qt follows the desktop itself (XSETTINGS, X resources).

// A key of a KDE config file group: the user's file first, then the system's
// (the KConfig cascade). Keys may carry "[$e]" style flags after the name.
static QByteArray kdeConfigValue(const char *file, const QByteArray &group, const QByteArray &key)
{
    QByteArrayList dirs;
    const QByteArray configHome = qgetenv("XDG_CONFIG_HOME");
    dirs << (configHome.isEmpty() ? qgetenv("HOME") + "/.config" : configHome);
    const QByteArray configDirs = qgetenv("XDG_CONFIG_DIRS");
    dirs << (configDirs.isEmpty() ? QByteArray("/etc/xdg") : configDirs).split(':');
    for (const QByteArray &dir : dirs) {
        QFile f(QString::fromLocal8Bit(dir + '/' + file));
        if (dir.isEmpty() || !f.open(QIODevice::ReadOnly)) continue;
        bool inGroup = false;
        while (!f.atEnd()) {
            const QByteArray line = f.readLine().trimmed();
            if (line.startsWith('[')) { inGroup = line == '[' + group + ']'; continue; }
            const int eq = line.indexOf('=');
            if (!inGroup || eq <= 0) continue;
            QByteArray name = line.left(eq).trimmed();
            if (name.contains('[')) name.truncate(name.indexOf('['));
            if (name == key) return line.mid(eq + 1).trimmed();
        }
    }
    return {};
}

// The cursor theme and size of GNOME's interface settings, through gsettings
// (GNOME, and the wlroots desktops whose settings tools write the same keys);
// empty without them. One line per key, empty when a read fails.
static QByteArrayList gnomeCursorSettings()
{
    FILE *p = popen("for k in cursor-theme cursor-size; do"
                    " gsettings get org.gnome.desktop.interface $k 2>/dev/null || echo; done", "r");
    if (!p) return {};
    char buf[256];
    QByteArray out;
    while (fgets(buf, sizeof buf, p)) out += buf;
    pclose(p);
    QByteArrayList values = out.split('\n');
    for (QByteArray &v : values) {
        v = v.trimmed();
        if (v.size() >= 2 && v.startsWith('\'') && v.endsWith('\''))
            v = v.mid(1, v.size() - 2);                             // 'Adwaita'
        else
            v = v.mid(v.lastIndexOf(' ') + 1);                      // 24, uint32 24
    }
    return values;
}

static void adoptDesktopCursor()
{
    const bool needTheme = qEnvironmentVariableIsEmpty("XCURSOR_THEME");
    const bool needSize = qEnvironmentVariableIsEmpty("XCURSOR_SIZE");
    if ((!needTheme && !needSize) || !QGuiApplication::platformName().startsWith(QLatin1String("wayland")))
        return;

    QByteArray theme, size;
    if (qgetenv("XDG_CURRENT_DESKTOP").split(':').contains("KDE")) {
        // Plasma's own defaults when the user hasn't chosen
        theme = kdeConfigValue("kcminputrc", "Mouse", "cursorTheme");
        size = kdeConfigValue("kcminputrc", "Mouse", "cursorSize");
        if (theme.isEmpty()) theme = "breeze_cursors";
        if (size.isEmpty()) size = "24";
    } else {
        const QByteArrayList gnome = gnomeCursorSettings();
        theme = gnome.value(0);
        size = gnome.value(1);
    }
    if (needTheme && !theme.isEmpty() && !theme.contains('/')) qputenv("XCURSOR_THEME", theme);
    bool ok = false;
    const int px = size.toInt(&ok);
    if (needSize && ok && px > 0 && px <= 512) qputenv("XCURSOR_SIZE", QByteArray::number(px));
}
#endif

int main(int argc, char *argv[])
{
#ifndef Q_OS_MACOS
    // X11 WM_CLASS instance, matched to the desktop entry's StartupWMClass
    // (otherwise the binary's name, which an AppImage changes)
    if (!qEnvironmentVariableIsSet("RESOURCE_NAME")) qputenv("RESOURCE_NAME", "dspi-console");
#endif
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#ifdef HAS_KDE_BLUR
    // Windows need an alpha channel from creation for the blurred sidebar to
    // show through: Qt can't add one to an existing surface, so the switch to
    // a transparent clear colour in applyBlur() would otherwise leave it opaque
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);
#endif
    QApplication app(argc, argv);
#ifndef Q_OS_MACOS
    adoptDesktopCursor();   // before any window shows a cursor
#endif
    app.installEventFilter(new TextFocusReleaser(&app));
#ifdef Q_OS_MACOS
    macUseSrgbWindows(&app);
    // Text drawn by CoreText, as AppKit draws it, rather than from Qt Quick's
    // distance-field glyphs (softer, lighter, approximate tracking)
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
#endif
    app.setApplicationName("DSPi Console");
    app.setOrganizationName("DSPi");
    app.setApplicationVersion("1.1.6-beta4");   // firmware release this Console targets
#ifndef Q_OS_MACOS
    // The Wayland app id, matched to dspi-console.desktop for the taskbar icon
    app.setDesktopFileName(QStringLiteral("dspi-console"));
    app.setWindowIcon(QIcon(QStringLiteral(":/dspi-console.svg")));
#endif

    setPlatformDarkMode();

    // Fusion style — consistent dark look across platforms. The app's own
    // style (qml/style) only replaces ToolTip and falls back to Fusion.
    QQuickStyle::setStyle(QStringLiteral(":/qml/style"));
    QQuickStyle::setFallbackStyle(QStringLiteral("Fusion"));

    // Dark palette, hardcoded
#ifdef Q_OS_MACOS
    QPalette darkPalette;
    // AppKit's windowBackgroundColor, as behind the native Console's content
    // pane and setup wizard (QML reads it as nativeWindowColor)
    darkPalette.setColor(QPalette::Window, macSystemColors().value(QStringLiteral("windowBackground"), QColor(50, 50, 50)).value<QColor>());
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
#else
    // The app's own dark palette, the same on every desktop (and in the
    // AppImage, which can't load the desktop's theme plugin)
    struct Swatch { QPalette::ColorGroup group; QPalette::ColorRole role; QColor color; };
    const Swatch swatches[] = {
        { QPalette::Active, QPalette::WindowText, QColor(230, 230, 230) },
        { QPalette::Active, QPalette::Button, QColor(44, 44, 44) },
        { QPalette::Active, QPalette::Light, QColor(54, 54, 54) },
        { QPalette::Active, QPalette::Midlight, QColor(44, 44, 44) },
        { QPalette::Active, QPalette::Dark, QColor(21, 21, 21) },
        { QPalette::Active, QPalette::Mid, QColor(29, 29, 29) },
        { QPalette::Active, QPalette::Text, QColor(230, 230, 230) },
        { QPalette::Active, QPalette::BrightText, QColor(255, 255, 255) },
        { QPalette::Active, QPalette::ButtonText, QColor(230, 230, 230) },
        { QPalette::Active, QPalette::Base, QColor(24, 24, 24) },
        { QPalette::Active, QPalette::Window, QColor(32, 32, 32) },
        { QPalette::Active, QPalette::Shadow, QColor(15, 15, 15) },
        { QPalette::Active, QPalette::Highlight, QColor(125, 155, 215) },
        { QPalette::Active, QPalette::HighlightedText, QColor(252, 252, 252) },
        { QPalette::Active, QPalette::Link, QColor(120, 155, 235) },
        { QPalette::Active, QPalette::LinkVisited, QColor(170, 130, 210) },
        { QPalette::Active, QPalette::AlternateBase, QColor(28, 28, 28) },
        { QPalette::Active, QPalette::ToolTipBase, QColor(38, 38, 38) },
        { QPalette::Active, QPalette::ToolTipText, QColor(230, 230, 230) },
        { QPalette::Active, QPalette::PlaceholderText, QColor(230, 230, 230, 128) },
        { QPalette::Disabled, QPalette::WindowText, QColor(97, 97, 97) },
        { QPalette::Disabled, QPalette::Button, QColor(42, 42, 42) },
        { QPalette::Disabled, QPalette::Light, QColor(53, 53, 53) },
        { QPalette::Disabled, QPalette::Midlight, QColor(43, 43, 43) },
        { QPalette::Disabled, QPalette::Dark, QColor(20, 20, 20) },
        { QPalette::Disabled, QPalette::Mid, QColor(27, 27, 27) },
        { QPalette::Disabled, QPalette::Text, QColor(92, 92, 92) },
        { QPalette::Disabled, QPalette::BrightText, QColor(255, 255, 255) },
        { QPalette::Disabled, QPalette::ButtonText, QColor(104, 104, 104) },
        { QPalette::Disabled, QPalette::Base, QColor(23, 23, 23) },
        { QPalette::Disabled, QPalette::Window, QColor(31, 31, 31) },
        { QPalette::Disabled, QPalette::Shadow, QColor(14, 14, 14) },
        { QPalette::Disabled, QPalette::Highlight, QColor(31, 31, 31) },
        { QPalette::Disabled, QPalette::HighlightedText, QColor(97, 97, 97) },
        { QPalette::Disabled, QPalette::Link, QColor(55, 67, 93) },
        { QPalette::Disabled, QPalette::LinkVisited, QColor(72, 58, 85) },
        { QPalette::Disabled, QPalette::AlternateBase, QColor(27, 27, 27) },
        { QPalette::Disabled, QPalette::ToolTipBase, QColor(38, 38, 38) },
        { QPalette::Disabled, QPalette::ToolTipText, QColor(230, 230, 230) },
        { QPalette::Disabled, QPalette::PlaceholderText, QColor(230, 230, 230, 128) },
        { QPalette::Inactive, QPalette::WindowText, QColor(230, 230, 230) },
        { QPalette::Inactive, QPalette::Button, QColor(44, 44, 44) },
        { QPalette::Inactive, QPalette::Light, QColor(54, 54, 54) },
        { QPalette::Inactive, QPalette::Midlight, QColor(44, 44, 44) },
        { QPalette::Inactive, QPalette::Dark, QColor(21, 21, 21) },
        { QPalette::Inactive, QPalette::Mid, QColor(29, 29, 29) },
        { QPalette::Inactive, QPalette::Text, QColor(230, 230, 230) },
        { QPalette::Inactive, QPalette::BrightText, QColor(255, 255, 255) },
        { QPalette::Inactive, QPalette::ButtonText, QColor(230, 230, 230) },
        { QPalette::Inactive, QPalette::Base, QColor(24, 24, 24) },
        { QPalette::Inactive, QPalette::Window, QColor(32, 32, 32) },
        { QPalette::Inactive, QPalette::Shadow, QColor(15, 15, 15) },
        { QPalette::Inactive, QPalette::Highlight, QColor(48, 58, 78) },
        { QPalette::Inactive, QPalette::HighlightedText, QColor(230, 230, 230) },
        { QPalette::Inactive, QPalette::Link, QColor(120, 155, 235) },
        { QPalette::Inactive, QPalette::LinkVisited, QColor(170, 130, 210) },
        { QPalette::Inactive, QPalette::AlternateBase, QColor(28, 28, 28) },
        { QPalette::Inactive, QPalette::ToolTipBase, QColor(38, 38, 38) },
        { QPalette::Inactive, QPalette::ToolTipText, QColor(230, 230, 230) },
        { QPalette::Inactive, QPalette::PlaceholderText, QColor(230, 230, 230, 128) },
    };
    QPalette darkPalette;
    for (const Swatch &s : swatches) darkPalette.setColor(s.group, s.role, s.color);
    app.setPalette(darkPalette);
#endif

    // Platform-appropriate default font
#ifdef Q_OS_MACOS
    // The system font, SF. Qt 5 offers `.AppleSystemUIFont` in Regular and Bold
    // only, so medium and semibold text comes out regular or bold. SF Pro,
    // where Apple's fonts are installed, is the same face (identical advances)
    // with every weight.
    const bool sfPro = QFontDatabase().families().contains(QStringLiteral("SF Pro"));
    QFont defaultFont(sfPro ? QStringLiteral("SF Pro") : QStringLiteral(".AppleSystemUIFont"), 13);
#else
    QFont defaultFont("Noto Sans", 13);
    // Fallback chain: Noto Sans → Segoe UI → system default
    if (!QFont(defaultFont).exactMatch()) {
        defaultFont = QFont("sans-serif", 13);
    }
#endif
    defaultFont.setStyleStrategy(QFont::PreferAntialias);
    app.setFont(defaultFont);

    // Expose platform info to QML for conditional font selection
    bool isMacOS = false;
#ifdef Q_OS_MACOS
    isMacOS = true;
#endif

    // Register QML types
    qmlRegisterType<BodePlotItem>("DSPi", 1, 0, "BodePlotItem");
    qmlRegisterType<PeqEditorItem>("DSPi", 1, 0, "PeqEditorItem");
    qmlRegisterType<SpectrumCurveItem>("DSPi", 1, 0, "SpectrumCurveItem");
    qmlRegisterType<SpectrumBarsItem>("DSPi", 1, 0, "SpectrumBarsItem");
    qmlRegisterType<PointerTracker>("DSPi", 1, 0, "PointerTracker");
    qmlRegisterType<BufferTraceItem>("DSPi", 1, 0, "BufferTraceItem");
    qmlRegisterType<MeterItem>("DSPi", 1, 0, "MeterItem");

    // Create bridge
    DSPiBridge bridge;

    // Before the engine, so it outlives every view that uses it
    RtaController rta(&bridge);
    SiggenController siggen(&bridge);
    CsController controlSurfaces(&bridge);
    FirmwareUpdater firmware(&bridge);
    AutoEqLibrary autoeq(&bridge);
    StatsController stats(&bridge);
    MonitorModel monitor(&bridge);
    ConfigFiles configFiles(&bridge);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty("rta", &rta);
    engine.rootContext()->setContextProperty("siggen", &siggen);
    engine.rootContext()->setContextProperty("controlSurfaces", &controlSurfaces);
    engine.rootContext()->setContextProperty("firmware", &firmware);
    engine.rootContext()->setContextProperty("autoeq", &autoeq);
    // Whether this machine ran Console before (any saved setting): an existing
    // user isn't put through the first-launch wizard on upgrade day
    {
        QStringList groups = QSettings().childGroups();
        groups.removeAll("onboarding");
        engine.rootContext()->setContextProperty("hadSettingsAtLaunch", !groups.isEmpty());
    }
    engine.rootContext()->setContextProperty("stats", &stats);
    engine.rootContext()->setContextProperty("monitor", &monitor);
    engine.rootContext()->setContextProperty("configFiles", &configFiles);
    engine.rootContext()->setContextProperty("isMacOS", isMacOS);
#ifdef Q_OS_MACOS
    // The native Console's colours, read by the MacColors singleton
    engine.rootContext()->setContextProperty("macSystemColors", macSystemColors());
    engine.rootContext()->setContextProperty("macSidebarSizeMode", macSidebarSizeMode());
#endif

    // Blur and shadow for the frameless windows (main window, Settings)
    WindowEffects windowEffects(isMacOS);
    engine.rootContext()->setContextProperty("windowEffects", &windowEffects);
    QPalette sysPal = QGuiApplication::palette();
    engine.rootContext()->setContextProperty("nativeWindowColor", sysPal.color(QPalette::Window));
    engine.rootContext()->setContextProperty("nativeButtonColor", sysPal.color(QPalette::Button));
    engine.rootContext()->setContextProperty("nativeBaseColor", sysPal.color(QPalette::Base));
    engine.rootContext()->setContextProperty("nativeAltBaseColor", sysPal.color(QPalette::AlternateBase));

    // Add QML import path for our custom module
    engine.addImportPath("qrc:/");

    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    auto *mainWindow = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    setupPlatformEffects(mainWindow);
#ifndef Q_OS_MACOS
    // The sidebar is resizable; QML updates the strip as it changes
    windowEffects.decorate(mainWindow, mainWindow->property("sidebarWidth").toInt(), true);
#endif

    return app.exec();
}
