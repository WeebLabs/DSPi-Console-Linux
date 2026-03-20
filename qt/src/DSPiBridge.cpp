#include "DSPiBridge.h"
#include <QDebug>
#include <cstring>
#include <cmath>

// Channel colors matching Swift app
static const char *kChannelColors[] = {
    "#4A8FE3", // 0: Master L
    "#F57373", // 1: Master R
    "#45C2A3", // 2: SPDIF 1 L / Out L
    "#59D180", // 3: SPDIF 1 R / Out R (RP2350)
    "#F0C459", // 4: SPDIF 2 L / Sub (RP2040 PDM)
    "#F2A64D", // 5: SPDIF 2 R
    "#598CF2", // 6: SPDIF 3 L
    "#8CB3F2", // 7: SPDIF 3 R
    "#D97390", // 8: SPDIF 4 L
    "#F299A6", // 9: SPDIF 4 R
    "#BA87F2", // 10: PDM (RP2350)
};

static const char *kDefaultChannelNames[] = {
    "USB L", "USB R",
    "SPDIF 1 L", "SPDIF 1 R",
    "SPDIF 2 L", "SPDIF 2 R",
    "SPDIF 3 L", "SPDIF 3 R",
    "SPDIF 4 L", "SPDIF 4 R",
    "PDM",
};

static const char *kDescriptors[] = {
    "IN1", "IN2",
    "OUT1", "OUT2", "OUT3", "OUT4", "OUT5", "OUT6", "OUT7", "OUT8", "OUT9",
};

