#include "RtaController.h"
#include "DSPiBridge.h"

#include <QMetaObject>
#include <QtAlgorithms>
#include <cstring>

RtaController::RtaController(DSPiBridge *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge), m_core(bridge->core())
{
    dspi_rta_set_callback(m_core, &RtaController::wakeCallback, this);
    std::memset(&m_snap, 0, sizeof(m_snap));
    m_snap.first_band = 0xFF;
    // A reconnect may change which channels exist
    connect(m_bridge, &DSPiBridge::devicesChanged, this, &RtaController::pushRequest);
}

RtaController::~RtaController() {
    // The worker outlives this object (it stops with the core)
    dspi_rta_set_callback(m_core, nullptr, nullptr);
}

// Worker thread: hand over to the GUI thread once per batch
void RtaController::wakeCallback(void *userData) {
    auto *self = static_cast<RtaController *>(userData);
    if (self->m_wakePending.testAndSetOrdered(0, 1))
        QMetaObject::invokeMethod(self, "onWake", Qt::QueuedConnection);
}

void RtaController::onWake() {
    m_wakePending.storeRelease(0);
    RtaCapsInfo caps;
    dspi_rta_get_caps(m_core, &caps);
    if (std::memcmp(&caps, &m_caps, sizeof(caps)) != 0) {
        m_caps = caps;
        emit capsChanged();
        pushRequest();
    }
    uint32_t version = m_snap.version, telemetry = m_snap.telemetry_version;
    dspi_rta_get_snapshot(m_core, &m_snap);
    if (m_snap.version != version) emit frameChanged();
    if (m_snap.telemetry_version != telemetry) emit telemetryChanged();
}

int RtaController::lowestShadedHz() const {
    if (!m_caps.supported || m_snap.count == 0) return 0;
    int n = 0;
    for (int i = 0; i < m_snap.count; i++) n = qMax(n, int(m_snap.frames[i].n_bands));
    int highest = -1;
    for (int b = m_caps.bass_bands; b < n && b < RTA_MAX_BANDS; b++)
        if (!(m_snap.populated >> b & 1)) highest = b;
    return highest >= 0 ? m_caps.centres[highest] : 0;
}

void RtaController::setFftOrder(int v) { if (v != m_fftOrder) { m_fftOrder = v; emit optionsChanged(); pushRequest(); } }
void RtaController::setAvgMs(int v) { if (v != m_avgMs) { m_avgMs = v; emit optionsChanged(); pushRequest(); } }
void RtaController::setPeakDecay(int v) { if (v != m_peakDecay) { m_peakDecay = v; emit optionsChanged(); pushRequest(); } }

int RtaController::subscribe(int tap, int mask, bool wantsBins) {
    int id = m_nextId++;
    m_subs.insert(id, { tap, mask, wantsBins, ++m_seq });
    pushRequest();
    return id;
}

void RtaController::update(int id, int tap, int mask, bool wantsBins) {
    auto it = m_subs.find(id);
    if (it == m_subs.end()) return;
    // An unchanged request keeps its place, so it doesn't take the tap
    if (it->tap == tap && it->mask == mask && it->bins == wantsBins) return;
    *it = { tap, mask, wantsBins, ++m_seq };
    pushRequest();
}

void RtaController::release(int id) {
    if (m_subs.remove(id)) pushRequest();
}

// The newest subscription picks the tap; every subscription at that tap adds
// its channels, except that one drawing bins gets its own channel alone (the
// device keeps bins for the last channel it transformed).
void RtaController::pushRequest() {
    RtaRequest r {};
    const Sub *primary = nullptr;
    for (const Sub &s : m_subs)
        if (s.mask && (!primary || s.seq > primary->seq)) primary = &s;
    if (primary && m_caps.supported) {
        r.tap = uint8_t(primary->tap);
        if (primary->bins) {
            r.mask = uint16_t(primary->mask);
        } else {
            for (const Sub &s : m_subs)
                if (s.tap == primary->tap) r.mask |= uint16_t(s.mask);
        }
        // Bins for one channel, if any view there draws them (whichever
        // view subscribed last)
        if (qPopulationCount(r.mask) == 1)
            for (const Sub &s : m_subs)
                if (s.tap == primary->tap && s.bins && s.mask == r.mask) r.wants_bins = true;
        r.fft_order = uint8_t(qBound<int>(m_caps.order_min, m_fftOrder, m_caps.order_max));
        r.avg_ms = uint16_t(qBound(0, m_avgMs, 10000));
        r.peak_decay_db_s = uint8_t(qBound(0, m_peakDecay, 100));
    }
    if (std::memcmp(&r, &m_sent, sizeof(r)) == 0) return;
    m_sent = r;
    dspi_rta_set_request(m_core, &r);
}

int RtaController::appChannel(int tap, int index) const {
    if (index < 0) return -1;
    return tap == RTA_TAP_INPUT ? m_bridge->inputAppId(index) : index + 2;
}

int RtaController::tapOf(int appChannel) const {
    if (appChannel < 0) return -1;
    return m_bridge->isInputChannel(appChannel) ? RTA_TAP_INPUT : RTA_TAP_OUTPUT;
}

int RtaController::tapIndex(int appChannel) const {
    for (int i = 0; i < 16; i++)
        if (m_bridge->inputAppId(i) == appChannel) return i;
    return appChannel >= 2 && appChannel <= 10 ? appChannel - 2 : -1;
}

QVariantList RtaController::availableChannels(int tap) const {
    QVariantList l;
    if (!m_caps.supported) return l;
    if (tap == RTA_TAP_INPUT) {
        int n = qMin<int>(m_bridge->liveInputCount(), m_caps.input_channels);
        for (int i = 0; i < n; i++) l.append(i);
    } else {
        int n = qMin<int>(m_bridge->numOutputChannels(), m_caps.output_channels);
        for (int o = 0; o < n; o++)
            if (m_bridge->outputEnabled(o)) l.append(o);
    }
    return l;
}
