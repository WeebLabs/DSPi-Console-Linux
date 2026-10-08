#include "PeqEditorItem.h"
#include "DSPiBridge.h"

#include <QPainter>
#include <QPainterPath>
#include <QMouseEvent>
#include <QHoverEvent>
#include <QWheelEvent>
#include <QKeyEvent>
#include <QGuiApplication>
#include <QCursor>
#include <cmath>
#include <cstring>

// Band colours, as in the band list (FilterRow.qml)
static const char *kBandColors[] = { "#4A8FE3", "#F57373", "#73C78C", "#EDB34D", "#998CEB",
                                     "#E68CC7", "#66C7D1", "#CCB86B", "#F2A64D", "#8CB3F2" };

// Limits (macOS PeqGraphModel)
static const float kMinFreq = 10.0f, kMaxFreqLimit = 21600.0f;
static const float kMaxGain = 30.0f, kMinQ = 0.1f, kMaxQ = 20.0f;
static const qreal kDotRadius = 5.0, kHitRadius = 10.0, kDragSlop = 2.0;

#ifdef Q_OS_MACOS
// PeqBandPalette (PeqGraphModel.swift), sRGB
static QColor bandColor(int b) {
    static const float rgb[10][3] = {
        {0.93f, 0.47f, 0.45f}, {0.95f, 0.64f, 0.36f}, {0.92f, 0.79f, 0.40f}, {0.55f, 0.80f, 0.52f},
        {0.36f, 0.77f, 0.68f}, {0.44f, 0.68f, 0.94f}, {0.58f, 0.60f, 0.94f}, {0.73f, 0.57f, 0.92f},
        {0.89f, 0.54f, 0.72f}, {0.80f, 0.62f, 0.50f} };
    const float *c = rgb[b % 10];
    return QColor::fromRgbF(c[0], c[1], c[2]);
}
#else
static QColor bandColor(int b) { return QColor(kBandColors[b % 10]); }
#endif
// A bypassed band keeps a trace of its colour (macOS: 35% colour, 65% grey)
static QColor bypassColor(int b) {
    QColor c = bandColor(b);
    qreal g = (c.redF() + c.greenF() + c.blueF()) / 3;
    return QColor::fromRgbF(g + (c.redF() - g) * 0.35, g + (c.greenF() - g) * 0.35, g + (c.blueF() - g) * 0.35);
}
static float clampf(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }

PeqEditorItem::PeqEditorItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setAcceptHoverEvents(true);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton);
    setFlag(ItemIsFocusScope, true);
    setActiveFocusOnTab(false);
    std::memset(m_bands, 0, sizeof(m_bands));
    std::memset(m_xover, 0, sizeof(m_xover));
    std::memset(m_bandCurve, 0, sizeof(m_bandCurve));
    std::memset(m_combined, 0, sizeof(m_combined));

    m_liveTimer.setSingleShot(true);
    connect(&m_liveTimer, &QTimer::timeout, this, &PeqEditorItem::flushLive);
    m_wheelCommit.setSingleShot(true);
    m_wheelCommit.setInterval(450);
    connect(&m_wheelCommit, &QTimer::timeout, this, &PeqEditorItem::commit);
    m_messageTimer.setSingleShot(true);
    m_messageTimer.setInterval(1800);
    connect(&m_messageTimer, &QTimer::timeout, this, [this]() { m_message.clear(); update(); });
    m_lastSend.start();

    m_lingerTimer.setSingleShot(true);
    m_lingerTimer.setInterval(350);
    connect(&m_lingerTimer, &QTimer::timeout, this, [this]() { m_lingerBand = -1; updateHud(); });

    // A sweep across the graph passes over bands too briefly to move the list
    m_revealTimer.setSingleShot(true);
    m_revealTimer.setInterval(250);
    connect(&m_revealTimer, &QTimer::timeout, this, [this]() {
        if (m_hover < 0) return;
        // The list holds still while a band is dragged or wheeled
        if (m_mode != Idle || m_wheelCommit.isActive()) { m_revealTimer.start(); return; }
        emit revealRow(m_hover);
    });

    m_easeTimer.setInterval(16);
    connect(&m_easeTimer, &QTimer::timeout, this, &PeqEditorItem::ease);
    m_easeClock.start();
}

// Ease each dot's hover and selection toward its target; stops when settled
void PeqEditorItem::ease() {
    float dt = m_easeClock.restart() / 1000.0f;
    float k = 1.0f - std::exp(-dt / 0.07f);
    bool moving = false;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        bool lit = b == m_hover || b == m_listHover || b == m_hudBand;
        float h = lit ? 1.0f : 0.0f, s = m_selected[b] ? 1.0f : 0.0f;
        m_hoverAmt[b] += (h - m_hoverAmt[b]) * k;
        m_selectAmt[b] += (s - m_selectAmt[b]) * k;
        if (std::fabs(h - m_hoverAmt[b]) > 0.01f || std::fabs(s - m_selectAmt[b]) > 0.01f) moving = true;
        else { m_hoverAmt[b] = h; m_selectAmt[b] = s; }
    }
    if (!moving) m_easeTimer.stop();
    update();
}

void PeqEditorItem::setBridge(QObject *bridge) {
    m_bridge = qobject_cast<DSPiBridge *>(bridge);
    if (!m_bridge) return;
    connect(m_bridge, &DSPiBridge::stateChanged, this, &PeqEditorItem::reload);
    connect(m_bridge, &DSPiBridge::magnitudesChanged, this, &PeqEditorItem::reload);
    connect(m_bridge, &DSPiBridge::previewChanged, this, &PeqEditorItem::reloadOffset);
    reload();
}

void PeqEditorItem::setChannel(int ch) {
    if (ch == m_channel) return;
    if (m_editing) commit();
    m_channel = ch;
    std::memset(m_selected, 0, sizeof(m_selected));
    m_anchor = -1;
    m_listAnchor = -1;
    m_wheelBand = -1;
    setHover(-1, -1);
    setListHovered(-1);
    emit channelChanged();
    emit selectionChanged();
    reload();
}

#define VIEW_SETTER(name, member) \
    void PeqEditorItem::name(decltype(member) v) { if (member != v) { member = v; emit viewChanged(); update(); } }
VIEW_SETTER(setDbTop, m_dbTop)
VIEW_SETTER(setDbBottom, m_dbBottom)
VIEW_SETTER(setMinFreq, m_minFreq)
VIEW_SETTER(setMaxFreq, m_maxFreq)
VIEW_SETTER(setLineWidth, m_lineWidth)
VIEW_SETTER(setShowGlow, m_showGlow)
#undef VIEW_SETTER

QVariantList PeqEditorItem::selectedBands() const {
    QVariantList l;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) if (m_selected[b]) l.append(b);
    return l;
}

// ── Model ──

