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

// The QML speaks stable app channel ids; the core speaks firmware wire
// channel indices. App ids (same scheme as the Windows Console):
//   0, 1    inputs 1-2 (USB L/R)
//   2..10   outputs 1-9
//   11..16  inputs 3-8 (RP2350 multichannel inputs)
// Output-indexed calls (matrix, output gain/mute/delay) take an output
// index 0..numOutputChannels-1, and input-indexed calls an input index.
static constexpr int kAppChannelCount = 17;
static constexpr int kAppExtraInputFirst = 11;

class DSPiBridge : public QObject
{
    Q_OBJECT

    // Connection / device
    Q_PROPERTY(bool connected READ connected NOTIFY statusChanged)
    Q_PROPERTY(QString selectedSerial READ selectedSerial NOTIFY stateChanged)
    Q_PROPERTY(QStringList availableSerials READ availableSerials NOTIFY devicesChanged)
    Q_PROPERTY(QString platformName READ platformName NOTIFY stateChanged)
    Q_PROPERTY(int numChannels READ numChannels NOTIFY stateChanged)
    Q_PROPERTY(int numInputChannels READ numInputChannels NOTIFY stateChanged)
    Q_PROPERTY(int numOutputChannels READ numOutputChannels NOTIFY stateChanged)
    Q_PROPERTY(QString firmwareVersion READ firmwareVersion NOTIFY stateChanged)
    Q_PROPERTY(int compat READ compat NOTIFY stateChanged)
    Q_PROPERTY(QString compatMessage READ compatMessage NOTIFY stateChanged)
    Q_PROPERTY(float maxDelayMs READ maxDelayMs NOTIFY stateChanged)

    // Global
    Q_PROPERTY(float preampDB READ preampDB NOTIFY stateChanged)
    Q_PROPERTY(bool bypass READ bypass NOTIFY stateChanged)

    // Volume
    Q_PROPERTY(float masterVolumeDB READ masterVolumeDB NOTIFY stateChanged)
    Q_PROPERTY(int masterVolumeMode READ masterVolumeMode NOTIFY stateChanged)
    Q_PROPERTY(float userVolumeDB READ userVolumeDB NOTIFY stateChanged)
    Q_PROPERTY(bool userMute READ userMute NOTIFY stateChanged)

    // Loudness
    Q_PROPERTY(bool loudnessEnabled READ loudnessEnabled NOTIFY stateChanged)
    Q_PROPERTY(float loudnessRefSPL READ loudnessRefSPL NOTIFY stateChanged)
    Q_PROPERTY(float loudnessIntensity READ loudnessIntensity NOTIFY stateChanged)
    Q_PROPERTY(int loudnessOutputMask READ loudnessOutputMask NOTIFY stateChanged)

    // Crossfeed
    Q_PROPERTY(bool crossfeedEnabled READ crossfeedEnabled NOTIFY stateChanged)
    Q_PROPERTY(int crossfeedPreset READ crossfeedPreset NOTIFY stateChanged)
    Q_PROPERTY(float crossfeedFreq READ crossfeedFreq NOTIFY stateChanged)
    Q_PROPERTY(float crossfeedFeed READ crossfeedFeed NOTIFY stateChanged)
    Q_PROPERTY(bool crossfeedITD READ crossfeedITD NOTIFY stateChanged)
    Q_PROPERTY(int crossfeedOutputPairMask READ crossfeedOutputPairMask NOTIFY stateChanged)

    // CPU / Status
    Q_PROPERTY(int cpu0 READ cpu0 NOTIFY statusChanged)
    Q_PROPERTY(int cpu1 READ cpu1 NOTIFY statusChanged)
    Q_PROPERTY(int clipFlags READ clipFlags NOTIFY statusChanged)
    Q_PROPERTY(int activeInputChannels READ activeInputChannels NOTIFY statusChanged)

