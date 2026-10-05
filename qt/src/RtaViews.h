#ifndef RTAVIEWS_H
#define RTAVIEWS_H

#include <QQuickPaintedItem>
#include <QPointer>
#include <QTimer>
#include <QElapsedTimer>
#include <QVector>
#include <QColor>
#include <QVariantList>

#include "RtaController.h"

// Eases displayed levels towards the latest frame between the device's
// frames (one pole, stepped by real time). Peaks jump up and only ease down.
// A change of what is shown (tap, channels, size) snaps instead of sliding.
class RtaSmoother
{
public:
    void setTarget(const QVector<float> &target, quint64 identity);
    // Advance by real time; true while still moving
    bool step(double fallTau, int peakFrom);
    const QVector<float> &values() const { return m_values; }
    bool settled() const { return m_settled; }

private:
    QVector<float> m_values, m_target;
    quint64 m_identity = ~0ull;
    QElapsedTimer m_clock;
    bool m_settled = true;
};

// Base: subscription to the controller while shown, and the display tick.
class RtaViewBase : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QObject *controller READ controller WRITE setController NOTIFY controllerChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(int tap READ tap WRITE setTap NOTIFY sourceChanged)
    Q_PROPERTY(qreal floorDb MEMBER m_floorDb WRITE setFloorDb NOTIFY styleChanged)
    Q_PROPERTY(qreal ceilingDb MEMBER m_ceilingDb WRITE setCeilingDb NOTIFY styleChanged)
    Q_PROPERTY(bool showPeak MEMBER m_showPeak WRITE setShowPeak NOTIFY styleChanged)
    Q_PROPERTY(bool smoothing MEMBER m_smoothing WRITE setSmoothing NOTIFY styleChanged)

public:
    explicit RtaViewBase(QQuickItem *parent = nullptr);
    ~RtaViewBase() override;

    QObject *controller() const { return m_rta; }
    void setController(QObject *c);
    bool active() const { return m_active; }
    void setActive(bool a);
    int tap() const { return m_tap; }
    void setTap(int t);
    void setFloorDb(qreal v);
    void setCeilingDb(qreal v);
    void setShowPeak(bool v);
    void setSmoothing(bool v);

signals:
    void controllerChanged();
    void activeChanged();
    void sourceChanged();
    void styleChanged();

protected:
    // The channels shown (indices at the tap) and whether bins are drawn
    virtual int channelMask() const = 0;
    virtual bool wantsBins() const { return false; }
    // Take the controller's latest frame as the smoothing target
    virtual void takeFrame() = 0;
    // Advance smoothing; true while anything still moves
    virtual bool stepSmoothing(double fallTau) = 0;

    void resubscribe();
    double fallTau() const;
    qreal yForDb(qreal db, qreal top, qreal bottom) const;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

    QPointer<RtaController> m_rta;
    bool m_active = false;
    int m_tap = 1;
    qreal m_floorDb = -90, m_ceilingDb = 6;
    bool m_showPeak = true, m_smoothing = true;
    quint64 m_populated = 0;      // bands with a level (bit per band)

private:
    void onFrame();
    void onTick();

    int m_sub = 0;
    QTimer m_tick;
};

// The spectrum on the response graph: a filled curve per channel on its own
// dBFS scale, sharing the graph's log frequency axis. One channel blends its
// bass bands into the FFT bins above them; several draw band curves.
class SpectrumCurveItem : public RtaViewBase
{
    Q_OBJECT
    Q_PROPERTY(QVariantList channels READ channels WRITE setChannels NOTIFY sourceChanged)
    Q_PROPERTY(QVariantList colors READ colors WRITE setColors NOTIFY styleChanged)
    Q_PROPERTY(qreal minFreq MEMBER m_minFreq WRITE setMinFreq NOTIFY styleChanged)
    Q_PROPERTY(qreal maxFreq MEMBER m_maxFreq WRITE setMaxFreq NOTIFY styleChanged)
    Q_PROPERTY(qreal strength MEMBER m_strength WRITE setStrength NOTIFY styleChanged)
    Q_PROPERTY(bool glow MEMBER m_glow WRITE setGlow NOTIFY styleChanged)
    Q_PROPERTY(qreal bottomInset MEMBER m_bottomInset WRITE setBottomInset NOTIFY styleChanged)
    // Channels left out of the drawing (window-local hiding)
    Q_PROPERTY(QVariantList hidden READ hidden WRITE setHidden NOTIFY styleChanged)

public:
    explicit SpectrumCurveItem(QQuickItem *parent = nullptr);
    void paint(QPainter *p) override;

    QVariantList channels() const { return m_channelList; }
    void setChannels(const QVariantList &l);
    QVariantList colors() const { return m_colorList; }
    void setColors(const QVariantList &l);
    QVariantList hidden() const { return m_hiddenList; }
    void setHidden(const QVariantList &l);
    void setMinFreq(qreal v);
    void setMaxFreq(qreal v);
    void setStrength(qreal v);
    void setGlow(bool v);
    void setBottomInset(qreal v);

protected:
    int channelMask() const override;
    bool wantsBins() const override { return m_channels.size() == 1; }
    void takeFrame() override;
    bool stepSmoothing(double fallTau) override;

private:
    qreal xForFreq(double f) const;
    // dB per pixel column for one channel: bands, and bins above the bass bank
    QVector<qreal> columnLevels(const QVector<float> &bands, const float *bins, int nBins,
                                int sampleRate, bool peaks) const;

    QVector<int> m_channels;
    QVariantList m_channelList, m_colorList, m_hiddenList;
    QVector<QColor> m_colors;
    QVector<int> m_hiddenSet;
    qreal m_minFreq = 15, m_maxFreq = 20000, m_strength = 1.0, m_bottomInset = 0;
    bool m_glow = false;
    // Per channel: avg bands then peak bands (2 * RTA_MAX_BANDS), and bins
    QVector<RtaSmoother> m_bands;
    RtaSmoother m_bins;
    int m_binsRate = 0;
};

// One channel's third-octave bars with peak caps, a 12 dB grid and labels.
class SpectrumBarsItem : public RtaViewBase
{
    Q_OBJECT
    Q_PROPERTY(int channel READ channel WRITE setChannel NOTIFY sourceChanged)
    Q_PROPERTY(QColor color MEMBER m_color WRITE setColor NOTIFY styleChanged)
    Q_PROPERTY(bool levelLabels MEMBER m_levelLabels WRITE setLevelLabels NOTIFY styleChanged)

public:
    explicit SpectrumBarsItem(QQuickItem *parent = nullptr);
    void paint(QPainter *p) override;

    int channel() const { return m_channel; }
    void setChannel(int c);
    void setColor(const QColor &c);
    void setLevelLabels(bool v);

protected:
    int channelMask() const override { return m_channel >= 0 && m_channel < 16 ? 1 << m_channel : 0; }
    void takeFrame() override;
    bool stepSmoothing(double fallTau) override;

private:
    int m_channel = -1;
    QColor m_color = Qt::white;
    bool m_levelLabels = false;
    RtaSmoother m_levels;          // avg bands then peak bands
};

#endif // RTAVIEWS_H
