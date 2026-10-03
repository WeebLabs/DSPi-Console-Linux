#include <QApplication>
#include <QTimer>
#include <memory>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QPalette>
#include <QFont>

#ifdef Q_OS_MACOS
#include <objc/runtime.h>
#include <objc/message.h>
#endif

#ifdef HAS_KDE_BLUR
#include <KWindowEffects>
#include <KWindowShadow>
#include <QImage>
#include <QPainter>
#include <cmath>
#endif

#include <QWindow>
#include <QQuickWindow>

#include "DSPiBridge.h"
#include "BodePlotItem.h"
#include "MeterItem.h"

static const int SIDEBAR_WIDTH = 260;

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

    // Create NSVisualEffectView sized to the sidebar
    typedef struct { double x, y, w, h; } NSRect;
    NSRect sidebarFrame = {0, 0, (double)SIDEBAR_WIDTH, 900}; // tall enough, autoresizes
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

#elif defined(HAS_KDE_BLUR)
    // KDE Plasma: blur is requested in enableKdeBlurWhenReady(), once KWin has
    // told us the effect exists.
    Q_UNUSED(qw);
#endif
}

#ifdef HAS_KDE_BLUR
// The window draws its own titlebar, so KWin gives it no decoration shadow.
// Ask KWin for one through the KDE shadow protocol, the same mechanism
// Plasma's frameless popups use. Needs KWindowSystem's Wayland plugin
// (kwayland-integration) on Wayland; without it create() just fails.
static void setupWindowShadow(QWindow *qw)
{
    const int r = 32;             // shadow reach in px
    const int offsetY = 5;        // light from above: deeper below the window
    const double maxAlpha = 0.55;
    const int size = 2 * r + 1;

    QImage img(size, size, QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            double dx = x - r, dy = y - (r + offsetY);
            double t = std::min(1.0, std::sqrt(dx * dx + dy * dy) / r);
            int a = int(255 * maxAlpha * (1 - t) * (1 - t));
            img.setPixel(x, y, qRgba(0, 0, 0, a));
        }
    }

    auto tile = [&](int x, int y, int w, int h) {
        auto t = KWindowShadowTile::Ptr::create();
        t->setImage(img.copy(x, y, w, h));
        return t;
    };

    auto *shadow = new KWindowShadow(qw);
    shadow->setTopLeftTile(tile(0, 0, r, r));
    shadow->setTopTile(tile(r, 0, 1, r));
    shadow->setTopRightTile(tile(r + 1, 0, r, r));
    shadow->setLeftTile(tile(0, r, r, 1));
    shadow->setRightTile(tile(r + 1, r, r, 1));
    shadow->setBottomLeftTile(tile(0, r + 1, r, r));
    shadow->setBottomTile(tile(r, r + 1, 1, r));
    shadow->setBottomRightTile(tile(r + 1, r + 1, r, r));
    shadow->setPadding(QMargins(r, r, r, r));
    shadow->setWindow(qw);

    // Shadow only while the window has focus, and never when maximised
    auto update = [qw, shadow]() {
        bool want = qw->isActive()
                 && !(qw->windowStates() & (Qt::WindowMaximized | Qt::WindowFullScreen));
        if (want) shadow->create();
        else shadow->destroy();
    };
    QObject::connect(qw, &QWindow::windowStateChanged, qw, update);
    QObject::connect(qw, &QWindow::activeChanged, qw, update);
    if (!shadow->create())
        qInfo("DSPi: no window shadow (KWin shadow protocol unavailable)");
    update();
}
#endif

#ifdef HAS_KDE_BLUR
// Blur behind the sidebar via KWin. On Wayland, KWindowEffects only learns
// which effects KWin offers after a round trip to the compositor, so poll
// briefly; once blur is available, make the window translucent, request the
// blur region and tell QML (hasBlurBehind) to draw the translucent sidebar.
static void enableKdeBlurWhenReady(QQuickWindow *qw, QQmlContext *ctx)
{
    auto *timer = new QTimer(qw);
    timer->setInterval(100);
    auto attempts = std::make_shared<int>(0);
    QObject::connect(timer, &QTimer::timeout, qw, [qw, ctx, timer, attempts]() {
        if (++*attempts > 50) { timer->deleteLater(); return; }   // give up after 5 s
        if (!KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind)) return;
        timer->deleteLater();

        qw->setColor(Qt::transparent);
        auto apply = [qw](int h) {
            KWindowEffects::enableBlurBehind(qw->winId(), true, QRegion(0, 0, SIDEBAR_WIDTH, h));
        };
        apply(qw->height());
        QObject::connect(qw, &QWindow::heightChanged, qw, apply);
        ctx->setContextProperty("hasBlurBehind", true);
    });
    timer->start();
}
#endif

int main(int argc, char *argv[])
{
    QApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QApplication app(argc, argv);
    app.setApplicationName("DSPi Console");
    app.setOrganizationName("DSPi");

    setPlatformDarkMode();

    // Fusion style — consistent dark look across platforms
    QQuickStyle::setStyle("Fusion");

    // Dark palette: use system palette on Linux, hardcoded dark on macOS/other
#ifdef Q_OS_MACOS
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
#endif

    // Platform-appropriate default font
#ifdef Q_OS_MACOS
    QFont defaultFont(".AppleSystemUIFont", 13);
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
    qmlRegisterType<MeterItem>("DSPi", 1, 0, "MeterItem");

    // Create bridge
    DSPiBridge bridge;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty("isMacOS", isMacOS);

    bool hasBlurBehind = isMacOS;
#ifdef HAS_KDE_BLUR
    // KWin announces its effects asynchronously on Wayland, so this starts
    // false and enableKdeBlurWhenReady() flips it once blur is confirmed.
    hasBlurBehind = false;
#endif
    engine.rootContext()->setContextProperty("hasBlurBehind", hasBlurBehind);
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

    setupPlatformEffects(qobject_cast<QQuickWindow *>(engine.rootObjects().first()));
#ifdef HAS_KDE_BLUR
    setupWindowShadow(qobject_cast<QQuickWindow *>(engine.rootObjects().first()));
    enableKdeBlurWhenReady(qobject_cast<QQuickWindow *>(engine.rootObjects().first()), engine.rootContext());
#endif

    return app.exec();
}
