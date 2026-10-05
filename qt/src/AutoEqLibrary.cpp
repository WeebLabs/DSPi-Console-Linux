#include "AutoEqLibrary.h"
#include "DSPiBridge.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <algorithm>

namespace {
// The AutoEQ results folders and their priority when one headphone was
// measured by several (lower wins), as on macOS
struct Source { const char *folder; const char *name; int priority; };
const Source kSources[] = {
    { "oratory1990", "oratory1990", 1 },
    { "crinacle", "crinacle", 2 },
    { "Rtings", "rtings", 3 },
    { "Innerfidelity", "innerfidelity", 3 },
    { "Headphone.com Legacy", "headphone.com", 4 },
};
constexpr int kSourceCount = int(sizeof(kSources) / sizeof(kSources[0]));
constexpr int kBands = 10;
constexpr int kParallel = 20;
const char *kFavoritesKey = "autoeq/favorites";

const QStringList kManufacturers = {
    "AKG", "Audio-Technica", "Audeze", "Bang & Olufsen", "Beats", "Beyerdynamic",
    "Bose", "Campfire Audio", "Dan Clark Audio", "Denon", "FiiO", "Final",
    "Focal", "Grado", "HarmonicDyne", "HIFIMAN", "JBL", "Koss", "Massdrop",
    "Meze", "Moondrop", "Philips", "Pioneer", "Sennheiser", "Shure", "Sony",
    "SteelSeries", "STAX", "Tin HiFi", "V-MODA", "ZMF", "64 Audio", "7Hz",
    "Anker", "Apple", "AFUL", "BLON", "CCA", "Dunu", "Empire Ears", "Etymotic",
    "FatFreq", "Hidizs", "HiBy", "iBasso", "JVC", "KZ", "Letshuoer", "Linsoul",
    "Noble Audio", "QKZ", "Samsung", "See Audio", "Simgot", "SoftEars",
    "Tangzu", "Thieaudio", "Tinhifi", "Tripowin", "TRN", "Truthear",
    "Unique Melody", "Westone", "Yanyin", "BGVP", "CCZ"
};

QString sourceDisplayName(const QString &s) {
    if (s == "crinacle") return "Crinacle";
    if (s == "rtings") return "Rtings";
    if (s == "innerfidelity") return "InnerFidelity";
    if (s == "headphone.com") return "Headphone.com";
    return s;
}

int filterType(const QString &t) {
    if (t == "peaking") return 1;
    if (t == "lowShelf") return 2;
    if (t == "highShelf") return 3;
    if (t == "lowPass") return 4;
    if (t == "highPass") return 5;
    return 0;
}

QString pathSegment(const QString &s) { return QString::fromUtf8(QUrl::toPercentEncoding(s)); }
}

// ── Model ──

int AutoEqModel::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_rows.size(); }

QVariant AutoEqModel::data(const QModelIndex &index, int role) const {
    if (!m_entries || !index.isValid() || index.row() >= m_rows.size()) return {};
    const AutoEqEntry &e = (*m_entries)[m_rows[index.row()]];
    switch (role) {
    case IdRole: return e.id;
    case NameRole: return e.displayName();
    case SourceRole: return e.source;
    case SourceNameRole: return sourceDisplayName(e.source);
    case FormFactorRole: return e.formFactor;
    case FavoriteRole: return m_favorites && m_favorites->contains(e.id);
    default: return {};
    }
}

QHash<int, QByteArray> AutoEqModel::roleNames() const {
    return { { IdRole, "entryId" }, { NameRole, "name" }, { SourceRole, "source" },
             { SourceNameRole, "sourceName" }, { FormFactorRole, "formFactor" }, { FavoriteRole, "favorite" } };
}

void AutoEqModel::reset(const QVector<AutoEqEntry> *entries, const QVector<int> &rows, const QSet<QString> *favorites) {
    beginResetModel();
    m_entries = entries;
    m_rows = rows;
    m_favorites = favorites;
    endResetModel();
}

void AutoEqModel::favoriteChanged(const QString &id) {
    for (int r = 0; r < m_rows.size(); r++)
        if ((*m_entries)[m_rows[r]].id == id) {
            emit dataChanged(index(r), index(r), { FavoriteRole });
            return;
        }
}

// ── Library ──