    // Presets
    Q_PROPERTY(int activePresetSlot READ activePresetSlot NOTIFY stateChanged)
    Q_PROPERTY(int presetOccupied READ presetOccupied NOTIFY stateChanged)
    Q_PROPERTY(int presetStartupMode READ presetStartupMode NOTIFY stateChanged)
    Q_PROPERTY(int presetDefaultSlot READ presetDefaultSlot NOTIFY stateChanged)
    // 0 = output (pin/IO) config stored independently, 1 = saved with presets.
    Q_PROPERTY(int outputConfigMode READ outputConfigMode NOTIFY stateChanged)

    // Input source / quick-access feature toggles
    Q_PROPERTY(int inputSource READ inputSource NOTIFY stateChanged)
    Q_PROPERTY(QVariantList inputSources READ inputSources NOTIFY stateChanged)
    Q_PROPERTY(bool levellerEnabled READ levellerEnabled NOTIFY stateChanged)
    Q_PROPERTY(bool psybassEnabled READ psybassEnabled NOTIFY stateChanged)

    // Volume leveller parameters
    Q_PROPERTY(float levellerAmount READ levellerAmount NOTIFY stateChanged)
    Q_PROPERTY(int levellerSpeed READ levellerSpeed NOTIFY stateChanged)
    Q_PROPERTY(float levellerMaxGain READ levellerMaxGain NOTIFY stateChanged)
    Q_PROPERTY(float levellerGate READ levellerGate NOTIFY stateChanged)
    Q_PROPERTY(bool levellerLookahead READ levellerLookahead NOTIFY stateChanged)
    Q_PROPERTY(int levellerDetectorMask READ levellerDetectorMask NOTIFY stateChanged)
    Q_PROPERTY(int levellerApplyMask READ levellerApplyMask NOTIFY stateChanged)

    // Psychoacoustic bass parameters
    Q_PROPERTY(float psybassCutoff READ psybassCutoff NOTIFY stateChanged)
    Q_PROPERTY(float psybassHarmonics READ psybassHarmonics NOTIFY stateChanged)
    Q_PROPERTY(float psybassDrive READ psybassDrive NOTIFY stateChanged)
    Q_PROPERTY(float psybassCharacter READ psybassCharacter NOTIFY stateChanged)
    Q_PROPERTY(float psybassOriginal READ psybassOriginal NOTIFY stateChanged)
    Q_PROPERTY(int psybassOutputMask READ psybassOutputMask NOTIFY stateChanged)

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
    int numInputChannels() const;
    int numOutputChannels() const;
    QString firmwareVersion() const;
    int compat() const;
    QString compatMessage() const;
    float maxDelayMs() const;

    float preampDB() const;
    bool bypass() const;

    float masterVolumeDB() const;
    int masterVolumeMode() const;
    float userVolumeDB() const;
    bool userMute() const;

    bool loudnessEnabled() const;
    float loudnessRefSPL() const;
    float loudnessIntensity() const;
    int loudnessOutputMask() const;

    bool crossfeedEnabled() const;
    int crossfeedPreset() const;
    float crossfeedFreq() const;
    float crossfeedFeed() const;
    bool crossfeedITD() const;
    int crossfeedOutputPairMask() const;

    int cpu0() const;
    int cpu1() const;
    int clipFlags() const;
    int activeInputChannels() const;

    int activePresetSlot() const;
    int presetOccupied() const;
    int presetStartupMode() const;
    int presetDefaultSlot() const;
    int outputConfigMode() const;

    int core1Mode() const;
    int inputSource() const;
    QVariantList inputSources() const;   // [{id, name}] available and enabled
    bool levellerEnabled() const;
    bool psybassEnabled() const;
    float levellerAmount() const { return state()->leveller_amount; }
    int levellerSpeed() const { return state()->leveller_speed; }
    float levellerMaxGain() const { return state()->leveller_max_gain_db; }
    float levellerGate() const { return state()->leveller_gate_db; }
    bool levellerLookahead() const { return state()->leveller_lookahead; }
    int levellerDetectorMask() const { return state()->leveller_detector_mask; }
    int levellerApplyMask() const { return state()->leveller_apply_mask; }
    float psybassCutoff() const { return state()->psybass_cutoff_hz; }
    float psybassHarmonics() const { return state()->psybass_harmonics_db; }
    float psybassDrive() const { return state()->psybass_drive_db; }
    float psybassCharacter() const { return state()->psybass_character_pct; }
    float psybassOriginal() const { return state()->psybass_original_db; }
    int psybassOutputMask() const { return state()->psybass_output_mask; }