void PeqEditorItem::updateActive() {
    bool on = m_bridge && m_channel >= 0 && m_bridge->connected() && m_bridge->channelExists(m_channel)
              && m_bridge->channelVisible(m_channel);
    if (on != m_active) {
        m_active = on;
        setAcceptedMouseButtons(on ? (Qt::LeftButton | Qt::RightButton) : Qt::NoButton);
        setAcceptHoverEvents(on);
        if (!on) setHover(-1, -1);
        emit activeChanged();
    }
}

// Follow the device unless a gesture holds live values
void PeqEditorItem::reload() {
    updateActive();
    if (!m_active || m_editing || m_mode == DragDot || m_mode == DragQ) { update(); return; }
    FilterParams bands[BANDS_PER_CHANNEL], xover[MAX_XOVER_BANDS];
    int nx = 0;
    if (!m_bridge->channelBands(m_channel, bands, xover, &nx)) return;
    float offset = m_bridge->channelGainOffset(m_channel);
    QColor color(m_bridge->channelColor(m_channel));
    bool same = std::memcmp(bands, m_bands, sizeof(bands)) == 0 && nx == m_xoverCount
                && std::memcmp(xover, m_xover, sizeof(FilterParams) * nx) == 0
                && offset == m_offset && color == m_channelColor;
    if (same) return;
    std::memcpy(m_bands, bands, sizeof(bands));
    std::memcpy(m_xover, xover, sizeof(xover));
    m_xoverCount = nx;
    m_offset = offset;
    m_channelColor = color;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        recomputeBand(b);
        if (!isEditable(b) && m_selected[b]) { m_selected[b] = false; emit selectionChanged(); kickEase(); }
    }
    recomputeCombined();
    updateHud();
    update();
}

// Mid-drag gain or preamp: only the level shift changes, the shapes don't
void PeqEditorItem::reloadOffset() {
    if (!m_active || m_channel < 0) return;
    float offset = m_bridge->channelGainOffset(m_channel);
    if (offset == m_offset) return;
    m_offset = offset;
    updateHud();
    update();
}

void PeqEditorItem::recomputeBand(int b) {
    FilterParams p = m_bands[b];
    p.bypass = false;                    // a bypassed band still shows its shape, greyed
    dspi_compute_magnitude_curve(&p, 1, m_bandCurve[b]);
}

void PeqEditorItem::recomputeCombined() {
    FilterParams all[BANDS_PER_CHANNEL + MAX_XOVER_BANDS];
    int n = 0;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) all[n++] = m_bands[b];
    for (int b = 0; b < m_xoverCount; b++) all[n++] = m_xover[b];
    dspi_compute_magnitude_curve(all, n, m_combined);
}

PeqEditorItem::Role PeqEditorItem::roleOf(int t) {
    switch (t) {
    case FILTER_PEAKING: case FILTER_LOWSHELF: case FILTER_HIGHSHELF:
    case FILTER_LOWSHELF1: case FILTER_HIGHSHELF1: return GainRole;
    case FILTER_LOWPASS: case FILTER_HIGHPASS: return QRole;
    case FILTER_LINKWITZ_TRANSFORM: return LockedRole;
    default: return FixedRole;
    }
}
bool PeqEditorItem::usesGain(int t) { return roleOf(t) == GainRole; }
bool PeqEditorItem::usesQ(int t) {
    return t == FILTER_PEAKING || t == FILTER_LOWSHELF || t == FILTER_HIGHSHELF || t == FILTER_LOWPASS
        || t == FILTER_HIGHPASS || t == FILTER_NOTCH || t == FILTER_ALLPASS;
}
// How much of a gain change shows at f0 (a shelf is half way at its corner)
float PeqEditorItem::gainScale(int t) { return t == FILTER_PEAKING ? 1.0f : 0.5f; }

bool PeqEditorItem::isEditable(int b) const {
    int t = m_bands[b].filter_type;
    return t != FILTER_FLAT && t < FILTER_XOVER_FIRST;
}

// Where a band's dot sits, in dB
float PeqEditorItem::dotDb(int b) const {
    const FilterParams &p = m_bands[b];
    switch (roleOf(p.filter_type)) {
    case GainRole: return p.gain * gainScale(p.filter_type);
    case QRole: return 20.0f * std::log10(qMax(p.q, kMinQ));
    case LockedRole: { FilterParams c = p; c.bypass = false; return dspi_compute_response(&c, 1, p.freq); }
    default: return (p.filter_type == FILTER_LOWPASS1 || p.filter_type == FILTER_HIGHPASS1) ? -3.0f : 0.0f;
    }
}

QPointF PeqEditorItem::dotPos(int b) const {
    qreal y = qBound(6.0, yForDb(dotDb(b) + m_offset), height() - 6.0);
    return QPointF(xForFreq(m_bands[b].freq), y);
}

// ── Geometry (same mapping as BodePlotItem) ──

qreal PeqEditorItem::xForFreq(float f) const {
    float lo = std::log10(m_minFreq), hi = std::log10(m_maxFreq);
    return (std::log10(qMax(f, 1.0f)) - lo) / (hi - lo) * width();
}
float PeqEditorItem::freqForX(qreal x) const {
    float lo = std::log10(m_minFreq), hi = std::log10(m_maxFreq);
    return std::pow(10.0f, lo + float(x / width()) * (hi - lo));
}
qreal PeqEditorItem::yForDb(float db) const {
    return height() - (db - m_dbBottom) / (m_dbTop - m_dbBottom) * height();
}
float PeqEditorItem::dbForY(qreal y) const {
    return m_dbBottom + float((height() - y) / height()) * (m_dbTop - m_dbBottom);
}

QPainterPath PeqEditorItem::curvePath(const double *mags, float offset) const {
    const float dataLo = std::log10(10.0f), dataHi = std::log10(20000.0f);
    QVector<QPointF> pts(MAGNITUDE_POINTS);
    for (int i = 0; i < MAGNITUDE_POINTS; i++) {
        float f = std::pow(10.0f, dataLo + float(i) / (MAGNITUDE_POINTS - 1) * (dataHi - dataLo));
        pts[i] = QPointF(xForFreq(f), yForDb(float(mags[i]) + offset));
    }
    QPainterPath path(pts[0]);
    for (int i = 0; i < MAGNITUDE_POINTS - 1; i++) {
        QPointF p0 = pts[qMax(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[qMin(MAGNITUDE_POINTS - 1, i + 2)];
        path.cubicTo(p1 + (p2 - p0) / 6.0, p2 - (p3 - p1) / 6.0, p2);
    }
    return path;
}

int PeqEditorItem::dotAt(const QPointF &p) const {
    int best = -1;
    qreal bestD = 1e9;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        if (!isEditable(b)) continue;
        qreal d = QLineF(p, dotPos(b)).length();
        if (d > kHitRadius) continue;
        // Selected and hovered dots draw on top, so they win close calls
        qreal score = d - (m_selected[b] ? 3 : 0) - (b == m_hover ? 2 : 0);
        if (score < bestD) { best = b; bestD = score; }
    }
    return best;
}

// The band whose lobe (between its curve and 0 dB) is under the pointer
int PeqEditorItem::lobeAt(const QPointF &p) const {
    float f = freqForX(p.x());
    const qreal y0 = yForDb(m_offset);
    int best = -1;
    qreal bestD = 1e9;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        if (!isEditable(b) || roleOf(m_bands[b].filter_type) == LockedRole) continue;
        FilterParams c = m_bands[b];
        c.bypass = false;
        qreal y = yForDb(dspi_compute_response(&c, 1, f) + m_offset);
        if (std::fabs(y - y0) < 3 || p.y() < qMin(y, y0) || p.y() > qMax(y, y0)) continue;
        // Nested fills: the one whose edge is nearest the pointer
        qreal d = std::fabs(p.y() - y);
        if (d < bestD) { best = b; bestD = d; }
    }
    return best;
}

