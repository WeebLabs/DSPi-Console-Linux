#include "MonitorModel.h"
#include "DSPiBridge.h"

#include <QDateTime>

static const int kLimit = 2000;

MonitorModel::MonitorModel(DSPiBridge *bridge, QObject *parent)
    : QAbstractListModel(parent), m_bridge(bridge), m_core(bridge->core())
{
    connect(m_bridge, &DSPiBridge::notificationsArrived, this, &MonitorModel::readNew);
}

int MonitorModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_text.size();
}

QVariant MonitorModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_text.size()) return {};
    if (role == TimeRole) return m_time[index.row()];
    if (role == TextRole || role == Qt::DisplayRole) return m_text[index.row()];
    return {};
}

QHash<int, QByteArray> MonitorModel::roleNames() const {
    return { { TimeRole, "time" }, { TextRole, "text" } };
}

void MonitorModel::setWatching(bool w) {
    if (w == m_watching) return;
    m_watching = w;
    emit watchingChanged();
    if (w) readNew();          // catch up on what came while closed
}

void MonitorModel::setPaused(bool p) {
    if (p == m_paused) return;
    m_paused = p;
    emit pausedChanged();
    if (!p) readNew();
}

void MonitorModel::readNew() {
    if (!m_watching) return;
    QByteArray buf(64 * 1024, '\0');
    QStringList time, text;
    for (;;) {
        quint64 last = dspi_monitor_read(m_core, m_lastId, buf.data(), uint32_t(buf.size()));
        if (last == m_lastId) break;
        m_lastId = last;
        if (m_paused) continue;           // lost to the log while paused
        const QStringList lines = QString::fromUtf8(buf.constData()).split('\n', Qt::SkipEmptyParts);
        for (const QString &l : lines) {
            int tab = l.indexOf('\t');
            qint64 ms = l.left(tab).toLongLong();
            time.append(QDateTime::fromMSecsSinceEpoch(ms).toString("HH:mm:ss.zzz"));
            text.append(l.mid(tab + 1));
        }
    }
    if (text.isEmpty()) return;

    // Keep the newest 2000
    int drop = qMax(0, m_text.size() + text.size() - kLimit);
    if (drop > 0) {
        int fromOld = qMin(drop, m_text.size());
        if (fromOld > 0) {
            beginRemoveRows(QModelIndex(), 0, fromOld - 1);
            m_time.erase(m_time.begin(), m_time.begin() + fromOld);
            m_text.erase(m_text.begin(), m_text.begin() + fromOld);
            endRemoveRows();
        }
        int fromNew = drop - fromOld;
        time = time.mid(fromNew);
        text = text.mid(fromNew);
    }
    beginInsertRows(QModelIndex(), m_text.size(), m_text.size() + text.size() - 1);
    m_time.append(time);
    m_text.append(text);
    endInsertRows();
    emit countChanged();
    emit appended();
}

void MonitorModel::clear() {
    dspi_monitor_clear(m_core);
    beginResetModel();
    m_time.clear();
    m_text.clear();
    endResetModel();
    emit countChanged();
}

QString MonitorModel::allText() const {
    QStringList out;
    for (int i = 0; i < m_text.size(); i++) out.append(m_time[i] + "  " + m_text[i]);
    return out.join('\n');
}
