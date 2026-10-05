#include "SiggenController.h"
#include "DSPiBridge.h"

#include <cstring>
#include <cmath>

namespace {
enum { Unused = 0, Hz = 1, Ms = 2, Cycles = 3, Count = 4, Ratio = 5, Pattern = 6 };
enum { Continuous = 0, Sweep = 1, PatternTiming = 2 };
enum { TypeChannelId = 14 };

struct Fallback { int timing; SiggenParam p[4]; };
// The macOS Console's built-in table, for a device that gives no descriptor
const Fallback kFallback[SIGGEN_TYPE_COUNT] = {
    { Continuous, { { Hz, 1, 30000, 1000 } } },                                       // sine
    { Continuous, { { Hz, 1, 30000, 100 } } },                                        // square
    { Continuous, {} },                                                               // white
    { Continuous, {} },                                                               // pink
    { Sweep, { { Hz, 1, 30000, 20 }, { Hz, 1, 30000, 20000 } } },                     // log sweep
    { Sweep, { { Hz, 1, 30000, 20 }, { Hz, 1, 30000, 20000 } } },                     // linear sweep
    { Sweep, { { Hz, 1, 30000, 20 }, { Hz, 1, 30000, 20000 }, { Count, 1, 24, 3 }, { Ms, 20, 10000, 250 } } },
    { PatternTiming, { { Ms, 10, 60000, 500 } } },                                    // impulse
    { PatternTiming, { { Ms, 10, 60000, 500 } } },                                    // clicks
    { PatternTiming, { { Ms, 1, 100, 5 }, { Ms, 10, 60000, 500 } } },                 // polarity
    { PatternTiming, { { Hz, 1, 30000, 1000 }, { Cycles, 1, 1000, 8 }, { Cycles, 0, 1000, 8 }, { Cycles, 0, 100, 2 } } },
    { Continuous, { { Hz, 1, 30000, 60 }, { Hz, 1, 30000, 7000 }, { Ratio, 0.1f, 10, 4 } } },
    { Continuous, { { Count, 2, 16, 10 }, { Hz, 1, 30000, 20 }, { Hz, 1, 30000, 20000 } } },
    { Continuous, { { Pattern, 0, 1, 0 } } },                                         // ISP
    { PatternTiming, { { Ms, 30, 1000, 120 } } },                                     // channel ID
};
}

SiggenController::SiggenController(DSPiBridge *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge), m_core(bridge->core())
{
    // The macOS default: a 1 kHz sine on outputs 1-2 at -20 dBFS
    m_draft.signal_type = 0;
    m_draft.channel_mask = 0x0003;
    m_draft.level_db = -20.0f;
    m_draft.p[0] = 1000.0f;

    m_poll.setInterval(300);
    connect(&m_poll, &QTimer::timeout, this, &SiggenController::refreshStatus);
    m_apply.setSingleShot(true);
    m_apply.setInterval(350);
    connect(&m_apply, &QTimer::timeout, this, &SiggenController::applyLive);

    connect(m_bridge, &DSPiBridge::devicesChanged, this, &SiggenController::onDeviceChanged);
    connect(m_bridge, &DSPiBridge::siggenNotified, this, &SiggenController::refreshStatus);
    onDeviceChanged();
}

// A new device (or none): read its generator once, adopt its applied signal
void SiggenController::onDeviceChanged() {
    const bool usable = m_bridge->connected() && m_bridge->compat() == COMPAT_OK;
    const QString serial = usable ? m_bridge->selectedSerial() : QString();
    if (serial == m_serial) return;
    m_serial = serial;
    m_apply.stop();
    std::memset(&m_status, 0, sizeof(m_status));
    std::memset(&m_sent, 0, sizeof(m_sent));
    std::memset(&m_caps, 0, sizeof(m_caps));
    if (usable && !dspi_siggen_fetch_caps(m_core, &m_caps)) {
        // USB trouble, not a missing generator: try again on the next change
        std::memset(&m_caps, 0, sizeof(m_caps));
        m_serial.clear();
    } else if (usable && m_caps.supported) {
        SiggenConfig applied;
        // The device's applied signal becomes the draft, unless it is an
        // Identify left behind (Channel ID on one output)
        if (dspi_siggen_get_config(m_core, &applied) && applied.channel_mask != 0
            && applied.signal_type != TypeChannelId) {
            m_draft = applied;
        } else {
            m_draft.channel_mask &= uint16_t(usableMask());
            if (!m_draft.channel_mask) m_draft.channel_mask = 1;
        }
        dspi_siggen_get_status(m_core, &m_status);
        if (running()) m_sent = m_draft;
    }
    emit capsChanged();
    emit draftChanged();
    emit statusChanged();
    updatePolling();
}

