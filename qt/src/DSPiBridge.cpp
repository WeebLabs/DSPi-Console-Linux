#include "DSPiBridge.h"
#include <QDebug>
#include <QSettings>
#include <QDateTime>
#include <cstring>
#include <cmath>

// Channel colors matching the macOS Console's ChannelPalette.
static const char *kInputColors[MAX_INPUTS] = {
    "#4A8FE3", // IN1 - blue
    "#F57373", // IN2 - red
    "#73C78C", // IN3 - green
    "#EDB34D", // IN4 - amber
    "#998CEB", // IN5 - violet
    "#E68CC7", // IN6 - pink
    "#66C7D1", // IN7 - teal
    "#CCB86B", // IN8 - olive
};

static const char *kOutputColors[MAX_OUTPUTS - 1] = {
    "#45C2A3", // OUT1 - teal
    "#59D180", // OUT2 - green
    "#F0C459", // OUT3 - amber
    "#F2A64D", // OUT4 - orange
    "#598CF2", // OUT5 - blue
    "#8CB3F2", // OUT6 - light blue
    "#D97390", // OUT7 - rose
    "#F299A6", // OUT8 - pink
};

static const char *kPdmColor = "#BA87F2";

DSPiBridge::DSPiBridge(QObject *parent)
    : QObject(parent)
{
    m_core = dspi_core_new();

    // Only the first input pair is visible on the graph by default
    for (int i = 0; i < kAppChannelCount; i++)
        m_channelVisible[i] = (i < 2);

    memset(&m_status, 0, sizeof(m_status));

    // Status timer (60ms)
    m_statusTimer = new QTimer(this);
    m_statusTimer->setInterval(60);
    connect(m_statusTimer, &QTimer::timeout, this, &DSPiBridge::pollStatus);
    m_statusTimer->start();

    // Hotplug timer (500ms)
    m_hotplugTimer = new QTimer(this);
    m_hotplugTimer->setInterval(500);
    connect(m_hotplugTimer, &QTimer::timeout, this, &DSPiBridge::pollHotplug);

    dspi_set_hotplug_callback(m_core, &DSPiBridge::hotplugCallback, this);
    m_hotplugTimer->start();

    scanDevices();
}

DSPiBridge::~DSPiBridge()
{
    if (m_statusTimer) m_statusTimer->stop();
    if (m_hotplugTimer) m_hotplugTimer->stop();
    if (m_core) dspi_core_free(m_core);
}

const DspState *DSPiBridge::state() const
{
    return dspi_get_state(m_core);
}

bool DSPiBridge::usable() const
{
    return connected() && state()->compat == COMPAT_OK;
}

// ── Channel mapping ──

int DSPiBridge::wire(int appCh) const
{
    auto *s = state();
    if (appCh < 0 || appCh >= kAppChannelCount) return -1;
    if (appCh < 2)
        return appCh < s->num_input_channels ? appCh : -1;
    if (appCh >= kAppExtraInputFirst) {
        int input = 2 + (appCh - kAppExtraInputFirst);
        return input < s->num_input_channels ? input : -1;
    }
    int output = appCh - 2;
    return output < s->num_output_channels ? s->num_input_channels + output : -1;
}

int DSPiBridge::appId(int wireCh) const
{
    auto *s = state();
    if (wireCh < 0 || wireCh >= s->num_channels) return -1;
    if (wireCh < s->num_input_channels)
        return wireCh < 2 ? wireCh : kAppExtraInputFirst + (wireCh - 2);
    return 2 + (wireCh - s->num_input_channels);
}

int DSPiBridge::outputOf(int appCh) const
{
    if (appCh < 2 || appCh >= kAppExtraInputFirst) return -1;
    int output = appCh - 2;
    return output < state()->num_output_channels ? output : -1;
}

int DSPiBridge::inputOf(int appCh) const
{
    int input = -1;
    if (appCh >= 0 && appCh < 2) input = appCh;
    else if (appCh >= kAppExtraInputFirst && appCh < kAppChannelCount)
        input = 2 + (appCh - kAppExtraInputFirst);
    return (input >= 0 && input < state()->num_input_channels) ? input : -1;
}

void DSPiBridge::markAllDirty()
{
    for (int i = 0; i < kAppChannelCount; i++) {
        m_magnitudeDirty[i] = true;
        m_magnitudeValid[i] = false;
    }
}

void DSPiBridge::markDirty(int appCh)
{
    if (appCh >= 0 && appCh < kAppChannelCount) {
        m_magnitudeDirty[appCh] = true;
        m_magnitudeValid[appCh] = false;
    }
}

// ── Hotplug ──

void DSPiBridge::hotplugCallback(uint8_t event, const char *serial, void *userData)
{
    auto *self = static_cast<DSPiBridge *>(userData);
    QString ser = QString::fromUtf8(serial);
    if (event == 0) {
        QMetaObject::invokeMethod(self, [self, ser]() {
            self->scanDevices();
            emit self->deviceArrived(ser);
            // The core reconnects a returning device by itself, but its state
            // has to be read again, so (re)select whenever nothing is selected.
            if (self->m_selectedSerial.isEmpty() || !self->connected())
                self->selectDevice(ser);
        }, Qt::QueuedConnection);
    } else {
        QMetaObject::invokeMethod(self, [self, ser]() {
            if (self->m_selectedSerial == ser) {
                dspi_disconnect(self->m_core);
                self->m_selectedSerial.clear();
                self->markAllDirty();
                emit self->stateChanged();
                emit self->statusChanged();
            }
            self->scanDevices();
            emit self->deviceDeparted(ser);
        }, Qt::QueuedConnection);
    }
}

// ── Timers ──

