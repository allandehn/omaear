#pragma once

#include <QByteArray>
#include <QQuickImageProvider>

// image://icons/<square|round>/<name>.svg: the app's own symbolic icons from
// qrc:/icons. Sources are drawn with square (miter) joins; "round" swaps in
// round joins so the icons follow a rounded theme. Colour is applied by the
// Controls icon (icon.color), exactly as for the plain qrc files.
// Use theme.iconBase + "<name>.svg" so the joins follow the live rounding.
QByteArray iconSvg(const QString &name, bool roundJoins);

class IconProvider : public QQuickImageProvider {
public:
    IconProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
