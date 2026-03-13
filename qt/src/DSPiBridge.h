#ifndef DSPIBRIDGE_H
#define DSPIBRIDGE_H

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVector>
#include <QString>
#include <QStringList>

extern "C" {
#include "dspi_core.h"
}

class BodePlotItem; // forward

class DSPiBridge : public QObject
{
    Q_OBJECT

    // Connection
    Q_PROPERTY(bool connected READ connected NOTIFY statusChanged)
    Q_PROPERTY(QString selectedSerial READ selectedSerial NOTIFY stateChanged)
    Q_PROPERTY(QStringList availableSerials READ availableSerials NOTIFY devicesChanged)
    Q_PROPERTY(QString platformName READ platformName NOTIFY stateChanged)
    Q_PROPERTY(int numChannels READ numChannels NOTIFY stateChanged)
    Q_PROPERTY(int numOutputChannels READ numOutputChannels NOTIFY stateChanged)

    // Global
    Q_PROPERTY(float preampDB READ preampDB NOTIFY stateChanged)
    Q_PROPERTY(bool bypass READ bypass NOTIFY stateChanged)

    // Loudness
    Q_PROPERTY(bool loudnessEnabled READ loudnessEnabled NOTIFY stateChanged)
    Q_PROPERTY(float loudnessRefSPL READ loudnessRefSPL NOTIFY stateChanged)
    Q_PROPERTY(float loudnessIntensity READ loudnessIntensity NOTIFY stateChanged)

    // Crossfeed
    Q_PROPERTY(bool crossfeedEnabled READ crossfeedEnabled NOTIFY stateChanged)
    Q_PROPERTY(int crossfeedPreset READ crossfeedPreset NOTIFY stateChanged)
    Q_PROPERTY(float crossfeedFreq READ crossfeedFreq NOTIFY stateChanged)
    Q_PROPERTY(float crossfeedFeed READ crossfeedFeed NOTIFY stateChanged)
    Q_PROPERTY(bool crossfeedITD READ crossfeedITD NOTIFY stateChanged)

    // CPU / Status
    Q_PROPERTY(int cpu0 READ cpu0 NOTIFY statusChanged)
    Q_PROPERTY(int cpu1 READ cpu1 NOTIFY statusChanged)
    Q_PROPERTY(int clipFlags READ clipFlags NOTIFY statusChanged)

    // Presets
    Q_PROPERTY(int activePresetSlot READ activePresetSlot NOTIFY stateChanged)
    Q_PROPERTY(int presetOccupied READ presetOccupied NOTIFY stateChanged)
    Q_PROPERTY(int presetStartupMode READ presetStartupMode NOTIFY stateChanged)
    Q_PROPERTY(int presetDefaultSlot READ presetDefaultSlot NOTIFY stateChanged)
    Q_PROPERTY(bool presetIncludePins READ presetIncludePins NOTIFY stateChanged)

    // Core1
    Q_PROPERTY(int core1Mode READ core1Mode NOTIFY stateChanged)

public:
    explicit DSPiBridge(QObject *parent = nullptr);
    ~DSPiBridge();

    // Property getters
    bool connected() const;
    QString selectedSerial() const;
    QStringList availableSerials() const;
    QString platformName() const;
    int numChannels() const;
    int numOutputChannels() const;

    float preampDB() const;
    bool bypass() const;

    bool loudnessEnabled() const;
    float loudnessRefSPL() const;
    float loudnessIntensity() const;

    bool crossfeedEnabled() const;
    int crossfeedPreset() const;
    float crossfeedFreq() const;
    float crossfeedFeed() const;
    bool crossfeedITD() const;

    int cpu0() const;
    int cpu1() const;
    int clipFlags() const;

    int activePresetSlot() const;
    int presetOccupied() const;
    int presetStartupMode() const;
    int presetDefaultSlot() const;
    bool presetIncludePins() const;

    int core1Mode() const;

    // Q_INVOKABLE getters
    Q_INVOKABLE float peakLevel(int ch) const;
    Q_INVOKABLE bool isClipping(int ch) const;
    Q_INVOKABLE QString channelName(int ch) const;
    Q_INVOKABLE QString channelColor(int ch) const;
    Q_INVOKABLE QString channelDescriptor(int ch) const;

    Q_INVOKABLE int filterType(int ch, int band) const;
    Q_INVOKABLE float filterFreq(int ch, int band) const;
    Q_INVOKABLE float filterGain(int ch, int band) const;
    Q_INVOKABLE float filterQ(int ch, int band) const;