    // Channel identity (app ids)
    Q_INVOKABLE bool channelExists(int ch) const;
    Q_INVOKABLE bool isInputChannel(int ch) const;
    Q_INVOKABLE int inputAppId(int input) const;   // input index -> app id
    Q_INVOKABLE float peakLevel(int ch) const;
    Q_INVOKABLE bool isClipping(int ch) const;
    Q_INVOKABLE QString channelName(int ch) const;
    Q_INVOKABLE QString channelColor(int ch) const;
    Q_INVOKABLE QString channelDescriptor(int ch) const;

    // PEQ bands (app id, band 0..9)
    Q_INVOKABLE int filterType(int ch, int band) const;
    Q_INVOKABLE float filterFreq(int ch, int band) const;
    Q_INVOKABLE float filterGain(int ch, int band) const;
    Q_INVOKABLE float filterQ(int ch, int band) const;
    Q_INVOKABLE float filterQp(int ch, int band) const;
    Q_INVOKABLE bool filterBypass(int ch, int band) const;

    // Crossover bands (output app id, band 0..3)
    Q_INVOKABLE int crossoverType(int ch, int band) const;
    Q_INVOKABLE float crossoverFreq(int ch, int band) const;
    Q_INVOKABLE bool crossoverBypass(int ch, int band) const;

    // Inputs (input index)
    Q_INVOKABLE float inputPreampDB(int input) const;
    Q_INVOKABLE float channelDelayMS(int ch) const;

    // Outputs (output index)
    Q_INVOKABLE bool outputEnabled(int idx) const;
    Q_INVOKABLE bool outputMuted(int idx) const;
    Q_INVOKABLE float outputGainDB(int idx) const;
    Q_INVOKABLE float outputDelayMS(int idx) const;
    Q_INVOKABLE bool isPdmOutput(int idx) const;

    // Matrix (input index, output index)
    Q_INVOKABLE bool matrixRouting(int input, int output) const;
    Q_INVOKABLE float matrixGain(int input, int output) const;
    Q_INVOKABLE bool matrixInvert(int input, int output) const;
    Q_INVOKABLE int outputPin(int physOut) const;
    Q_INVOKABLE int numPinOutputs() const;

    Q_INVOKABLE QString presetName(int slot) const;
    Q_INVOKABLE bool isPresetOccupied(int slot) const;

    Q_INVOKABLE QVariantList magnitudeCurve(int ch);

    // Setters
    Q_INVOKABLE void setPreamp(float db);
    Q_INVOKABLE void sendPreampToDevice(float db);
    Q_INVOKABLE void setInputPreamp(int input, float db);
    Q_INVOKABLE void setBypass(bool en);

    Q_INVOKABLE void setMasterVolume(float db);
    Q_INVOKABLE void setMasterVolumeMode(int mode);
    Q_INVOKABLE int saveMasterVolume();
    Q_INVOKABLE void setUserVolume(float db);
    Q_INVOKABLE void setUserMute(bool muted);

    Q_INVOKABLE void setFilter(int ch, int band, int type, float freq, float gain, float q);
    Q_INVOKABLE void setLinkwitzTransform(int ch, int band, float f0, float q0, float fp, float qp);
    Q_INVOKABLE void setBandBypass(int ch, int band, bool bypass);
    Q_INVOKABLE void setCrossover(int ch, int band, int type, float freq);
    Q_INVOKABLE void setCrossoverBypass(int ch, int band, bool bypass);
    Q_INVOKABLE void setChannelDelay(int ch, float ms);

    Q_INVOKABLE void setLoudness(bool en);
    Q_INVOKABLE void setLoudnessRef(float spl);
    Q_INVOKABLE void setLoudnessIntensity(float pct);
    Q_INVOKABLE void setLoudnessOutputMask(int mask);

