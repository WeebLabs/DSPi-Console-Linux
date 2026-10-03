#ifndef TEXTFOCUSRELEASER_H
#define TEXTFOCUSRELEASER_H

#include <QKeyEvent>
#include <QMouseEvent>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>

// Clicking anywhere outside a focused text field, or pressing Return/Enter in
// a single-line field, takes focus away from it (committing the edit), in
// every window: number fields, renames, search.
class TextFocusReleaser : public QObject
{
public:
    using QObject::QObject;

    // Focus goes to an invisible item, created once per window: forcing focus
    // onto the window's root item is a no-op (it already holds focus as the
    // field's scope), so the field would keep it.
    static void release(QQuickWindow *window)
    {
        QQuickItem *root = window->contentItem();
        auto *sink = root->findChild<QQuickItem *>(QStringLiteral("__focusSink"), Qt::FindDirectChildrenOnly);
        if (!sink) {
            sink = new QQuickItem(root);
            sink->setObjectName(QStringLiteral("__focusSink"));
        }
        sink->forceActiveFocus(Qt::OtherFocusReason);
    }

protected:
    bool eventFilter(QObject *obj, QEvent *event) override
    {
        if (event->type() == QEvent::MouseButtonPress) {
            if (auto *window = qobject_cast<QQuickWindow *>(obj)) {
                QQuickItem *focus = window->activeFocusItem();
                if (focus && (focus->inherits("QQuickTextInput") || focus->inherits("QQuickTextEdit"))) {
                    auto *press = static_cast<QMouseEvent *>(event);
                    QRectF area = focus->mapRectToScene(QRectF(0, 0, focus->width(), focus->height()));
                    if (!area.contains(press->windowPos()))
                        release(window);
                }
            }
        } else if (event->type() == QEvent::KeyPress) {
            auto *key = static_cast<QKeyEvent *>(event);
            if (key->key() == Qt::Key_Return || key->key() == Qt::Key_Enter) {
                if (auto *window = qobject_cast<QQuickWindow *>(obj)) {
                    QQuickItem *focus = window->activeFocusItem();
                    if (focus && focus->inherits("QQuickTextInput")) {
                        // Let the field handle Enter (commit) first, then release it
                        QPointer<QQuickItem> field(focus);
                        QTimer::singleShot(0, window, [window, field]() {
                            if (field && window->activeFocusItem() == field)
                                release(window);
                        });
                    }
                }
            }
        }
        return QObject::eventFilter(obj, event);
    }
};

#endif // TEXTFOCUSRELEASER_H
