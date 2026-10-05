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
        connect(m_bridge, &DSPiBridge::previewChanged, this, &BodePlotItem::refreshNow);
        refresh();
    }
}

// The curves as they'd be drawn now from the bridge's state
QVector<ChannelCurve> BodePlotItem::buildCurves() const {
    QVector<ChannelCurve> curves;
    for (int eqCh = 0; eqCh < kAppChannelCount; eqCh++) {
        if (!m_bridge->channelExists(eqCh) || !isShown(eqCh)) continue;
        if (eqCh == m_excludeChannel) continue;     // drawn by the editor

        ChannelCurve curve;
        curve.color = QColor(m_bridge->channelColor(eqCh));
        curve.visible = true;

        // Curves include the output gain or the input preamp
        curve.gainOffset = m_bridge->channelGainOffset(eqCh);

        double mags[MAGNITUDE_POINTS];
        m_bridge->getMagnitudeCurve(eqCh, mags);
        curve.magnitudes.resize(MAGNITUDE_POINTS);
        for (int i = 0; i < MAGNITUDE_POINTS; i++) {
            curve.magnitudes[i] = mags[i] + curve.gainOffset;
        }
        curves.append(curve);
    }
    return curves;
}

static bool sameCurves(const QVector<ChannelCurve> &a, const QVector<ChannelCurve> &b) {
    if (a.size() != b.size()) return false;
    for (int i = 0; i < a.size(); i++)
        if (a[i].color != b[i].color || a[i].magnitudes != b[i].magnitudes) return false;
    return true;
}

// What's on screen mid-animation: current blended toward target
QVector<ChannelCurve> BodePlotItem::shownCurves() const {
    if (m_animProgress >= 1.0f) return m_targetCurves;
    QVector<ChannelCurve> shown = m_targetCurves;
    for (int i = 0; i < shown.size() && i < m_currentCurves.size(); i++) {
        const auto &from = m_currentCurves[i].magnitudes;
        auto &to = shown[i].magnitudes;
        for (int j = 0; j < to.size() && j < from.size(); j++)
            to[j] = from[j] + (to[j] - from[j]) * m_animProgress;
    }
    return shown;
}

// bridge.stateChanged fires for many edits that don't touch the graph:
// rebuilding the curves is cheap (magnitudes are cached), so compare and do
// nothing — no animation, no repaint — unless a curve actually changed.
void BodePlotItem::refresh() {
    if (!m_bridge) return;
    updatePhase();
    QVector<ChannelCurve> next = buildCurves();
    if (sameCurves(next, m_targetCurves)) return;

    if (m_targetCurves.isEmpty()) {
        m_animProgress = 1.0f;
        m_currentCurves = m_targetCurves = next;
        update();
        return;
    }
    // Animate from what's on screen now to the new curves
    m_currentCurves = shownCurves();
    m_targetCurves = next;
    m_animProgress = 0.0f;
    m_animation->stop();
    m_animation->start();
}

void BodePlotItem::refreshNow() {
    if (!m_bridge) return;
    QVector<ChannelCurve> next = buildCurves();
    if (sameCurves(next, m_targetCurves) && m_animProgress >= 1.0f) return;
    m_animation->stop();
    m_animProgress = 1.0f;
    m_currentCurves = m_targetCurves = next;
    update();
}

