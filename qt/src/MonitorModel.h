#ifndef MONITORMODEL_H
#define MONITORMODEL_H

#include <QAbstractListModel>
#include <QStringList>
#include <QVector>

class DSPiBridge;
struct FfiCore;

// The Interrupt Monitor's log: the device's notifications, one decoded line
// each, from the core's log (which keeps the last 2000 whether or not the
// window is open). Lines are read when a notification batch arrives and the
// window shows; paused, new lines are skipped rather than queued.
class MonitorModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool watching READ watching WRITE setWatching NOTIFY watchingChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles { TimeRole = Qt::UserRole + 1, TextRole };
    explicit MonitorModel(DSPiBridge *bridge, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool watching() const { return m_watching; }
    void setWatching(bool w);
    bool paused() const { return m_paused; }
    void setPaused(bool p);
    int count() const { return m_text.size(); }

    Q_INVOKABLE void clear();
    // Every line, for copying
    Q_INVOKABLE QString allText() const;

signals:
    void watchingChanged();
    void pausedChanged();
    void countChanged();
    void appended();

private:
    void readNew();

    DSPiBridge *m_bridge;
    FfiCore *m_core;
    bool m_watching = false;
    bool m_paused = false;
    quint64 m_lastId = 0;
    QStringList m_time, m_text;
};

#endif // MONITORMODEL_H
