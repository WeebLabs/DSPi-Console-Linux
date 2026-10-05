#ifndef SIGGENCONTROLLER_H
#define SIGGENCONTROLLER_H

#include <QObject>
#include <QTimer>
#include <QVariantMap>

extern "C" {
#include "dspi_core.h"
}

class DSPiBridge;

// The device's signal generator: its caps, the draft signal the window
// edits (kept for the session, seeded from the device's applied config at
// connect), and the generator's status. While a signal plays, edits to the
// draft re-apply after a short pause; an unchanged draft is never re-sent,
// since every send restarts the signal with a fade. The device ACKs a
// config even when it refuses one, so starts are checked by reading back.
class SiggenController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool supported READ supported NOTIFY capsChanged)
    Q_PROPERTY(int outputChannels READ outputChannels NOTIFY capsChanged)
    Q_PROPERTY(int validMask READ validMask NOTIFY capsChanged)
    Q_PROPERTY(int multitoneMax READ multitoneMax NOTIFY capsChanged)

    // Draft: type, channelMask, invertMask, flags, levelDb, durationMs,
    // repeat, gapMs, p (list of 4)
    Q_PROPERTY(QVariantMap draft READ draft NOTIFY draftChanged)

    Q_PROPERTY(int state READ state NOTIFY statusChanged)
    Q_PROPERTY(bool running READ running NOTIFY statusChanged)
    Q_PROPERTY(int signalType READ signalType NOTIFY statusChanged)
    Q_PROPERTY(int activeChannel READ activeChannel NOTIFY statusChanged)
    Q_PROPERTY(int elapsedMs READ elapsedMs NOTIFY statusChanged)
    Q_PROPERTY(int cyclesDone READ cyclesDone NOTIFY statusChanged)
    Q_PROPERTY(int stopReason READ stopReason NOTIFY statusChanged)
    Q_PROPERTY(double currentFreq READ currentFreq NOTIFY statusChanged)

    // The window is open: poll the status while a signal plays
    Q_PROPERTY(bool watching READ watching WRITE setWatching NOTIFY watchingChanged)

public:
    explicit SiggenController(DSPiBridge *bridge, QObject *parent = nullptr);

    bool supported() const { return m_caps.supported; }
    int outputChannels() const { return m_caps.output_channels; }
    int validMask() const { return m_caps.valid_mask; }
    int multitoneMax() const { return m_caps.multitone_max; }
    QVariantMap draft() const;

    int state() const { return m_status.state; }
    bool running() const { return m_status.state != 0; }
    int signalType() const { return m_status.signal_type; }
    int activeChannel() const { return m_status.active_channel == 0xFF ? -1 : m_status.active_channel; }
    int elapsedMs() const { return int(m_status.elapsed_ms); }
    int cyclesDone() const { return m_status.cycles_done; }
    int stopReason() const { return m_status.stop_reason; }
    double currentFreq() const { return m_status.current_freq; }

    bool watching() const { return m_watching; }
    void setWatching(bool w);

    // {timing, params: [{semantic, min, max, def}] x4}: the device's
    // descriptor, or the built-in one when it gave none
    Q_INVOKABLE QVariantMap typeInfo(int type) const;

    // Draft edits
    Q_INVOKABLE void selectType(int type);
    Q_INVOKABLE void setDraftValue(const QString &field, const QVariant &value);
    Q_INVOKABLE void setParam(int index, double value);
    Q_INVOKABLE void setFlag(int flag, bool on);
    Q_INVOKABLE void cycleOutput(int output);     // off -> on -> inverted -> off
    Q_INVOKABLE void selectAllOutputs();
    Q_INVOKABLE void clearOutputs();

    // Transport. start() returns false if the device refused the signal.
    Q_INVOKABLE bool start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void stopNow();
    // Channel ID on one output, leaving the draft alone
    Q_INVOKABLE void identify(int output);

signals:
    void capsChanged();
    void draftChanged();
    void statusChanged();
    void watchingChanged();

private:
    void onDeviceChanged();
    void refreshStatus();
    void scheduleApply();
    void applyLive();
    void updatePolling();
    int usableMask() const;
    SiggenConfig normalised(SiggenConfig c) const;
    SiggenTypeInfo typeDesc(int type) const;

    DSPiBridge *m_bridge;
    FfiCore *m_core;
    SiggenCaps m_caps {};
    SiggenConfig m_draft {};
    SiggenConfig m_sent {};          // last config sent while running
    SiggenStatus m_status {};
    QString m_serial;                // device the caps and status belong to
    bool m_watching = false;
    QTimer m_poll;
    QTimer m_apply;
};

#endif // SIGGENCONTROLLER_H