void SiggenController::refreshStatus() {
    if (!m_caps.supported) return;
    SiggenStatus s;
    if (!dspi_siggen_get_status(m_core, &s)) return;
    if (std::memcmp(&s, &m_status, sizeof(s)) != 0) {
        m_status = s;
        emit statusChanged();
    }
    updatePolling();
}

void SiggenController::setWatching(bool w) {
    if (w == m_watching) return;
    m_watching = w;
    emit watchingChanged();
    if (w) refreshStatus();
    updatePolling();
}

// Fades, gaps and walk steps come only from polling
void SiggenController::updatePolling() {
    bool on = m_watching && running() && m_caps.supported;
    if (on && !m_poll.isActive()) m_poll.start();
    else if (!on) m_poll.stop();
}

int SiggenController::usableMask() const {
    if (m_caps.valid_mask) return m_caps.valid_mask;
    int n = m_caps.output_channels ? m_caps.output_channels : m_bridge->numOutputChannels();
    return (1 << qBound(0, n, 16)) - 1;
}

SiggenTypeInfo SiggenController::typeDesc(int type) const {
    type = qBound(0, type, SIGGEN_TYPE_COUNT - 1);
    if (m_caps.supported && type < m_caps.type_count && m_caps.types[type].id == type)
        return m_caps.types[type];
    SiggenTypeInfo t {};
    t.id = uint8_t(type);
    t.timing = uint8_t(kFallback[type].timing);
    for (int k = 0; k < 4; k++) t.params[k] = kFallback[type].p[k];
    return t;
}

QVariantMap SiggenController::typeInfo(int type) const {
    SiggenTypeInfo t = typeDesc(type);
    QVariantList params;
    for (const SiggenParam &p : t.params)
        params.append(QVariantMap{ { "semantic", p.semantic }, { "min", p.min }, { "max", p.max }, { "def", p.def } });
    return { { "timing", t.timing }, { "params", params } };
}

QVariantMap SiggenController::draft() const {
    QVariantList p;
    for (float v : m_draft.p) p.append(v);
    return {
        { "type", m_draft.signal_type }, { "channelMask", m_draft.channel_mask },
        { "invertMask", m_draft.invert_mask }, { "flags", m_draft.flags },
        { "levelDb", m_draft.level_db }, { "durationMs", m_draft.duration_ms },
        { "repeat", m_draft.repeat }, { "gapMs", m_draft.gap_ms }, { "p", p },
    };
}

// What is sent: levels and parameters in range, unused parameters zero,
// inverted outputs a subset of the selected ones
SiggenConfig SiggenController::normalised(SiggenConfig c) const {
    SiggenTypeInfo t = typeDesc(c.signal_type);
    c.level_db = std::isfinite(c.level_db) ? qBound(-120.0f, c.level_db, 0.0f) : -20.0f;
    for (int k = 0; k < 4; k++) {
        const SiggenParam &d = t.params[k];
        if (d.semantic == Unused) { c.p[k] = 0; continue; }
        float v = std::isfinite(c.p[k]) ? c.p[k] : d.def;
        v = qMax(v, d.min);
        if (d.max > 0) v = qMin(v, d.max);
        c.p[k] = v;
    }
    c.channel_mask &= uint16_t(usableMask());
    c.invert_mask &= c.channel_mask;
    if (t.timing == Sweep && c.duration_ms == 0) c.duration_ms = 1000;   // refused otherwise
    return c;
}

void SiggenController::selectType(int type) {
    type = qBound(0, type, SIGGEN_TYPE_COUNT - 1);
    SiggenTypeInfo t = typeDesc(type);
    m_draft.signal_type = uint8_t(type);
    for (int k = 0; k < 4; k++) m_draft.p[k] = t.params[k].semantic == Unused ? 0 : t.params[k].def;
    m_draft.repeat = 0;
    m_draft.gap_ms = 0;
    m_draft.duration_ms = t.timing == Sweep ? 5000 : 0;
    emit draftChanged();
    scheduleApply();
}

