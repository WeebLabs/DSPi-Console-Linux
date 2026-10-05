#ifndef BODEPLOTITEM_H
#define BODEPLOTITEM_H

#include <QQuickPaintedItem>
#include <QPainter>
#include <QVariantList>
#include <QVector>
#include <QColor>
#include <QVariantAnimation>

class DSPiBridge;

struct ChannelCurve {
    QColor color;
    QVector<double> magnitudes; // 201 points
    bool visible = true;
    double gainOffset = 0.0;
};

class BodePlotItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(float dbTop READ dbTop WRITE setDbTop NOTIFY settingsChanged)
    Q_PROPERTY(float dbBottom READ dbBottom WRITE setDbBottom NOTIFY settingsChanged)
    Q_PROPERTY(float minFreq READ minFreq WRITE setMinFreq NOTIFY settingsChanged)
    Q_PROPERTY(float maxFreq READ maxFreq WRITE setMaxFreq NOTIFY settingsChanged)
    Q_PROPERTY(bool showGlow READ showGlow WRITE setShowGlow NOTIFY settingsChanged)
    Q_PROPERTY(bool showFreqGrid READ showFreqGrid WRITE setShowFreqGrid NOTIFY settingsChanged)
    Q_PROPERTY(bool showDbGrid READ showDbGrid WRITE setShowDbGrid NOTIFY settingsChanged)
    Q_PROPERTY(bool showFreqLabels READ showFreqLabels WRITE setShowFreqLabels NOTIFY settingsChanged)
    Q_PROPERTY(bool showDbLabels READ showDbLabels WRITE setShowDbLabels NOTIFY settingsChanged)
    Q_PROPERTY(float lineWidth READ lineWidth WRITE setLineWidth NOTIFY settingsChanged)
    // What this instance draws: everything, the grid and labels (under the
    // spectrum), or the curves and phase (over it)
    Q_PROPERTY(int drawLayer READ drawLayer WRITE setDrawLayer NOTIFY settingsChanged)
    // Strength of the grid lines: 0.5 is the default look, 0-2
    Q_PROPERTY(float gridOpacity READ gridOpacity WRITE setGridOpacity NOTIFY settingsChanged)
    // Curves of the channels visible in the main window, or (pop-out graph
    // with its own selection) of shownChannels (app ids)
    Q_PROPERTY(bool followVisibility READ followVisibility WRITE setFollowVisibility NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList shownChannels READ shownChannels WRITE setShownChannels NOTIFY settingsChanged)
    // The channel the on-graph editor draws itself (-1 = none)
    Q_PROPERTY(int excludeChannel READ excludeChannel WRITE setExcludeChannel NOTIFY settingsChanged)
    // Dotted phase trace of one channel, on a degree axis at the right
    Q_PROPERTY(bool showPhase READ showPhase WRITE setShowPhase NOTIFY settingsChanged)
    Q_PROPERTY(bool phaseUnwrapped READ phaseUnwrapped WRITE setPhaseUnwrapped NOTIFY settingsChanged)
    Q_PROPERTY(int phaseChannel READ phaseChannel WRITE setPhaseChannel NOTIFY settingsChanged)

public:
    explicit BodePlotItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    float dbTop() const { return m_dbTop; }
    float dbBottom() const { return m_dbBottom; }
    float minFreq() const { return m_minFreq; }
    float maxFreq() const { return m_maxFreq; }
    bool showGlow() const { return m_showGlow; }
    bool showFreqGrid() const { return m_showFreqGrid; }
    bool showDbGrid() const { return m_showDbGrid; }
    bool showFreqLabels() const { return m_showFreqLabels; }
    bool showDbLabels() const { return m_showDbLabels; }
    float lineWidth() const { return m_lineWidth; }
    enum Layer { AllLayers = 0, GridLayer = 1, CurveLayer = 2 };
    int drawLayer() const { return m_layer; }
    void setDrawLayer(int v);
    float gridOpacity() const { return m_gridOpacity; }
    void setGridOpacity(float v);
    bool followVisibility() const { return m_followVisibility; }
    void setFollowVisibility(bool v);
    QVariantList shownChannels() const { return m_shownList; }
    void setShownChannels(const QVariantList &l);
    int excludeChannel() const { return m_excludeChannel; }
    bool showPhase() const { return m_showPhase; }
    bool phaseUnwrapped() const { return m_phaseUnwrapped; }
    int phaseChannel() const { return m_phaseChannel; }
    void setExcludeChannel(int ch);
    void setShowPhase(bool v);
    void setPhaseUnwrapped(bool v);
    void setPhaseChannel(int ch);

    void setDbTop(float v);
    void setDbBottom(float v);
    void setMinFreq(float v);
    void setMaxFreq(float v);
    void setShowGlow(bool v);
    void setShowFreqGrid(bool v);
    void setShowDbGrid(bool v);
    void setShowFreqLabels(bool v);
    void setShowDbLabels(bool v);
    void setLineWidth(float v);

    Q_INVOKABLE void setBridge(QObject *bridge);
    Q_INVOKABLE void refresh();
    // Rebuild the curves and repaint at once (live drags: no animation)
    void refreshNow();

signals:
    void settingsChanged();

private:
    QVector<ChannelCurve> buildCurves() const;
    QVector<ChannelCurve> shownCurves() const;
    void drawGrid(QPainter *painter, const QRectF &rect);
    QColor gridColor(int alpha) const;
    void drawCurves(QPainter *painter, const QRectF &rect);
    void drawLabels(QPainter *painter, const QRectF &rect);
    void drawPhase(QPainter *painter, const QRectF &rect);
    void updatePhase();
    QPainterPath buildCurvePath(const QVector<double> &magnitudes, const QRectF &rect);

    qreal xForFreq(float freq, qreal width) const;
    qreal yForDb(float db, qreal height) const;

    float m_dbTop = 25.0f;
    float m_dbBottom = -25.0f;
    float m_minFreq = 15.0f;
    float m_maxFreq = 20000.0f;
    bool m_showGlow = true;
    bool m_showFreqGrid = true;
    bool m_showDbGrid = true;
    bool m_showFreqLabels = true;
    bool m_showDbLabels = true;
    float m_lineWidth = 2.0f;
    int m_layer = AllLayers;
    float m_gridOpacity = 0.5f;
    bool m_followVisibility = true;
    QVariantList m_shownList;
    QVector<int> m_shown;
    bool isShown(int eqCh) const;
    int m_excludeChannel = -1;
    bool m_showPhase = false;
    bool m_phaseUnwrapped = false;
    int m_phaseChannel = -1;
    QVector<double> m_phase;            // degrees, empty when not shown

    DSPiBridge *m_bridge = nullptr;

    // Animation state
    QVector<ChannelCurve> m_currentCurves;
    QVector<ChannelCurve> m_targetCurves;
    QVariantAnimation *m_animation = nullptr;
    float m_animProgress = 1.0f;
};

#endif // BODEPLOTITEM_H