void DSPiBridge::pollStatus()
{
    if (!usable()) return;
    SystemStatus newStatus;
    if (dspi_fetch_status(m_core, &newStatus)) {
        // Clip flags are sticky on the device. Latch each clip here with a
        // timestamp and read-then-clear the device flags, so a clip marker
        // clears itself 10 s after the last clip (as on the macOS Console).
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (newStatus.clip_flags) {
            for (int w = 0; w < MAX_CHANNELS; w++)
                if ((newStatus.clip_flags >> w) & 1u) m_lastClipMs[w] = now;
            dspi_clear_clips(m_core);
        }
        uint32_t latched = 0;
        for (int w = 0; w < MAX_CHANNELS; w++)
            if (m_lastClipMs[w] && now - m_lastClipMs[w] < 10000) latched |= (1u << w);
        newStatus.clip_flags = latched;

        bool changed = memcmp(&m_status, &newStatus, sizeof(SystemStatus)) != 0;
        m_status = newStatus;

        bool anyLimiter = false;
        for (int o = 0; o < state()->num_output_channels; o++)
            anyLimiter |= state()->limiter_enabled[o];
        if (anyLimiter && (++m_pollTick % 4) == 0) {
            float gr[MAX_OUTPUTS];
            if (dspi_fetch_limiter_meter(m_core, gr) && memcmp(gr, m_limiterGR, sizeof(gr)) != 0) {
                memcpy(m_limiterGR, gr, sizeof(gr));
                changed = true;
            }
        } else if (!anyLimiter) {
            memset(m_limiterGR, 0, sizeof(m_limiterGR));
        }
        if (changed) emit statusChanged();
    }
}

void DSPiBridge::pollHotplug()
{
    dspi_poll_hotplug(m_core);
    // Retry the scan while disconnected: covers an initial scan that ran
    // before USB enumeration finished.
    if (!connected())
        scanDevices();
}

// ── Property getters ──

bool DSPiBridge::connected() const { return dspi_is_connected(m_core); }
QString DSPiBridge::selectedSerial() const { return m_selectedSerial; }
QStringList DSPiBridge::availableSerials() const { return m_availableSerials; }

QString DSPiBridge::platformName() const {
    return state()->platform_id == 1 ? "RP2350" : "RP2040";
}

int DSPiBridge::numChannels() const { return state()->num_channels; }
int DSPiBridge::numInputChannels() const { return state()->num_input_channels; }
int DSPiBridge::numOutputChannels() const { return state()->num_output_channels; }

QString DSPiBridge::firmwareVersion() const {
    auto *s = state();
    if (!connected() || (s->fw_major == 0 && s->fw_minor == 0 && s->fw_patch == 0)) return "";
    QString v = QString("%1.%2.%3").arg(s->fw_major).arg(s->fw_minor).arg(s->fw_patch);
    if (s->fw_beta) v += QString("-beta%1").arg(s->fw_beta);
    return v;
}

int DSPiBridge::compat() const { return connected() ? state()->compat : COMPAT_UNKNOWN; }

QString DSPiBridge::compatMessage() const {
    switch (compat()) {
    case COMPAT_FIRMWARE_TOO_OLD:
        return QString("This DSPi runs firmware %1, which is too old for this Console. "
                       "Update it to firmware 1.1.6.").arg(firmwareVersion().isEmpty() ? "older than 1.1.6" : firmwareVersion());
    case COMPAT_FIRMWARE_TOO_NEW:
        return QString("This DSPi runs firmware %1, which is newer than this Console understands. "
                       "Update the Console.").arg(firmwareVersion());
    default:
        return "";
    }
}

float DSPiBridge::maxDelayMs() const { return dspi_max_delay_ms(m_core); }

float DSPiBridge::preampDB() const { return state()->input_preamp_db[0]; }
bool DSPiBridge::bypass() const { return state()->bypass; }

float DSPiBridge::masterVolumeDB() const { return state()->master_volume_db; }
int DSPiBridge::masterVolumeMode() const { return state()->master_volume_mode; }
float DSPiBridge::userVolumeDB() const { return state()->user_volume_db; }
bool DSPiBridge::userMute() const { return state()->user_mute; }

bool DSPiBridge::loudnessEnabled() const { return state()->loudness_enabled; }
float DSPiBridge::loudnessRefSPL() const { return state()->loudness_ref_spl; }
float DSPiBridge::loudnessIntensity() const { return state()->loudness_intensity; }
int DSPiBridge::loudnessOutputMask() const { return state()->loudness_output_mask; }

bool DSPiBridge::crossfeedEnabled() const { return state()->crossfeed_enabled; }
int DSPiBridge::crossfeedPreset() const { return state()->crossfeed_preset; }
float DSPiBridge::crossfeedFreq() const { return state()->crossfeed_freq; }
float DSPiBridge::crossfeedFeed() const { return state()->crossfeed_feed; }
bool DSPiBridge::crossfeedITD() const { return state()->crossfeed_itd; }
int DSPiBridge::crossfeedOutputPairMask() const { return state()->crossfeed_output_pair_mask; }

int DSPiBridge::cpu0() const { return m_status.cpu0; }
int DSPiBridge::cpu1() const { return m_status.cpu1; }

int DSPiBridge::clipFlags() const {
    // Re-key the wire-indexed clip bits by app id for the QML.
    int flags = 0;
    for (int w = 0; w < state()->num_channels; w++) {
        int id = appId(w);
        if (id >= 0 && ((m_status.clip_flags >> w) & 1u))
            flags |= (1 << id);
    }
    return flags;
}

int DSPiBridge::activeInputChannels() const { return m_status.active_input_channels; }

int DSPiBridge::activePresetSlot() const { return state()->active_preset_slot; }
int DSPiBridge::presetOccupied() const { return state()->preset_occupied; }
int DSPiBridge::presetStartupMode() const { return state()->preset_startup_mode; }
int DSPiBridge::presetDefaultSlot() const { return state()->preset_default_slot; }
int DSPiBridge::outputConfigMode() const { return state()->output_config_mode; }

int DSPiBridge::core1Mode() const { return state()->core1_mode; }

// ── Channel identity ──

bool DSPiBridge::channelExists(int ch) const { return wire(ch) >= 0; }

bool DSPiBridge::isInputChannel(int ch) const { return inputOf(ch) >= 0; }

int DSPiBridge::inputAppId(int input) const {
    if (input < 0 || input >= state()->num_input_channels) return -1;
    return input < 2 ? input : kAppExtraInputFirst + (input - 2);
}