AutoEqLibrary::AutoEqLibrary(DSPiBridge *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge)
{
    // Favourites keep their names, so the menu needs no database
    const QStringList saved = QSettings().value(kFavoritesKey).toStringList();
    for (const QString &item : saved) {
        const int bar = item.indexOf('\t');
        const QString id = bar < 0 ? item : item.left(bar);
        m_favorites.insert(id);
        m_favoriteList.append(QVariantMap{ { "id", id }, { "name", bar < 0 ? id : item.mid(bar + 1) } });
    }
}

QString AutoEqLibrary::userPath() const {
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/autoeq_database.json";
}

bool AutoEqLibrary::hasUserDatabase() const { return QFile::exists(userPath()); }

bool AutoEqLibrary::readDatabase(const QByteArray &json, QString *error) {
    QJsonParseError pe;
    const QJsonObject root = QJsonDocument::fromJson(json, &pe).object();
    const QJsonArray list = root.value("entries").toArray();
    if (pe.error != QJsonParseError::NoError || list.isEmpty()) {
        if (error) *error = "This is not an AutoEQ database file.";
        return false;
    }
    QVector<AutoEqEntry> entries;
    entries.reserve(list.size());
    for (const QJsonValue &v : list) {
        const QJsonObject o = v.toObject();
        AutoEqEntry e;
        e.id = o.value("id").toString();
        e.manufacturer = o.value("manufacturer").toString();
        e.model = o.value("model").toString();
        e.source = o.value("source").toString();
        e.formFactor = o.value("formFactor").toString();
        e.preamp = o.value("preamp").toDouble();
        for (const QJsonValue &f : o.value("filters").toArray()) {
            const QJsonObject fo = f.toObject();
            e.filters.append({ fo.value("type").toString(), fo.value("freq").toDouble(1000),
                               fo.value("q").toDouble(0.707), fo.value("gain").toDouble() });
        }
        if (!e.id.isEmpty()) entries.append(e);
    }
    m_entries = entries;
    m_byId.clear();
    for (int i = 0; i < m_entries.size(); i++) m_byId.insert(m_entries[i].id, i);
    const QDateTime when = QDateTime::fromString(root.value("generatedAt").toString(), Qt::ISODateWithMs);
    m_date = when.isValid() ? QLocale().toString(when.toLocalTime().date(), QLocale::ShortFormat)
                            : root.value("generatedAt").toString();
    return true;
}

void AutoEqLibrary::load() {
    if (m_loaded) return;
    m_loaded = true;
    m_error.clear();
    QFile user(userPath());
    QFile bundled(":/autoeq/autoeq_database.json");
    QFile &f = user.exists() ? user : bundled;
    if (!f.open(QIODevice::ReadOnly) || !readDatabase(f.readAll(), nullptr))
        m_error = "The AutoEQ database could not be read.";
    filter();
    emit databaseChanged();
}

void AutoEqLibrary::setQuery(const QString &q) {
    if (q == m_query) return;
    m_query = q;
    emit queryChanged();
    filter();
}

void AutoEqLibrary::filter() {
    QVector<int> rows;
    const QString q = m_query.trimmed().toLower();
    for (int i = 0; i < m_entries.size(); i++) {
        const AutoEqEntry &e = m_entries[i];
        if (q.isEmpty() || e.manufacturer.toLower().contains(q) || e.model.toLower().contains(q)
            || e.displayName().toLower().contains(q))
            rows.append(i);
    }
    m_model.reset(&m_entries, rows, &m_favorites);
}

QVariantMap AutoEqLibrary::entry(const QString &id) {
    load();
    const auto it = m_byId.constFind(id);
    if (it == m_byId.constEnd()) return {};
    const AutoEqEntry &e = m_entries[*it];
    return { { "id", e.id }, { "name", e.displayName() }, { "source", sourceDisplayName(e.source) },
             { "formFactor", e.formFactor } };
}

void AutoEqLibrary::toggleFavorite(const QString &id) {
    load();
    if (m_favorites.contains(id)) {
        m_favorites.remove(id);
        for (int i = 0; i < m_favoriteList.size(); i++)
            if (m_favoriteList[i].toMap().value("id") == id) { m_favoriteList.removeAt(i); break; }
    } else {
        const auto it = m_byId.constFind(id);
        if (it == m_byId.constEnd()) return;
        m_favorites.insert(id);
        m_favoriteList.append(QVariantMap{ { "id", id }, { "name", m_entries[*it].displayName() } });
    }
    QStringList saved;
    for (const QVariant &v : m_favoriteList) {
        const QVariantMap m = v.toMap();
        saved << m.value("id").toString() + "\t" + m.value("name").toString();
    }
    QSettings().setValue(kFavoritesKey, saved);
    m_model.favoriteChanged(id);
    emit favoritesChanged();
}