bool PeqEditorItem::nearCurve(const QPointF &p) const {
    // The combined curve's level under the pointer, from its 201 points
    const float lo = std::log10(10.0f), hi = std::log10(20000.0f);
    float t = (std::log10(qMax(freqForX(p.x()), 10.0f)) - lo) / (hi - lo) * (MAGNITUDE_POINTS - 1);
    if (t < 0 || t > MAGNITUDE_POINTS - 1) return false;
    int i = qMin(int(t), MAGNITUDE_POINTS - 2);
    double db = m_combined[i] + (m_combined[i + 1] - m_combined[i]) * (t - i);
    return std::fabs(yForDb(float(db) + m_offset) - p.y()) <= 6.0;
}

// ── Editing ──

void PeqEditorItem::beginEdit() {
    std::memcpy(m_start, m_bands, sizeof(m_bands));
    m_axisLock = 0;
}

void PeqEditorItem::markLive(int b) {
    m_pending[b] = true;
    m_changed[b] = true;
    m_editing = true;
    // First change at once, then the latest every 30 ms
    if (!m_liveTimer.isActive()) {
        qint64 wait = 30 - m_lastSend.elapsed();
        m_liveTimer.start(wait > 0 ? int(wait) : 0);
    }
}

void PeqEditorItem::flushLive() {
    if (!m_bridge) return;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++)
        if (m_pending[b]) { m_bridge->sendBandLive(m_channel, b, m_bands[b]); m_pending[b] = false; }
    m_lastSend.restart();
}

void PeqEditorItem::commit() {
    m_liveTimer.stop();
    m_wheelCommit.stop();
    if (!m_bridge || !m_editing) { m_editing = false; return; }
    QVector<int> bands;
    QVector<FilterParams> params;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++)
        if (m_changed[b]) { bands.append(b); params.append(m_bands[b]); m_changed[b] = false; m_pending[b] = false; }
    m_editing = false;
    if (!bands.isEmpty()) m_bridge->commitBands(m_channel, bands, params);
}

void PeqEditorItem::commitBand(int b, const FilterParams &p) {
    m_bands[b] = p;
    m_changed[b] = true;
    m_editing = true;
    recomputeBand(b);
    recomputeCombined();
    commit();
    update();
}

// Move the gesture's bands to follow the pointer
void PeqEditorItem::applyDrag(const QPointF &pos, Qt::KeyboardModifiers mods) {
    QPointF d = pos - m_pressPos;
    if (mods & Qt::ShiftModifier) d *= 0.12;                 // fine
    if (mods & Qt::AltModifier) {                            // one axis, chosen once
        if (m_axisLock == 0 && (std::fabs(d.x()) > 4 || std::fabs(d.y()) > 4))
            m_axisLock = std::fabs(d.x()) >= std::fabs(d.y()) ? 1 : 2;
        if (m_axisLock == 1) d.setY(0);
        else if (m_axisLock == 2) d.setX(0);
        else d = QPointF();
    }
    float span = std::log10(m_maxFreq) - std::log10(m_minFreq);
    float ratio = std::pow(10.0f, float(d.x() / width()) * span);
    float dDb = -float(d.y() / height()) * (m_dbTop - m_dbBottom);
    float fHi = qMin(kMaxFreqLimit, m_maxFreq), fLo = qMax(kMinFreq, m_minFreq);

    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        bool moving = m_selected[b] || b == m_pressBand;
        if (!moving || !isEditable(b)) continue;
        const FilterParams &s = m_start[b];
        FilterParams p = s;
        int t = s.filter_type;
        if (m_mode == DragQ) {
            if (!usesQ(t)) continue;
            p.q = clampf(s.q * std::pow(2.0f, -float(pos.y() - m_pressPos.y()) / 60.0f), kMinQ, kMaxQ);
        } else {
            if (roleOf(t) == LockedRole) continue;
            p.freq = clampf(s.freq * ratio, fLo, fHi);
            if (roleOf(t) == GainRole)
                p.gain = clampf(s.gain + dDb / gainScale(t), -kMaxGain, kMaxGain);
            else if (roleOf(t) == QRole)
                p.q = clampf(std::pow(10.0f, (20.0f * std::log10(qMax(s.q, kMinQ)) + dDb) / 20.0f), kMinQ, kMaxQ);
        }
        if (std::memcmp(&p, &m_bands[b], sizeof(p)) != 0) {
            m_bands[b] = p;
            recomputeBand(b);
            markLive(b);
        }
    }
    recomputeCombined();
    updateHud();
    update();
}

int PeqEditorItem::firstFreeBand() const {
    for (int b = 0; b < BANDS_PER_CHANNEL; b++)
        if (m_bands[b].filter_type == FILTER_FLAT) return b;
    return -1;
}

void PeqEditorItem::createBand(float freq, float gain, int type, float q) {
    int b = firstFreeBand();
    if (b < 0) { showMessage(QString("All %1 bands in use").arg(BANDS_PER_CHANNEL)); return; }
    FilterParams p = m_bands[b];
    p.filter_type = uint8_t(type);
    p.bypass = false;
    p.freq = clampf(freq, kMinFreq, kMaxFreqLimit);
    p.gain = usesGain(type) ? clampf(gain, -kMaxGain, kMaxGain) : 0.0f;
    p.q = q;
    std::memset(m_selected, 0, sizeof(m_selected));
    m_selected[b] = true;
    m_anchor = b;
    emit selectionChanged();
    commitBand(b, p);
    updateHud();
}

