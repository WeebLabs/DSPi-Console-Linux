#ifndef POINTERTRACKER_H
#define POINTERTRACKER_H

#include <QQuickItem>
#include <QPointer>

// Whether the pointer is over this item, whatever is on top of it. Qt Quick
// hands hover to the topmost item that takes it, so a HoverHandler or
// MouseArea under the graph editor or a band chip misses the pointer coming
// in; this watches the window's own pointer moves instead. `containsPointer`
// changes only when the pointer crosses the item's edge.
class PointerTracker : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(bool containsPointer READ containsPointer NOTIFY containsPointerChanged)

public:
    explicit PointerTracker(QQuickItem *parent = nullptr);
    bool containsPointer() const { return m_inside; }

signals:
    void containsPointerChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void setInside(bool inside);

    QPointer<QQuickWindow> m_window;
    bool m_inside = false;
};

#endif // POINTERTRACKER_H