void AutoEqLibrary::clearFavorites() {
    const QSet<QString> was = m_favorites;
    m_favorites.clear();
    m_favoriteList.clear();
    QSettings().remove(kFavoritesKey);
    for (const QString &id : was) m_model.favoriteChanged(id);
    emit favoritesChanged();
}

bool AutoEqLibrary::apply(const QString &id) {
    if (!m_bridge->connected()) return false;
    load();
    const auto it = m_byId.constFind(id);
    if (it == m_byId.constEnd()) return false;
    const AutoEqEntry &e = m_entries[*it];
    // Inputs 1 and 2 (app channels 0 and 1): the preamp, the profile's
    // filters, and every remaining band off
    for (int input = 0; input < 2; input++) m_bridge->setInputPreamp(input, float(e.preamp));
    for (int ch = 0; ch < 2; ch++)
        for (int band = 0; band < kBands; band++) {
            if (band < e.filters.size()) {
                const AutoEqEntry::Filter &f = e.filters[band];
                m_bridge->setFilter(ch, band, filterType(f.type), float(f.freq), float(f.gain), float(f.q));
            } else {
                m_bridge->setFilter(ch, band, 0, 1000.0f, 0.0f, 0.707f);
            }
        }
    return true;
}

// ── Updating the database ──

QVariantMap AutoEqLibrary::importFile(const QUrl &file) {
    QFile f(file.toLocalFile());
    if (!f.open(QIODevice::ReadOnly)) return { { "ok", false }, { "message", "The file could not be opened." } };
    const QByteArray data = f.readAll();
    QString error;
    if (!readDatabase(data, &error)) {
        // Leave the database as it was
        m_loaded = false;
        load();
        return { { "ok", false }, { "message", error } };
    }
    QDir().mkpath(QFileInfo(userPath()).path());
    QSaveFile out(userPath());
    if (!out.open(QIODevice::WriteOnly) || out.write(data) != data.size() || !out.commit())
        return { { "ok", false }, { "message", "The database could not be saved: " + out.errorString() } };
    m_loaded = true;
    m_error.clear();
    filter();
    emit databaseChanged();
    return { { "ok", true }, { "message", QString("Database updated successfully.\nEntries: %1").arg(m_entries.size()) } };
}

QVariantMap AutoEqLibrary::resetToBuiltIn() {
    if (hasUserDatabase() && !QFile::remove(userPath()))
        return { { "ok", false }, { "message", "The updated database could not be removed." } };
    m_loaded = false;
    load();
    return { { "ok", true }, { "message", QString("Reset to built-in database.\nEntries: %1").arg(m_entries.size()) } };
}

void AutoEqLibrary::setRebuild(bool on, double progress, const QString &status) {
    m_rebuilding = on;
    m_progress = progress;
    m_status = status;
    emit rebuildChanged();
}

// Downloads every profile from the AutoEQ project and builds a fresh
// database: list each source's target folders and their headphone folders
// through the GitHub API, then fetch each ParametricEQ.txt
void AutoEqLibrary::startRebuild() {
    if (m_rebuilding) return;
    m_listings.clear();
    m_profiles.clear();
    m_found.clear();
    m_nextProfile = m_inFlight = m_done = 0;
    for (int s = 0; s < kSourceCount; s++) m_listings.append({ s, QString() });
    setRebuild(true, 0, "Discovering profiles...");
    nextListing();
}

void AutoEqLibrary::cancelRebuild() {
    if (!m_rebuilding) return;
    m_rebuilding = false;
    for (const QPointer<QNetworkReply> &r : m_replies) if (r) r->abort();
    m_replies.clear();
    setRebuild(false, 0, QString());
}

