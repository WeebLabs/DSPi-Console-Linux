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

signals:
    void settingsChanged();

private:
    void drawGrid(QPainter *painter, const QRectF &rect);
    void drawCurves(QPainter *painter, const QRectF &rect);
    void drawLabels(QPainter *painter, const QRectF &rect);
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

    DSPiBridge *m_bridge = nullptr;

    // Animation state
    QVector<ChannelCurve> m_currentCurves;
    QVector<ChannelCurve> m_targetCurves;
    QVariantAnimation *m_animation = nullptr;
    float m_animProgress = 1.0f;
};

#endif // BODEPLOTITEM_H
