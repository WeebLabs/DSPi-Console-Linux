#include "FirmwareUpdater.h"
#include "DSPiBridge.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <thread>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#ifdef Q_OS_MACOS
#include <sys/mount.h>
#include <vector>
#endif

extern "C" {
#include "dspi_core.h"
}

namespace {
#ifdef Q_OS_MACOS
int syncData(int fd) { return ::fsync(fd); }
#else
int syncData(int fd) { return ::fdatasync(fd); }
#endif
// How long the board may sit on the bus with no drive before that's a failure
constexpr int kVolumeWaitMs = 8000;
// How long to wait for the device to come back after a write (reboot, USB
// enumeration, our reconnect and platform read)
constexpr int kVerifyTimeoutMs = 30000;
// Past this fraction a write error is the bootloader rebooting as it takes
// the last blocks, the normal ending
constexpr double kRebootThreshold = 0.95;
constexpr int kChunk = 16 * 1024;
}

// ── Versions ──

FwVersion FwVersion::parse(const QString &text) {
    FwVersion v;
    QRegularExpressionMatch m = QRegularExpression("^(\\d+)(?:\\.(\\d+))?(?:\\.(\\d+))?(.*)$").match(text.trimmed());
    if (!m.hasMatch()) return v;
    v.major = m.captured(1).toInt();
    v.minor = m.captured(2).toInt();
    v.patch = m.captured(3).toInt();
    QRegularExpressionMatch b = QRegularExpression("^[-. ]*beta\\s*(\\d+)", QRegularExpression::CaseInsensitiveOption)
                                    .match(m.captured(4));
    v.beta = b.hasMatch() ? b.captured(1).toInt() : 0;
    v.valid = true;
    return v;
}

QString FwVersion::text() const {
    if (!valid) return QString();
    QString t = QString("%1.%2.%3").arg(major).arg(minor).arg(patch);
    if (beta == -1) return t + " early beta";
    if (beta > 0) return t + QString(" beta %1").arg(beta);
    return t;
}

bool FwVersion::operator<(const FwVersion &o) const {
    if (major != o.major) return major < o.major;
    if (minor != o.minor) return minor < o.minor;
    if (patch != o.patch) return patch < o.patch;
    return betaRank() < o.betaRank();
}

// The bundled image for a chip, e.g. :/firmware/DSPi-RP2350-v1.1.6-beta4.uf2
static QString imagePath(bool rp2350) {
    const QString token = rp2350 ? "-RP2350-" : "-RP2040-";
    for (const QString &name : QDir(":/firmware").entryList({ "*.uf2" }))
        if (name.contains(token)) return ":/firmware/" + name;
    return QString();
}

// ── Updater ──

FirmwareUpdater::FirmwareUpdater(DSPiBridge *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge)
{
    m_expected = FwVersion::parse(QCoreApplication::applicationVersion());
    m_scanTimer.setInterval(1000);
    connect(&m_scanTimer, &QTimer::timeout, this, &FirmwareUpdater::scan);
    m_verifyTimer.setInterval(250);
    connect(&m_verifyTimer, &QTimer::timeout, this, &FirmwareUpdater::verifyTick);
    connect(m_bridge, &DSPiBridge::stateChanged, this, &FirmwareUpdater::deviceChanged);
    // statusChanged comes with every meter poll; pass on only a connection change
    connect(m_bridge, &DSPiBridge::statusChanged, this, [this]() {
        if (m_bridge->connected() != m_wasConnected) { m_wasConnected = m_bridge->connected(); emit deviceChanged(); }
    });
}

FirmwareUpdater::~FirmwareUpdater() {
    if (m_writer.joinable()) m_writer.join();
}

static FwVersion deviceFw(DSPiBridge *bridge) {
    FwVersion v;
    if (!bridge->connected()) return v;
    const DspState *s = dspi_get_state(bridge->core());
    if (s->fw_major == 0 && s->fw_minor == 0 && s->fw_patch == 0) return v;
    v.major = s->fw_major; v.minor = s->fw_minor; v.patch = s->fw_patch;
    v.beta = s->fw_beta == FW_BETA_EARLY ? -1 : s->fw_beta;
    v.valid = true;
    return v;
}

QString FirmwareUpdater::deviceVersion() const { return deviceFw(m_bridge).text(); }

int FirmwareUpdater::match() const {
    const FwVersion d = deviceFw(m_bridge);
    if (!d.valid || !m_expected.valid) return 0;
    if (d == m_expected) return 1;
    return d < m_expected ? 2 : 3;
}

QString FirmwareUpdater::chipName() const {
    return m_chip == Rp2350 ? "RP2350 (Pico 2)" : m_chip == Rp2040 ? "RP2040 (Pico)" : QString();
}
QString FirmwareUpdater::volumeName() const {
    return m_chip == Rp2350 ? "RP2350" : m_chip == Rp2040 ? "RPI-RP2" : QString();
}

