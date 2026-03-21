#include "BodePlotItem.h"
#include "DSPiBridge.h"
#include <QPainterPath>
#include <cmath>

BodePlotItem::BodePlotItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setRenderTarget(QQuickPaintedItem::Image);

    m_animation = new QVariantAnimation(this);
    m_animation->setDuration(200);
    m_animation->setEasingCurve(QEasingCurve::OutCubic);
    m_animation->setStartValue(0.0f);
    m_animation->setEndValue(1.0f);
    connect(m_animation, &QVariantAnimation::valueChanged, this, [this](const QVariant &val) {
        m_animProgress = val.toFloat();
        update();
    });
}

void BodePlotItem::setBridge(QObject *bridge) {
    m_bridge = qobject_cast<DSPiBridge*>(bridge);
    if (m_bridge) {
        connect(m_bridge, &DSPiBridge::magnitudesChanged, this, &BodePlotItem::refresh);
        connect(m_bridge, &DSPiBridge::stateChanged, this, &BodePlotItem::refresh);
        refresh();
    }
}

void BodePlotItem::refresh() {
    if (!m_bridge) return;

    // Save current curves for animation
    m_currentCurves.clear();
    if (m_animProgress < 1.0f) {
        // Mid-animation: interpolate current state as starting point
        for (int i = 0; i < m_targetCurves.size(); i++) {
            ChannelCurve c = m_targetCurves[i];
            if (i < m_currentCurves.size()) {
                for (int j = 0; j < c.magnitudes.size() && j < m_currentCurves[i].magnitudes.size(); j++) {
                    c.magnitudes[j] = m_currentCurves[i].magnitudes[j] +
                        (m_targetCurves[i].magnitudes[j] - m_currentCurves[i].magnitudes[j]) * m_animProgress;
                }
            }
            m_currentCurves.append(c);
        }
    } else {
        m_currentCurves = m_targetCurves;
    }

    // Build new target curves
    m_targetCurves.clear();
    int numCh = m_bridge->numChannels();

    for (int eqCh = 0; eqCh < numCh; eqCh++) {
        if (!m_bridge->channelVisible(eqCh)) continue;

        ChannelCurve curve;
        curve.color = QColor(m_bridge->channelColor(eqCh));
        curve.visible = true;

        // Get gain offset for output channels
        if (eqCh >= 2) {
            curve.gainOffset = m_bridge->outputGainDB(eqCh - 2);
        }

        double mags[MAGNITUDE_POINTS];
        m_bridge->getMagnitudeCurve(eqCh, mags);
        curve.magnitudes.resize(MAGNITUDE_POINTS);
        for (int i = 0; i < MAGNITUDE_POINTS; i++) {
            curve.magnitudes[i] = mags[i] + curve.gainOffset;
        }

        m_targetCurves.append(curve);
    }

    // Start animation
    if (!m_currentCurves.isEmpty()) {
        m_animProgress = 0.0f;
        m_animation->stop();
        m_animation->start();
    } else {
        m_animProgress = 1.0f;
        m_currentCurves = m_targetCurves;
        update();
    }
}

void BodePlotItem::paint(QPainter *painter) {
    QRectF rect(0, 0, width(), height());
    painter->setRenderHint(QPainter::Antialiasing);

    drawGrid(painter, rect);
    drawCurves(painter, rect);
    drawLabels(painter, rect);
}

qreal BodePlotItem::xForFreq(float freq, qreal w) const {
    float logMin = std::log10(m_minFreq);
    float logMax = std::log10(m_maxFreq);
    float logVal = std::log10(freq);
    return static_cast<qreal>((logVal - logMin) / (logMax - logMin)) * w;
}

qreal BodePlotItem::yForDb(float db, qreal h) const {
    float normalized = (db - m_dbBottom) / (m_dbTop - m_dbBottom);
    return h - static_cast<qreal>(normalized) * h;
}