    Q_INVOKABLE void setCrossfeed(bool en);
    Q_INVOKABLE void setCrossfeedPreset(int p);
    Q_INVOKABLE void setCrossfeedFreq(float freq);
    Q_INVOKABLE void setCrossfeedFeed(float feed);
    Q_INVOKABLE void setCrossfeedITD(bool en);
    Q_INVOKABLE void setCrossfeedOutputPairMask(int mask);

    Q_INVOKABLE void setMatrixRoute(int input, int output, bool enabled, float gain, bool invert);
    Q_INVOKABLE bool setOutputEnable(int output, bool enabled);
    Q_INVOKABLE void setOutputGain(int output, float db);
    Q_INVOKABLE void sendOutputGainToDevice(int output, float db);
    Q_INVOKABLE void setOutputMute(int output, bool muted);
    Q_INVOKABLE void setOutputDelay(int output, float ms);
    Q_INVOKABLE void sendOutputDelayToDevice(int output, float ms);
    Q_INVOKABLE int setOutputPin(int output, int pin);
    Q_INVOKABLE void setOutputConfigMode(int mode);
    Q_INVOKABLE int saveOutputConfig();

    Q_INVOKABLE void setChannelName(int ch, const QString &name);
    Q_INVOKABLE void resetChannelNames();   // every channel back to its default name

    Q_INVOKABLE int savePreset(int slot);
    Q_INVOKABLE int loadPreset(int slot);
    Q_INVOKABLE int deletePreset(int slot);
    Q_INVOKABLE int copyPreset(int fromSlot, int toSlot);
    Q_INVOKABLE void setPresetName(int slot, const QString &name);
    Q_INVOKABLE void setPresetStartup(int mode, int slot);

    Q_INVOKABLE int saveParams();
    Q_INVOKABLE int loadParams();
    Q_INVOKABLE int factoryReset();
    Q_INVOKABLE void enterBootloader();

    Q_INVOKABLE void clearClips();
    Q_INVOKABLE int checkCore1Conflict(int output);

    Q_INVOKABLE void scanDevices();
    Q_INVOKABLE void selectDevice(const QString &serial);
    Q_INVOKABLE void disconnectDevice();
    Q_INVOKABLE void reconnect();

    Q_INVOKABLE void setInputSource(int source);
    Q_INVOKABLE void setLevellerEnabled(bool en);
    Q_INVOKABLE void setPsybassEnabled(bool en);

    // Leveller (sendOnly = live drag: no stateChanged, avoids feedback)
    Q_INVOKABLE void setLevellerAmount(float pct, bool sendOnly = false);
    Q_INVOKABLE void setLevellerSpeed(int speed);
    Q_INVOKABLE void setLevellerMaxGain(float db, bool sendOnly = false);
    Q_INVOKABLE void setLevellerGate(float db, bool sendOnly = false);
    Q_INVOKABLE void setLevellerLookahead(bool en);
    Q_INVOKABLE void setLevellerMasks(int detector, int apply);

    // Psybass: param 0 cutoff, 1 harmonics, 2 drive, 3 character, 4 original
    Q_INVOKABLE void setPsybassParam(int param, float value, bool sendOnly = false);
    Q_INVOKABLE void setPsybassOutputMask(int mask);

    // Matrix helpers
    Q_INVOKABLE void directRouting();          // input k -> output k at 0 dB, PDM off
    Q_INVOKABLE void clearRouting();           // disconnect all, keep gains/polarity
    // Outputs that would be switched off to enable `output` (PDM vs Core 1 EQ worker)
    Q_INVOKABLE QVariantList core1ConflictOutputs(int output) const;
    Q_INVOKABLE void enableOutputResolvingConflict(int output);

    // Input stereo-pair links (IN1/2, IN3/4, ...). A linked pair mirrors
    // preamp and filter edits. Links are remembered per device and pause
    // while fewer inputs are live.
    Q_INVOKABLE int liveInputCount() const;
    Q_INVOKABLE int pairPartner(int ch) const;     // the other input of ch's pair, or -1
    Q_INVOKABLE bool pairAvailable(int ch) const;  // both inputs of the pair are live
    Q_INVOKABLE bool isInputLinked(int ch) const;  // link set and pair live
    Q_INVOKABLE int linkedPartner(int ch) const;   // partner while linked, else -1
    Q_INVOKABLE bool inputPairMatches(int ch) const;
    // keepCh: app id whose settings are copied onto the other input, or -1
    Q_INVOKABLE void setInputLinked(int ch, bool linked, int keepCh);

