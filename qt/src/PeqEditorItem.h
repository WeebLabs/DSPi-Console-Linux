#ifndef PEQEDITORITEM_H
#define PEQEDITORITEM_H

#include <QQuickPaintedItem>
#include <QPainterPath>
#include <QElapsedTimer>
#include <QTimer>
#include <QVariantList>
#include <QVector>
#include <QColor>
extern "C" {
#include "dspi_core.h"
}

class DSPiBridge;

// On-graph PEQ editing for one channel, laid over the BodePlotItem (which
// leaves that channel out). Draws the channel's bands (lobes, combined curve,
// a dot per band) and edits them by mouse, wheel and keyboard, after the
// macOS Console's PeqGraphEditor. A drag redraws only this item and sends
// the device the latest values at most every 30 ms; the release commits once.
class PeqEditorItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(int channel READ channel WRITE setChannel NOTIFY channelChanged)
    Q_PROPERTY(float dbTop MEMBER m_dbTop WRITE setDbTop NOTIFY viewChanged)
    Q_PROPERTY(float dbBottom MEMBER m_dbBottom WRITE setDbBottom NOTIFY viewChanged)
    Q_PROPERTY(float minFreq MEMBER m_minFreq WRITE setMinFreq NOTIFY viewChanged)
    Q_PROPERTY(float maxFreq MEMBER m_maxFreq WRITE setMaxFreq NOTIFY viewChanged)
    Q_PROPERTY(float lineWidth MEMBER m_lineWidth WRITE setLineWidth NOTIFY viewChanged)
    Q_PROPERTY(bool showGlow MEMBER m_showGlow WRITE setShowGlow NOTIFY viewChanged)
    Q_PROPERTY(bool showFreqReadout MEMBER m_showFreqReadout NOTIFY viewChanged)
    Q_PROPERTY(bool showLevelReadout MEMBER m_showLevelReadout NOTIFY viewChanged)
    // Graph background, for the pip in a selected dot
    Q_PROPERTY(QColor backgroundColor MEMBER m_background NOTIFY viewChanged)
    // True while a channel is being edited (the graph should leave it out)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QVariantList selectedBands READ selectedBands NOTIFY selectionChanged)
    Q_PROPERTY(int hoveredBand READ hoveredBand NOTIFY hoverChanged)
    // The band list's row under the pointer: its dot and lobe light up
    Q_PROPERTY(int listHovered READ listHovered WRITE setListHovered NOTIFY listHoveredChanged)
    // The band whose control panel (HUD) shows: hovered, lingering 0.35 s
    // after the pointer leaves it, held while the pointer is on the panel,
    // else the selection's anchor. -1 = none.
    Q_PROPERTY(int hudBand READ hudBand NOTIFY hudChanged)
    Q_PROPERTY(QPointF hudPoint READ hudPoint NOTIFY hudChanged)       // the band's dot
    Q_PROPERTY(bool hudBoost READ hudBoost NOTIFY hudChanged)          // dot at or above 0 dB
    Q_PROPERTY(QVariantMap hudValues READ hudValues NOTIFY hudChanged)
    Q_PROPERTY(bool hudHold READ hudHold WRITE setHudHold NOTIFY hudChanged)

public:
    explicit PeqEditorItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    int channel() const { return m_channel; }
    void setChannel(int ch);
    void setDbTop(float v);
    void setDbBottom(float v);
    void setMinFreq(float v);
    void setMaxFreq(float v);
    void setLineWidth(float v);
    void setShowGlow(bool v);
    bool active() const { return m_active; }
    QVariantList selectedBands() const;
    int hoveredBand() const { return m_hover; }
    int listHovered() const { return m_listHover; }
    void setListHovered(int band);
    int hudBand() const { return m_hudBand; }
    QPointF hudPoint() const { return m_hudBand >= 0 ? dotPos(m_hudBand) : QPointF(); }
    bool hudBoost() const { return m_hudBand >= 0 && dotDb(m_hudBand) >= 0; }
    QVariantMap hudValues() const;
    bool hudHold() const { return m_hudHold; }
    void setHudHold(bool hold);

    Q_INVOKABLE void setBridge(QObject *bridge);
    // Context menu actions; each applies to the selection
    Q_INVOKABLE QVariantMap bandInfo(int band) const;
    Q_INVOKABLE void deleteSelection();
    Q_INVOKABLE void toggleBypassSelection();
    Q_INVOKABLE void invertGainSelection();
    Q_INVOKABLE void setOrderSelection(int order);      // 1 or 2
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void deselectAll();
    Q_INVOKABLE void selectBand(int band, bool toggle, bool range);
    // A click on a band's number in the list: toggle adds or removes it,
    // range takes the run of rows from the last one clicked (row order)
    Q_INVOKABLE void listClick(int band, bool toggle, bool range);
    // HUD edits on one band (field: "freq", "gain", "q"), committed at once
    Q_INVOKABLE void setBandValue(int band, const QString &field, double value);
    Q_INVOKABLE void setBandType(int band, int type);
    Q_INVOKABLE void toggleBandBypass(int band);
    // Add a band of this shape where the shape card was opened
    Q_INVOKABLE void createShape(int type, double freq, double gain);
    // The Ctrl-click card closed (picked or dismissed)
    Q_INVOKABLE void cardClosed();