void BodePlotItem::paint(QPainter *painter) {
    QRectF rect(0, 0, width(), height());
    painter->setRenderHint(QPainter::Antialiasing);

    if (m_layer != CurveLayer) drawGrid(painter, rect);
    if (m_layer != GridLayer) {
        drawCurves(painter, rect);
        drawPhase(painter, rect);
    }
    if (m_layer != CurveLayer) drawLabels(painter, rect);
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

// A grid line's alpha at the user's grid strength (0.5 = as designed)
QColor BodePlotItem::gridColor(int alpha) const {
    return QColor(255, 255, 255, qBound(0, int(std::lround(alpha * m_gridOpacity * 2.0f)), 255));
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
        QPen majorPen(gridColor(38), 1.0);
        painter->setPen(majorPen);
        for (float f : majorFreqs) {
            if (f >= m_minFreq && f <= m_maxFreq) {
                qreal x = xForFreq(f, w);
                painter->drawLine(QPointF(x, 0), QPointF(x, h));
            }
        }

        // Minor lines (white 6%)
        QPen minorPen(gridColor(15), 1.0);
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

        QPen dbPen(gridColor(26), 1.0);
        painter->setPen(dbPen);
        for (float db = startDB; db <= m_dbTop; db += step) {
            if (std::abs(db) > 0.01f) { // skip 0dB
                qreal y = yForDb(db, h);
                painter->drawLine(QPointF(0, y), QPointF(w, y));
            }
        }

        // 0dB reference (30% opacity)
        if (m_dbBottom <= 0 && m_dbTop >= 0) {
            QPen zeroPen(gridColor(77), 1.0);
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
bool BodePlotItem::isShown(int eqCh) const {
    return m_followVisibility ? m_bridge->channelVisible(eqCh) : m_shown.contains(eqCh);
}

void BodePlotItem::setFollowVisibility(bool v) {
    if (m_followVisibility == v) return;
    m_followVisibility = v;
    emit settingsChanged();
    updatePhase();
    refreshNow();
}

void BodePlotItem::setShownChannels(const QVariantList &l) {
    if (l == m_shownList) return;
    m_shownList = l;
    m_shown.clear();
    for (const QVariant &v : l) m_shown.append(v.toInt());
    emit settingsChanged();
    if (!m_followVisibility) { updatePhase(); refreshNow(); }
}

void BodePlotItem::setDrawLayer(int v) { if (m_layer != v) { m_layer = v; emit settingsChanged(); update(); } }
void BodePlotItem::setGridOpacity(float v) { if (m_gridOpacity != v) { m_gridOpacity = v; emit settingsChanged(); update(); } }
void BodePlotItem::setLineWidth(float v) { if (m_lineWidth != v) { m_lineWidth = v; emit settingsChanged(); update(); } }

void BodePlotItem::setExcludeChannel(int ch) { if (m_excludeChannel != ch) { m_excludeChannel = ch; emit settingsChanged(); refreshNow(); } }
void BodePlotItem::setShowPhase(bool v) { if (m_showPhase != v) { m_showPhase = v; emit settingsChanged(); updatePhase(); update(); } }
void BodePlotItem::setPhaseUnwrapped(bool v) { if (m_phaseUnwrapped != v) { m_phaseUnwrapped = v; emit settingsChanged(); updatePhase(); update(); } }
void BodePlotItem::setPhaseChannel(int ch) { if (m_phaseChannel != ch) { m_phaseChannel = ch; emit settingsChanged(); updatePhase(); update(); } }

// The phase trace follows committed changes (not a drag in progress)
void BodePlotItem::updatePhase() {
    QVector<double> next;
    if (m_bridge && m_showPhase && m_phaseChannel >= 0 && m_bridge->channelExists(m_phaseChannel)
        && isShown(m_phaseChannel)) {
        next.resize(MAGNITUDE_POINTS);
        m_bridge->getPhaseCurve(m_phaseChannel, m_phaseUnwrapped, next.data());
    }
    if (next != m_phase) { m_phase = next; update(); }
}

// Dotted phase trace and its degree axis on the right. The axis scales with
// the dB range, as on macOS: +-180 degrees at the default 50 dB.
void BodePlotItem::drawPhase(QPainter *painter, const QRectF &rect) {
    if (m_phase.isEmpty()) return;
    double top = 180.0 * (m_dbTop - m_dbBottom) / 50.0;
    // Map degrees onto the dB scale, centred on the middle of the view
    double mid = (m_dbTop + m_dbBottom) / 2.0, half = (m_dbTop - m_dbBottom) / 2.0;
    QVector<double> asDb(m_phase.size());
    for (int i = 0; i < m_phase.size(); i++) asDb[i] = mid + m_phase[i] / top * half;
    QPainterPath path = buildCurvePath(asDb, rect);
    QPen pen(QColor(237, 237, 237), m_lineWidth * 0.9, Qt::CustomDashLine, Qt::RoundCap);
    pen.setDashPattern({0.1, 3.0});
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    painter->drawPath(path);

    QFont font = painter->font();
    font.setPixelSize(9);
    font.setWeight(QFont::Medium);
    painter->setFont(font);
    painter->setPen(QColor(237, 237, 237, 140));
    for (double deg : {top, top / 2, 0.0, -top / 2, -top}) {
        qreal y = yForDb(float(mid + deg / top * half), rect.height());
        QString t = deg == 0 ? QString("0\u00b0") : QString::asprintf("%+.0f\u00b0", deg);
        painter->drawText(QRectF(rect.width() - 64, y - 7, 60, 14), Qt::AlignRight | Qt::AlignVCenter, t);
    }
}
