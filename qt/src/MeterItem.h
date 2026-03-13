#ifndef METERITEM_H
#define METERITEM_H

#include <QQuickPaintedItem>
#include <QColor>

class MeterItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(float level READ level WRITE setLevel NOTIFY levelChanged)
    Q_PROPERTY(bool clipping READ clipping WRITE setClipping NOTIFY clippingChanged)
    Q_PROPERTY(QColor barColor READ barColor WRITE setBarColor NOTIFY barColorChanged)

public:
    explicit MeterItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    float level() const { return m_level; }
    bool clipping() const { return m_clipping; }
    QColor barColor() const { return m_barColor; }

    void setLevel(float v);
    void setClipping(bool v);
    void setBarColor(const QColor &c);

signals:
    void levelChanged();
    void clippingChanged();
    void barColorChanged();

private:
    float m_level = 0.0f;
    bool m_clipping = false;
    QColor m_barColor = QColor(74, 143, 227);
};

#endif // METERITEM_H