// Keyboard and context edits on the selection
void PeqEditorItem::nudge(float octaves, float db, float qFactor, const bool *targets) {
    if (!targets) targets = m_selected;
    float fHi = qMin(kMaxFreqLimit, m_maxFreq), fLo = qMax(kMinFreq, m_minFreq);
    const bool dragging = m_mode == DragDot || m_mode == DragQ;
    auto apply = [&](FilterParams &p) {
        if (octaves != 0) p.freq = clampf(p.freq * std::pow(2.0f, octaves), fLo, fHi);
        if (db != 0 && usesGain(p.filter_type)) p.gain = clampf(p.gain + db, -kMaxGain, kMaxGain);
        if (qFactor != 1 && usesQ(p.filter_type)) p.q = clampf(p.q * qFactor, kMinQ, kMaxQ);
    };
    bool any = false;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        if (!targets[b] || !isEditable(b) || roleOf(m_bands[b].filter_type) == LockedRole) continue;
        apply(m_bands[b]);
        // Mid-drag, the drag rebuilds the bands from its start values on
        // every move: change those too, or the next move undoes this
        if (dragging && (m_selected[b] || b == m_pressBand)) apply(m_start[b]);
        recomputeBand(b);
        markLive(b);
        any = true;
    }
    if (!any) return;
    recomputeCombined();
    if (!dragging) m_wheelCommit.start();     // a drag commits on release
    updateHud();
    update();
}

void PeqEditorItem::setHover(int dot, int band) {
    if (dot == m_hoverDot && band == m_hover) return;
    // Leaving a dot keeps its chip up briefly, so the pointer can reach it
    if (m_hoverDot >= 0 && dot < 0) { m_lingerBand = m_hoverDot; m_lingerTimer.start(); }
    const bool bandChanged = band != m_hover;
    m_hoverDot = dot;
    m_hover = band;
    updateHud();
    if (bandChanged) {
        emit hoverChanged();
        if (band >= 0) m_revealTimer.start(); else m_revealTimer.stop();
    }
    kickEase();
}

void PeqEditorItem::kickEase() {
    if (!m_easeTimer.isActive()) { m_easeClock.restart(); m_easeTimer.start(); }
}

void PeqEditorItem::showMessage(const QString &text) {
    m_message = text;
    m_messageTimer.start();
    update();
}

// ── Control panel (HUD) ──

// The selected band the chip stays on: the one it already shows, else the
// anchor, else the lowest in frequency
int PeqEditorItem::chipPin() const {
    if (m_hudBand >= 0 && m_selected[m_hudBand]) return m_hudBand;
    if (m_anchor >= 0 && m_selected[m_anchor]) return m_anchor;
    int pin = -1;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++)
        if (m_selected[b] && isEditable(b) && (pin < 0 || m_bands[b].freq < m_bands[pin].freq)) pin = b;
    return pin;
}

// Which band the chip shows. While bands are selected it stays on them, and
// hovering another band only lights that band and its row; with none
// selected it follows the hovered dot
void PeqEditorItem::updateHud() {
    int b, pin;
    if ((m_mode == DragDot || m_mode == DragQ) && m_pressBand >= 0) b = m_pressBand;
    else if (m_mode == Marquee) b = m_hudBand;          // settles when the marquee ends
    else if (m_wheelBand >= 0) b = m_wheelBand;
    else if ((pin = chipPin()) >= 0) b = pin;
    else if (m_hoverDot >= 0) b = m_hoverDot;
    else if (m_hudHold && m_hudBand >= 0) b = m_hudBand;
    else b = m_lingerBand;
    if (b >= 0 && !isEditable(b)) b = -1;
    if (b != m_hudBand) {
        m_hudBand = b;
        kickEase();                       // the chip's band is lit
    }
    emit hudChanged();      // also when the band's values or dot moved
}

void PeqEditorItem::setHudHold(bool hold) {
    if (hold == m_hudHold) return;
    m_hudHold = hold;
    if (!hold) m_lingerTimer.start();   // linger once more after leaving the panel
    else m_lingerTimer.stop();
    updateHud();
}

QVariantMap PeqEditorItem::hudValues() const {
    QVariantMap m;
    if (m_hudBand < 0) return m;
    const FilterParams &f = m_bands[m_hudBand];
    m["band"] = m_hudBand;
    m["type"] = int(f.filter_type);
    m["freq"] = f.freq;
    m["gain"] = f.gain;
    m["q"] = f.q;
    m["bypass"] = f.bypass;
    m["color"] = f.bypass ? bypassColor(m_hudBand) : bandColor(m_hudBand);
    m["usesGain"] = usesGain(f.filter_type);
    m["usesQ"] = usesQ(f.filter_type);
    return m;
}

void PeqEditorItem::setBandValue(int band, const QString &field, double value) {
    if (band < 0 || band >= BANDS_PER_CHANNEL || !isEditable(band)) return;
    FilterParams p = m_bands[band];
    if (field == "freq") p.freq = clampf(float(value), kMinFreq, kMaxFreqLimit);
    else if (field == "gain" && usesGain(p.filter_type)) p.gain = clampf(float(value), -kMaxGain, kMaxGain);
    else if (field == "q" && usesQ(p.filter_type)) p.q = clampf(float(value), kMinQ, kMaxQ);
    else return;
    commitBand(band, p);
    updateHud();
}

void PeqEditorItem::setBandType(int band, int type) {
    if (band < 0 || band >= BANDS_PER_CHANNEL || !isEditable(band)) return;
    FilterParams p = m_bands[band];
    if (p.filter_type == type) return;
    int old = p.filter_type;
    p.filter_type = uint8_t(type);
    if (!usesGain(type)) p.gain = 0.0f;
    else if (!usesGain(old)) p.gain = 0.0f;
    // A bell or notch keeps its width; the others start at Butterworth
    if (type != FILTER_PEAKING && type != FILTER_NOTCH && usesQ(type)) p.q = 0.707f;
    else if ((type == FILTER_PEAKING || type == FILTER_NOTCH) && !(old == FILTER_PEAKING || old == FILTER_NOTCH)) p.q = 1.0f;
    commitBand(band, p);
    updateHud();
}

void PeqEditorItem::toggleBypass(int band) {
    if (band < 0 || band >= BANDS_PER_CHANNEL || !isEditable(band)) return;
    QVector<int> bands;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++)
        if (isEditable(b) && (m_selected[band] ? m_selected[b] : b == band)) bands.append(b);
    const bool bypass = !m_bands[bands.first()].bypass;
    QVector<FilterParams> params;
    for (int b : bands) {
        m_bands[b].bypass = bypass;
        params.append(m_bands[b]);
    }
    recomputeCombined();
    m_bridge->commitBands(m_channel, bands, params);
    updateHud();
    update();
}

void PeqEditorItem::createShape(int type, double freq, double gain) {
    createBand(float(freq), float(gain), type, (type == FILTER_PEAKING || type == FILTER_NOTCH) ? 1.0f : 0.707f);
    updateHud();
}

// ── Selection API ──

