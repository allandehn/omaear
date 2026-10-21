#pragma once

#include <QString>
#include <QByteArray>

// Result of GET /repos/allandehn/omaear/releases/latest.
// Failed covers offline, 404 (no releases yet), rate limits, and bad JSON.
enum class UpdateKind { Current, Available, Failed };

struct UpdateOffer {
    UpdateKind kind = UpdateKind::Failed;
    QString latest; // tag_name with one leading v/V removed
    QString url;    // html_url, may be empty
};

// True when remoteTag is a newer semantic version than appVersion.
// Leading v/V is ignored. Components compare as integers, so 0.1.10 > 0.1.9.
bool versionIsNewer(const QString &remoteTag, const QString &appVersion);

// httpStatus other than 200, or a body with no numeric tag, is Failed.
UpdateOffer parseLatestRelease(const QByteArray &body, int httpStatus, const QString &appVersion);