void BodePlotItem::drawGrid(QPainter *painter, const QRectF &rect) {
    qreal w = rect.width();
    qreal h = rect.height();

    // Frequency gridlines
    if (m_showFreqGrid) {
        static const float majorFreqs[] = {100.0f, 1000.0f, 10000.0f};
        static const float minorFreqs[] = {
            20, 30, 40, 50, 60, 70, 80, 90,
            200, 300, 400, 500, 600, 700, 800, 900,
            2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000,
            20000
        };

        // Major lines (white 15%)
        QPen majorPen(QColor(255, 255, 255, 38), 1.0);
        painter->setPen(majorPen);
        for (float f : majorFreqs) {
            if (f >= m_minFreq && f <= m_maxFreq) {
                qreal x = xForFreq(f, w);
                painter->drawLine(QPointF(x, 0), QPointF(x, h));
            }
        }

        // Minor lines (white 6%)
        QPen minorPen(QColor(255, 255, 255, 15), 1.0);
        painter->setPen(minorPen);
        for (float f : minorFreqs) {
            if (f >= m_minFreq && f <= m_maxFreq) {
                bool isMajor = false;
                for (float mf : majorFreqs) if (f == mf) { isMajor = true; break; }
                if (!isMajor) {
                    qreal x = xForFreq(f, w);
                    painter->drawLine(QPointF(x, 0), QPointF(x, h));
                }
            }
        }
    }

    // dB gridlines
    if (m_showDbGrid) {
        float dbSpan = m_dbTop - m_dbBottom;
        float step = dbSpan <= 12 ? 1.0f : (dbSpan <= 30 ? 3.0f : (dbSpan <= 60 ? 5.0f : 10.0f));
        float startDB = std::ceil(m_dbBottom / step) * step;

        QPen dbPen(QColor(255, 255, 255, 26), 1.0);
        painter->setPen(dbPen);
        for (float db = startDB; db <= m_dbTop; db += step) {
            if (std::abs(db) > 0.01f) { // skip 0dB
                qreal y = yForDb(db, h);
                painter->drawLine(QPointF(0, y), QPointF(w, y));
            }
        }

        // 0dB reference (30% opacity)
        if (m_dbBottom <= 0 && m_dbTop >= 0) {
            QPen zeroPen(QColor(255, 255, 255, 77), 1.0);
            painter->setPen(zeroPen);
            qreal y = yForDb(0, h);
            painter->drawLine(QPointF(0, y), QPointF(w, y));
        }
    }
}

QPainterPath BodePlotItem::buildCurvePath(const QVector<double> &magnitudes, const QRectF &rect) {
    QPainterPath path;
    if (magnitudes.isEmpty()) return path;

    qreal w = rect.width();
    qreal h = rect.height();
    float dataLogMin = std::log10(10.0f);
    float dataLogMax = std::log10(20000.0f);
    float viewLogMin = std::log10(m_minFreq);
    float viewLogMax = std::log10(m_maxFreq);
    float viewLogSpan = viewLogMax - viewLogMin;

    int count = magnitudes.size();

    // Build point list
    QVector<QPointF> pts(count);
    for (int i = 0; i < count; i++) {
        float dataLog = dataLogMin + float(i) / float(count - 1) * (dataLogMax - dataLogMin);
        qreal x = static_cast<qreal>((dataLog - viewLogMin) / viewLogSpan) * w;
        float db = static_cast<float>(magnitudes[i]);
        float normalized = (db - m_dbBottom) / (m_dbTop - m_dbBottom);
        qreal y = h - static_cast<qreal>(normalized) * h;
        pts[i] = QPointF(x, y);
    }

    // Catmull-Rom → cubic Bezier spline for smooth curves
    path.moveTo(pts[0]);
    for (int i = 0; i < count - 1; i++) {
        QPointF p0 = pts[qMax(0, i - 1)];
        QPointF p1 = pts[i];
        QPointF p2 = pts[qMin(count - 1, i + 1)];
        QPointF p3 = pts[qMin(count - 1, i + 2)];

        QPointF cp1 = p1 + (p2 - p0) / 6.0;
        QPointF cp2 = p2 - (p3 - p1) / 6.0;
        path.cubicTo(cp1, cp2, p2);
    }
    return path;
}

void BodePlotItem::drawCurves(QPainter *painter, const QRectF &rect) {
    // Determine which curves to draw based on animation progress
    auto &fromCurves = m_currentCurves;
    auto &toCurves = m_targetCurves;
    float t = m_animProgress;

    for (int ci = 0; ci < toCurves.size(); ci++) {
        const auto &target = toCurves[ci];
        QVector<double> interpolated(MAGNITUDE_POINTS, 0.0);

        if (ci < fromCurves.size() && t < 1.0f) {
            // Interpolate between old and new
            const auto &from = fromCurves[ci];
            for (int i = 0; i < MAGNITUDE_POINTS; i++) {
                double fromVal = (i < from.magnitudes.size()) ? from.magnitudes[i] : 0.0;
                double toVal = (i < target.magnitudes.size()) ? target.magnitudes[i] : 0.0;
                interpolated[i] = fromVal + (toVal - fromVal) * t;
            }
        } else {
            interpolated = target.magnitudes;
        }

        QPainterPath path = buildCurvePath(interpolated, rect);

        // Glow effect
        if (m_showGlow) {
            QColor glowColor = target.color;
            glowColor.setAlphaF(0.3);
            QPen glowPen(glowColor, m_lineWidth * 4.0);
            glowPen.setCapStyle(Qt::RoundCap);
            glowPen.setJoinStyle(Qt::RoundJoin);
            painter->setPen(glowPen);
            painter->drawPath(path);

            glowColor.setAlphaF(0.6);
            QPen glow2Pen(glowColor, m_lineWidth * 2.0);
            glow2Pen.setCapStyle(Qt::RoundCap);
            glow2Pen.setJoinStyle(Qt::RoundJoin);
            painter->setPen(glow2Pen);
            painter->drawPath(path);
        }

        // Main curve
        QPen curvePen(target.color, m_lineWidth);
        curvePen.setCapStyle(Qt::RoundCap);
        curvePen.setJoinStyle(Qt::RoundJoin);
        painter->setPen(curvePen);
        painter->drawPath(path);
    }
}