void PeqEditorItem::selectBand(int band, bool toggle, bool range) {
    if (band < 0 || band >= BANDS_PER_CHANNEL || !isEditable(band)) return;
    if (range && m_anchor >= 0) {
        // Range in frequency order from the anchor
        float a = m_bands[m_anchor].freq, z = m_bands[band].freq;
        if (a > z) std::swap(a, z);
        for (int b = 0; b < BANDS_PER_CHANNEL; b++)
            if (isEditable(b) && m_bands[b].freq >= a && m_bands[b].freq <= z) m_selected[b] = true;
    } else if (toggle) {
        m_selected[band] = !m_selected[band];
        m_anchor = band;
    } else {
        std::memset(m_selected, 0, sizeof(m_selected));
        m_selected[band] = true;
        m_anchor = band;
    }
    emit selectionChanged();
    kickEase();
    updateHud();
    update();
}

void PeqEditorItem::listClick(int band, bool toggle, bool range) {
    if (band < 0 || band >= BANDS_PER_CHANNEL || !isEditable(band)) return;
    int from = -1;
    if (range && !toggle) {
        if (m_listAnchor >= 0 && m_selected[m_listAnchor]) from = m_listAnchor;
        else {
            int n = 0;
            for (int b = 0; b < BANDS_PER_CHANNEL; b++) if (m_selected[b]) { n++; from = b; }
            if (n != 1) from = -1;
        }
    }
    if (toggle) {
        m_selected[band] = !m_selected[band];
        m_listAnchor = band;
    } else if (from >= 0) {
        // The anchor stays put, so a second Shift-click reshapes the run
        std::memset(m_selected, 0, sizeof(m_selected));
        for (int b = qMin(from, band); b <= qMax(from, band); b++) m_selected[b] = isEditable(b);
        m_listAnchor = from;
    } else {
        std::memset(m_selected, 0, sizeof(m_selected));
        m_selected[band] = true;
        m_listAnchor = band;
    }
    int count = 0, only = -1;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) if (m_selected[b]) { count++; only = b; }
    if (count == 1) m_anchor = only;
    emit selectionChanged();
    kickEase();
    updateHud();
    update();
}

void PeqEditorItem::setListHovered(int band) {
    if (band == m_listHover) return;
    m_listHover = band;
    emit listHoveredChanged();
    kickEase();
    update();
}

void PeqEditorItem::selectAll() {
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) m_selected[b] = isEditable(b);
    emit selectionChanged();
    kickEase();
    updateHud();
    update();
}

void PeqEditorItem::deselectAll() {
    std::memset(m_selected, 0, sizeof(m_selected));
    m_anchor = -1;
    emit selectionChanged();
    kickEase();
    updateHud();
    update();
}

QVariantMap PeqEditorItem::bandInfo(int band) const {
    QVariantMap m;
    if (band < 0 || band >= BANDS_PER_CHANNEL) return m;
    int t = m_bands[band].filter_type;
    m["type"] = t;
    m["bypass"] = m_bands[band].bypass;
    m["hasGain"] = usesGain(t);
    // Shapes that come in two orders, and which one this is
    int order = 0;
    switch (t) {
    case FILTER_LOWSHELF: case FILTER_HIGHSHELF: case FILTER_LOWPASS: case FILTER_HIGHPASS: case FILTER_ALLPASS: order = 2; break;
    case FILTER_LOWSHELF1: case FILTER_HIGHSHELF1: case FILTER_LOWPASS1: case FILTER_HIGHPASS1: case FILTER_ALLPASS1: order = 1; break;
    }
    m["order"] = order;
    m["allPass"] = t == FILTER_ALLPASS || t == FILTER_ALLPASS1;
    return m;
}

void PeqEditorItem::deleteSelection() {
    QVector<int> bands; QVector<FilterParams> params;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        if (!m_selected[b]) continue;
        FilterParams p = m_bands[b];
        p.filter_type = FILTER_FLAT;
        p.bypass = false;
        m_bands[b] = p;
        bands.append(b); params.append(p);
        m_selected[b] = false;
        recomputeBand(b);
    }
    if (bands.isEmpty()) return;
    m_anchor = -1;
    recomputeCombined();
    emit selectionChanged();
    kickEase();
    m_bridge->commitBands(m_channel, bands, params);
    updateHud();
    update();
}

void PeqEditorItem::invertGainSelection() {
    QVector<int> bands; QVector<FilterParams> params;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        if (!m_selected[b] || !usesGain(m_bands[b].filter_type)) continue;
        m_bands[b].gain = -m_bands[b].gain;
        recomputeBand(b);
        bands.append(b); params.append(m_bands[b]);
    }
    if (bands.isEmpty()) return;
    recomputeCombined();
    m_bridge->commitBands(m_channel, bands, params);
    updateHud();
    update();
}

void PeqEditorItem::setOrderSelection(int order) {
    auto swapOrder = [order](int t) {
        switch (t) {
        case FILTER_LOWSHELF: case FILTER_LOWSHELF1: return order == 1 ? FILTER_LOWSHELF1 : FILTER_LOWSHELF;
        case FILTER_HIGHSHELF: case FILTER_HIGHSHELF1: return order == 1 ? FILTER_HIGHSHELF1 : FILTER_HIGHSHELF;
        case FILTER_LOWPASS: case FILTER_LOWPASS1: return order == 1 ? FILTER_LOWPASS1 : FILTER_LOWPASS;
        case FILTER_HIGHPASS: case FILTER_HIGHPASS1: return order == 1 ? FILTER_HIGHPASS1 : FILTER_HIGHPASS;
        case FILTER_ALLPASS: case FILTER_ALLPASS1: return order == 1 ? FILTER_ALLPASS1 : FILTER_ALLPASS;
        default: return t;
        }
    };
    QVector<int> bands; QVector<FilterParams> params;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
        if (!m_selected[b]) continue;
        int t = swapOrder(m_bands[b].filter_type);
        if (t == m_bands[b].filter_type) continue;
        m_bands[b].filter_type = uint8_t(t);
        recomputeBand(b);
        bands.append(b); params.append(m_bands[b]);
    }
    if (bands.isEmpty()) return;
    recomputeCombined();
    m_bridge->commitBands(m_channel, bands, params);
    updateHud();
    update();
}

// ── Mouse ──