void FirmwareUpdater::publish(const QString &state) {
    if (state == m_state) return;
    m_state = state;
    emit stateChanged();
}

void FirmwareUpdater::fail(const QString &message, bool mundane, bool noBoard) {
    m_failure = message;
    m_failureMundane = mundane;
    m_noBoard = noBoard;
    m_state = "failed";
    emit stateChanged();
}

void FirmwareUpdater::beginWatching() {
    m_watching = true;
    m_scanTimer.start();
    scan();
}

void FirmwareUpdater::stopWatching() {
    m_watching = false;
    m_scanTimer.stop();
    if (!m_installing) { m_armed = false; publish("idle"); }
}

// Where the drive with this label is mounted. Read from the kernel's mount
// table, which touches no filesystem: a board that rebooted mid-write can
// leave a dead mount behind, and stat-ing one can block.
QString FirmwareUpdater::mountPointOf(const QString &device, const QString &label) {
#ifdef Q_OS_MACOS
    // macOS mounts the drive itself under /Volumes; MNT_NOWAIT reads the
    // cached table without asking any filesystem
    Q_UNUSED(device);
    const int n = getfsstat(nullptr, 0, MNT_NOWAIT);
    if (n <= 0) return QString();
    std::vector<struct statfs> mounts(static_cast<size_t>(n));
    const int got = getfsstat(mounts.data(), int(mounts.size() * sizeof(struct statfs)), MNT_NOWAIT);
    for (int i = 0; i < got; ++i) {
        const QString mountPoint = QFile::decodeName(mounts[size_t(i)].f_mntonname);
        if (QFileInfo(mountPoint).fileName() == label) return mountPoint;
    }
    return QString();
#endif
    QFile f("/proc/self/mountinfo");
    if (!f.open(QIODevice::ReadOnly)) return QString();
    const QStringList lines = QString::fromUtf8(f.readAll()).split('\n', Qt::SkipEmptyParts);
    auto unescape = [](QString s) {
        return s.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace("\\134", "\\");
    };
    for (const QString &line : lines) {
        const QStringList parts = line.split(' ');
        const int dash = parts.indexOf("-");
        if (parts.size() < 5 || dash < 0 || dash + 2 >= parts.size()) continue;
        const QString mountPoint = unescape(parts[4]);
        const QString source = unescape(parts[dash + 2]);
        if ((!device.isEmpty() && source == device) || QFileInfo(mountPoint).fileName() == label)
            return mountPoint;
    }
    return QString();
}

// What is attached, as a state. Stops once an install has begun: mid-write
// the board vanishing is the expected reboot, and afterwards the outcome
// holds until reset().
void FirmwareUpdater::scan() {
    if (m_installing) return;
    uint32_t rp2040 = 0, rp2350 = 0;
    dspi_bootloader_counts(&rp2040, &rp2350);
    const uint32_t count = rp2040 + rp2350;

    if (count == 0) {
        m_volumeWait.invalidate();
        m_chip = None;
        publish("waitingForBoard");
        return;
    }
    if (count > 1) {
        m_volumeWait.invalidate();
        fail(QString("%1 boards are in bootloader mode. Disconnect all but the one you want to update.").arg(count), true);
        return;
    }

    const Chip chip = rp2350 ? Rp2350 : Rp2040;
    if (chip != m_chip) { m_chip = chip; m_mountTried.clear(); emit stateChanged(); }
    const QString label = volumeName();
    const QString byLabel = "/dev/disk/by-label/" + label;
    m_device = QFileInfo::exists(byLabel) ? QFileInfo(byLabel).canonicalFilePath() : QString();
    m_mountPoint = mountPointOf(m_device, label);

    if (!m_mountPoint.isEmpty()) {
        m_volumeWait.invalidate();
        publish("ready");
        if (m_armed) install();
        return;
    }

    // The drive appears a moment after the board; most Linux desktops don't
    // mount it on their own, so ask udisks once it shows up
    if (!m_device.isEmpty() && m_mountTried != m_device) {
        m_mountTried = m_device;
        QPointer<FirmwareUpdater> self(this);
        auto *p = new QProcess(this);
        connect(p, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [self, p](int, QProcess::ExitStatus) {
            p->deleteLater();
            if (self && self->m_watching) self->scan();
        });
        connect(p, &QProcess::errorOccurred, p, [p](QProcess::ProcessError) { p->deleteLater(); });
        p->start("udisksctl", { "mount", "--no-user-interaction", "-b", m_device });
    }
    if (!m_volumeWait.isValid()) m_volumeWait.start();
    if (m_volumeWait.elapsed() >= kVolumeWaitMs) {
        fail(QString("The board is connected but its %1 drive could not be mounted. Mount it from your file manager and try again.").arg(label), true);
        return;
    }
    publish("waitingForVolume");
}