void AutoEqLibrary::nextListing() {
    if (!m_rebuilding) return;
    if (m_listings.isEmpty()) {
        if (m_profiles.isEmpty()) { failRebuild("Failed to download database"); return; }
        m_status = QString("Downloading 0 / %1 profiles...").arg(m_profiles.size());
        emit rebuildChanged();
        pumpDownloads();
        return;
    }
    const Listing l = m_listings.takeFirst();
    QString path = "results/" + pathSegment(kSources[l.source].folder);
    if (!l.target.isEmpty()) path += "/" + pathSegment(l.target);
    QNetworkRequest req(QUrl("https://api.github.com/repos/jaakkopasanen/AutoEq/contents/" + path));
    req.setRawHeader("Accept", "application/vnd.github.v3+json");
    req.setHeader(QNetworkRequest::UserAgentHeader, "DSPi-Console-Linux");
    QNetworkReply *reply = m_net.get(req);
    m_replies.append(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, l]() { listingDone(reply, l.source, l.target); });
}

void AutoEqLibrary::listingDone(QNetworkReply *reply, int source, const QString &target) {
    reply->deleteLater();
    if (!m_rebuilding) return;
    // A folder that can't be listed is skipped, as on macOS
    if (reply->error() == QNetworkReply::NoError) {
        for (const QJsonValue &v : QJsonDocument::fromJson(reply->readAll()).array()) {
            const QJsonObject o = v.toObject();
            if (o.value("type").toString() != "dir") continue;
            const QString name = o.value("name").toString();
            if (target.isEmpty()) {
                m_listings.append({ source, name });
            } else {
                const QString file = name + " ParametricEQ.txt";
                const QUrl url("https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/"
                               + pathSegment(kSources[source].folder) + "/" + pathSegment(target) + "/"
                               + pathSegment(name) + "/" + pathSegment(file));
                m_profiles.append({ source, target, name, url });
            }
        }
        if (!target.isEmpty()) {
            m_status = QString("Found %1 profiles...").arg(m_profiles.size());
            emit rebuildChanged();
        }
    }
    nextListing();
}

void AutoEqLibrary::pumpDownloads() {
    while (m_rebuilding && m_inFlight < kParallel && m_nextProfile < m_profiles.size()) {
        const int i = m_nextProfile++;
        QNetworkRequest req(m_profiles[i].url);
        req.setHeader(QNetworkRequest::UserAgentHeader, "DSPi-Console-Linux");
        QNetworkReply *reply = m_net.get(req);
        m_replies.append(reply);
        m_inFlight++;
        connect(reply, &QNetworkReply::finished, this, [this, reply, i]() { downloadDone(reply, i); });
    }
    if (m_rebuilding && m_inFlight == 0 && m_nextProfile >= m_profiles.size()) finishRebuild();
}

