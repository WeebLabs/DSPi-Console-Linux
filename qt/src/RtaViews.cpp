#include "RtaViews.h"

#include <QPainter>
#include <QPainterPath>
#include <QLinearGradient>
#include <QFontMetricsF>
#include <cmath>
#include <limits>
#ifdef Q_OS_MACOS
#include "MacSystemColors.h"

// secondaryLabelColor as AppKit resolves it (SwiftUI .secondary), read once
static QColor macSecondary(qreal opacity) {
    static const QColor base = [] {
        const QVariant v = macSystemColors().value(QStringLiteral("secondaryLabel"));
        return v.isValid() ? v.value<QColor>() : QColor::fromRgbF(1, 1, 1, 0.549);
    }();
    QColor c = base;
    c.setAlphaF(base.alphaF() * opacity);
    return c;
}
#endif

static const qreal kNaN = std::numeric_limits<qreal>::quiet_NaN();

static quint64 identityOf(int tap, int channel, int count, int extra = 0) {
    return (quint64(tap & 0xFF) << 48) | (quint64(channel & 0xFF) << 40) | (quint64(count & 0xFFFF) << 24)
         | quint64(extra & 0xFFFFFF);
}

// ── RtaSmoother ──

void RtaSmoother::setTarget(const QVector<float> &target, quint64 identity) {
    if (identity != m_identity || target.size() != m_values.size()) {
        m_identity = identity;
        m_values = target;
        m_target = target;
        m_settled = true;
        return;
    }
    if (m_settled) m_clock.start();
    m_target = target;
    m_settled = m_values == m_target;
}

bool RtaSmoother::step(double fallTau, int peakFrom) {
    if (m_settled) return false;
    double dt = 1.0 / 60;
    if (m_clock.isValid()) dt = qMin(0.1, m_clock.restart() / 1000.0);
    else m_clock.start();
    bool moving = false;
    for (int i = 0; i < m_values.size(); i++) {
        float &v = m_values[i];
        const float t = m_target[i];
        if (v == t) continue;
        double tau = fallTau;
        if (t > v) tau = i >= peakFrom ? 0.0 : fallTau * 0.4;     // peaks jump up
        if (tau <= 0) { v = t; continue; }
        v += float((t - v) * (1.0 - std::exp(-dt / tau)));
        if (std::fabs(t - v) < 0.05f) v = t;
        else moving = true;
    }
    m_settled = !moving;
    return moving;
}

// ── RtaViewBase ──

RtaViewBase::RtaViewBase(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    m_tick.setInterval(16);
    connect(&m_tick, &QTimer::timeout, this, &RtaViewBase::onTick);
}

RtaViewBase::~RtaViewBase() {
    if (m_rta && m_sub) m_rta->release(m_sub);
}

void RtaViewBase::setController(QObject *c) {
    auto *rta = qobject_cast<RtaController *>(c);
    if (rta == m_rta) return;
    if (m_rta) {
        if (m_sub) m_rta->release(m_sub);
        m_sub = 0;
        disconnect(m_rta, nullptr, this, nullptr);
    }
    m_rta = rta;
    if (m_rta) {
        connect(m_rta, &RtaController::frameChanged, this, &RtaViewBase::onFrame);
        connect(m_rta, &RtaController::capsChanged, this, &RtaViewBase::resubscribe);
    }
    emit controllerChanged();
    resubscribe();
}

void RtaViewBase::setActive(bool a) { if (a != m_active) { m_active = a; emit activeChanged(); resubscribe(); } }
void RtaViewBase::setTap(int t) { if (t != m_tap) { m_tap = t; emit sourceChanged(); resubscribe(); } }
void RtaViewBase::setFloorDb(qreal v) { if (v != m_floorDb) { m_floorDb = v; emit styleChanged(); update(); } }
void RtaViewBase::setCeilingDb(qreal v) { if (v != m_ceilingDb) { m_ceilingDb = v; emit styleChanged(); update(); } }
void RtaViewBase::setShowPeak(bool v) { if (v != m_showPeak) { m_showPeak = v; emit styleChanged(); update(); } }
void RtaViewBase::setSmoothing(bool v) { if (v != m_smoothing) { m_smoothing = v; emit styleChanged(); } }

void RtaViewBase::itemChange(ItemChange change, const ItemChangeData &value) {
    QQuickPaintedItem::itemChange(change, value);
    if (change == ItemVisibleHasChanged) resubscribe();
}