void PeqEditorItem::mousePressEvent(QMouseEvent *e) {
    if (!m_active) { e->ignore(); return; }
    forceActiveFocus(Qt::MouseFocusReason);
    QPointF p = e->localPos();
    int b = dotAt(p);
    if (e->button() == Qt::RightButton) {
        if (b >= 0 && !m_selected[b]) selectBand(b, false, false);
        int count = 0;
        for (int i = 0; i < BANDS_PER_CHANNEL; i++) if (m_selected[i]) count++;
        emit contextMenuRequested(p.x(), p.y(), b, count);
        return;
    }
    m_pressPos = p;
    m_pressMods = e->modifiers();
    m_pressBand = b;
    m_wheelBand = -1;
    if (b >= 0) {
        m_mode = PressDot;
        // A plain press on an unselected dot selects it alone at once
        if (!(m_pressMods & (Qt::ControlModifier | Qt::ShiftModifier | Qt::AltModifier)) && !m_selected[b])
            selectBand(b, false, false);
        // A modified press outside the selection leaves the chip on the selection
        if (m_selected[b]) { m_hudBand = b; kickEase(); }
        updateHud();
    } else if (m_pressMods & Qt::ControlModifier) {
        // Ctrl-click: a card to pick the new band's shape, opened at once
        m_mode = Idle;
        if (firstFreeBand() < 0) { showMessage(QString("All %1 bands in use").arg(BANDS_PER_CHANNEL)); return; }
        m_cardOpen = true;
        m_cardPoint = p;
        setHover(-1, -1);
        float db = dbForY(p.y());
        emit shapeCardRequested(p.x(), p.y(), freqForX(p.x()), db - m_offset, db >= 0);
        update();
    } else {
        // On the curve with a band free, a drag pulls a new band out of it
        m_mode = firstFreeBand() >= 0 && nearCurve(p) ? PressCurve : PressEmpty;
    }
}

void PeqEditorItem::cardClosed() {
    if (!m_cardOpen) return;
    m_cardOpen = false;
    update();
}

void PeqEditorItem::mouseMoveEvent(QMouseEvent *e) {
    QPointF p = e->localPos();
    m_pointer = p;
    if (m_mode == PressDot && QLineF(p, m_pressPos).length() > kDragSlop) {
        if (roleOf(m_bands[m_pressBand].filter_type) == LockedRole) { m_mode = Idle; return; }
        // Dragging a dot outside the selection moves it alone
        if (!m_selected[m_pressBand]) selectBand(m_pressBand, (m_pressMods & Qt::ControlModifier) != 0, false);
        beginEdit();
        m_mode = (m_pressMods & Qt::ControlModifier) ? DragQ : DragDot;
        setCursor(m_mode == DragQ ? Qt::SizeVerCursor : Qt::ClosedHandCursor);
    }
    if (m_mode == DragDot || m_mode == DragQ) {
        applyDrag(p, e->modifiers());
        return;
    }
    if (m_mode == PressCurve && QLineF(p, m_pressPos).length() > kDragSlop) {
        // A new band at 0 dB where the curve was grabbed: a shelf near either
        // end of the graph, else a bell; then it drags like any other
        int b = firstFreeBand();
        qreal frac = m_pressPos.x() / width();
        int type = frac < 0.12 ? FILTER_LOWSHELF : frac > 0.88 ? FILTER_HIGHSHELF : FILTER_PEAKING;
        FilterParams np = m_bands[b];
        np.filter_type = uint8_t(type);
        np.bypass = false;
        np.freq = clampf(freqForX(m_pressPos.x()), kMinFreq, kMaxFreqLimit);
        np.gain = 0.0f;
        np.q = type == FILTER_PEAKING ? 1.0f : 0.707f;
        m_bands[b] = np;
        recomputeBand(b);
        std::memset(m_selected, 0, sizeof(m_selected));
        m_selected[b] = true;
        m_anchor = b;
        m_pressBand = b;
        emit selectionChanged();
        kickEase();
        beginEdit();
        m_mode = DragDot;
        markLive(b);
        setCursor(Qt::ClosedHandCursor);
    }
    if (m_mode == PressEmpty && QLineF(p, m_pressPos).length() > kDragSlop) {
        m_mode = Marquee;
        m_marqueeAdd = (m_pressMods & Qt::ShiftModifier) != 0;
    }
    if (m_mode == Marquee) {
        m_marquee = QRectF(m_pressPos, p).normalized();
        bool before[BANDS_PER_CHANNEL];
        std::memcpy(before, m_selected, sizeof(before));
        if (!m_marqueeAdd) std::memset(m_selected, 0, sizeof(m_selected));
        for (int b = 0; b < BANDS_PER_CHANNEL; b++)
            if (isEditable(b) && m_marquee.contains(dotPos(b))) m_selected[b] = true;
        if (std::memcmp(before, m_selected, sizeof(before)) != 0) { emit selectionChanged(); kickEase(); }
        update();
    }
}

void PeqEditorItem::mouseReleaseEvent(QMouseEvent *e) {
    Mode mode = m_mode;
    m_mode = Idle;
    unsetCursor();
    if (mode == DragDot || mode == DragQ) {
        commit();
    } else if (mode == PressDot) {
        // A click: modifiers decide what it does
        if (m_pressMods & Qt::AltModifier) {
            toggleBypass(m_pressBand);
        } else if (m_pressMods & Qt::ShiftModifier) {
            selectBand(m_pressBand, false, true);
        } else if (m_pressMods & Qt::ControlModifier) {
            selectBand(m_pressBand, true, false);
        } else {
            selectBand(m_pressBand, false, false);
        }
    } else if (mode == PressEmpty || mode == PressCurve) {
        // An explicit deselect dismisses the chip at once, without the grace delay
        m_lingerBand = -1;
        m_lingerTimer.stop();
        deselectAll();
    } else if (mode == Marquee) {
        m_marquee = QRectF();
        update();
    }
    m_pressBand = -1;
    updateHud();                          // the chip settles on the selection
    e->accept();
}

void PeqEditorItem::mouseDoubleClickEvent(QMouseEvent *e) {
    if (!m_active || e->button() != Qt::LeftButton) return;
    QPointF p = e->localPos();
    int b = dotAt(p);
    if (b >= 0) {
        // Its chip, with the frequency ready to type (the first click selected it)
        m_mode = Idle;
        updateHud();
        if (m_hudBand == b) emit editFrequencyRequested();
        return;
    }
    // A bell where the pointer is, at the pointer's level
    createBand(freqForX(p.x()), dbForY(p.y()) - m_offset, FILTER_PEAKING, 1.0f);
    m_mode = Idle;
}

void PeqEditorItem::hoverMoveEvent(QHoverEvent *e) {
    m_pointer = e->posF();
    m_pointerInside = true;
    if (m_cardOpen) return;               // only the card responds while it's up
    int b = dotAt(m_pointer);
    // Moving the pointer hands the chip back from the wheeled band
    if (m_wheelBand >= 0) { m_wheelBand = -1; updateHud(); }
    setHover(b, b >= 0 ? b : lobeAt(m_pointer));
    setCursor(b >= 0 || (firstFreeBand() >= 0 && nearCurve(m_pointer)) ? Qt::OpenHandCursor : Qt::ArrowCursor);
    update();
}

void PeqEditorItem::hoverLeaveEvent(QHoverEvent *) {
    m_pointerInside = false;
    if (m_wheelBand >= 0) { m_wheelBand = -1; updateHud(); }
    setHover(-1, -1);
    update();
}

