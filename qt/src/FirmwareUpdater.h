#ifndef FIRMWAREUPDATER_H
#define FIRMWAREUPDATER_H

#include <QObject>
#include <QElapsedTimer>
#include <QTimer>
#include <QVariantList>
#include <thread>

class DSPiBridge;

// A firmware version: major.minor.patch plus the beta ordinal (0 = final,
// -1 = an early 1.1.6 beta that predates the ordinal on the wire).
struct FwVersion {
    int major = 0, minor = 0, patch = 0, beta = 0;
    bool valid = false;
    static FwVersion parse(const QString &text);      // "1.1.6-beta4", "1.1.7"
    QString text() const;                              // "1.1.6 beta 4"
    // Final outranks every beta of its patch; an early beta sorts below beta 1
    int betaRank() const { return beta == 0 ? 256 : beta; }
    bool operator==(const FwVersion &o) const {
        return major == o.major && minor == o.minor && patch == o.patch && beta == o.beta;
    }
    bool operator<(const FwVersion &o) const;
};

// Installs the firmware bundled with this Console onto a board, as the macOS
// Console does: the device restarts into its ROM bootloader (BOOTSEL), the
// UF2 is written to the bootloader's drive, and the update counts only once
// the device comes back reporting the version written. It never flashes on
// its own: installWhenReady() is the user's decision, and it covers one
// board. On Linux the bootloader drive is often not mounted automatically,
// so it is mounted through udisks.
class FirmwareUpdater : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString expectedVersion READ expectedVersion CONSTANT)
    Q_PROPERTY(QString deviceVersion READ deviceVersion NOTIFY deviceChanged)
    // 0 = no device / unknown, 1 = matches, 2 = device older, 3 = device newer
    Q_PROPERTY(int match READ match NOTIFY deviceChanged)

    // idle, waitingForBoard, waitingForVolume, ready, writing, waitingForDevice,
    // verified, failed
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString chipName READ chipName NOTIFY stateChanged)       // "RP2350 (Pico 2)"
    Q_PROPERTY(QString volumeName READ volumeName NOTIFY stateChanged)   // "RP2350"
    Q_PROPERTY(QString failure READ failure NOTIFY stateChanged)
    // A detection-side stumble (no board, no drive, two boards) rather than a
    // failed write
    Q_PROPERTY(bool failureMundane READ failureMundane NOTIFY stateChanged)
    Q_PROPERTY(bool noBoardFailure READ noBoardFailure NOTIFY stateChanged)
    Q_PROPERTY(QString verifiedVersion READ verifiedVersion NOTIFY stateChanged)

public:
    explicit FirmwareUpdater(DSPiBridge *bridge, QObject *parent = nullptr);
    ~FirmwareUpdater() override;

    QString expectedVersion() const { return m_expected.text(); }
    QString deviceVersion() const;
    int match() const;
    QString state() const { return m_state; }
    double progress() const { return m_progress; }
    QString chipName() const;
    QString volumeName() const;
    QString failure() const { return m_failure; }
    bool failureMundane() const { return m_failureMundane; }
    bool noBoardFailure() const { return m_noBoard; }
    QString verifiedVersion() const { return m_verified.text(); }

    // Detection runs while an update UI is open
    Q_INVOKABLE void beginWatching();
    Q_INVOKABLE void stopWatching();
    // The user's decision: write the next ready board (now, if one is ready)
    Q_INVOKABLE void installWhenReady();
    // Back to detection after an outcome (Try Again, Update Another Board)
    Q_INVOKABLE void reset();
    // Restart the connected device into its bootloader
    Q_INVOKABLE void enterBootloader();
    // -1, 0 or 1 as version a sorts before, with or after b ("1.1.6-beta4")
    Q_INVOKABLE int compareVersions(const QString &a, const QString &b) const;
    // The release notes shipped with this build (whatsnew.json), as a list
    Q_INVOKABLE QVariantList releaseNotes() const;

signals:
    void deviceChanged();
    void stateChanged();
    void progressChanged();

private:
    enum Chip { None, Rp2040, Rp2350 };
    void scan();
    void publish(const QString &state);
    void fail(const QString &message, bool mundane, bool noBoard = false);
    void install();
    void writeFinished(const QString &error);
    void verifyTick();
    static QString mountPointOf(const QString &device, const QString &label);

    DSPiBridge *m_bridge;
    FwVersion m_expected;
    QTimer m_scanTimer;
    QTimer m_verifyTimer;
    QElapsedTimer m_verifyClock;
    QElapsedTimer m_volumeWait;

    QString m_state = "idle";
    double m_progress = 0;
    Chip m_chip = None;
    QString m_mountPoint;
    QString m_device;            // the drive's block device, e.g. /dev/sdb1
    QString m_mountTried;        // the device a mount was last asked for
    QString m_failure;
    bool m_failureMundane = false;
    bool m_noBoard = false;
    FwVersion m_verified;
    FwVersion m_image;           // what is being written

    bool m_installing = false;   // from install() until reset()
    bool m_armed = false;
    bool m_watching = false;
    bool m_wasConnected = false;
    std::thread m_writer;        // joined on shutdown: a write is never cut short
};

#endif // FIRMWAREUPDATER_H