// Subscribed only while shown: hidden views cost the device nothing
void RtaViewBase::resubscribe() {
    const int mask = channelMask();
    const bool want = m_rta && m_active && isVisible() && mask;
    if (want) {
        if (m_sub) m_rta->update(m_sub, m_tap, mask, wantsBins());
        else m_sub = m_rta->subscribe(m_tap, mask, wantsBins());
    } else if (m_sub) {
        if (m_rta) m_rta->release(m_sub);
        m_sub = 0;
    }
    onFrame();
}

double RtaViewBase::fallTau() const {
    if (!m_smoothing || !m_rta) return 0.0;
    return qBound(0.035, m_rta->refreshInterval() * 0.35, 0.40);
}

qreal RtaViewBase::yForDb(qreal db, qreal top, qreal bottom) const {
    qreal span = qMax<qreal>(1, m_ceilingDb - m_floorDb);
    qreal n = qBound<qreal>(0, (db - m_floorDb) / span, 1);
    return bottom - n * (bottom - top);
}

void RtaViewBase::onFrame() {
    if (m_sub && m_rta) {
        takeFrame();
        m_populated = m_rta->snapshot().tap == m_tap ? m_rta->snapshot().populated : 0;
    } else {
        takeFrame();          // nothing subscribed: clears the targets
        m_populated = 0;
    }
    if (fallTau() > 0) {
        if (stepSmoothing(fallTau()) && !m_tick.isActive()) m_tick.start();
    } else {
        stepSmoothing(0);
    }
    update();
}

void RtaViewBase::onTick() {
    bool moving = stepSmoothing(fallTau());
    update();
    if (!moving) m_tick.stop();
}

// Frame for channel `ch` at this view's tap, or null
static const RtaChannelFrame *frameFor(const RtaSnapshot &s, int tap, int ch) {
    if (s.tap != tap) return nullptr;
    for (int i = 0; i < s.count && i < RTA_MAX_CHANNELS; i++)
        if (s.frames[i].channel == ch) return &s.frames[i];
    return nullptr;
}

static QVector<float> levelsOf(const RtaChannelFrame *f) {
    QVector<float> v;
    if (!f) return v;
    int n = qMin<int>(f->n_bands, RTA_MAX_BANDS);
    v.resize(2 * n);
    for (int b = 0; b < n; b++) {
        v[b] = f->avg_db[b];
        v[n + b] = f->peak_db[b];
    }
    return v;
}

// ── SpectrumCurveItem ──

SpectrumCurveItem::SpectrumCurveItem(QQuickItem *parent) : RtaViewBase(parent) {}

void SpectrumCurveItem::setChannels(const QVariantList &l) {
    if (l == m_channelList) return;
    m_channelList = l;
    m_channels.clear();
    for (const QVariant &v : l) m_channels.append(v.toInt());
    m_bands.resize(m_channels.size());
    emit sourceChanged();
    resubscribe();
}

void SpectrumCurveItem::setColors(const QVariantList &l) {
    if (l == m_colorList) return;
    m_colorList = l;
    m_colors.clear();
    for (const QVariant &v : l) m_colors.append(QColor(v.toString()));
    emit styleChanged();
    update();
}

void SpectrumCurveItem::setHidden(const QVariantList &l) {
    if (l == m_hiddenList) return;
    m_hiddenList = l;
    m_hiddenSet.clear();
    for (const QVariant &v : l) m_hiddenSet.append(v.toInt());
    emit styleChanged();
    update();
}

void SpectrumCurveItem::setMinFreq(qreal v) { if (v != m_minFreq) { m_minFreq = v; emit styleChanged(); update(); } }
void SpectrumCurveItem::setMaxFreq(qreal v) { if (v != m_maxFreq) { m_maxFreq = v; emit styleChanged(); update(); } }
void SpectrumCurveItem::setStrength(qreal v) { if (v != m_strength) { m_strength = v; emit styleChanged(); update(); } }
void SpectrumCurveItem::setGlow(bool v) { if (v != m_glow) { m_glow = v; emit styleChanged(); update(); } }
void SpectrumCurveItem::setBottomInset(qreal v) { if (v != m_bottomInset) { m_bottomInset = v; emit styleChanged(); update(); } }

int SpectrumCurveItem::channelMask() const {
    int m = 0;
    for (int c : m_channels) if (c >= 0 && c < 16) m |= 1 << c;
    return m;
}

