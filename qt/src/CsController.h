#ifndef CSCONTROLLER_H
#define CSCONTROLLER_H

#include <QByteArray>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

class DSPiBridge;

// Control Surfaces: the device's wired controls, IR remote, display, aux
// outputs, channel groups and macros. The configuration is read once per
// device and kept by the core; every operation goes through apply() and the
// core re-reads what it changed. `model` is the core's snapshot (see
// core/src/cs.rs); `changed` is emitted only when it actually differs.
class CsController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap model READ model NOTIFY changed)
    Q_PROPERTY(bool supported READ supported NOTIFY changed)
    // What the firmware has, for showing pages (cheap to bind to, unlike `model`)
    Q_PROPERTY(bool loaded READ loaded NOTIFY changed)
    Q_PROPERTY(bool hasGroups READ hasGroups NOTIFY changed)
    Q_PROPERTY(bool hasMacros READ hasMacros NOTIFY changed)
    Q_PROPERTY(bool hasAux READ hasAux NOTIFY changed)
    // Bumped on every model change: a dependency token for bindings that
    // only need to re-run (reading `model` converts the whole map)
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    // Applied edits the device hasn't saved to flash
    Q_PROPERTY(bool unsaved READ unsaved NOTIFY changed)
    // The display's live state (link, page on screen, I2C errors): polled
    // while its card is open, so kept apart from `model`
    Q_PROPERTY(QVariantMap displayState READ displayState NOTIFY displayStateChanged)
    // Aux outputs' live switch and level ({state: [16], level: [16] in 8.8 %}),
    // which a control on the device can move continuously
    Q_PROPERTY(QVariantMap auxLive READ auxLive NOTIFY auxLiveChanged)
    // A display card is open: poll the panel's state once a second
    Q_PROPERTY(bool watchDisplay READ watchDisplay WRITE setWatchDisplay NOTIFY watchDisplayChanged)

public:
    explicit CsController(DSPiBridge *bridge, QObject *parent = nullptr);

    QVariantMap model() const { return m_model; }
    QVariantMap displayState() const { return m_displayState; }
    QVariantMap auxLive() const { return m_auxLive; }
    bool supported() const { return m_model.value("supported").toBool(); }
    bool loaded() const { return !m_model.isEmpty(); }
    bool hasGroups() const { return supported() && m_model.value("maxGroups").toInt() > 0; }
    bool hasMacros() const { return supported() && m_model.value("maxMacros").toInt() > 0; }
    bool hasAux() const { return supported() && m_model.value("types").toList().size() > 10; }
    int revision() const { return m_revision; }
    bool unsaved() const;
    bool watchDisplay() const { return m_displayPoll.isActive(); }
    void setWatchDisplay(bool on);

    // One operation ({op, index, ...}); returns {ok, status, error, ...}
    Q_INVOKABLE QVariantMap apply(const QVariantMap &op);
    // An aux level while its slider is dragged: sent, but the model and the
    // pages aren't refreshed until the release commits with apply()
    Q_INVOKABLE void sendOnly(const QVariantMap &op);
    Q_INVOKABLE void refresh();
    // The shared save bar: write the live configuration to flash, or reload
    // the saved one. Returns the device's status code (0 = done).
    Q_INVOKABLE int save();
    Q_INVOKABLE int revert();

    // A PIN_CONFIG_* / CS status code as the macOS Console words it ("" = done)
    Q_INVOKABLE QString statusMessage(int code) const;

signals:
    void changed();
    void watchDisplayChanged();
    void displayStateChanged();
    void auxLiveChanged();
    // IR learning ended: state 2 = captured, 3 = timed out
    void learnFinished(int state, int protocol, double code);
    // The saved configuration was reloaded (Revert), or another device came:
    // pages drop their drafts
    void reloaded();

private:
    void onDeviceChanged();
    void onNotified(bool aux, bool learn);
    QVariantMap call(const QByteArray &json);
    void reload();

    DSPiBridge *m_bridge;
    QString m_serial;
    QVariantMap m_model;
    QByteArray m_snapshot;          // the model's JSON, to skip no-op updates
    QVariantMap m_displayState;
    QVariantMap m_auxLive;
    QTimer m_displayPoll;
    QTimer m_macroPoll;
    int m_macroPolls = 0;
    int m_revision = 0;
};

#endif // CSCONTROLLER_H