DSPiBridge::DSPiBridge(QObject *parent)
    : QObject(parent)
{
    m_core = dspi_core_new();

    // Initialize channel visibility
    for (int i = 0; i < MAX_CHANNELS; i++) {
        m_channelVisible[i] = (i < 2); // Only master L/R visible by default
    }

    // Initialize status
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

    // Register hotplug callback
    dspi_set_hotplug_callback(m_core, &DSPiBridge::hotplugCallback, this);
    m_hotplugTimer->start();

    // Initial device scan
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

void DSPiBridge::markAllDirty()
{
    for (int i = 0; i < MAX_CHANNELS; i++) {
        m_magnitudeDirty[i] = true;
        m_magnitudeValid[i] = false;
    }
}

// ── Hotplug callback ──

void DSPiBridge::hotplugCallback(uint8_t event, const char *serial, void *userData)
{
    auto *self = static_cast<DSPiBridge *>(userData);
    QString ser = QString::fromUtf8(serial);
    if (event == 0) {
        QMetaObject::invokeMethod(self, [self, ser]() {
            self->scanDevices();
            emit self->deviceArrived(ser);
            // Auto-connect if no device selected
            if (!self->connected()) {
                self->selectDevice(ser);
            }
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
    if (!connected()) return;
    SystemStatus newStatus;
    if (dspi_fetch_status(m_core, &newStatus)) {
        bool changed = memcmp(&m_status, &newStatus, sizeof(SystemStatus)) != 0;
        m_status = newStatus;
        if (changed) emit statusChanged();
    }
}

void DSPiBridge::pollHotplug()
{
    dspi_poll_hotplug(m_core);
    // Retry scan if not connected — covers the case where initial scan
    // ran before USB enumeration completed and hotplug missed the device
    if (!connected()) {
        scanDevices();
    }
}

// ── Property getters ──

bool DSPiBridge::connected() const { return dspi_is_connected(m_core); }
QString DSPiBridge::selectedSerial() const { return m_selectedSerial; }
QStringList DSPiBridge::availableSerials() const { return m_availableSerials; }

QString DSPiBridge::platformName() const {
    auto *s = state();
    return s->platform_id == 1 ? "RP2350" : "RP2040";
}

int DSPiBridge::numChannels() const { return state()->num_channels; }
int DSPiBridge::numOutputChannels() const { return state()->num_output_channels; }

float DSPiBridge::preampDB() const { return state()->preamp_db; }
bool DSPiBridge::bypass() const { return state()->bypass; }

bool DSPiBridge::loudnessEnabled() const { return state()->loudness_enabled; }
float DSPiBridge::loudnessRefSPL() const { return state()->loudness_ref_spl; }
float DSPiBridge::loudnessIntensity() const { return state()->loudness_intensity; }

bool DSPiBridge::crossfeedEnabled() const { return state()->crossfeed_enabled; }
int DSPiBridge::crossfeedPreset() const { return state()->crossfeed_preset; }
float DSPiBridge::crossfeedFreq() const { return state()->crossfeed_freq; }
float DSPiBridge::crossfeedFeed() const { return state()->crossfeed_feed; }
bool DSPiBridge::crossfeedITD() const { return state()->crossfeed_itd; }

int DSPiBridge::cpu0() const { return m_status.cpu0; }
int DSPiBridge::cpu1() const { return m_status.cpu1; }
int DSPiBridge::clipFlags() const { return m_status.clip_flags; }

int DSPiBridge::activePresetSlot() const { return state()->active_preset_slot; }
int DSPiBridge::presetOccupied() const { return state()->preset_occupied; }
int DSPiBridge::presetStartupMode() const { return state()->preset_startup_mode; }
int DSPiBridge::presetDefaultSlot() const { return state()->preset_default_slot; }
bool DSPiBridge::presetIncludePins() const { return state()->preset_include_pins; }

int DSPiBridge::core1Mode() const { return state()->core1_mode; }

// ── Q_INVOKABLE getters ──

float DSPiBridge::peakLevel(int ch) const {
    if (ch < 0 || ch >= MAX_CHANNELS) return 0.0f;
    return m_status.peaks[ch];
}

bool DSPiBridge::isClipping(int ch) const {
    if (ch < 0 || ch >= MAX_CHANNELS) return false;
    return (m_status.clip_flags >> ch) & 1;
}

QString DSPiBridge::channelName(int ch) const {
    if (ch < 0 || ch >= MAX_CHANNELS) return "";
    auto *s = state();
    // Try device name first
    QString name = QString::fromUtf8(reinterpret_cast<const char*>(s->channel_names[ch]));
    if (name.isEmpty() && ch < 11) {
        return QString::fromUtf8(kDefaultChannelNames[ch]);
    }
    return name;
}

QString DSPiBridge::channelColor(int ch) const {
    if (ch < 0 || ch >= 11) return "#FFFFFF";
    return QString::fromUtf8(kChannelColors[ch]);
}

QString DSPiBridge::channelDescriptor(int ch) const {
    if (ch < 0 || ch >= 11) return "";
    return QString::fromUtf8(kDescriptors[ch]);
}

int DSPiBridge::filterType(int ch, int band) const {
    if (ch < 0 || ch >= MAX_CHANNELS || band < 0 || band >= BANDS_PER_CHANNEL) return 0;
    return static_cast<int>(state()->filters[ch][band].filter_type);
}

float DSPiBridge::filterFreq(int ch, int band) const {
    if (ch < 0 || ch >= MAX_CHANNELS || band < 0 || band >= BANDS_PER_CHANNEL) return 1000.0f;
    return state()->filters[ch][band].freq;
}

float DSPiBridge::filterGain(int ch, int band) const {
    if (ch < 0 || ch >= MAX_CHANNELS || band < 0 || band >= BANDS_PER_CHANNEL) return 0.0f;
    return state()->filters[ch][band].gain;
}

float DSPiBridge::filterQ(int ch, int band) const {
    if (ch < 0 || ch >= MAX_CHANNELS || band < 0 || band >= BANDS_PER_CHANNEL) return 0.707f;
    return state()->filters[ch][band].q;
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

bool DSPiBridge::matrixRouting(int input, int output) const {
    if (input < 0 || input >= 2 || output < 0 || output >= MAX_OUTPUTS) return false;
    return state()->matrix_routing[input][output];
}

float DSPiBridge::matrixGain(int input, int output) const {
    if (input < 0 || input >= 2 || output < 0 || output >= MAX_OUTPUTS) return 0.0f;
    return state()->matrix_gain[input][output];
}

bool DSPiBridge::matrixInvert(int input, int output) const {
    if (input < 0 || input >= 2 || output < 0 || output >= MAX_OUTPUTS) return false;
    return state()->matrix_invert[input][output];
}

int DSPiBridge::outputPin(int physOut) const {
    if (physOut < 0 || physOut >= MAX_PHYSICAL_OUTPUTS) return -1;
    return state()->output_pins[physOut];
}

QString DSPiBridge::presetName(int slot) const {
    if (slot < 0 || slot >= MAX_PRESETS) return "";
    return QString::fromUtf8(reinterpret_cast<const char*>(state()->preset_names[slot]));
}

bool DSPiBridge::isPresetOccupied(int slot) const {
    if (slot < 0 || slot >= MAX_PRESETS) return false;
    return (state()->preset_occupied >> slot) & 1;
}

// ── Magnitude curves ──

QVariantList DSPiBridge::magnitudeCurve(int eqCh) {
    QVariantList result;
    if (eqCh < 0 || eqCh >= MAX_CHANNELS) return result;

    auto *s = state();
    if (m_magnitudeDirty[eqCh] || !m_magnitudeValid[eqCh]) {
        dspi_compute_magnitude_curve(s->filters[eqCh], BANDS_PER_CHANNEL, m_magnitudeCache[eqCh]);
        m_magnitudeDirty[eqCh] = false;
        m_magnitudeValid[eqCh] = true;
    }

    result.reserve(MAGNITUDE_POINTS);
    for (int i = 0; i < MAGNITUDE_POINTS; i++) {
        result.append(m_magnitudeCache[eqCh][i]);
    }
    return result;
}

void DSPiBridge::getMagnitudeCurve(int eqCh, double *out) {
    if (eqCh < 0 || eqCh >= MAX_CHANNELS) return;

    auto *s = state();
    if (m_magnitudeDirty[eqCh] || !m_magnitudeValid[eqCh]) {
        dspi_compute_magnitude_curve(s->filters[eqCh], BANDS_PER_CHANNEL, m_magnitudeCache[eqCh]);
        m_magnitudeDirty[eqCh] = false;
        m_magnitudeValid[eqCh] = true;
    }

    memcpy(out, m_magnitudeCache[eqCh], sizeof(double) * MAGNITUDE_POINTS);
}

bool DSPiBridge::isMagnitudeDirty(int eqCh) const {
    if (eqCh < 0 || eqCh >= MAX_CHANNELS) return false;
    return m_magnitudeDirty[eqCh];
}

void DSPiBridge::clearMagnitudeDirty(int eqCh) {
    if (eqCh >= 0 && eqCh < MAX_CHANNELS) m_magnitudeDirty[eqCh] = false;
}

bool DSPiBridge::channelVisible(int eqCh) const {
    if (eqCh < 0 || eqCh >= MAX_CHANNELS) return false;
    return m_channelVisible[eqCh];
}

void DSPiBridge::setChannelVisible(int eqCh, bool visible) {
    if (eqCh < 0 || eqCh >= MAX_CHANNELS) return;
    if (m_channelVisible[eqCh] != visible) {
        m_channelVisible[eqCh] = visible;
        emit magnitudesChanged();
    }
}

// ── Q_INVOKABLE setters ──

void DSPiBridge::setPreamp(float db) {
    dspi_set_preamp(m_core, db);
    emit stateChanged();
}

void DSPiBridge::sendPreampToDevice(float db) {
    dspi_set_preamp(m_core, db);
    // No stateChanged - used during drag to avoid feedback loop
}

void DSPiBridge::setBypass(bool en) {
    dspi_set_bypass(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setFilter(int ch, int band, int type, float freq, float gain, float q) {
    FilterParams p;
    p.filter_type = static_cast<FilterType>(type);
    p.freq = freq;
    p.gain = gain;
    p.q = q;
    dspi_set_filter(m_core, ch, band, p);
    m_magnitudeDirty[ch] = true;
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::setLoudness(bool en) {
    dspi_set_loudness(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setLoudnessRef(float spl) {
    dspi_set_loudness_ref(m_core, spl);
    emit stateChanged();
}

void DSPiBridge::setLoudnessIntensity(float pct) {
    dspi_set_loudness_intensity(m_core, pct);
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

void DSPiBridge::setCrossfeedFreq(float freq) {
    dspi_set_crossfeed_freq(m_core, freq);
    emit stateChanged();
}

void DSPiBridge::setCrossfeedFeed(float feed) {
    dspi_set_crossfeed_feed(m_core, feed);
    emit stateChanged();
}

void DSPiBridge::setCrossfeedITD(bool en) {
    dspi_set_crossfeed_itd(m_core, en);
    emit stateChanged();
}

void DSPiBridge::setMatrixRoute(int input, int output, bool enabled, float gain, bool invert) {
    dspi_set_matrix_route(m_core, input, output, enabled, gain, invert);
    emit stateChanged();
}

void DSPiBridge::setOutputEnable(int output, bool enabled) {
    dspi_set_output_enable(m_core, output, enabled);
    emit stateChanged();
}

void DSPiBridge::setOutputGain(int output, float db) {
    dspi_set_output_gain(m_core, output, db);
    emit stateChanged();
    emit magnitudesChanged();
}

void DSPiBridge::sendOutputGainToDevice(int output, float db) {
    dspi_set_output_gain(m_core, output, db);
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
    return dspi_set_output_pin(m_core, output, pin);
}

void DSPiBridge::setChannelName(int ch, const QString &name) {
    QByteArray utf8 = name.toUtf8();
    dspi_set_channel_name(m_core, ch, utf8.constData());
    emit stateChanged();
}

int DSPiBridge::savePreset(int slot) {
    int status = dspi_save_preset(m_core, slot);
    emit stateChanged();
    return status;
}

int DSPiBridge::loadPreset(int slot) {
    int status = dspi_load_preset(m_core, slot);
    if (status == 0) {
        markAllDirty();
        emit stateChanged();
        emit magnitudesChanged();
    }
    return status;
}

int DSPiBridge::deletePreset(int slot) {
    int status = dspi_delete_preset(m_core, slot);
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

void DSPiBridge::setPresetIncludePins(bool include) {
    dspi_set_preset_include_pins(m_core, include);
    emit stateChanged();
}

int DSPiBridge::saveParams() {
    return dspi_save_params(m_core);
}

int DSPiBridge::loadParams() {
    int status = dspi_load_params(m_core);
    if (status == 0) {
        markAllDirty();
        emit stateChanged();
        emit magnitudesChanged();
    }
    return status;
}

int DSPiBridge::factoryReset() {
    int status = dspi_factory_reset(m_core);
    if (status == 0) {
        markAllDirty();
        emit stateChanged();
        emit magnitudesChanged();
    }
    return status;
}

void DSPiBridge::clearClips() {
    dspi_clear_clips(m_core);
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
        serials.append(QString::fromUtf8(reinterpret_cast<const char*>(devices[i].serial),
                                          devices[i].serial_len));
    }
    if (serials != m_availableSerials) {
        m_availableSerials = serials;
        emit devicesChanged();
    }

    // Auto-connect to first device if none selected
    if (!connected() && !m_availableSerials.isEmpty()) {
        selectDevice(m_availableSerials.first());
    }
}

void DSPiBridge::selectDevice(const QString &serial) {
    QByteArray utf8 = serial.toUtf8();
    if (dspi_select_device(m_core, utf8.constData())) {
        m_selectedSerial = serial;
        dspi_fetch_all(m_core);
        markAllDirty();

        // Make newly enabled outputs visible
        auto *s = state();
        for (int i = 0; i < MAX_CHANNELS; i++) {
            if (i < 2) {
                m_channelVisible[i] = true;
            } else {
                int outIdx = i - 2;
                m_channelVisible[i] = (outIdx < s->num_output_channels && s->output_enabled[outIdx]);
            }
        }

        emit stateChanged();
        emit statusChanged();
        emit magnitudesChanged();
        emit devicesChanged();
    }
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