void SpectrumCurveItem::takeFrame() {
    const bool live = m_rta && channelMask() && m_active && isVisible();
    for (int i = 0; i < m_channels.size(); i++) {
        const RtaChannelFrame *f = live ? frameFor(m_rta->snapshot(), m_tap, m_channels[i]) : nullptr;
        m_bands[i].setTarget(levelsOf(f), identityOf(m_tap, m_channels[i], f ? f->n_bands : 0));
    }
    QVector<float> bins;
    m_binsRate = 0;
    if (live && m_channels.size() == 1) {
        const RtaSnapshot &s = m_rta->snapshot();
        if (s.tap == m_tap && s.bins_count > 0 && s.bins_channel == m_channels[0]) {
            bins = QVector<float>(s.bins_db, s.bins_db + s.bins_count);
            m_binsRate = int(s.bins_sample_rate);
        }
    }
    m_bins.setTarget(bins, identityOf(m_tap, m_channels.value(0, -1), bins.size(), m_binsRate / 100));
}

bool SpectrumCurveItem::stepSmoothing(double tau) {
    bool moving = false;
    for (RtaSmoother &s : m_bands) moving |= s.step(tau, s.values().size() / 2);
    moving |= m_bins.step(tau, std::numeric_limits<int>::max());
    return moving;
}

qreal SpectrumCurveItem::xForFreq(double f) const {
    double lo = std::log10(m_minFreq), hi = std::log10(m_maxFreq);
    return (std::log10(qMax(f, 1.0)) - lo) / (hi - lo) * width();
}

static const qreal kColumnStep = 2.0;

// 3x3 box blur in place (premultiplied ARGB), for the glow
static void boxBlur(QImage &img) {
    const int w = img.width(), h = img.height();
    if (w < 3 || h < 3) return;
    QImage src = img.copy();
    for (int y = 0; y < h; y++) {
        QRgb *out = reinterpret_cast<QRgb *>(img.scanLine(y));
        for (int x = 0; x < w; x++) {
            int a = 0, r = 0, g = 0, b = 0, n = 0;
            for (int dy = -1; dy <= 1; dy++) {
                int yy = y + dy;
                if (yy < 0 || yy >= h) continue;
                const QRgb *in = reinterpret_cast<const QRgb *>(src.constScanLine(yy));
                for (int dx = -1; dx <= 1; dx++) {
                    int xx = x + dx;
                    if (xx < 0 || xx >= w) continue;
                    QRgb c = in[xx];
                    a += qAlpha(c); r += qRed(c); g += qGreen(c); b += qBlue(c); n++;
                }
            }
            out[x] = qRgba(r / n, g / n, b / n, a / n);
        }
    }
}