float DSPiBridge::peakLevel(int ch) const {
    int w = wire(ch);
    return w >= 0 ? m_status.peaks[w] : 0.0f;
}

bool DSPiBridge::isClipping(int ch) const {
    int w = wire(ch);
    return w >= 0 && ((m_status.clip_flags >> w) & 1u);
}

QString DSPiBridge::channelName(int ch) const {
    int w = wire(ch);
    if (w < 0) return "";
    QString name = QString::fromUtf8(reinterpret_cast<const char *>(state()->channel_names[w]));
    if (!name.isEmpty()) return name;
    int in = inputOf(ch);
    if (in >= 0) return in < 2 ? (in == 0 ? "USB L" : "USB R") : QString("Input %1").arg(in + 1);
    int out = outputOf(ch);
    return isPdmOutput(out) ? QString("PDM") : QString("Output %1").arg(out + 1);
}

QString DSPiBridge::channelColor(int ch) const {
    int in = inputOf(ch);
    if (in >= 0) return QString::fromUtf8(kInputColors[in]);
    int out = outputOf(ch);
    if (out < 0) return "#FFFFFF";
    if (isPdmOutput(out)) return QString::fromUtf8(kPdmColor);
    return QString::fromUtf8(kOutputColors[out % (MAX_OUTPUTS - 1)]);
}

QString DSPiBridge::channelDescriptor(int ch) const {
    int in = inputOf(ch);
    if (in >= 0) return QString("IN%1").arg(in + 1);
    int out = outputOf(ch);
    return out >= 0 ? QString("OUT%1").arg(out + 1) : QString();
}

// ── PEQ bands ──

#define BAND_OR(ch, band, fallback)                                            \
    int w = wire(ch);                                                          \
    if (w < 0 || band < 0 || band >= BANDS_PER_CHANNEL) return fallback;       \
    const FilterParams &f = state()->filters[w][band];

int DSPiBridge::filterType(int ch, int band) const { BAND_OR(ch, band, 0) return f.filter_type; }
float DSPiBridge::filterFreq(int ch, int band) const { BAND_OR(ch, band, 1000.0f) return f.freq; }
float DSPiBridge::filterGain(int ch, int band) const { BAND_OR(ch, band, 0.0f) return f.gain; }
float DSPiBridge::filterQ(int ch, int band) const { BAND_OR(ch, band, 0.707f) return f.q; }
float DSPiBridge::filterQp(int ch, int band) const { BAND_OR(ch, band, 0.707f) return f.qp; }
bool DSPiBridge::filterBypass(int ch, int band) const { BAND_OR(ch, band, false) return f.bypass; }

#undef BAND_OR

// ── Crossover bands ──

#define XOVER_OR(ch, band, fallback)                                           \
    if (outputOf(ch) < 0 || band < 0 || band >= MAX_XOVER_BANDS) return fallback; \
    const FilterParams &f = state()->xover[wire(ch)][band];

int DSPiBridge::crossoverType(int ch, int band) const { XOVER_OR(ch, band, 0) return f.filter_type; }
float DSPiBridge::crossoverFreq(int ch, int band) const { XOVER_OR(ch, band, 1000.0f) return f.freq; }
bool DSPiBridge::crossoverBypass(int ch, int band) const { XOVER_OR(ch, band, false) return f.bypass; }

#undef XOVER_OR

// ── Inputs / outputs / matrix ──

float DSPiBridge::inputPreampDB(int input) const {
    if (input < 0 || input >= MAX_INPUTS) return 0.0f;
    return state()->input_preamp_db[input];
}

float DSPiBridge::channelDelayMS(int ch) const {
    int w = wire(ch);
    return w >= 0 ? state()->channel_delays[w] : 0.0f;
}

bool DSPiBridge::outputEnabled(int idx) const {
    if (idx < 0 || idx >= MAX_OUTPUTS) return false;
    return state()->output_enabled[idx];
}

bool DSPiBridge::outputMuted(int idx) const {
    if (idx < 0 || idx >= MAX_OUTPUTS) return false;
    return state()->output_muted[idx];
}

float DSPiBridge::outputGainDB(int idx) const {
    if (idx < 0 || idx >= MAX_OUTPUTS) return 0.0f;
    return state()->output_gain_db[idx];
}

float DSPiBridge::outputDelayMS(int idx) const {
    if (idx < 0 || idx >= MAX_OUTPUTS) return 0.0f;
    return state()->output_delay_ms[idx];
}

bool DSPiBridge::isPdmOutput(int idx) const {
    return idx >= 0 && idx == state()->num_output_channels - 1;
}

bool DSPiBridge::matrixRouting(int input, int output) const {
    if (input < 0 || input >= MAX_INPUTS || output < 0 || output >= MAX_OUTPUTS) return false;
    return state()->matrix_routing[input][output];
}

float DSPiBridge::matrixGain(int input, int output) const {
    if (input < 0 || input >= MAX_INPUTS || output < 0 || output >= MAX_OUTPUTS) return 0.0f;
    return state()->matrix_gain[input][output];
}

bool DSPiBridge::matrixInvert(int input, int output) const {
    if (input < 0 || input >= MAX_INPUTS || output < 0 || output >= MAX_OUTPUTS) return false;
    return state()->matrix_invert[input][output];
}

int DSPiBridge::outputPin(int physOut) const {
    if (physOut < 0 || physOut >= MAX_PHYSICAL_OUTPUTS) return -1;
    return state()->output_pins[physOut];
}

int DSPiBridge::numPinOutputs() const { return state()->num_pin_outputs; }

QString DSPiBridge::presetName(int slot) const {
    if (slot < 0 || slot >= MAX_PRESETS) return "";
    return QString::fromUtf8(reinterpret_cast<const char *>(state()->preset_names[slot]));
}

bool DSPiBridge::isPresetOccupied(int slot) const {
    if (slot < 0 || slot >= MAX_PRESETS) return false;
    return (state()->preset_occupied >> slot) & 1;
}

// ── Magnitude curves ──

