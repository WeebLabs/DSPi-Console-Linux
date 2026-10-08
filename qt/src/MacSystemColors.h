#ifndef MACSYSTEMCOLORS_H
#define MACSYSTEMCOLORS_H

#include <QVariantMap>

// macOS only: system colour name -> QColor in the dark appearance (see
// MacSystemColors.mm). QML reads them through the MacColors singleton.
QVariantMap macSystemColors();

class QCoreApplication;
// macOS only: draw every window in sRGB, colour-managed like the native app
void macUseSrgbWindows(QCoreApplication *app);

#endif // MACSYSTEMCOLORS_H