// Catmull-Rom through the band points (x, dB), evaluated per pixel column,
// with the FFT bins taking over above the bass bank (one octave crossfade).
QVector<qreal> SpectrumCurveItem::columnLevels(const QVector<float> &levels, const float *bins, int nBins,
                                               int sampleRate, bool peaks) const {
    const int cols = int(std::ceil(width() / kColumnStep)) + 1;
    QVector<qreal> out(cols, kNaN);
    const int nb = levels.size() / 2;
    if (nb == 0 || !m_rta) return out;
    const RtaCapsInfo &caps = m_rta->caps();

    // Band points; one beyond each edge keeps the curve running off the plot
    QVector<QPointF> pts;
    for (int b = 0; b < nb; b++) {
        if (!(m_populated >> b & 1)) continue;
        pts.append(QPointF(xForFreq(caps.centres[b]), levels[peaks ? nb + b : b]));
    }
    while (pts.size() > 2 && pts[1].x() < 0) pts.removeFirst();
    while (pts.size() > 2 && pts[pts.size() - 2].x() > width()) pts.removeLast();

    if (pts.size() >= 2) {
        int seg = 0;
        for (int c = 0; c < cols; c++) {
            qreal x = c * kColumnStep;
            if (x < pts.first().x() || x > pts.last().x()) continue;
            while (seg < pts.size() - 2 && x > pts[seg + 1].x()) seg++;
            const QPointF &p1 = pts[seg], &p2 = pts[seg + 1];
            const qreal y0 = pts[qMax(0, seg - 1)].y(), y3 = pts[qMin(pts.size() - 1, seg + 2)].y();
            qreal t = (x - p1.x()) / qMax<qreal>(1e-6, p2.x() - p1.x());
            qreal t2 = t * t, t3 = t2 * t;
            out[c] = 0.5 * ((2 * p1.y()) + (-y0 + p2.y()) * t + (2 * y0 - 5 * p1.y() + 4 * p2.y() - y3) * t2
                            + (-y0 + 3 * p1.y() - 3 * p2.y() + y3) * t3);
        }
    }

    if (peaks || !bins || nBins < 2 || sampleRate <= 0 || caps.bass_bands < 1) return out;

    // Bins: the loudest in each column, gaps filled across
    QVector<qreal> binCol(cols, kNaN);
    const double df = sampleRate / (2.0 * nBins);
    for (int k = 1; k < nBins; k++) {
        qreal x = xForFreq(k * df);
        if (x < -kColumnStep || x > width() + kColumnStep) continue;
        int c = qBound(0, int(std::lround(x / kColumnStep)), cols - 1);
        if (std::isnan(binCol[c]) || bins[k] > binCol[c]) binCol[c] = bins[k];
    }
    int last = -1;
    for (int c = 0; c < cols; c++) {
        if (std::isnan(binCol[c])) continue;
        if (last >= 0 && c - last > 1)
            for (int j = last + 1; j < c; j++)
                binCol[j] = binCol[last] + (binCol[c] - binCol[last]) * (j - last) / qreal(c - last);
        last = c;
    }

    // Crossfade from the top of the bass bank to two bands above it
    const int bb = caps.bass_bands;
    const double fLo = caps.centres[qMax(0, bb - 1)], fHi = caps.centres[qMin(RTA_MAX_BANDS - 1, bb + 2)];
    const double lLo = std::log10(fLo), lHi = std::log10(fHi);
    const double lo = std::log10(m_minFreq), hi = std::log10(m_maxFreq);
    for (int c = 0; c < cols; c++) {
        double f = std::pow(10.0, lo + (c * kColumnStep / width()) * (hi - lo));
        double w = qBound(0.0, (std::log10(f) - lLo) / (lHi - lLo), 1.0);
        w = w * w * (3 - 2 * w);
        if (std::isnan(binCol[c])) continue;
        if (std::isnan(out[c])) out[c] = w > 0.999 ? binCol[c] : kNaN;
        else out[c] = out[c] * (1 - w) + binCol[c] * w;
    }
    return out;
}