    // Whole-list band operations (crossover = the XO tab of an output)
    Q_INVOKABLE void clearPeq(int ch);
    Q_INVOKABLE void clearAllBands(int ch, bool crossover);
    Q_INVOKABLE void setAllBandsBypass(int ch, bool bypass, bool crossover);
    Q_INVOKABLE bool canSetAllBypass(int ch, bool bypass, bool crossover) const;

    // Output limiter (output index)
    Q_INVOKABLE bool limiterEnabled(int out) const;
    Q_INVOKABLE float limiterThreshold(int out) const;
    Q_INVOKABLE float limiterRelease(int out) const;
    Q_INVOKABLE int limiterLinkGroup(int out) const;
    Q_INVOKABLE float limiterReduction(int out) const;   // dB, > 0 while limiting
    Q_INVOKABLE void setLimiterEnabled(int out, bool en);
    Q_INVOKABLE void setLimiterThreshold(int out, float db);
    Q_INVOKABLE void setLimiterRelease(int out, float ms);
    Q_INVOKABLE void setLimiterLinkGroup(int out, int group);
    Q_INVOKABLE void copyLimiterToAll(int out);
    Q_INVOKABLE void linkAllLimiterPairs();
    Q_INVOKABLE void unlinkAllLimiters();
    Q_INVOKABLE void disableAllLimiters();

    // Channel clipboard (Copy / Paste Parameters)
    Q_INVOKABLE void copyChannel(int ch);
    Q_INVOKABLE bool canPaste() const;
    Q_INVOKABLE void pasteChannel(int ch);

    // Magnitude curve access for C++ BodePlotItem (app ids)
    void getMagnitudeCurve(int ch, double *out);
    bool isMagnitudeDirty(int ch) const;
    void clearMagnitudeDirty(int ch);

    // Channel visibility for graph (app ids)
    Q_INVOKABLE bool channelVisible(int ch) const;
    Q_INVOKABLE void setChannelVisible(int ch, bool visible);

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

    // Magnitude caching (app ids)
    bool m_magnitudeDirty[kAppChannelCount] = {};
    double m_magnitudeCache[kAppChannelCount][MAGNITUDE_POINTS] = {};
    bool m_magnitudeValid[kAppChannelCount] = {};

    // Channel visibility (app ids)
    bool m_channelVisible[kAppChannelCount];

    const DspState *state() const;
    bool usable() const;              // connected to compatible firmware
    int wire(int appCh) const;        // app id -> wire channel, -1 if absent
    int appId(int wireCh) const;      // wire channel -> app id, -1 if absent
    int outputOf(int appCh) const;    // output index of an output app id, else -1
    int inputOf(int appCh) const;     // input index of an input app id, else -1
    void markAllDirty();
    void markDirty(int appCh);
    void computeCurve(int appCh);

    void applyFilter(int ch, int band, const FilterParams &p);
    void copyInputSettings(int from, int to);
    int pairIndex(int ch) const;                  // 0..3 for an input, else -1
    void loadLinks();
    void saveLinks();
    uint8_t m_links = 0x01;                       // bit p: input pair p linked
    float m_limiterGR[MAX_OUTPUTS] = {};
    qint64 m_lastClipMs[MAX_CHANNELS] = {};      // per wire channel, 0 = never
    int m_pollTick = 0;

    struct ChannelClip {
        bool valid = false;
        bool output = false;
        FilterParams filters[BANDS_PER_CHANNEL];
        FilterParams xover[MAX_XOVER_BANDS];
        float gain = 0, delay = 0;
        bool mute = false;
    } m_clip;

    static void hotplugCallback(uint8_t event, const char *serial, void *userData);
};

#endif // DSPIBRIDGE_H
