#include "updates.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QList>

namespace {
QString stripTag(QString tag)
{
    tag = tag.trimmed();
    // Only a version marker, so a tag that merely starts with "v" is left alone.
    if (tag.size() > 1 && tag.at(0).toLower() == u'v' && tag.at(1).isDigit())
        tag = tag.mid(1).trimmed();
    return tag;
}

QList<int> versionParts(const QString &version)
{
    QList<int> parts;
    const QStringList bits = version.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    for (const QString &bit : bits) {
        int value = 0;
        for (const QChar &ch : bit) {
            if (!ch.isDigit())
                break;
            value = value * 10 + ch.digitValue();
        }
        parts.append(value);
    }
    return parts;
}

bool hasDigit(const QString &text)
{
    for (const QChar &ch : text) {
        if (ch.isDigit())
            return true;
    }
    return false;
}
}

bool versionIsNewer(const QString &remoteTag, const QString &appVersion)
{
    const QList<int> remote = versionParts(stripTag(remoteTag));
    const QList<int> local = versionParts(stripTag(appVersion));
    const int count = qMax(remote.size(), local.size());
    for (int i = 0; i < count; ++i) {
        const int r = i < remote.size() ? remote.at(i) : 0;
        const int l = i < local.size() ? local.at(i) : 0;
        if (r != l)
            return r > l;
    }
    return false;
}

UpdateOffer parseLatestRelease(const QByteArray &body, int httpStatus, const QString &appVersion)
{
    UpdateOffer offer;
    if (httpStatus != 200)
        return offer;
    const QJsonObject obj = QJsonDocument::fromJson(body).object();
    const QString latest = stripTag(obj.value(QStringLiteral("tag_name")).toString());
    if (!hasDigit(latest))
        return offer;
    offer.latest = latest;
    offer.url = obj.value(QStringLiteral("html_url")).toString().trimmed();
    offer.kind = versionIsNewer(latest, appVersion) ? UpdateKind::Available : UpdateKind::Current;
    return offer;
}
