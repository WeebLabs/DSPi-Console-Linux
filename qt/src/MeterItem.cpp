#include "MeterItem.h"
#include <QPainter>
#include <QPainterPath>

MeterItem::MeterItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void MeterItem::paint(QPainter *painter) {
    qreal w = width();
    qreal h = height();
    qreal radius = 2.0;

    // Level fill in the channel colour; at silence it shrinks to a dot so
    // every channel still shows its colour (as on the macOS Console).
    qreal fillWidth = qMax(h, w * qBound(0.0f, m_level, 1.0f));
    QPainterPath fillPath;
    fillPath.addRoundedRect(QRectF(0, 0, fillWidth, h), radius, radius);
    painter->fillPath(fillPath, m_barColor);

    // Clip marker at the right end of the meter
    if (m_clipping) {
        QPainterPath clipPath;
        clipPath.addRoundedRect(QRectF(w - h * 1.5, 0, h * 1.5, h), radius, radius);
        painter->fillPath(clipPath, QColor(255, 69, 58));
    }
}

void MeterItem::setLevel(float v) {
    if (m_level != v) {
        m_level = v;
        emit levelChanged();
        update();
    }
}

void MeterItem::setClipping(bool v) {
    if (m_clipping != v) {
        m_clipping = v;
        emit clippingChanged();
        update();
    }
}

void MeterItem::setBarColor(const QColor &c) {
    if (m_barColor != c) {
        m_barColor = c;
        emit barColorChanged();
        update();
    }
}
