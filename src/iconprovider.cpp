#include "iconprovider.h"

#include <QBuffer>
#include <QFile>
#include <QImageReader>

QByteArray iconSvg(const QString &name, bool roundJoins)
{
    if (name.contains(QLatin1Char('/')) || !name.endsWith(QStringLiteral(".svg")))
        return {};
    QFile file(QStringLiteral(":/icons/") + name);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    QByteArray svg = file.readAll();
    if (roundJoins)
        svg.replace("stroke-linejoin=\"miter\"", "stroke-linejoin=\"round\"");
    return svg;
}

IconProvider::IconProvider()
    : QQuickImageProvider(Image)
{
}

QImage IconProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int slash = id.indexOf(QLatin1Char('/'));
    const bool round = slash > 0 && id.left(slash) == QStringLiteral("round");
    QByteArray svg = iconSvg(id.mid(slash + 1), round);
    QBuffer buffer(&svg);
    QImageReader reader(&buffer, "svg");
    const QSize want = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(16, 16);
    reader.setScaledSize(want);
    QImage image = reader.read();
    if (size)
        *size = image.size();
    return image;
}
