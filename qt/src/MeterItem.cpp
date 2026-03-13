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

    // Track background
    QPainterPath trackPath;
    trackPath.addRoundedRect(QRectF(0, 0, w, h), radius, radius);
    painter->fillPath(trackPath, Qt::transparent);

    // Active fill
    if (m_level > 0.001f) {
        qreal fillWidth = w * qBound(0.0f, m_level, 1.0f);
        QPainterPath fillPath;
        fillPath.addRoundedRect(QRectF(0, 0, fillWidth, h), radius, radius);

        QColor fillColor = m_clipping ? QColor(255, 80, 80) : m_barColor;
        painter->fillPath(fillPath, fillColor);
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