void DSPiBridge::computeCurve(int appCh)
{
    // PEQ bands plus, for an output, its crossover bands.
    FilterParams bands[BANDS_PER_CHANNEL + MAX_XOVER_BANDS];
    int n = 0;
    int w = wire(appCh);
    if (w >= 0) {
        auto *s = state();
        for (int b = 0; b < BANDS_PER_CHANNEL; b++) bands[n++] = s->filters[w][b];
        if (outputOf(appCh) >= 0)
            for (int b = 0; b < MAX_XOVER_BANDS; b++) bands[n++] = s->xover[w][b];
    }
    dspi_compute_magnitude_curve(bands, n, m_magnitudeCache[appCh]);
    m_magnitudeDirty[appCh] = false;
    m_magnitudeValid[appCh] = true;
}

QVariantList DSPiBridge::magnitudeCurve(int ch) {
    QVariantList result;
    if (ch < 0 || ch >= kAppChannelCount) return result;
    if (m_magnitudeDirty[ch] || !m_magnitudeValid[ch]) computeCurve(ch);
    result.reserve(MAGNITUDE_POINTS);
    for (int i = 0; i < MAGNITUDE_POINTS; i++) result.append(m_magnitudeCache[ch][i]);
    return result;
}

void DSPiBridge::getMagnitudeCurve(int ch, double *out) {
    if (ch < 0 || ch >= kAppChannelCount) return;
    if (m_magnitudeDirty[ch] || !m_magnitudeValid[ch]) computeCurve(ch);
    memcpy(out, m_magnitudeCache[ch], sizeof(double) * MAGNITUDE_POINTS);
}

bool DSPiBridge::isMagnitudeDirty(int ch) const {
    if (ch < 0 || ch >= kAppChannelCount) return false;
    return m_magnitudeDirty[ch];
}

void DSPiBridge::clearMagnitudeDirty(int ch) {
    if (ch >= 0 && ch < kAppChannelCount) m_magnitudeDirty[ch] = false;
}

bool DSPiBridge::channelVisible(int ch) const {
    if (ch < 0 || ch >= kAppChannelCount) return false;
    return m_channelVisible[ch];
}

void DSPiBridge::setChannelVisible(int ch, bool visible) {
    if (ch < 0 || ch >= kAppChannelCount) return;
    if (m_channelVisible[ch] != visible) {
        m_channelVisible[ch] = visible;
        emit magnitudesChanged();
    }
}

// ── Setters ──

void DSPiBridge::setPreamp(float db) {
    dspi_set_preamp(m_core, db);
    emit stateChanged();
}

void DSPiBridge::sendPreampToDevice(float db) {
    dspi_set_preamp(m_core, db);
    // No stateChanged: used during a drag to avoid a feedback loop
}

