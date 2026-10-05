#include "CsController.h"
#include "DSPiBridge.h"

#include <QJsonDocument>
#include <QJsonObject>

extern "C" {
#include "dspi_core.h"
}

CsController::CsController(DSPiBridge *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge)
{
    m_displayPoll.setInterval(1000);
    connect(&m_displayPoll, &QTimer::timeout, this, [this]() { apply({ { "op", "displayStatus" } }); });
    // A running macro pushes nothing, so follow it until it ends (with a ceiling:
    // steps can carry minute-long delays)
    m_macroPoll.setInterval(250);
    connect(&m_macroPoll, &QTimer::timeout, this, [this]() {
        apply({ { "op", "refreshStatus" } });
        const int running = m_model.value("ext").toMap().value("macroRunning").toInt();
        if (running == 0xFF || ++m_macroPolls >= 120) m_macroPoll.stop();
    });

    connect(m_bridge, &DSPiBridge::devicesChanged, this, &CsController::onDeviceChanged);
    connect(m_bridge, &DSPiBridge::csNotified, this, &CsController::onNotified);
    onDeviceChanged();
}

bool CsController::unsaved() const {
    return m_model.value("status").toMap().value("dirty").toBool();
}

void CsController::setWatchDisplay(bool on) {
    if (on == m_displayPoll.isActive()) return;
    if (on && supported()) m_displayPoll.start(); else m_displayPoll.stop();
    emit watchDisplayChanged();
}

// A new device (or none): read its configuration once the window has drawn
void CsController::onDeviceChanged() {
    const bool usable = m_bridge->connected() && m_bridge->compat() == COMPAT_OK;
    const QString serial = usable ? m_bridge->selectedSerial() : QString();
    if (serial == m_serial) return;
    m_serial = serial;
    m_macroPoll.stop();
    m_displayPoll.stop();
    m_model.clear();
    m_snapshot.clear();
    m_displayState.clear();
    m_auxLive.clear();
    m_revision++;
    emit changed();
    emit displayStateChanged();
    emit auxLiveChanged();
    emit reloaded();
    if (!usable) return;
    QTimer::singleShot(0, this, [this, serial]() {
        if (serial == m_serial) refresh();
    });
}

void CsController::refresh() {
    if (!m_bridge->connected()) return;
    if (!dspi_cs_fetch(m_bridge->core())) {
        // USB trouble rather than missing support: read again on the next change
        m_serial.clear();
        return;
    }
    reload();
    emit reloaded();
}

// Re-read the core's snapshot; tell the pages only if something changed
void CsController::reload() {
    QByteArray buf(64 * 1024, '\0');
    uint32_t needed = dspi_cs_snapshot(m_bridge->core(), buf.data(), uint32_t(buf.size()));
    if (needed > uint32_t(buf.size())) {
        buf.resize(int(needed));
        needed = dspi_cs_snapshot(m_bridge->core(), buf.data(), uint32_t(buf.size()));
    }
    buf.truncate(int(qMax<uint32_t>(1, needed) - 1));
    QJsonObject obj = QJsonDocument::fromJson(buf).object();
    QJsonObject display = obj.value("display").toObject();
    const QVariantMap state = display.take("status").toObject().toVariantMap();
    if (!display.isEmpty()) obj["display"] = display;
    if (state != m_displayState) {
        m_displayState = state;
        emit displayStateChanged();
    }
    const QVariantMap aux { { "state", obj.take("auxState").toVariant() }, { "level", obj.take("auxLevel").toVariant() } };
    if (aux != m_auxLive) {
        m_auxLive = aux;
        emit auxLiveChanged();
    }
    const QByteArray snapshot = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    if (snapshot == m_snapshot) return;
    m_snapshot = snapshot;
    m_model = obj.toVariantMap();
    m_revision++;
    emit changed();
}

QVariantMap CsController::call(const QByteArray &json) {
    QByteArray buf(4096, '\0');
    uint32_t needed = dspi_cs_apply(m_bridge->core(), json.constData(), buf.data(), uint32_t(buf.size()));
    if (needed > uint32_t(buf.size())) return { { "ok", false }, { "error", "Reply too long." } };
    buf.truncate(int(qMax<uint32_t>(1, needed) - 1));
    return QJsonDocument::fromJson(buf).object().toVariantMap();
}

QVariantMap CsController::apply(const QVariantMap &op) {
    if (!m_bridge->connected()) return { { "ok", false }, { "status", 0xFF } };
    QVariantMap r = call(QJsonDocument(QJsonObject::fromVariantMap(op)).toJson(QJsonDocument::Compact));
    reload();
    const QString kind = op.value("op").toString();
    if (kind == "macroFire" && r.value("ok").toBool()) {
        m_macroPolls = 0;
        m_macroPoll.start();
    }
    return r;
}

void CsController::sendOnly(const QVariantMap &op) {
    if (m_bridge->connected())
        call(QJsonDocument(QJsonObject::fromVariantMap(op)).toJson(QJsonDocument::Compact));
}

int CsController::save() {
    const int st = apply({ { "op", "save" } }).value("status", 0xFF).toInt();
    return st;
}

int CsController::revert() {
    const int st = apply({ { "op", "revert" } }).value("status", 0xFF).toInt();
    emit reloaded();
    return st;
}

void CsController::onNotified(bool aux, bool learn) {
    if (aux) reload();
    if (learn) {
        reload();
        const QVariantMap l = m_model.value("learn").toMap();
        if (!l.isEmpty())
            emit learnFinished(l.value("state").toInt(), l.value("protocol").toInt(), l.value("code").toDouble());
    }
}

QString CsController::statusMessage(int code) const {
    switch (code) {
    case 0x00: return QString();
    case 0x01: return "A pin is out of range, or an encoder's two pins are equal";
    case 0x02: return "A pin is already claimed by another peripheral or binding";
    case 0x11: return "Unsupported component type";
    case 0x12: return "Unsupported function";
    case 0x13: return "That action isn't allowed for this component and function";
    case 0x14: return "A value, step, range, or flag is out of bounds";
    case 0x15: return "A potentiometer must use an ADC pin (GPIO 26, 27, or 28)";
    case 0x10: return "Invalid slot";
    case 0x16: return "Still applying, please retry";
    case 0x17: return "The selected channel or band isn't valid for this function";
    case 0x18: return "That press gesture isn't allowed here";
    case 0x19: return "This PWM pin conflicts with another dimmable LED or output";
    case 0x1A: return "Another button already uses this GPIO and gesture";
    case 0x1B: return "The device was busy; please try again";
    case 0x1C: return "The device could not write to flash";
    case 0x1D: return "Another slot already holds the IR receiver (one per device)";
    case 0x1E: return "Add an IR receiver before learning a remote button";
    case 0x1F: return "That group is empty, missing, or holds the wrong kind of channel";
    case 0x20: return "Invalid macro or step count";
    case 0x21: return "A macro step isn't valid";
    case 0x22: return "Another slot already holds the display (one per device)";
    case 0x23: return "SDA and SCL must be an even/odd GPIO pair on the same I2C bus";
    case 0x24: return "That I2C bus belongs to the I2C control interface";
    case 0x25: return "That display page isn't valid";
    case 0x26: return "The target isn't an auxiliary output, or a level control needs a dimmable one";
    default:   return "Failed to apply the binding";
    }
}