void PeqEditorItem::wheelEvent(QWheelEvent *e) {
    if (!m_active) { e->ignore(); return; }
    QPointF p = e->position();
    int b = dotAt(p);
    if (b < 0) b = lobeAt(p);
    if (b < 0) { e->ignore(); return; }
    // The wheel acts on the whole selection when the band is part of it,
    // else on the band alone; either way the selection stays as it is
    bool targets[BANDS_PER_CHANNEL] = {};
    if (m_selected[b]) std::memcpy(targets, m_selected, sizeof(targets));
    else targets[b] = true;
    m_wheelBand = b;
    if (m_hover < 0) setHover(m_hoverDot, b);
    // A notch of a mouse wheel counts 8 (as on macOS); a touchpad is finer
    float delta = e->pixelDelta().isNull() ? e->angleDelta().y() / 120.0f * 8.0f : e->pixelDelta().y() * 0.5f;
    if (e->modifiers() & Qt::ShiftModifier) delta *= 0.12f;
    if (e->modifiers() & Qt::ControlModifier) nudge(0, delta * 0.05f, 1, targets);
    else nudge(0, 0, std::pow(2.0f, delta / 100.0f), targets);
    updateHud();
    e->accept();
}

void PeqEditorItem::keyPressEvent(QKeyEvent *e) {
    if (!m_active) { e->ignore(); return; }
    bool shift = e->modifiers() & Qt::ShiftModifier;
    bool any = false;
    for (int b = 0; b < BANDS_PER_CHANNEL; b++) any = any || m_selected[b];
    switch (e->key()) {
    case Qt::Key_Delete: case Qt::Key_Backspace:
        deleteSelection(); break;
    case Qt::Key_Escape:
        if (any) deselectAll(); else e->ignore();
        break;
    case Qt::Key_A:
        if (e->modifiers() & Qt::ControlModifier) selectAll(); else e->ignore();
        break;
    case Qt::Key_Tab: case Qt::Key_Backtab: {
        // Step through the bands in frequency order
        QVector<int> order;
        for (int b = 0; b < BANDS_PER_CHANNEL; b++) if (isEditable(b)) order.append(b);
        if (order.isEmpty()) break;
        std::sort(order.begin(), order.end(), [this](int a, int z) { return m_bands[a].freq < m_bands[z].freq; });
        int at = order.indexOf(m_anchor);
        bool back = e->key() == Qt::Key_Backtab;
        int next = at < 0 ? (back ? order.size() - 1 : 0) : (at + (back ? -1 : 1) + order.size()) % order.size();
        selectBand(order[next], false, false);
        break;
    }
    case Qt::Key_Left: case Qt::Key_Right:
        if (!any) { e->ignore(); break; }
        nudge((e->key() == Qt::Key_Right ? 1.0f : -1.0f) / (shift ? 96.0f : 12.0f), 0, 1);
        break;
    case Qt::Key_Up: case Qt::Key_Down: {
        if (!any) { e->ignore(); break; }
        float dir = e->key() == Qt::Key_Up ? 1.0f : -1.0f;
        // Gain, or Q with Alt (and for bands without gain)
        bool q = e->modifiers() & Qt::AltModifier;
        if (!q) { bool gainAny = false; for (int b = 0; b < BANDS_PER_CHANNEL; b++) if (m_selected[b] && usesGain(m_bands[b].filter_type)) gainAny = true; q = !gainAny; }
        if (q) nudge(0, 0, std::pow(2.0f, dir * (shift ? 0.02f : 0.1f)));
        else nudge(0, dir * (shift ? 0.1f : 0.5f), 1);
        break;
    }
    default:
        e->ignore();
    }
}

// ── Drawing ──

