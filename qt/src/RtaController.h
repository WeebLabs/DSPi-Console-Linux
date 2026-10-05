#ifndef RTACONTROLLER_H
#define RTACONTROLLER_H

#include <QObject>
#include <QHash>
#include <QVariantList>
#include <QAtomicInt>
#include <QElapsedTimer>

extern "C" {
#include "dspi_core.h"
}

class DSPiBridge;

// The spectrum analyser, shared by every view that shows it. The device does
// the analysis; the core polls it on its own thread. Views subscribe while
// they are on screen with the tap and channels they show; the newest
// subscription picks the tap, and the channels of every subscription at that
// tap are polled together. frameChanged fires only when the picture changed,
// telemetryChanged when the status line did (about twice a second).
//
// Channels are indices at a tap: input index (tap 0) or output index (tap 1).
class RtaController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool supported READ supported NOTIFY capsChanged)
    Q_PROPERTY(int inputChannels READ inputChannels NOTIFY capsChanged)
    Q_PROPERTY(int outputChannels READ outputChannels NOTIFY capsChanged)
    Q_PROPERTY(int orderMin READ orderMin NOTIFY capsChanged)
    Q_PROPERTY(int orderMax READ orderMax NOTIFY capsChanged)
    Q_PROPERTY(int dynamicRange READ dynamicRange NOTIFY capsChanged)
    Q_PROPERTY(int bassDynamicRange READ bassDynamicRange NOTIFY capsChanged)

    // Engine options (Settings): sent to the device, never stored there
    Q_PROPERTY(int fftOrder READ fftOrder WRITE setFftOrder NOTIFY optionsChanged)
    Q_PROPERTY(int avgMs READ avgMs WRITE setAvgMs NOTIFY optionsChanged)
    Q_PROPERTY(int peakDecay READ peakDecay WRITE setPeakDecay NOTIFY optionsChanged)

    // Telemetry
    Q_PROPERTY(bool running READ running NOTIFY telemetryChanged)
    Q_PROPERTY(int liveCount READ liveCount NOTIFY telemetryChanged)
    Q_PROPERTY(double refreshMs READ refreshMs NOTIFY telemetryChanged)
    Q_PROPERTY(int framesPerSecond READ framesPerSecond NOTIFY telemetryChanged)
    Q_PROPERTY(int transformUs READ transformUs NOTIFY telemetryChanged)
    Q_PROPERTY(double mainLoopPercent READ mainLoopPercent NOTIFY telemetryChanged)
    Q_PROPERTY(double bassPercent READ bassPercent NOTIFY telemetryChanged)
    Q_PROPERTY(bool bassSaturated READ bassSaturated NOTIFY telemetryChanged)
    Q_PROPERTY(bool configRejected READ configRejected NOTIFY telemetryChanged)
    Q_PROPERTY(int appliedOrder READ appliedOrder NOTIFY telemetryChanged)
    Q_PROPERTY(int sampleRate READ sampleRate NOTIFY telemetryChanged)
    // Lowest band with a level, in Hz (0 = none missing)
    Q_PROPERTY(int lowestShadedHz READ lowestShadedHz NOTIFY telemetryChanged)

public:
    explicit RtaController(DSPiBridge *bridge, QObject *parent = nullptr);
    ~RtaController() override;

    bool supported() const { return m_caps.supported; }
    int inputChannels() const { return m_caps.input_channels; }
    int outputChannels() const { return m_caps.output_channels; }
    int orderMin() const { return m_caps.order_min; }
    int orderMax() const { return m_caps.order_max; }
    int dynamicRange() const { return m_caps.dynamic_range_db; }
    int bassDynamicRange() const { return m_caps.bass_dynamic_range_db; }
    const RtaCapsInfo &caps() const { return m_caps; }
    const RtaSnapshot &snapshot() const { return m_snap; }

    int fftOrder() const { return m_fftOrder; }
    int avgMs() const { return m_avgMs; }
    int peakDecay() const { return m_peakDecay; }
    void setFftOrder(int v);
    void setAvgMs(int v);
    void setPeakDecay(int v);

    bool running() const { return m_snap.running; }
    int liveCount() const { return m_snap.live_count; }
    double refreshMs() const { return m_snap.refresh_interval_s * 1000.0; }
    int framesPerSecond() const { return m_snap.frames_per_s; }
    int transformUs() const { return m_snap.last_frame_us; }
    double mainLoopPercent() const { return m_snap.busy_us_per_s / 10000.0; }
    double bassPercent() const { return m_snap.bass_busy_us_per_s / 10000.0; }
    bool bassSaturated() const { return m_snap.bass_busy_us_per_s == 0xFFFF; }
    bool configRejected() const { return m_snap.config_rejected; }
    int appliedOrder() const { return m_snap.fft_order; }
    int sampleRate() const { return m_snap.sample_rate; }
    int lowestShadedHz() const;

    // A view's interest: tap, channel mask, and whether it draws FFT bins.
    // Returns an id for update/release.
    int subscribe(int tap, int mask, bool wantsBins);
    void update(int id, int tap, int mask, bool wantsBins);
    void release(int id);

    // Seconds between new frames of one channel (for display smoothing)
    double refreshInterval() const { return m_snap.refresh_interval_s; }

    // App channel id of a tap channel, and back
    Q_INVOKABLE int appChannel(int tap, int index) const;
    Q_INVOKABLE int tapOf(int appChannel) const;          // 0 input, 1 output, -1 none
    Q_INVOKABLE int tapIndex(int appChannel) const;
    // Channels that can be analysed at a tap now (live inputs, enabled outputs)
    Q_INVOKABLE QVariantList availableChannels(int tap) const;

signals:
    void capsChanged();
    void optionsChanged();
    void frameChanged();
    void telemetryChanged();

private slots:
    void onWake();

private:
    static void wakeCallback(void *userData);
    void pushRequest();

    struct Sub { int tap; int mask; bool bins; quint64 seq; };

    DSPiBridge *m_bridge;
    FfiCore *m_core;
    RtaCapsInfo m_caps {};
    RtaSnapshot m_snap {};
    QHash<int, Sub> m_subs;
    quint64 m_seq = 0;
    int m_nextId = 1;
    QAtomicInt m_wakePending = 0;
    RtaRequest m_sent {};
    int m_fftOrder = 10;
    int m_avgMs = 300;
    int m_peakDecay = 12;
};

#endif // RTACONTROLLER_H
