#ifndef AUTOEQLIBRARY_H
#define AUTOEQLIBRARY_H

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QSet>
#include <QUrl>
#include <QVariantList>
#include <QVector>

class DSPiBridge;
class QNetworkReply;

// One AutoEQ headphone profile: a preamp and up to ten parametric filters
struct AutoEqEntry {
    QString id, manufacturer, model, source, formFactor;
    double preamp = 0;
    struct Filter { QString type; double freq, q, gain; };
    QVector<Filter> filters;
    QString displayName() const { return model.isEmpty() ? manufacturer : manufacturer + " " + model; }
};

// The browser's rows: the database filtered by the search text
class AutoEqModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Role { IdRole = Qt::UserRole + 1, NameRole, SourceRole, SourceNameRole, FormFactorRole, FavoriteRole };
    explicit AutoEqModel(QObject *parent = nullptr) : QAbstractListModel(parent) {}
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(const QVector<AutoEqEntry> *entries, const QVector<int> &rows, const QSet<QString> *favorites);
    void favoriteChanged(const QString &id);
private:
    const QVector<AutoEqEntry> *m_entries = nullptr;
    const QSet<QString> *m_favorites = nullptr;
    QVector<int> m_rows;
};

// AutoEQ headphone profiles, as on macOS: the database bundled with Console
// (or the user's updated copy), search, favourites, applying a profile to
// inputs 1 and 2, and updating the database (import a file, rebuild from the
// AutoEQ project on GitHub, or go back to the bundled one).
class AutoEqLibrary : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *results READ results CONSTANT)
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(int entryCount READ entryCount NOTIFY databaseChanged)
    Q_PROPERTY(QString databaseDate READ databaseDate NOTIFY databaseChanged)
    Q_PROPERTY(bool hasUserDatabase READ hasUserDatabase NOTIFY databaseChanged)
    Q_PROPERTY(QString loadError READ loadError NOTIFY databaseChanged)
    // [{id, name}] in the order they were added
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY favoritesChanged)
    Q_PROPERTY(bool rebuilding READ rebuilding NOTIFY rebuildChanged)
    Q_PROPERTY(double rebuildProgress READ rebuildProgress NOTIFY rebuildChanged)
    Q_PROPERTY(QString rebuildStatus READ rebuildStatus NOTIFY rebuildChanged)

public:
    explicit AutoEqLibrary(DSPiBridge *bridge, QObject *parent = nullptr);

    QObject *results() { return &m_model; }
    QString query() const { return m_query; }
    void setQuery(const QString &q);
    int entryCount() const { return m_entries.size(); }
    QString databaseDate() const { return m_date; }
    bool hasUserDatabase() const;
    QString loadError() const { return m_error; }
    QVariantList favorites() const { return m_favoriteList; }
    bool rebuilding() const { return m_rebuilding; }
    double rebuildProgress() const { return m_progress; }
    QString rebuildStatus() const { return m_status; }

    // Read the database now (the browser does on opening)
    Q_INVOKABLE void load();
    // {id, name, source, formFactor} for one profile ({} if unknown)
    Q_INVOKABLE QVariantMap entry(const QString &id);
    Q_INVOKABLE void toggleFavorite(const QString &id);
    Q_INVOKABLE void clearFavorites();
    // Preamp and filters onto inputs 1 and 2; false without a device
    Q_INVOKABLE bool apply(const QString &id);

    // {ok, message}
    Q_INVOKABLE QVariantMap importFile(const QUrl &file);
    Q_INVOKABLE QVariantMap resetToBuiltIn();
    Q_INVOKABLE void startRebuild();
    Q_INVOKABLE void cancelRebuild();

signals:
    void queryChanged();
    void databaseChanged();
    void favoritesChanged();
    void rebuildChanged();
    void rebuildFinished(bool ok, const QString &message);

private:
    bool readDatabase(const QByteArray &json, QString *error);
    void filter();
    QString userPath() const;
    void setRebuild(bool on, double progress, const QString &status);
    // Rebuild steps
    void nextListing();
    void listingDone(QNetworkReply *reply, int source, const QString &target);
    void pumpDownloads();
    void downloadDone(QNetworkReply *reply, int profile);
    void finishRebuild();
    void failRebuild(const QString &message);

    DSPiBridge *m_bridge;
    AutoEqModel m_model;
    QVector<AutoEqEntry> m_entries;
    QHash<QString, int> m_byId;
    bool m_loaded = false;
    QString m_query;
    QString m_date;
    QString m_error;
    QSet<QString> m_favorites;
    QVariantList m_favoriteList;

    // Rebuild from GitHub
    QNetworkAccessManager m_net;
    bool m_rebuilding = false;
    double m_progress = 0;
    QString m_status;
    struct Listing { int source; QString target; };            // target empty = the source folder
    struct Profile { int source; QString target, headphone; QUrl url; };
    QList<Listing> m_listings;
    QVector<Profile> m_profiles;
    int m_nextProfile = 0;
    int m_inFlight = 0;
    int m_done = 0;
    QHash<QString, QPair<AutoEqEntry, int>> m_found;         // manufacturer/model -> entry, priority
    QList<QPointer<QNetworkReply>> m_replies;
};

#endif // AUTOEQLIBRARY_H
