#include "WindowEffects.h"

#include <QTimer>
#include <QWindow>
#include <QColor>
#include <QVariant>
#include <memory>

#ifdef HAS_KDE_BLUR
#include <KWindowEffects>
#include <KWindowShadow>
#include <QImage>
#include <cmath>
#endif

WindowEffects::WindowEffects(bool blurAlwaysAvailable, QObject *parent)
    : QObject(parent), m_blurAvailable(blurAlwaysAvailable)
{
}

void WindowEffects::decorate(QWindow *window, int blurWidth, bool shadow)
{
    if (!window) return;
#ifdef HAS_KDE_BLUR
    if (blurWidth > 0) {
        m_windows.append({window, blurWidth});
        if (m_blurAvailable) applyBlur(window, blurWidth);
        else pollForBlur();

        // A Wayland surface is recreated each time the window is shown
        connect(window, &QWindow::visibleChanged, this, [this, window, blurWidth](bool visible) {
            if (visible && m_blurAvailable) applyBlur(window, blurWidth);
        });
        connect(window, &QWindow::heightChanged, this, [this, window, blurWidth]() {
            if (m_blurAvailable) applyBlur(window, blurWidth);
        });
    }
    if (shadow) attachShadow(window);
#else
    Q_UNUSED(blurWidth);
    Q_UNUSED(shadow);
#endif
}

void WindowEffects::pollForBlur()
{
#ifdef HAS_KDE_BLUR
    if (m_polling) return;
    m_polling = true;
    auto *timer = new QTimer(this);
    timer->setInterval(100);
    auto attempts = std::make_shared<int>(0);
    connect(timer, &QTimer::timeout, this, [this, timer, attempts]() {
        if (++*attempts > 50) { timer->deleteLater(); return; }   // give up after 5 s
        if (!KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind)) return;
        timer->deleteLater();
        m_blurAvailable = true;
        for (const Decorated &d : qAsConst(m_windows))
            if (d.window) applyBlur(d.window, d.blurWidth);
        emit blurAvailableChanged();
    });
    timer->start();
#endif
}

void WindowEffects::applyBlur(QWindow *window, int blurWidth)
{
#ifdef HAS_KDE_BLUR
    // Transparent clear colour so the blurred backdrop shows through the
    // translucent sidebar; the rest of each window paints its own background.
    window->setProperty("color", QColor(Qt::transparent));
    if (window->isVisible())
        KWindowEffects::enableBlurBehind(window, true, QRegion(0, 0, blurWidth, window->height()));
#else
    Q_UNUSED(window);
    Q_UNUSED(blurWidth);
#endif
}

void WindowEffects::attachShadow(QWindow *window)
{
#ifdef HAS_KDE_BLUR
    // Shadow tiles: a soft falloff, a little deeper below the window.
    static QImage img = [] {
        const int r = 32, offsetY = 5;
        const double maxAlpha = 0.55;
        const int size = 2 * r + 1;
        QImage im(size, size, QImage::Format_ARGB32_Premultiplied);
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++) {
                double dx = x - r, dy = y - (r + offsetY);
                double t = std::min(1.0, std::sqrt(dx * dx + dy * dy) / r);
                int a = int(255 * maxAlpha * (1 - t) * (1 - t));
                im.setPixel(x, y, qRgba(0, 0, 0, a));
            }
        return im;
    }();
    const int r = 32;

    auto tile = [&](int x, int y, int w, int h) {
        auto t = KWindowShadowTile::Ptr::create();
        t->setImage(img.copy(x, y, w, h));
        return t;
    };

    auto *shadow = new KWindowShadow(window);
    shadow->setTopLeftTile(tile(0, 0, r, r));
    shadow->setTopTile(tile(r, 0, 1, r));
    shadow->setTopRightTile(tile(r + 1, 0, r, r));
    shadow->setLeftTile(tile(0, r, r, 1));
    shadow->setRightTile(tile(r + 1, r, r, 1));
    shadow->setBottomLeftTile(tile(0, r + 1, r, r));
    shadow->setBottomTile(tile(r, r + 1, 1, r));
    shadow->setBottomRightTile(tile(r + 1, r + 1, r, r));
    shadow->setPadding(QMargins(r, r, r, r));
    shadow->setWindow(window);

    // Shadow only while the window is shown, focused and not maximised
    auto update = [window, shadow]() {
        bool want = window->isVisible() && window->isActive()
                 && !(window->windowStates() & (Qt::WindowMaximized | Qt::WindowFullScreen));
        if (want) shadow->create();
        else shadow->destroy();
    };
    connect(window, &QWindow::windowStateChanged, shadow, update);
    connect(window, &QWindow::activeChanged, shadow, update);
    connect(window, &QWindow::visibleChanged, shadow, update);
    update();
#else
    Q_UNUSED(window);
#endif
}