void AutoEqLibrary::downloadDone(QNetworkReply *reply, int index) {
    reply->deleteLater();
    if (!m_rebuilding) return;
    m_inFlight--;
    m_done++;
    m_replies.removeAll(reply);
    if (reply->error() == QNetworkReply::NoError) {
        const Profile &p = m_profiles[index];
        // Parse the ParametricEQ.txt: "Preamp: -6.2 dB" and
        // "Filter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70"
        AutoEqEntry e;
        static const QHash<QString, QString> types = {
            { "PK", "peaking" }, { "PEQ", "peaking" }, { "LSC", "lowShelf" }, { "LSB", "lowShelf" }, { "LS", "lowShelf" },
            { "HSC", "highShelf" }, { "HSB", "highShelf" }, { "HS", "highShelf" }, { "LP", "lowPass" }, { "LPQ", "lowPass" },
            { "HP", "highPass" }, { "HPQ", "highPass" } };
        static const QRegularExpression number("-?\\d+\\.?\\d*");
        static const QRegularExpression fc("Fc\\s+([\\d.]+)", QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression gain("Gain\\s+(-?[\\d.]+)", QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression q("\\sQ\\s+([\\d.]+)");
        for (const QString &raw : QString::fromUtf8(reply->readAll()).split('\n')) {
            const QString line = raw.trimmed();
            if (line.startsWith("preamp:", Qt::CaseInsensitive)) {
                const QRegularExpressionMatch m = number.match(line);
                if (m.hasMatch()) e.preamp = m.captured(0).toDouble();
                continue;
            }
            if (!line.contains("Filter") || !line.contains(':')) continue;
            const QString upper = line.toUpper();
            if (!upper.contains(" ON ")) continue;
            QString type;
            for (auto it = types.constBegin(); it != types.constEnd(); ++it)
                if (upper.contains(" " + it.key() + " ")) { type = it.value(); break; }
            if (type.isEmpty()) continue;
            const QRegularExpressionMatch mf = fc.match(line), mg = gain.match(line), mq = q.match(line);
            e.filters.append({ type, mf.hasMatch() ? mf.captured(1).toDouble() : 1000.0,
                               mq.hasMatch() ? mq.captured(1).toDouble() : 0.707,
                               mg.hasMatch() ? mg.captured(1).toDouble() : 0.0 });
        }
        if (!e.filters.isEmpty()) {
            // Manufacturer from the known list, else the first word
            QString manufacturer, model;
            for (const QString &m : kManufacturers) {
                if (p.headphone.compare(m, Qt::CaseInsensitive) == 0
                    || p.headphone.startsWith(m + " ", Qt::CaseInsensitive)) {
                    manufacturer = m;
                    model = p.headphone.mid(m.size()).trimmed();
                    if (model.isEmpty()) model = p.headphone;
                    break;
                }
            }
            if (manufacturer.isEmpty()) {
                const int space = p.headphone.indexOf(' ');
                manufacturer = space < 0 ? p.headphone : p.headphone.left(space);
                model = space < 0 ? QString() : p.headphone.mid(space + 1);
            }
            const QString t = p.target.toLower();
            e.formFactor = t.contains("in-ear") || t.contains("in_ear") || t.contains("iem") ? "in-ear"
                         : t.contains("earbud") ? "earbud" : "over-ear";
            e.manufacturer = manufacturer;
            e.model = model;
            e.source = kSources[p.source].name;
            e.id = e.source + "/" + p.headphone;
            const QString key = manufacturer.toLower() + "/" + model.toLower();
            const int priority = kSources[p.source].priority;
            auto it = m_found.find(key);
            if (it == m_found.end() || priority < it->second) m_found.insert(key, { e, priority });
        }
    }
    m_progress = double(m_done) / double(qMax(1, m_profiles.size()));
    m_status = QString("Downloading %1 / %2 profiles...").arg(m_done).arg(m_profiles.size());
    emit rebuildChanged();
    pumpDownloads();
}

void AutoEqLibrary::finishRebuild() {
    m_status = "Building database...";
    emit rebuildChanged();
    QVector<AutoEqEntry> entries;
    for (const auto &v : m_found) entries.append(v.first);
    std::sort(entries.begin(), entries.end(), [](const AutoEqEntry &a, const AutoEqEntry &b) {
        const int c = QString::compare(a.manufacturer, b.manufacturer, Qt::CaseInsensitive);
        return c != 0 ? c < 0 : QString::compare(a.model, b.model, Qt::CaseInsensitive) < 0;
    });
    QJsonArray list;
    for (const AutoEqEntry &e : entries) {
        QJsonArray filters;
        for (const AutoEqEntry::Filter &f : e.filters)
            filters.append(QJsonObject{ { "type", f.type }, { "freq", f.freq }, { "q", f.q }, { "gain", f.gain } });
        list.append(QJsonObject{ { "id", e.id }, { "manufacturer", e.manufacturer }, { "model", e.model },
                                 { "source", e.source }, { "formFactor", e.formFactor }, { "preamp", e.preamp },
                                 { "filters", filters } });
    }
    const QByteArray data = QJsonDocument(QJsonObject{
        { "version", 1 }, { "generatedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs) },
        { "entryCount", entries.size() }, { "entries", list } }).toJson(QJsonDocument::Indented);
    QDir().mkpath(QFileInfo(userPath()).path());
    QSaveFile out(userPath());
    if (entries.isEmpty() || !out.open(QIODevice::WriteOnly) || out.write(data) != data.size() || !out.commit()) {
        failRebuild(entries.isEmpty() ? "Failed to download database" : "The database could not be saved.");
        return;
    }
    m_loaded = false;
    load();
    m_replies.clear();
    setRebuild(false, 1.0, QString("Complete! %1 profiles.").arg(m_entries.size()));
    emit rebuildFinished(true, QString("Database rebuilt successfully!\nEntries: %1").arg(m_entries.size()));
}

void AutoEqLibrary::failRebuild(const QString &message) {
    m_replies.clear();
    setRebuild(false, 0, QString());
    emit rebuildFinished(false, "Rebuild failed: " + message);
}