signals:
    void channelChanged();
    void viewChanged();
    void activeChanged();
    void selectionChanged();
    void hoverChanged();
    void listHoveredChanged();
    // The pointer rested on a band's dot: the list shows its row
    void revealRow(int band);
    // Right-click: band under the pointer (-1 = none), selection size
    void contextMenuRequested(qreal x, qreal y, int band, int selectionCount);
    void hudChanged();
    // Ctrl-click on empty graph: pick a shape for a new band at freq / gain.
    // boost: the point is at or above 0 dB (the card goes above it)
    void shapeCardRequested(qreal x, qreal y, double freq, double gain, bool boost);
    // Double-click on a dot: the chip's frequency field takes the keyboard
    void editFrequencyRequested();

protected:
    void mousePressEvent(QMouseEvent *e) override;
    void mouseMoveEvent(QMouseEvent *e) override;
    void mouseReleaseEvent(QMouseEvent *e) override;
    void mouseDoubleClickEvent(QMouseEvent *e) override;
    void hoverMoveEvent(QHoverEvent *e) override;
    void hoverLeaveEvent(QHoverEvent *e) override;
    void wheelEvent(QWheelEvent *e) override;
    void keyPressEvent(QKeyEvent *e) override;

private:
    enum Role { GainRole, QRole, FixedRole, LockedRole };
    enum Mode { Idle, PressDot, DragDot, DragQ, PressEmpty, PressCurve, Marquee };

    // Model
    void reload();                         // from the bridge, unless editing
    void updateActive();
    void recomputeBand(int b);
    void recomputeCombined();
    static Role roleOf(int type);
    static bool usesGain(int type);
    static bool usesQ(int type);
    static float gainScale(int type);
    float dotDb(int b) const;
    QPointF dotPos(int b) const;
    bool isEditable(int b) const;         // has a dot

    // Geometry
    qreal xForFreq(float f) const;
    float freqForX(qreal x) const;
    qreal yForDb(float db) const;
    float dbForY(qreal y) const;
    QPainterPath curvePath(const double *mags, float offset) const;
    int dotAt(const QPointF &p) const;
    int lobeAt(const QPointF &p) const;
    bool nearCurve(const QPointF &p) const;   // within 6 px of the combined curve

    // Editing
    void beginEdit();                     // snapshot the selection's start values
    void applyDrag(const QPointF &pos, Qt::KeyboardModifiers mods);
    void markLive(int b);
    void flushLive();
    void commit();
    void commitBand(int b, const FilterParams &p);   // immediate edits
    int firstFreeBand() const;
    void createBand(float freq, float gain, int type, float q);
    // Steps the bands in `targets` (the selection when null)
    void nudge(float octaves, float db, float qFactor, const bool *targets = nullptr);
    void setHover(int dot, int band);
    int chipPin() const;                  // the selected band the chip stays on
    void kickEase();
    void showMessage(const QString &text);

    // Drawing
    void drawBand(QPainter *p, int b, float lift);
    void updateHud();
    void drawReadouts(QPainter *p);

    DSPiBridge *m_bridge = nullptr;
    int m_channel = -1;
    bool m_active = false;
    QColor m_channelColor = Qt::white;
    float m_dbTop = 25.0f, m_dbBottom = -25.0f, m_minFreq = 15.0f, m_maxFreq = 20000.0f;
    float m_lineWidth = 2.0f;
    bool m_showGlow = true, m_showFreqReadout = true, m_showLevelReadout = true;
    QColor m_background = QColor(44, 44, 44);

    FilterParams m_bands[BANDS_PER_CHANNEL];
    FilterParams m_xover[MAX_XOVER_BANDS];
    int m_xoverCount = 0;
    float m_offset = 0.0f;
    double m_bandCurve[BANDS_PER_CHANNEL][MAGNITUDE_POINTS];
    double m_combined[MAGNITUDE_POINTS];

    // Selection and hover
    bool m_selected[BANDS_PER_CHANNEL] = {};
    int m_anchor = -1;
    int m_hover = -1;                     // band under the pointer: its dot, else its fill
    int m_hoverDot = -1;                  // dot under the pointer
    int m_wheelBand = -1;                 // band the wheel last adjusted; holds the chip until the pointer moves
    int m_listHover = -1;
    int m_listAnchor = -1;                // where a Shift-click in the list extends from
    QTimer m_revealTimer;                 // dwell before the list reveals the hovered band
    QPointF m_pointer;
    bool m_pointerInside = false;

    // Gesture
    Mode m_mode = Idle;
    int m_pressBand = -1;
    QPointF m_pressPos;
    Qt::KeyboardModifiers m_pressMods;
    int m_axisLock = 0;                   // 0 undecided, 1 horizontal, 2 vertical
    FilterParams m_start[BANDS_PER_CHANNEL];
    QRectF m_marquee;
    bool m_marqueeAdd = false;
    bool m_editing = false;               // live values not yet committed

    // Live device writes
    bool m_pending[BANDS_PER_CHANNEL] = {};
    bool m_changed[BANDS_PER_CHANNEL] = {};
    QTimer m_liveTimer;                   // 30 ms throttle
    QElapsedTimer m_lastSend;
    QTimer m_wheelCommit;                 // commit after a pause in wheel/key edits

    QString m_message;
    QTimer m_messageTimer;

    bool m_cardOpen = false;              // the Ctrl-click card is up
    QPointF m_cardPoint;                  // where its band will go
    int m_hudBand = -1;
    int m_lingerBand = -1;
    bool m_hudHold = false;
    QTimer m_lingerTimer;

    // Dot hover/selection easing (macOS: exponential, 70 ms)
    float m_hoverAmt[BANDS_PER_CHANNEL] = {};
    float m_selectAmt[BANDS_PER_CHANNEL] = {};
    QTimer m_easeTimer;
    QElapsedTimer m_easeClock;
    void ease();
};

#endif // PEQEDITORITEM_H
