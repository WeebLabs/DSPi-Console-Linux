#include "PointerTracker.h"

#include <QQuickWindow>
#include <QMouseEvent>
#include <QHoverEvent>

PointerTracker::PointerTracker(QQuickItem *parent) : QQuickItem(parent) {
    setFlag(ItemHasContents, false);
}

void PointerTracker::itemChange(ItemChange change, const ItemChangeData &value) {
    QQuickItem::itemChange(change, value);
    if (change != ItemSceneChange) return;
    if (m_window) m_window->removeEventFilter(this);
    m_window = value.window;
    if (m_window) m_window->installEventFilter(this);
    setInside(false);
}

bool PointerTracker::eventFilter(QObject *, QEvent *event) {
    switch (event->type()) {
    case QEvent::MouseMove:
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease: {
        auto *me = static_cast<QMouseEvent *>(event);
        setInside(isVisible() && contains(mapFromScene(me->windowPos())));
        break;
    }
    case QEvent::Enter: {
        auto *ee = static_cast<QEnterEvent *>(event);
        setInside(isVisible() && contains(mapFromScene(ee->windowPos())));
        break;
    }
    case QEvent::Leave:
        setInside(false);
        break;
    default:
        break;
    }
    return false;              // only watching
}

void PointerTracker::setInside(bool inside) {
    if (inside == m_inside) return;
    m_inside = inside;
    emit containsPointerChanged();
}