void PeqEditorItem::paint(QPainter *p) {
    if (!m_active || width() < 10 || height() < 10) return;
    p->setRenderHint(QPainter::Antialiasing);
#ifdef Q_OS_MACOS
    // Global EQ bypass dims the bands of input channels only (PeqGraphEditor
    // dimAll; config.flat is set for inputs)
    if (m_bridge->bypass() && m_bridge->isInputChannel(m_channel)) p->setOpacity(0.5);
#else
    if (m_bridge->bypass()) p->setOpacity(0.5);   // global EQ bypass
#endif

    // Lobes and outlines: plain bands first, lit ones on top
    for (int pass = 0; pass < 2; pass++)
        for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
            if (!isEditable(b)) continue;
            float lift = qMax(m_hoverAmt[b], m_selectAmt[b]);
            if ((lift > 0.01f) == (pass == 1)) drawBand(p, b, lift);
        }

    // The channel's combined curve (the graph leaves it out while editing)
    QPainterPath curve = curvePath(m_combined, m_offset);
    if (m_showGlow) {
        QColor g = m_channelColor;
        g.setAlphaF(0.3);
        p->setPen(QPen(g, m_lineWidth * 4.0, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->drawPath(curve);
        g.setAlphaF(0.6);
        p->setPen(QPen(g, m_lineWidth * 2.0, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->drawPath(curve);
    }
    p->setPen(QPen(m_channelColor, m_lineWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    p->drawPath(curve);

    // Dots: flat discs in the band colour, emphasised last
    for (int pass = 0; pass < 2; pass++) {
        for (int b = 0; b < BANDS_PER_CHANNEL; b++) {
            if (!isEditable(b)) continue;
            bool emph = m_hoverAmt[b] > 0.01f || m_selectAmt[b] > 0.01f;
            if (emph != (pass == 1)) continue;
            QColor c = bandColor(b);
            if (m_bands[b].bypass) { c = bypassColor(b); c.setAlphaF(0.55); }
            float lift = qMax(m_hoverAmt[b], m_selectAmt[b]);
            qreal r = kDotRadius + 1.5 * lift + 0.5 * m_selectAmt[b];
            QPointF at = dotPos(b);
            p->setPen(Qt::NoPen);
            p->setBrush(c);
            p->drawEllipse(at, r, r);
            if (m_selectAmt[b] > 0.01f) {
#ifdef Q_OS_MACOS
                // peqNodeColor: the centre mixes in at min(2 x selection, 1)
                QColor pipColor = m_background;
                pipColor.setAlphaF(m_background.alphaF() * qMin(2.0f * m_selectAmt[b], 1.0f));
                p->setBrush(pipColor);
#else
                p->setBrush(m_background);
#endif
                qreal pip = 2.2 * m_selectAmt[b];
                p->drawEllipse(at, pip, pip);
            }
        }
    }

    // Marquee
    if (m_mode == Marquee && !m_marquee.isEmpty()) {
#ifdef Q_OS_MACOS
        // A layer of its own over the Metal view: never dimmed by the bypass
        p->setOpacity(1.0);
        QPen pen(QColor::fromRgbF(1, 1, 1, 0.45), 1.0, Qt::DashLine);
        pen.setDashPattern({4, 3});
        p->setPen(pen);
        p->setBrush(QColor::fromRgbF(1, 1, 1, 0.06));
#else
        QPen pen(QColor(255, 255, 255, 115), 1.0, Qt::DashLine);
        pen.setDashPattern({4, 3});
        p->setPen(pen);
        p->setBrush(QColor(255, 255, 255, 15));
#endif
        p->drawRect(m_marquee);
    }

    p->setOpacity(1.0);
    drawReadouts(p);

}

void PeqEditorItem::drawBand(QPainter *p, int b, float lift) {
    const bool bypassed = m_bands[b].bypass;
    QColor c = bypassed ? bypassColor(b) : bandColor(b);
    QPainterPath curve = curvePath(m_bandCurve[b], m_offset);
    const qreal y0 = yForDb(m_offset);

    // How far the band strays from 0 dB inside the view, and on which side
    double peak = 0;
    for (int i = 0; i < MAGNITUDE_POINTS; i++)
        if (std::fabs(m_bandCurve[b][i]) > std::fabs(peak)) peak = m_bandCurve[b][i];
    const qreal yPeak = qBound(-height(), yForDb(float(peak) + m_offset), 2 * height());
    const qreal span = std::fabs(yPeak - y0);
    if (span < 0.5) return;
    // A band that barely departs from flat fades out rather than leaving a line
    const qreal presence = qBound(0.0, (span - 2.0) / 8.0, 1.0);
    const qreal smooth = presence * presence * (3 - 2 * presence);

    // Lobe: the area between the band's curve and 0 dB, strongest along the
    // curve and fading to nothing at 0 dB (alpha ~ t^1.5, as on macOS)
    QPainterPath lobe = curve;
    lobe.lineTo(curve.currentPosition().x(), y0);
    lobe.lineTo(curve.elementAt(0).x, y0);
    lobe.closeSubpath();
    const qreal fillAlpha = (bypassed ? 0.06 + 0.06 * lift : 0.22 + 0.2 * lift) * smooth;
    QLinearGradient g(0, y0, 0, yPeak);
    for (int i = 0; i <= 6; i++) {
        qreal t = i / 6.0;
        QColor stop = c;
        stop.setAlphaF(fillAlpha * std::pow(t, 1.5));
        g.setColorAt(t, stop);
    }
    p->setPen(Qt::NoPen);
    p->setBrush(g);
    p->drawPath(lobe);

    // Outline while lit (always faint on a bypassed band), dissolving as it nears 0 dB
    const qreal lineAlpha = (bypassed ? 0.35 + 0.25 * lift : 0.9 * lift) * smooth;
    if (lineAlpha > 0.01) {
        const qreal fade = qMin(span, 14.0) / span;      // 14 px to full strength
        QLinearGradient lg(0, y0, 0, yPeak);
        QColor clear = c, solid = c;
        clear.setAlphaF(0);
        solid.setAlphaF(lineAlpha);
#ifdef Q_OS_MACOS
        // peqStroke: the outline fades by smoothstep(2, 10) px from 0 dB
        Q_UNUSED(fade);
        lg.setColorAt(0, clear);
        for (int k = 0; k <= 8; k++) {
            const qreal d = 2.0 + k;
            if (d >= span) break;
            const qreal s = k / 8.0;
            QColor stop = c;
            stop.setAlphaF(lineAlpha * s * s * (3 - 2 * s));
            lg.setColorAt(d / span, stop);
        }
        if (span > 10.0) lg.setColorAt(1, solid);
        else {
            const qreal s = qBound(0.0, (span - 2.0) / 8.0, 1.0);
            QColor stop = c;
            stop.setAlphaF(lineAlpha * s * s * (3 - 2 * s));
            lg.setColorAt(1, stop);
        }
#else
        lg.setColorAt(0, clear);
        lg.setColorAt(fade, solid);
        lg.setColorAt(1, solid);
#endif
        p->setBrush(Qt::NoBrush);
        p->setPen(QPen(QBrush(lg), 1.25, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->drawPath(curve);
    }
}

static QString freqText(float f) {
    return f >= 1000.0f ? QString::number(f / 1000.0f, 'f', f >= 10000.0f ? 1 : 2) + " kHz"
                        : QString::number(f, 'f', f < 100.0f ? 1 : 0) + " Hz";
}

// Pointer readouts over empty graph, a ghost dot where a double-click would
// add a band, and any transient message
void PeqEditorItem::drawReadouts(QPainter *p) {
    QFont font = p->font();
    font.setPixelSize(10);
    font.setBold(true);
    p->setFont(font);
    auto pill = [&](const QRectF &r, const QString &text) {
        p->setPen(Qt::NoPen);
#ifdef Q_OS_MACOS
        // Axis labels in PeqGraphEditor: sRGB (0.09, 0.09, 0.11) at 0.92, text white at 0.85
        p->setBrush(QColor::fromRgbF(0.09, 0.09, 0.11, 0.92));
        p->drawRoundedRect(r, 4, 4);
        p->setPen(QColor::fromRgbF(1, 1, 1, 0.85));
#else
        p->setBrush(QColor(23, 23, 28, 235));
        p->drawRoundedRect(r, 4, 4);
        p->setPen(QColor(255, 255, 255, 220));
#endif
        p->drawText(r, Qt::AlignCenter, text);
    };
    if (m_cardOpen) {
        // The new band's place while its shape is being picked
        p->setPen(Qt::NoPen);
        p->setBrush(QColor(255, 255, 255, 77));
        p->drawEllipse(m_cardPoint, kDotRadius, kDotRadius);
        return;
    }
    bool overEmpty = m_pointerInside && m_hoverDot < 0 && m_mode != DragDot && m_mode != DragQ && m_mode != Marquee;
    if (overEmpty) {
        if (m_showFreqReadout) {
            QString t = freqText(freqForX(m_pointer.x()));
            qreal w = p->fontMetrics().horizontalAdvance(t) + 12;
            pill(QRectF(qBound(2.0, m_pointer.x() - w / 2, width() - w - 2), height() - 18, w, 16), t);
        }
        if (m_showLevelReadout) {
            QString t = QString::asprintf("%+.1f dB", dbForY(m_pointer.y()));
            qreal w = p->fontMetrics().horizontalAdvance(t) + 12;
            pill(QRectF(2, qBound(2.0, m_pointer.y() - 8, height() - 18), w, 16), t);
        }
        if (firstFreeBand() >= 0) {
            p->setPen(Qt::NoPen);
            p->setBrush(QColor(255, 255, 255, 77));
            p->drawEllipse(m_pointer, kDotRadius, kDotRadius);
        }
    }
    if (!m_message.isEmpty()) {
        qreal w = p->fontMetrics().horizontalAdvance(m_message) + 16;
        pill(QRectF((width() - w) / 2, 8, w, 18), m_message);
    }
}