void FirmwareUpdater::installWhenReady() {
    m_armed = true;
    if (m_state == "ready") install();
    else if (!m_scanTimer.isActive()) beginWatching();
}

void FirmwareUpdater::reset() {
    if (m_state == "writing" || m_state == "waitingForDevice") return;
    m_installing = false;
    m_armed = false;
    m_volumeWait.invalidate();
    m_mountTried.clear();
    m_failure.clear();
    m_noBoard = false;
    m_progress = 0;
    emit progressChanged();
    m_state = "idle";
    emit stateChanged();
    if (m_watching) scan();
}

void FirmwareUpdater::enterBootloader() {
    if (m_bridge->connected()) m_bridge->enterBootloader();
}

int FirmwareUpdater::compareVersions(const QString &a, const QString &b) const {
    const FwVersion x = FwVersion::parse(a), y = FwVersion::parse(b);
    return x == y ? 0 : x < y ? -1 : 1;
}

QVariantList FirmwareUpdater::releaseNotes() const {
    QFile f(":/whatsnew.json");
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QJsonDocument::fromJson(f.readAll()).array().toVariantList();
}

void FirmwareUpdater::install() {
    if (m_installing) return;
    // The decision is spent here, success or not: a later board is a new one
    m_armed = false;
    m_installing = true;

    const QString path = imagePath(m_chip == Rp2350);
    if (path.isEmpty()) {
        fail(QString("This build of DSPi Console does not include firmware for the %1.").arg(chipName()), false);
        return;
    }
    m_image = FwVersion::parse(path.mid(path.lastIndexOf("-v") + 2).remove(".uf2"));
    if (!m_image.valid || !(m_image == m_expected)) {
        fail(QString("The bundled firmware is version %1 but this Console expects %2. The app was built incorrectly; do not install it.")
                 .arg(m_image.text(), m_expected.text()), false);
        return;
    }
    QFile image(path);
    if (!image.open(QIODevice::ReadOnly)) {
        fail("Writing the firmware failed: could not read the bundled image.", false);
        return;
    }
    const QByteArray data = image.readAll();
    const QString dest = m_mountPoint + "/" + QFileInfo(path).fileName();
    const QString device = m_device;

    m_progress = 0;
    emit progressChanged();
    publish("writing");

    // Written in chunks, each synced to the board so the progress is real.
    // The bootloader reboots as it takes the last blocks, so an error late in
    // the write, or once the drive has gone, is the normal ending.
    QPointer<FirmwareUpdater> self(this);
    if (m_writer.joinable()) m_writer.join();
    m_writer = std::thread([self, data, dest, device]() {
        QString error;
        const int fd = ::open(QFile::encodeName(dest).constData(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            error = "could not open the board's drive for writing.";
        } else {
            qint64 written = 0;
            const qint64 total = data.size();
            while (written < total) {
                const int n = int(qMin<qint64>(kChunk, total - written));
                const bool ok = ::write(fd, data.constData() + written, size_t(n)) == n && syncData(fd) == 0;
                if (!ok) {
                    const double fraction = double(written) / double(total);
                    if (fraction < kRebootThreshold && (device.isEmpty() || QFileInfo::exists(device)))
                        error = QString::fromLocal8Bit(strerror(errno)) + ".";
                    break;
                }
                written += n;
                const double fraction = double(written) / double(total);
                QMetaObject::invokeMethod(QCoreApplication::instance(), [self, fraction]() {
                    if (!self) return;
                    self->m_progress = fraction;
                    emit self->progressChanged();
                }, Qt::QueuedConnection);
            }
            ::close(fd);    // may fail once the board has gone; every byte is out by then
        }
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, error]() {
            if (self) self->writeFinished(error);
        }, Qt::QueuedConnection);
    });
}

void FirmwareUpdater::writeFinished(const QString &error) {
    if (!error.isEmpty()) {
        fail("Writing the firmware failed: " + error, false);
        return;
    }
    // The copy returning proves nothing: success is the device coming back
    // and reporting what was written
    publish("waitingForDevice");
    m_verifyClock.start();
    m_verifyTimer.start();
}

void FirmwareUpdater::verifyTick() {
    const FwVersion v = deviceFw(m_bridge);
    if (v.valid) {
        m_verifyTimer.stop();
        if (v == m_image) {
            m_verified = v;
            publish("verified");
        } else {
            fail(QString("The device came back running firmware %1 instead of %2.").arg(v.text(), m_image.text()), false);
        }
        return;
    }
    if (m_verifyClock.elapsed() > kVerifyTimeoutMs) {
        m_verifyTimer.stop();
        fail("The firmware was written but the device did not reappear. Unplug it, plug it back in, and check whether it works.", false);
    }
}