void BodePlotItem::drawLabels(QPainter *painter, const QRectF &rect) {
    qreal w = rect.width();
    qreal h = rect.height();

    QFont labelFont;
    labelFont.setPointSize(9);
    labelFont.setWeight(QFont::Medium);
    painter->setFont(labelFont);

    // Frequency labels
    if (m_showFreqLabels) {
        struct FreqLabel { float freq; const char *text; };
        static const FreqLabel labels[] = {
            {20, "20"}, {50, "50"}, {100, "100"}, {200, "200"}, {500, "500"},
            {1000, "1k"}, {2000, "2k"}, {5000, "5k"}, {10000, "10k"}, {20000, "20k"}
        };

        painter->setPen(QColor(255, 255, 255, 102)); // 40% opacity
        for (const auto &lbl : labels) {
            if (lbl.freq >= m_minFreq && lbl.freq <= m_maxFreq) {
                qreal x = xForFreq(lbl.freq, w);
                QRectF textRect(x - 20, h - 14, 40, 14);
                painter->drawText(textRect, Qt::AlignHCenter | Qt::AlignBottom, lbl.text);
            }
        }
    }

    // dB labels
    if (m_showDbLabels) {
        float dbSpan = m_dbTop - m_dbBottom;
        float step = dbSpan <= 12 ? 1.0f : (dbSpan <= 30 ? 3.0f : (dbSpan <= 60 ? 5.0f : 10.0f));
        float startDB = std::ceil(m_dbBottom / step) * step;

        painter->setPen(QColor(255, 255, 255, 102));
        for (float db = startDB; db <= m_dbTop; db += step) {
            qreal y = yForDb(db, h);
            QString label = db >= 0 ? QString("+%1").arg(db, 0, 'g', 4) :
                                      QString("%1").arg(db, 0, 'g', 4);
            QRectF textRect(4, y - 7, 40, 14);
            painter->drawText(textRect, Qt::AlignLeft | Qt::AlignVCenter, label);
        }
    }
}

// ── Property setters ──

void BodePlotItem::setDbTop(float v) { if (m_dbTop != v) { m_dbTop = v; emit settingsChanged(); update(); } }
void BodePlotItem::setDbBottom(float v) { if (m_dbBottom != v) { m_dbBottom = v; emit settingsChanged(); update(); } }
void BodePlotItem::setMinFreq(float v) { if (m_minFreq != v) { m_minFreq = v; emit settingsChanged(); update(); } }
void BodePlotItem::setMaxFreq(float v) { if (m_maxFreq != v) { m_maxFreq = v; emit settingsChanged(); update(); } }
void BodePlotItem::setShowGlow(bool v) { if (m_showGlow != v) { m_showGlow = v; emit settingsChanged(); update(); } }
void BodePlotItem::setShowFreqGrid(bool v) { if (m_showFreqGrid != v) { m_showFreqGrid = v; emit settingsChanged(); update(); } }
void BodePlotItem::setShowDbGrid(bool v) { if (m_showDbGrid != v) { m_showDbGrid = v; emit settingsChanged(); update(); } }
void BodePlotItem::setShowFreqLabels(bool v) { if (m_showFreqLabels != v) { m_showFreqLabels = v; emit settingsChanged(); update(); } }
void BodePlotItem::setShowDbLabels(bool v) { if (m_showDbLabels != v) { m_showDbLabels = v; emit settingsChanged(); update(); } }
void BodePlotItem::setLineWidth(float v) { if (m_lineWidth != v) { m_lineWidth = v; emit settingsChanged(); update(); } }
