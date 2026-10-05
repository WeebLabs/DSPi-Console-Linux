#ifndef WINDOWEFFECTS_H
#define WINDOWEFFECTS_H

#include <QObject>
#include <QPointer>
#include <QVector>
#include <QRect>

class QWindow;
void releaseHeldButton(QWindow *window);

// Desktop effects for the app's frameless windows: a blurred, translucent
// sidebar strip and a drop shadow drawn by the window manager.
//
// On KDE Plasma this uses KWindowEffects / KWindowShadow (on Wayland they need
// the kwayland-integration plugin). KWin announces its effects
// asynchronously, so blurAvailable starts false and turns true once KWin
// confirms blur; QML binds the sidebar colour to it. Elsewhere both effects
// are no-ops and the sidebars stay solid.
class WindowEffects : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool blurAvailable READ blurAvailable NOTIFY blurAvailableChanged)

public:
    explicit WindowEffects(bool blurAlwaysAvailable, QObject *parent = nullptr);

    bool blurAvailable() const { return m_blurAvailable; }

    // Blur behind the strip [0, blurWidth) of `window` (0 = no blur) and give
    // it a shadow while it has focus. Re-applied each time the window is shown.
    Q_INVOKABLE void decorate(QWindow *window, int blurWidth, bool shadow = true);

    // Change the width of a decorated window's blurred strip (resizable sidebar)
    Q_INVOKABLE void setBlurWidth(QWindow *window, int blurWidth);

    // Blur behind a rounded rectangle of a shown window (a translucent
    // popover card). A no-op without blur; call again after each show.
    Q_INVOKABLE void blurBehind(QWindow *window, const QRect &area, int radius);
    // Hand a titlebar drag or an edge resize to the window manager. It keeps
    // the button release, so Qt is told the button went up right away: left
    // believing it held, Qt Quick delivers no hover until the next click.
    Q_INVOKABLE bool systemMove(QWindow *window);
    Q_INVOKABLE bool systemResize(QWindow *window, int edges);

signals:
    void blurAvailableChanged();

private:
    struct Decorated {
        QPointer<QWindow> window;
        int blurWidth;
    };

    void pollForBlur();
    void applyBlur(QWindow *window, int blurWidth);
    int blurWidthOf(QWindow *window) const;
    void attachShadow(QWindow *window);

    bool m_blurAvailable = false;
    bool m_polling = false;
    QVector<Decorated> m_windows;
};

#endif // WINDOWEFFECTS_H