// sendOnly: a live update during a drag. The device and the core's state
// change, but stateChanged isn't emitted (it re-evaluates the whole UI);
// the release commits with a normal call.
void DSPiBridge::setInputPreamp(int input, float db, bool sendOnly) {
    if (input < 0 || input >= state()->num_input_channels) return;
    dspi_set_input_preamp(m_core, input, db);
    // A linked pair gets one per-input write each (never the legacy
    // all-inputs preamp, which would clobber the other pairs).
    int partner = inputOf(linkedPartner(inputAppId(input)));
    if (partner >= 0) dspi_set_input_preamp(m_core, partner, db);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setBypass(bool en) {
    dspi_set_bypass(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setMasterVolume(float db, bool sendOnly) {
    dspi_set_master_volume(m_core, db);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setMasterVolumeMode(int mode) {
    dspi_set_master_volume_mode(m_core, mode);
    emit stateChanged();
}

int DSPiBridge::saveMasterVolume() {
    return dspi_save_master_volume(m_core);
}

void DSPiBridge::setUserVolume(float db, bool sendOnly) {
    dspi_set_user_volume(m_core, db);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setUserMute(bool muted) {
    dspi_set_user_mute(m_core, muted);
    emit stateChanged();
}

// Write one PEQ band to ch, and to its partner while the pair is linked.
void DSPiBridge::applyFilter(int ch, int band, const FilterParams &p) {
    for (int target : {ch, linkedPartner(ch)}) {
        int w = wire(target);
        if (w < 0) continue;
        dspi_set_filter(m_core, w, band, p);
        markDirty(target);
    }
}

void DSPiBridge::setFilter(int ch, int band, int type, float freq, float gain, float q) {
    int w = wire(ch);
    if (w < 0 || band < 0 || band >= BANDS_PER_CHANNEL) return;
    // Keep the band's bypass state and Linkwitz target Q across edits.
    FilterParams p = state()->filters[w][band];
    if (type != p.filter_type && type == FILTER_LINKWITZ_TRANSFORM) {
        // A new Linkwitz Transform starts with the target equal to the driver,
        // so it does nothing until fp or Qp changes.
        gain = freq;
        p.qp = q;
    }
    p.filter_type = static_cast<uint8_t>(type);
    p.freq = freq;
    p.gain = gain;
    p.q = q;
    applyFilter(ch, band, p);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::setLinkwitzTransform(int ch, int band, float f0, float q0, float fp, float qp) {
    int w = wire(ch);
    if (w < 0 || band < 0 || band >= BANDS_PER_CHANNEL) return;
    FilterParams p = state()->filters[w][band];
    p.filter_type = FILTER_LINKWITZ_TRANSFORM;
    p.freq = f0;
    p.q = q0;
    p.gain = fp;
    p.qp = qp;
    applyFilter(ch, band, p);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::setBandBypass(int ch, int band, bool bypass) {
    int w = wire(ch);
    if (w < 0 || band < 0 || band >= BANDS_PER_CHANNEL) return;
    for (int target : {ch, linkedPartner(ch)}) {
        int tw = wire(target);
        if (tw < 0) continue;
        dspi_set_band_bypass(m_core, tw, band, bypass);
        markDirty(target);
    }
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::setCrossover(int ch, int band, int type, float freq) {
    if (outputOf(ch) < 0 || band < 0 || band >= MAX_XOVER_BANDS) return;
    int w = wire(ch);
    FilterParams p = state()->xover[w][band];
    p.filter_type = static_cast<uint8_t>(type);
    p.freq = freq;
    dspi_set_crossover(m_core, w, band, p);
    markDirty(ch);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::setCrossoverBypass(int ch, int band, bool bypass) {
    if (outputOf(ch) < 0 || band < 0 || band >= MAX_XOVER_BANDS) return;
    dspi_set_band_bypass(m_core, wire(ch), XOVER_BAND_BASE + band, bypass);
    markDirty(ch);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::setChannelDelay(int ch, float ms) {
    int w = wire(ch);
    if (w < 0) return;
    dspi_set_delay(m_core, w, ms);
    emit stateChanged();
}

void DSPiBridge::setLoudness(bool en) {
    dspi_set_loudness(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setLoudnessRef(float spl, bool sendOnly) {
    dspi_set_loudness_ref(m_core, spl);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setLoudnessIntensity(float pct, bool sendOnly) {
    dspi_set_loudness_intensity(m_core, pct);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setLoudnessOutputMask(int mask) {
    dspi_set_loudness_mask(m_core, static_cast<uint16_t>(mask));
    emit stateChanged();
}

void DSPiBridge::setCrossfeed(bool en) {
    dspi_set_crossfeed(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setCrossfeedPreset(int p) {
    dspi_set_crossfeed_preset(m_core, p);
    emit stateChanged();
}

void DSPiBridge::setCrossfeedFreq(float freq, bool sendOnly) {
    dspi_set_crossfeed_freq(m_core, freq);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setCrossfeedFeed(float feed, bool sendOnly) {
    dspi_set_crossfeed_feed(m_core, feed);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setCrossfeedITD(bool en) {
    dspi_set_crossfeed_itd(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setCrossfeedOutputPairMask(int mask) {
    dspi_set_crossfeed_outputs(m_core, static_cast<uint8_t>(mask));
    emit stateChanged();
}

void DSPiBridge::setMatrixRoute(int input, int output, bool enabled, float gain, bool invert) {
    if (input < 0 || input >= state()->num_input_channels) return;
    dspi_set_matrix_route(m_core, input, output, enabled, gain, invert);
    emit stateChanged();
}

bool DSPiBridge::setOutputEnable(int output, bool enabled) {
    int8_t result = dspi_set_output_enable(m_core, output, enabled);
    emit stateChanged();
    emit magnitudesChanged();
    return result == (enabled ? 1 : 0);
}

void DSPiBridge::setOutputGain(int output, float db) {
    dspi_set_output_gain(m_core, output, db);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::sendOutputGainToDevice(int output, float db) {
    dspi_set_output_gain(m_core, output, db);
    emit previewChanged();
}

void DSPiBridge::setOutputMute(int output, bool muted) {
    dspi_set_output_mute(m_core, output, muted);
    emit stateChanged();
}

void DSPiBridge::setOutputDelay(int output, float ms) {
    dspi_set_output_delay(m_core, output, ms);
    emit stateChanged();
}

void DSPiBridge::sendOutputDelayToDevice(int output, float ms) {
    dspi_set_output_delay(m_core, output, ms);
}

int DSPiBridge::setOutputPin(int output, int pin) {
    int status = dspi_set_output_pin(m_core, output, pin);
    emit stateChanged();
    return status;
}

void DSPiBridge::setOutputConfigMode(int mode) {
    dspi_set_output_config_mode(m_core, mode);
    emit stateChanged();
}

int DSPiBridge::saveOutputConfig() {
    return dspi_save_output_config(m_core);
}

void DSPiBridge::setChannelName(int ch, const QString &name) {
    int w = wire(ch);
    if (w < 0) return;
    QByteArray utf8 = name.toUtf8();
    dspi_set_channel_name(m_core, w, utf8.constData());
    emit stateChanged();
}

int DSPiBridge::savePreset(int slot) {
    int status = dspi_save_preset(m_core, slot);
    emit stateChanged();
    return status;
}

int DSPiBridge::loadPreset(int slot) {
    int status = dspi_load_preset(m_core, slot);
    if (status == PRESET_OK) {
        markAllDirty();
        emit stateChanged();
        emit magnitudesChanged();
    }
    return status;
}

int DSPiBridge::deletePreset(int slot) {
    int status = dspi_delete_preset(m_core, slot);
    markAllDirty();
    emit stateChanged();
    emit magnitudesChanged();
    return status;
}

int DSPiBridge::copyPreset(int fromSlot, int toSlot) {
    int status = dspi_copy_preset(m_core, fromSlot, toSlot);
    emit stateChanged();
    return status;
}

void DSPiBridge::setPresetName(int slot, const QString &name) {
    QByteArray utf8 = name.toUtf8();
    dspi_set_preset_name(m_core, slot, utf8.constData());
    emit stateChanged();
}

void DSPiBridge::setPresetStartup(int mode, int slot) {
    dspi_set_preset_startup(m_core, mode, slot);
    emit stateChanged();
}

int DSPiBridge::saveParams() {
    return dspi_save_params(m_core);
}

int DSPiBridge::loadParams() {
    int status = dspi_load_params(m_core);
    if (status == FLASH_OK) {
        markAllDirty();
        emit stateChanged();
        emit magnitudesChanged();
    }
    return status;
}

int DSPiBridge::factoryReset() {
    int status = dspi_factory_reset(m_core);
    if (status == FLASH_OK) {
        markAllDirty();
        emit stateChanged();
        emit magnitudesChanged();
    }
    return status;
}

void DSPiBridge::enterBootloader() {
    dspi_enter_bootloader(m_core);
}

void DSPiBridge::clearClips() {
    dspi_clear_clips(m_core);
    memset(m_lastClipMs, 0, sizeof(m_lastClipMs));
    m_status.clip_flags = 0;
    emit statusChanged();
}

int DSPiBridge::checkCore1Conflict(int output) {
    return dspi_check_core1_conflict(m_core, output);
}

// ── Device management ──

void DSPiBridge::scanDevices() {
    DeviceInfo devices[8];
    uint32_t count = dspi_scan_devices(m_core, devices, 8);

    QStringList serials;
    for (uint32_t i = 0; i < count; i++) {
        serials.append(QString::fromUtf8(reinterpret_cast<const char *>(devices[i].serial),
                                         devices[i].serial_len));
    }
    if (serials != m_availableSerials) {
        m_availableSerials = serials;
        emit devicesChanged();
    }

    if (!connected() && !m_availableSerials.isEmpty())
        selectDevice(m_availableSerials.first());
}

void DSPiBridge::selectDevice(const QString &serial) {
    QByteArray utf8 = serial.toUtf8();
    if (!dspi_select_device(m_core, utf8.constData())) return;

    m_selectedSerial = serial;
    memset(&m_status, 0, sizeof(m_status));
    memset(m_limiterGR, 0, sizeof(m_limiterGR));
    memset(m_lastClipMs, 0, sizeof(m_lastClipMs));
    loadLinks();
    if (!dspi_fetch_all(m_core))
        qWarning() << "DSPi: could not read device state for" << serial;
    else if (state()->compat != COMPAT_OK)
        qWarning() << "DSPi:" << compatMessage();
    markAllDirty();

    // Show the first input pair and every enabled output on the graph
    for (int ch = 0; ch < kAppChannelCount; ch++) {
        int out = outputOf(ch);
        m_channelVisible[ch] = (ch < 2) || (out >= 0 && state()->output_enabled[out]);
    }

    emit stateChanged();
    emit statusChanged();
    emit magnitudesChanged();
    emit devicesChanged();
}

void DSPiBridge::disconnectDevice() {
    dspi_disconnect(m_core);
    m_selectedSerial.clear();
    markAllDirty();
    emit stateChanged();
    emit statusChanged();
}

void DSPiBridge::reconnect() {
    if (!m_selectedSerial.isEmpty()) {
        QString serial = m_selectedSerial;
        disconnectDevice();
        selectDevice(serial);
    }
}

// ── Input pair links ──

int DSPiBridge::liveInputCount() const {
    return qMin<int>(state()->num_input_channels, qMax<int>(2, m_status.active_input_channels));
}

int DSPiBridge::pairIndex(int ch) const {
    int in = inputOf(ch);
    return in >= 0 ? in / 2 : -1;
}

int DSPiBridge::pairPartner(int ch) const {
    int in = inputOf(ch);
    return in >= 0 ? inputAppId(in ^ 1) : -1;
}

bool DSPiBridge::pairAvailable(int ch) const {
    int in = inputOf(ch);
    return in >= 0 && (in | 1) < liveInputCount();
}

bool DSPiBridge::isInputLinked(int ch) const {
    int p = pairIndex(ch);
    return p >= 0 && pairAvailable(ch) && ((m_links >> p) & 1);
}

int DSPiBridge::linkedPartner(int ch) const {
    return isInputLinked(ch) ? pairPartner(ch) : -1;
}

bool DSPiBridge::inputPairMatches(int ch) const {
    int a = wire(ch), b = wire(pairPartner(ch));
    if (a < 0 || b < 0) return true;
    auto *s = state();
    if (s->input_preamp_db[inputOf(ch)] != s->input_preamp_db[inputOf(pairPartner(ch))]) return false;
    for (int band = 0; band < BANDS_PER_CHANNEL; band++) {
        const FilterParams &x = s->filters[a][band], &y = s->filters[b][band];
        if (x.filter_type == FILTER_FLAT && y.filter_type == FILTER_FLAT) continue;
        if (x.filter_type != y.filter_type || x.bypass != y.bypass || x.freq != y.freq
            || x.q != y.q || x.gain != y.gain
            || (x.filter_type == FILTER_LINKWITZ_TRANSFORM && x.qp != y.qp))
            return false;
    }
    return true;
}

void DSPiBridge::copyInputSettings(int from, int to) {
    int wf = wire(from), wt = wire(to);
    if (wf < 0 || wt < 0) return;
    for (int band = 0; band < BANDS_PER_CHANNEL; band++)
        dspi_set_filter(m_core, wt, band, state()->filters[wf][band]);
    dspi_set_input_preamp(m_core, inputOf(to), state()->input_preamp_db[inputOf(from)]);
    markDirty(to);
}

void DSPiBridge::setInputLinked(int ch, bool linked, int keepCh) {
    int p = pairIndex(ch);
    if (p < 0) return;
    if (linked && keepCh >= 0 && (keepCh == ch || keepCh == pairPartner(ch)))
        copyInputSettings(keepCh, keepCh == ch ? pairPartner(ch) : ch);
    if (linked) m_links |= (1 << p);
    else m_links &= ~(1 << p);
    saveLinks();
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::loadLinks() {
    QSettings settings;
    m_links = static_cast<uint8_t>(settings.value("inputLinks/" + m_selectedSerial, 0x01).toUInt());
}

void DSPiBridge::saveLinks() {
    if (m_selectedSerial.isEmpty()) return;
    QSettings settings;
    settings.setValue("inputLinks/" + m_selectedSerial, m_links);
}

// ── Whole-list band operations ──

void DSPiBridge::clearPeq(int ch) {
    FilterParams off = {};
    off.filter_type = FILTER_FLAT;
    off.freq = 1000.0f;
    off.q = 0.707f;
    off.qp = 0.707f;
    for (int band = 0; band < BANDS_PER_CHANNEL; band++) applyFilter(ch, band, off);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::clearAllBands(int ch, bool crossover) {
    if (!crossover) { clearPeq(ch); return; }
    if (outputOf(ch) < 0) return;
    FilterParams off = {};
    off.filter_type = FILTER_FLAT;
    off.freq = 1000.0f;
    off.q = 0.707f;
    off.qp = 0.707f;
    for (int band = 0; band < MAX_XOVER_BANDS; band++) dspi_set_crossover(m_core, wire(ch), band, off);
    markDirty(ch);
    emit stateChanged();
    emit magnitudesChanged();
}

bool DSPiBridge::canSetAllBypass(int ch, bool bypass, bool crossover) const {
    int w = wire(ch);
    if (w < 0 || (crossover && outputOf(ch) < 0)) return false;
    int n = crossover ? MAX_XOVER_BANDS : BANDS_PER_CHANNEL;
    for (int band = 0; band < n; band++) {
        const FilterParams &f = crossover ? state()->xover[w][band] : state()->filters[w][band];
        if (f.filter_type != FILTER_FLAT && f.bypass != bypass) return true;
    }
    return false;
}

void DSPiBridge::setAllBandsBypass(int ch, bool bypass, bool crossover) {
    int w = wire(ch);
    if (w < 0 || (crossover && outputOf(ch) < 0)) return;
    int n = crossover ? MAX_XOVER_BANDS : BANDS_PER_CHANNEL;
    for (int band = 0; band < n; band++) {
        const FilterParams &f = crossover ? state()->xover[w][band] : state()->filters[w][band];
        if (f.filter_type == FILTER_FLAT || f.bypass == bypass) continue;
        if (crossover) {
            dspi_set_band_bypass(m_core, w, XOVER_BAND_BASE + band, bypass);
        } else {
            for (int target : {ch, linkedPartner(ch)}) {
                int tw = wire(target);
                if (tw >= 0) { dspi_set_band_bypass(m_core, tw, band, bypass); markDirty(target); }
            }
        }
    }
    markDirty(ch);
    emit stateChanged();
    emit magnitudesChanged();
}

// ── Output limiter ──

static bool validOut(const DspState *s, int out) { return out >= 0 && out < s->num_output_channels; }

bool DSPiBridge::limiterEnabled(int out) const { return validOut(state(), out) && state()->limiter_enabled[out]; }
float DSPiBridge::limiterThreshold(int out) const { return validOut(state(), out) ? state()->limiter_threshold_db[out] : -1.0f; }
float DSPiBridge::limiterRelease(int out) const { return validOut(state(), out) ? state()->limiter_release_ms[out] : 100.0f; }
int DSPiBridge::limiterLinkGroup(int out) const { return validOut(state(), out) ? state()->limiter_link_group[out] : 0; }
float DSPiBridge::limiterReduction(int out) const { return validOut(state(), out) ? m_limiterGR[out] : 0.0f; }

void DSPiBridge::setLimiterEnabled(int out, bool en) {
    if (!validOut(state(), out)) return;
    dspi_set_limiter_param(m_core, out, LIMITER_PARAM_ENABLED, en ? 1.0f : 0.0f);
    emit stateChanged();
}

void DSPiBridge::setLimiterThreshold(int out, float db, bool sendOnly) {
    if (!validOut(state(), out)) return;
    dspi_set_limiter_param(m_core, out, LIMITER_PARAM_THRESHOLD_DB, db);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setLimiterRelease(int out, float ms, bool sendOnly) {
    if (!validOut(state(), out)) return;
    dspi_set_limiter_param(m_core, out, LIMITER_PARAM_RELEASE_MS, ms);
    if (!sendOnly) emit stateChanged();
}

void DSPiBridge::setLimiterLinkGroup(int out, int group) {
    if (!validOut(state(), out)) return;
    dspi_set_limiter_param(m_core, out, LIMITER_PARAM_LINK_GROUP, group);
    emit stateChanged();
}

void DSPiBridge::copyLimiterToAll(int out) {
    if (!validOut(state(), out)) return;
    auto *s = state();
    float en = s->limiter_enabled[out] ? 1.0f : 0.0f;
    float th = s->limiter_threshold_db[out], rel = s->limiter_release_ms[out];
    dspi_set_limiter_param(m_core, LIMITER_ALL_OUTPUTS, LIMITER_PARAM_THRESHOLD_DB, th);
    dspi_set_limiter_param(m_core, LIMITER_ALL_OUTPUTS, LIMITER_PARAM_RELEASE_MS, rel);
    dspi_set_limiter_param(m_core, LIMITER_ALL_OUTPUTS, LIMITER_PARAM_ENABLED, en);
    emit stateChanged();
}

void DSPiBridge::linkAllLimiterPairs() {
    // Outputs 1+2 in group 1, 3+4 in group 2, ...; PDM stays unlinked.
    int n = state()->num_output_channels;
    for (int o = 0; o < n; o++) {
        int group = isPdmOutput(o) ? 0 : qMin(4, o / 2 + 1);
        dspi_set_limiter_param(m_core, o, LIMITER_PARAM_LINK_GROUP, group);
    }
    emit stateChanged();
}

void DSPiBridge::unlinkAllLimiters() {
    dspi_set_limiter_param(m_core, LIMITER_ALL_OUTPUTS, LIMITER_PARAM_LINK_GROUP, 0);
    emit stateChanged();
}

void DSPiBridge::disableAllLimiters() {
    dspi_set_limiter_param(m_core, LIMITER_ALL_OUTPUTS, LIMITER_PARAM_ENABLED, 0);
    emit stateChanged();
}

// ── Channel clipboard ──

void DSPiBridge::copyChannel(int ch) {
    int w = wire(ch);
    if (w < 0) return;
    auto *s = state();
    m_clip.valid = true;
    m_clip.output = outputOf(ch) >= 0;
    memcpy(m_clip.filters, s->filters[w], sizeof(m_clip.filters));
    memcpy(m_clip.xover, s->xover[w], sizeof(m_clip.xover));
    if (m_clip.output) {
        int out = outputOf(ch);
        m_clip.gain = s->output_gain_db[out];
        m_clip.delay = s->output_delay_ms[out];
        m_clip.mute = s->output_muted[out];
    }
}

bool DSPiBridge::canPaste() const { return m_clip.valid; }

void DSPiBridge::pasteChannel(int ch) {
    if (!m_clip.valid || wire(ch) < 0) return;
    // Always all 10 PEQ bands (a linked input updates its partner too).
    for (int band = 0; band < BANDS_PER_CHANNEL; band++) applyFilter(ch, band, m_clip.filters[band]);
    int out = outputOf(ch);
    if (m_clip.output && out >= 0) {
        for (int band = 0; band < MAX_XOVER_BANDS; band++)
            dspi_set_crossover(m_core, wire(ch), band, m_clip.xover[band]);
        dspi_set_output_gain(m_core, out, m_clip.gain);
        dspi_set_output_delay(m_core, out, m_clip.delay);
        dspi_set_output_mute(m_core, out, m_clip.mute);
    }
    markDirty(ch);
    emit stateChanged();
    emit magnitudesChanged();
}

// ── Input source / feature toggles ──

int DSPiBridge::inputSource() const { return state()->input_source; }

QVariantList DSPiBridge::inputSources() const {
    // Firmware InputSource: 0 USB, 1 S/PDIF 1, 2 I2S, 3 ADAT, 4-6 S/PDIF 2-4.
    auto *s = state();
    bool extraSpdif = (s->spdif_inputs_enabled & ~1u) != 0;
    QVariantList list;
    auto add = [&](int id, const QString &name) {
        QVariantMap m; m["id"] = id; m["name"] = name; list.append(m);
    };
    add(0, "USB");
    add(1, extraSpdif ? "S/PDIF 1" : "S/PDIF");
    for (int k = 1; k < 4; k++)
        if (s->spdif_inputs_enabled & (1u << k)) add(3 + k, QString("S/PDIF %1").arg(k + 1));
    add(2, "I2S");
    if (s->platform_id == 1 && s->adat_input_enabled) add(3, "ADAT");
    return list;
}

bool DSPiBridge::levellerEnabled() const { return state()->leveller_enabled; }
bool DSPiBridge::psybassEnabled() const { return state()->psybass_enabled; }

void DSPiBridge::setInputSource(int source) {
    dspi_set_input_source(m_core, source);
    emit stateChanged();
}

void DSPiBridge::setLevellerEnabled(bool en) {
    dspi_set_leveller_enabled(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setPsybassEnabled(bool en) {
    dspi_set_psybass_enabled(m_core, en);
    emit stateChanged();
}

// ── Matrix helpers ──

void DSPiBridge::directRouting() {
    auto *s = state();
    int nIn = s->num_input_channels, nOut = s->num_output_channels;
    // PDM shares Core 1 with the EQ-worker outputs, so a 1:1 layout turns it off
    if (nOut > 0 && s->output_enabled[nOut - 1]) dspi_set_output_enable(m_core, nOut - 1, false);
    for (int i = 0; i < nIn; i++)
        for (int o = 0; o < nOut; o++) {
            bool on = (i == o) && !isPdmOutput(o);
            dspi_set_matrix_route(m_core, i, o, on, on ? 0.0f : s->matrix_gain[i][o],
                                  on ? false : s->matrix_invert[i][o]);
        }
    for (int o = 0; o < qMin(nIn, nOut - 1); o++)
        if (!s->output_enabled[o]) dspi_set_output_enable(m_core, o, true);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::clearRouting() {
    auto *s = state();
    for (int i = 0; i < s->num_input_channels; i++)
        for (int o = 0; o < s->num_output_channels; o++)
            if (s->matrix_routing[i][o])
                dspi_set_matrix_route(m_core, i, o, false, s->matrix_gain[i][o], s->matrix_invert[i][o]);
    emit stateChanged();
}

QVariantList DSPiBridge::core1ConflictOutputs(int output) const {
    // Core 1 runs either the PDM output or the EQ worker for outputs
    // 2..(n-2) (RP2350: OUT3-8, RP2040: OUT3-4); never both.
    auto *s = state();
    int n = s->num_output_channels;
    QVariantList list;
    if (output < 0 || output >= n || s->output_enabled[output]) return list;
    if (isPdmOutput(output)) {
        for (int o = 2; o < n - 1; o++) if (s->output_enabled[o]) list.append(o);
    } else if (output >= 2 && s->output_enabled[n - 1]) {
        list.append(n - 1);
    }
    return list;
}

void DSPiBridge::enableOutputResolvingConflict(int output) {
    for (const QVariant &v : core1ConflictOutputs(output))
        dspi_set_output_enable(m_core, v.toInt(), false);
    dspi_set_output_enable(m_core, output, true);
    emit stateChanged();
    emit magnitudesChanged();
}

// ── Volume leveller / psychoacoustic bass ──

#define LIVE(call) do { call; if (!sendOnly) emit stateChanged(); } while (0)

void DSPiBridge::setLevellerAmount(float pct, bool sendOnly) { LIVE(dspi_set_leveller_amount(m_core, pct)); }
void DSPiBridge::setLevellerMaxGain(float db, bool sendOnly) { LIVE(dspi_set_leveller_max_gain(m_core, db)); }
void DSPiBridge::setLevellerGate(float db, bool sendOnly) { LIVE(dspi_set_leveller_gate(m_core, db)); }
void DSPiBridge::setPsybassParam(int param, float value, bool sendOnly) { LIVE(dspi_set_psybass_param(m_core, param, value)); }

#undef LIVE

void DSPiBridge::setLevellerSpeed(int speed) {
    dspi_set_leveller_speed(m_core, speed);
    emit stateChanged();
}

void DSPiBridge::setLevellerLookahead(bool en) {
    dspi_set_leveller_lookahead(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setLevellerMasks(int detector, int apply) {
    dspi_set_leveller_masks(m_core, detector, apply);
    emit stateChanged();
}

void DSPiBridge::setPsybassOutputMask(int mask) {
    dspi_set_psybass_mask(m_core, mask);
    emit stateChanged();
}

// ── Channel names ──

void DSPiBridge::resetChannelNames() {
    auto *s = state();
    int nIn = s->num_input_channels, nOut = s->num_output_channels;
    for (int i = 0; i < nIn; i++) {
        // Stereo USB input: USB L / USB R; multichannel: USB 1..8
        QString name = nIn == 2 ? (i == 0 ? "USB L" : "USB R") : QString("USB %1").arg(i + 1);
        dspi_set_channel_name(m_core, i, name.toUtf8().constData());
    }
    for (int o = 0; o < nOut; o++) {
        QString name = (o == nOut - 1) ? QString("PDM")
                     : QString("SPDIF %1 %2").arg(o / 2 + 1).arg(o % 2 ? "R" : "L");
        dspi_set_channel_name(m_core, nIn + o, name.toUtf8().constData());
    }
    emit stateChanged();
}