void SpectrumCurveItem::paint(QPainter *p) {
    if (!m_rta || width() < 4 || height() < 4) return;
    p->setRenderHint(QPainter::Antialiasing);
    const qreal bottom = height() - m_bottomInset;
    const qreal o = qBound<qreal>(0, m_strength, 1);

    struct Curve { QPainterPath line, fill, peak; QColor color; };
    QVector<Curve> curves;
    qreal dataStart = width();

    auto pathsOf = [&](const QVector<qreal> &cols, QPainterPath &line, QPainterPath *fill) {
        int c = 0;
        const int n = cols.size();
        while (c < n) {
            while (c < n && std::isnan(cols[c])) c++;
            if (c >= n) break;
            int start = c;
            QPolygonF poly;
            while (c < n && !std::isnan(cols[c])) {
                poly << QPointF(qMin(c * kColumnStep, width()), yForDb(cols[c], 0, bottom));
                c++;
            }
            dataStart = qMin(dataStart, start * kColumnStep);
            line.addPolygon(poly);
            if (fill) {
                QPolygonF area = poly;
                area << QPointF(poly.last().x(), bottom) << QPointF(poly.first().x(), bottom);
                fill->addPolygon(area);
                fill->closeSubpath();
            }
        }
    };

    for (int i = 0; i < m_channels.size(); i++) {
        if (m_hiddenSet.contains(m_channels[i])) continue;
        const QVector<float> &lv = m_bands[i].values();
        if (lv.isEmpty()) continue;
        const bool withBins = m_channels.size() == 1 && !m_bins.values().isEmpty();
        Curve cv;
        cv.color = m_colors.value(i, QColor(Qt::white));
        pathsOf(columnLevels(lv, withBins ? m_bins.values().constData() : nullptr,
                             withBins ? m_bins.values().size() : 0, m_binsRate, false),
                cv.line, &cv.fill);
        if (m_showPeak) pathsOf(columnLevels(lv, nullptr, 0, 0, true), cv.peak, nullptr);
        curves.append(cv);
    }
    if (curves.isEmpty()) return;

    // Data that starts inside the plot fades in over 30 px
    const bool fade = dataStart > 1 && dataStart < width();
    QImage layer;
    QPainter lp;
    QPainter *dp = p;
    if (fade) {
        layer = QImage(QSize(int(std::ceil(width())), int(std::ceil(height()))), QImage::Format_ARGB32_Premultiplied);
        layer.fill(Qt::transparent);
        lp.begin(&layer);
        lp.setRenderHint(QPainter::Antialiasing);
        dp = &lp;
    }

    auto alpha = [](QColor c, qreal a) { c.setAlphaF(qBound<qreal>(0, a, 1)); return c; };
    for (const Curve &cv : curves) {
        QLinearGradient g(0, 0, 0, bottom);
        g.setColorAt(0, alpha(cv.color, 0.34 * o));
        g.setColorAt(1, alpha(cv.color, 0.02 * o));
        dp->setPen(Qt::NoPen);
        dp->setBrush(g);
        dp->drawPath(cv.fill);
    }
    dp->setBrush(Qt::NoBrush);
    if (m_glow) {
        // One blur for every channel: strokes drawn at a third of the size,
        // box-blurred and scaled back up (about a 4 px Gaussian)
        const qreal k = 1.0 / 3;
        QImage glow(QSize(int(std::ceil(width() * k)) + 2, int(std::ceil(height() * k)) + 2),
                    QImage::Format_ARGB32_Premultiplied);
        glow.fill(Qt::transparent);
        {
            QPainter gp(&glow);
            gp.setRenderHint(QPainter::Antialiasing);
            gp.scale(k, k);
            for (const Curve &cv : curves) {
                gp.setPen(QPen(alpha(cv.color, 0.35 * o), 2 / k * 0.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
                gp.drawPath(cv.line);
            }
        }
        boxBlur(glow);
        boxBlur(glow);
        dp->save();
        dp->setRenderHint(QPainter::SmoothPixmapTransform);
        dp->drawImage(QRectF(0, 0, glow.width() / k, glow.height() / k), glow);
        dp->restore();
    }
    for (const Curve &cv : curves) {
        dp->setPen(QPen(alpha(cv.color, 0.55 * o), 1, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        dp->drawPath(cv.line);
    }
    for (const Curve &cv : curves) {
        if (cv.peak.isEmpty()) continue;
        dp->setPen(QPen(alpha(cv.color, 0.35 * o), 1, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        dp->drawPath(cv.peak);
    }

    if (fade) {
        QLinearGradient ramp(dataStart, 0, dataStart + 30, 0);
        ramp.setColorAt(0, QColor(0, 0, 0, 0));
        ramp.setColorAt(1, QColor(0, 0, 0, 255));
        lp.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        lp.fillRect(layer.rect(), ramp);
        lp.end();
        p->drawImage(0, 0, layer);
    }
}

// ── SpectrumBarsItem ──

SpectrumBarsItem::SpectrumBarsItem(QQuickItem *parent) : RtaViewBase(parent) {}

void SpectrumBarsItem::setChannel(int c) { if (c != m_channel) { m_channel = c; emit sourceChanged(); resubscribe(); } }
void SpectrumBarsItem::setColor(const QColor &c) { if (c != m_color) { m_color = c; emit styleChanged(); update(); } }
void SpectrumBarsItem::setLevelLabels(bool v) { if (v != m_levelLabels) { m_levelLabels = v; emit styleChanged(); update(); } }

void SpectrumBarsItem::takeFrame() {
    const bool live = m_rta && channelMask() && m_active && isVisible();
    const RtaChannelFrame *f = live ? frameFor(m_rta->snapshot(), m_tap, m_channel) : nullptr;
    m_levels.setTarget(levelsOf(f), identityOf(m_tap, m_channel, f ? f->n_bands : 0));
}

bool SpectrumBarsItem::stepSmoothing(double tau) {
    return m_levels.step(tau, m_levels.values().size() / 2);
}

static QString freqLabel(int hz) {
    return hz >= 1000 ? QString::number(hz / 1000) + "k" : QString::number(hz);
}

void SpectrumBarsItem::paint(QPainter *p) {
    if (width() < 8 || height() < 20) return;
    p->setRenderHint(QPainter::Antialiasing);
    const qreal labelRow = 12;
    const qreal plotH = height() - labelRow;
    const qreal w = width();
    QFont font = p->font();
    font.setPixelSize(9);
    p->setFont(font);
    QFontMetricsF fm(font);

    // Grid: a line every 12 dB, 0 dBFS stronger
    for (int db = int(std::floor(m_ceilingDb / 12.0)) * 12; db > m_floorDb; db -= 12) {
        qreal y = std::round(yForDb(db, 0, plotH)) + 0.5;
#ifdef Q_OS_MACOS
        // RtaBandGrid: .secondary at 0.35 (0 dBFS) or 0.12
        p->setPen(QPen(macSecondary(db == 0 ? 0.35 : 0.12), db == 0 ? 1.0 : 0.5));
#else
        p->setPen(QPen(QColor(255, 255, 255, db == 0 ? 50 : 18), db == 0 ? 1.0 : 0.5));
#endif
        p->drawLine(QPointF(0, y), QPointF(w, y));
        if (m_levelLabels) {
#ifdef Q_OS_MACOS
            p->setPen(macSecondary(0.6));
#else
            p->setPen(QColor(255, 255, 255, 90));
#endif
            QString t = QString::number(db);
            p->drawText(QRectF(w - 40, y - 12, 38, 11), Qt::AlignRight | Qt::AlignBottom, t);
        }
    }

    if (!m_rta) return;
    const QVector<float> &lv = m_levels.values();
    const int nb = lv.size() / 2;
    QVector<int> shown;
    for (int b = 0; b < nb; b++) if (m_populated >> b & 1) shown.append(b);
    if (shown.isEmpty()) return;

    const qreal slot = w / shown.size();
    const qreal gap = qBound<qreal>(0.5, slot * 0.18, 2.0);
    const qreal barW = qMax<qreal>(1.0, slot - gap);
    const qreal radius = qMin<qreal>(1.5, barW / 3);
    QColor top = m_color, base = m_color, cap = m_color;
    top.setAlphaF(0.95);
    base.setAlphaF(0.45);
    cap.setAlphaF(0.9);
    QLinearGradient g(0, 0, 0, plotH);
    g.setColorAt(0, top);
    g.setColorAt(1, base);
    const qreal span = qMax<qreal>(1, m_ceilingDb - m_floorDb);

    p->setPen(Qt::NoPen);
    p->save();
    p->setClipRect(QRectF(0, 0, w, plotH));
    for (int i = 0; i < shown.size(); i++) {
        const int b = shown[i];
        const qreal x = i * slot + gap / 2;
        const qreal n = qBound<qreal>(0, (lv[b] - m_floorDb) / span, 1);
        if (n >= 0.001) {
            const qreal y = plotH * (1 - n);
#ifdef Q_OS_MACOS
            // rtaBarFragment: 0.95 at the bar's own top to 0.45 at its foot
            QLinearGradient bar(0, y, 0, plotH);
            bar.setColorAt(0, top);
            bar.setColorAt(1, base);
            p->setBrush(bar);
#else
            p->setBrush(g);
#endif
            p->drawRoundedRect(QRectF(x, y, barW, plotH - y + radius), radius, radius);
        }
        if (m_showPeak) {
            const qreal pn = qBound<qreal>(0, (lv[nb + b] - m_floorDb) / span, 1);
            if (pn >= 0.001) {
                p->setBrush(cap);
                p->drawRect(QRectF(x, qMax<qreal>(0, plotH * (1 - pn) - 1), barW, 1.5));
            }
        }
    }
    p->restore();

    // Frequency labels: decades first, then the 2s and 5s where they fit
    const RtaCapsInfo &caps = m_rta->caps();
    static const int marks[] = { 10, 100, 1000, 10000, 20, 200, 2000, 20000, 50, 500, 5000 };
    QVector<QRectF> placed;
#ifdef Q_OS_MACOS
    p->setPen(macSecondary(1.0));        // RtaBandGrid frequency labels: .secondary
#else
    p->setPen(QColor(255, 255, 255, 115));
#endif
    for (int hz : marks) {
        int at = -1;
        for (int i = 0; i < shown.size(); i++)
            if (std::fabs(caps.centres[shown[i]] - hz) <= hz * 0.03) { at = i; break; }
        if (at < 0) continue;
        QString t = freqLabel(hz);
        qreal tw = fm.horizontalAdvance(t);
        QRectF r(at * slot + slot / 2 - tw / 2, plotH + 1, tw, labelRow - 1);
        if (r.left() < 0 || r.right() > w) continue;
        bool clash = false;
        for (const QRectF &q : placed) if (r.adjusted(-4, 0, 4, 0).intersects(q)) { clash = true; break; }
        if (clash) continue;
        placed.append(r);
        p->drawText(r, Qt::AlignCenter, t);
    }
}