    Q_INVOKABLE bool outputEnabled(int idx) const;
    Q_INVOKABLE bool outputMuted(int idx) const;
    Q_INVOKABLE float outputGainDB(int idx) const;
    Q_INVOKABLE float outputDelayMS(int idx) const;

    Q_INVOKABLE bool matrixRouting(int input, int output) const;
    Q_INVOKABLE float matrixGain(int input, int output) const;
    Q_INVOKABLE bool matrixInvert(int input, int output) const;
    Q_INVOKABLE int outputPin(int physOut) const;

    Q_INVOKABLE QString presetName(int slot) const;
    Q_INVOKABLE bool isPresetOccupied(int slot) const;

    Q_INVOKABLE QVariantList magnitudeCurve(int eqCh);

    // Q_INVOKABLE setters
    Q_INVOKABLE void setPreamp(float db);
    Q_INVOKABLE void sendPreampToDevice(float db);
    Q_INVOKABLE void setBypass(bool en);

    Q_INVOKABLE void setFilter(int ch, int band, int type, float freq, float gain, float q);

    Q_INVOKABLE void setLoudness(bool en);
    Q_INVOKABLE void setLoudnessRef(float spl);
    Q_INVOKABLE void setLoudnessIntensity(float pct);

    Q_INVOKABLE void setCrossfeed(bool en);
    Q_INVOKABLE void setCrossfeedPreset(int p);
    Q_INVOKABLE void setCrossfeedFreq(float freq);
    Q_INVOKABLE void setCrossfeedFeed(float feed);
    Q_INVOKABLE void setCrossfeedITD(bool en);

    Q_INVOKABLE void setMatrixRoute(int input, int output, bool enabled, float gain, bool invert);
    Q_INVOKABLE void setOutputEnable(int output, bool enabled);
    Q_INVOKABLE void setOutputGain(int output, float db);
    Q_INVOKABLE void sendOutputGainToDevice(int output, float db);
    Q_INVOKABLE void setOutputMute(int output, bool muted);
    Q_INVOKABLE void setOutputDelay(int output, float ms);
    Q_INVOKABLE void sendOutputDelayToDevice(int output, float ms);
    Q_INVOKABLE int setOutputPin(int output, int pin);

    Q_INVOKABLE void setChannelName(int ch, const QString &name);

    Q_INVOKABLE int savePreset(int slot);
    Q_INVOKABLE int loadPreset(int slot);
    Q_INVOKABLE int deletePreset(int slot);
    Q_INVOKABLE void setPresetName(int slot, const QString &name);
    Q_INVOKABLE void setPresetStartup(int mode, int slot);
    Q_INVOKABLE void setPresetIncludePins(bool include);

    Q_INVOKABLE int saveParams();
    Q_INVOKABLE int loadParams();
    Q_INVOKABLE int factoryReset();

    Q_INVOKABLE void clearClips();
    Q_INVOKABLE int checkCore1Conflict(int output);

    Q_INVOKABLE void scanDevices();
    Q_INVOKABLE void selectDevice(const QString &serial);
    Q_INVOKABLE void disconnectDevice();
    Q_INVOKABLE void reconnect();

    // Magnitude curve access for C++ BodePlotItem
    void getMagnitudeCurve(int eqCh, double *out);
    bool isMagnitudeDirty(int eqCh) const;
    void clearMagnitudeDirty(int eqCh);

    // Channel visibility for graph
    Q_INVOKABLE bool channelVisible(int eqCh) const;
    Q_INVOKABLE void setChannelVisible(int eqCh, bool visible);

signals:
    void stateChanged();
    void statusChanged();
    void devicesChanged();
    void deviceArrived(const QString &serial);
    void deviceDeparted(const QString &serial);
    void magnitudesChanged();

private slots:
    void pollStatus();
    void pollHotplug();

private:
    FfiCore *m_core = nullptr;
    SystemStatus m_status = {};
    QString m_selectedSerial;
    QStringList m_availableSerials;
    QTimer *m_statusTimer = nullptr;
    QTimer *m_hotplugTimer = nullptr;

    // Magnitude caching
    bool m_magnitudeDirty[MAX_CHANNELS] = {};
    double m_magnitudeCache[MAX_CHANNELS][MAGNITUDE_POINTS] = {};
    bool m_magnitudeValid[MAX_CHANNELS] = {};

    // Channel visibility
    bool m_channelVisible[MAX_CHANNELS];

    const DspState *state() const;
    void markAllDirty();

    static void hotplugCallback(uint8_t event, const char *serial, void *userData);
};

#endif // DSPIBRIDGE_H