void SiggenController::setDraftValue(const QString &field, const QVariant &value) {
    SiggenConfig before = m_draft;
    if (field == "levelDb") m_draft.level_db = qBound(-120.0f, value.toFloat(), 0.0f);
    else if (field == "durationMs") m_draft.duration_ms = uint32_t(qMax(0.0, value.toDouble()));
    else if (field == "repeat") m_draft.repeat = uint16_t(qBound(0, value.toInt(), 65535));
    else if (field == "gapMs") m_draft.gap_ms = uint16_t(qBound(0, value.toInt(), 65535));
    else return;
    if (std::memcmp(&before, &m_draft, sizeof(before)) == 0) return;
    emit draftChanged();
    scheduleApply();
}

void SiggenController::setParam(int index, double value) {
    if (index < 0 || index > 3 || m_draft.p[index] == float(value)) return;
    m_draft.p[index] = float(value);
    emit draftChanged();
    scheduleApply();
}

void SiggenController::setFlag(int flag, bool on) {
    uint8_t f = on ? (m_draft.flags | flag) : (m_draft.flags & ~flag);
    if (f == m_draft.flags) return;
    m_draft.flags = f;
    emit draftChanged();
    scheduleApply();
}

void SiggenController::cycleOutput(int output) {
    if (output < 0 || output > 15) return;
    const uint16_t bit = uint16_t(1 << output);
    if (!(m_draft.channel_mask & bit)) m_draft.channel_mask |= bit;
    else if (!(m_draft.invert_mask & bit)) m_draft.invert_mask |= bit;
    else { m_draft.channel_mask &= ~bit; m_draft.invert_mask &= ~bit; }
    emit draftChanged();
    scheduleApply();
}

void SiggenController::selectAllOutputs() {
    if (m_draft.channel_mask == uint16_t(usableMask())) return;
    m_draft.channel_mask = uint16_t(usableMask());
    emit draftChanged();
    scheduleApply();
}

void SiggenController::clearOutputs() {
    if (!m_draft.channel_mask && !m_draft.invert_mask) return;
    m_draft.channel_mask = 0;
    m_draft.invert_mask = 0;
    emit draftChanged();
    scheduleApply();
}

// Edits while a signal plays apply after a pause in the typing or dragging
void SiggenController::scheduleApply() {
    if (running()) m_apply.start();
}

void SiggenController::applyLive() {
    if (!running() || !m_caps.supported) return;
    SiggenConfig c = normalised(m_draft);
    if (std::memcmp(&c, &m_sent, sizeof(c)) == 0) return;
    if (!c.channel_mask) {
        // The device refuses an empty selection: no outputs means stop
        stop();
        return;
    }
    if (dspi_siggen_set_config(m_core, &c)) m_sent = c;
    refreshStatus();
}

bool SiggenController::start() {
    if (!m_caps.supported) return false;
    m_apply.stop();
    SiggenConfig c = normalised(m_draft);
    if (!c.channel_mask) return false;
    if (!dspi_siggen_set_config(m_core, &c)) return false;
    // The device ACKs a config it refuses; idle, it applies one at once
    SiggenConfig back;
    if (!running() && dspi_siggen_get_config(m_core, &back)
        && (back.signal_type != c.signal_type || back.channel_mask != c.channel_mask)) {
        refreshStatus();
        return false;
    }
    bool ok = dspi_siggen_control(m_core, SIGGEN_CTL_START);
    if (ok) m_sent = c;
    refreshStatus();
    return ok;
}

void SiggenController::stop() {
    m_apply.stop();
    dspi_siggen_control(m_core, SIGGEN_CTL_STOP);
    refreshStatus();
}

void SiggenController::stopNow() {
    m_apply.stop();
    dspi_siggen_control(m_core, SIGGEN_CTL_STOP_NOW);
    refreshStatus();
}

void SiggenController::identify(int output) {
    if (!m_caps.supported || output < 0 || output > 15) return;
    SiggenConfig c {};
    c.signal_type = TypeChannelId;
    c.channel_mask = uint16_t((1 << output) & usableMask());
    if (!c.channel_mask) return;
    c.level_db = -12.0f;
    c.repeat = 2;
    c.p[0] = 120.0f;
    m_apply.stop();
    if (dspi_siggen_set_config(m_core, &c) && dspi_siggen_control(m_core, SIGGEN_CTL_START)) m_sent = c;
    refreshStatus();
}
