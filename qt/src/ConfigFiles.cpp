#include "ConfigFiles.h"
#include "DSPiBridge.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <functional>

// Call a core function that fills a text buffer and returns the size it
// needs, growing the buffer once if the first one was too small
static QByteArray coreText(const std::function<uint32_t(char *, uint32_t)> &call) {
    QByteArray buf(64 * 1024, '\0');
    uint32_t needed = call(buf.data(), uint32_t(buf.size()));
    if (needed > uint32_t(buf.size())) {
        buf.resize(int(needed));
        needed = call(buf.data(), uint32_t(buf.size()));
    }
    buf.truncate(int(qMax<uint32_t>(1, needed) - 1));
    return buf;
}

static QVariantMap jsonMap(const QByteArray &json) {
    return QJsonDocument::fromJson(json).object().toVariantMap();
}

ConfigFiles::ConfigFiles(DSPiBridge *bridge, QObject *parent) : QObject(parent), m_bridge(bridge) {}

bool ConfigFiles::readFile(const QUrl &file, QByteArray &out, QString &error) {
    QFile f(file.toLocalFile());
    if (!f.open(QIODevice::ReadOnly)) {
        error = "The file could not be opened: " + f.errorString() + ".";
        return false;
    }
    out = f.readAll();
    return true;
}

bool ConfigFiles::writeFile(const QUrl &file, const QByteArray &data, QString &error) {
    QSaveFile f(file.toLocalFile());
    if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size() || !f.commit()) {
        error = "The file could not be written: " + f.errorString() + ".";
        return false;
    }
    return true;
}

// ── Device configuration ──

QVariantMap ConfigFiles::exportConfiguration(const QUrl &file) {
    if (!m_bridge->connected()) return { { "ok", false }, { "error", "No device connected." } };
    const QByteArray name = QFileInfo(file.toLocalFile()).completeBaseName().toUtf8();
    const QByteArray version = QCoreApplication::applicationVersion().toUtf8();
    const uint8_t links = m_bridge->inputLinks();
    QByteArray text = coreText([&](char *buf, uint32_t len) {
        return dspi_config_export(m_bridge->core(), name.constData(), version.constData(), links, buf, len);
    });
    QString error;
    if (!writeFile(file, text, error)) return { { "ok", false }, { "error", error } };

    // What went into it
    const QJsonObject doc = QJsonDocument::fromJson(text).object();
    int channels = 0, bands = 0, xover = 0, points = 0;
    for (const QJsonValue &c : doc["channels"].toArray()) {
        channels++;
        for (const QJsonValue &b : c["eq"].toArray()) bands += b["type"].toInt() != 0;
        for (const QJsonValue &b : c["crossover"].toArray()) xover += b["type"].toInt() != 0;
    }
    for (const QJsonValue &x : doc["matrix"].toArray()) points += x["enabled"].toBool();
    return { { "ok", true },
             { "message", QString("%1 channels, %2 active EQ bands, %3 crossover bands, %4 crosspoints.")
                              .arg(channels).arg(bands).arg(xover).arg(points) } };
}

QVariantMap ConfigFiles::inspectConfiguration(const QUrl &file) {
    QString error;
    if (!readFile(file, m_configText, error)) return { { "ok", false }, { "error", error } };
    QVariantMap m = jsonMap(coreText([&](char *buf, uint32_t len) {
        return dspi_config_inspect(m_configText.constData(), buf, len);
    }));
    if (!m.value("ok").toBool()) return m;
    QDateTime saved = QDateTime::fromString(m.value("savedUtc").toString(), Qt::ISODateWithMs);
    if (!saved.isValid()) saved = QDateTime::fromString(m.value("savedUtc").toString(), Qt::ISODate);
    m["saved"] = saved.isValid() ? saved.toLocalTime().toString("yyyy-MM-dd HH:mm") : QString();
    const QString platform = m.value("platform").toString();
    m["crossPlatform"] = !platform.isEmpty() && platform != m_bridge->platformName();
    return m;
}

QVariantMap ConfigFiles::importConfiguration(const QUrl &file, bool volumes, bool hardware) {
    if (!m_bridge->connected()) return { { "ok", false }, { "error", "No device connected." } };
    QString error;
    if (m_configText.isEmpty() && !readFile(file, m_configText, error)) return { { "ok", false }, { "error", error } };
    const uint32_t options = (volumes ? 1u : 0u) | (hardware ? 2u : 0u);
    QVariantMap r = jsonMap(coreText([&](char *buf, uint32_t len) {
        return dspi_config_import(m_bridge->core(), m_configText.constData(), options, buf, len);
    }));
    m_configText.clear();
    if (r.value("ok").toBool()) {
        if (!r.value("links").isNull()) m_bridge->restoreInputLinks(uint8_t(r.value("links").toUInt()));
        if (r.value("hardwareWritten").toBool()) m_bridge->markHardwareUnsaved();
    }
    m_bridge->refreshAll();
    return r;
}

// ── Filter files ──

QVariantMap ConfigFiles::exportFilters(const QUrl &file) {
    if (!m_bridge->connected()) return { { "ok", false }, { "error", "No device connected." } };
    const uint8_t inputs = uint8_t(m_bridge->liveInputCount());
    QByteArray text = coreText([&](char *buf, uint32_t len) {
        return dspi_filters_export(m_bridge->core(), inputs, buf, len);
    });
    QString error;
    if (!writeFile(file, text, error)) return { { "ok", false }, { "error", error } };
    return { { "ok", true } };
}

QVariantMap ConfigFiles::inspectFilters(const QUrl &file) {
    QString error;
    if (!readFile(file, m_filterText, error)) return { { "ok", false }, { "error", error } };
    const uint8_t inputs = uint8_t(m_bridge->liveInputCount());
    QVariantMap m = jsonMap(coreText([&](char *buf, uint32_t len) {
        return dspi_filters_inspect(m_bridge->core(), m_filterText.constData(), inputs, buf, len);
    }));
    m["ok"] = !m.value("channels").toList().isEmpty();
    if (!m["ok"].toBool())
        m["error"] = "No filters this device can use were found in the file.";
    return m;
}

QVariantMap ConfigFiles::importFilters(const QVariantList &wires) {
    if (!m_bridge->connected()) return { { "ok", false }, { "error", "No device connected." } };
    QByteArray chosen;
    for (const QVariant &w : wires) chosen.append(char(w.toInt()));
    QVariantMap r = jsonMap(coreText([&](char *buf, uint32_t len) {
        return dspi_filters_import(m_bridge->core(), m_filterText.constData(),
                                   reinterpret_cast<const uint8_t *>(chosen.constData()), uint32_t(chosen.size()), buf, len);
    }));
    m_bridge->refreshAll();
    return r;
}
