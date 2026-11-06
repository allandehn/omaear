#pragma once

#include <QCoreApplication>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QStandardPaths>
#include <QThread>
#include <QNetworkRequest>
#include <QQmlNetworkAccessManagerFactory>
#include <QPointer>
#include <QRegularExpression>
#include <QSet>
#include <QUrl>

// User-Agent for EPISODE AUDIO only (HttpFileBuffer: play, prefetch, resume).
//
// Episode audio is fetched with a generic media player identity (the one
// ffmpeg, mpv and VLC send). If a host refuses that identity, the
// downloader retries once with kAudioAppUserAgent. Feeds,
// artwork and Explore keep the app's own identity.
inline constexpr const char kAudioGenericUserAgent[] = "Lavf/61.1.100";
inline constexpr const char kAudioAppUserAgent[] =
    "omaear/" OMAEAR_VERSION " (+https://github.com/allandehn/omaear)";

// Every network request in both processes goes through this manager.
//
// HTTP/2 is turned off on purpose. Qt's HTTP/2 path does not race IPv6 against
// IPv4 the way HTTP/1.1 does, so on a network with broken IPv6 the first request
// to a dual-stack host stalls ~5 s, and HTTP/2 connection setup is slower
// for covers here even when IPv6 is not involved. Redirect hops keep the
// attribute, since Qt copies the original request when it follows them.
class AppNetworkAccessManager : public QNetworkAccessManager {
public:
    using QNetworkAccessManager::QNetworkAccessManager;

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request,
                                 QIODevice *outgoingData = nullptr) override
    {
        QNetworkRequest req(request);
        req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
        return QNetworkAccessManager::createRequest(op, req, outgoingData);
    }
};

// The Explore cover disk cache (owned by Qt Quick's image reader thread).
inline QPointer<QNetworkDiskCache> &coverDiskCache()
{
    static QPointer<QNetworkDiskCache> cache;
    return cache;
}

// Every URL a cover can be fetched under: as given, plus the 400px tile and
// 600px preview sizes of Apple's CDN path.
inline QStringList coverUrlVariants(const QString &cover)
{
    if (cover.isEmpty())
        return {};
    static const QRegularExpression size(QStringLiteral("/\\d+x\\d+bb\\."));
    QString tile = cover, preview = cover;
    tile.replace(size, QStringLiteral("/400x400bb."));
    preview.replace(size, QStringLiteral("/600x600bb."));
    QStringList out{cover};
    if (!out.contains(tile))
        out << tile;
    if (!out.contains(preview))
        out << preview;
    return out;
}

// Removes the given URLs from an HTTP cache; returns how many were there.
inline int removeFromCache(QAbstractNetworkCache *cache, const QStringList &urls)
{
    int removed = 0;
    if (!cache)
        return 0;
    // Count by metaData: QNetworkDiskCache::remove() can report false after removing.
    for (const QString &u : QSet<QString>(urls.begin(), urls.end())) {
        const QUrl url(u);
        if (!cache->metaData(url).isValid())
            continue;
        cache->remove(url);
        ++removed;
    }
    return removed;
}

// Force refresh: drop these cover URLs from the disk cache, on the cache's own thread.
inline void dropCoverUrlsFromDiskCache(const QStringList &urls)
{
    QNetworkDiskCache *cache = coverDiskCache().data();
    if (!cache || urls.isEmpty())
        return;
    QMetaObject::invokeMethod(cache, [cache, urls]() { removeFromCache(cache, urls); }, Qt::QueuedConnection);
}

// Qt Quick (remote Image sources such as Explore covers or episode art that is
// not cached yet, XMLHttpRequest) uses this so QML loads take the same path.
class AppNetworkAccessManagerFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        auto *nam = new AppNetworkAccessManager(parent);
        // Remote Image loads (Explore covers) run on Qt Quick's image reader thread.
        // Give that manager a small HTTP disk cache: Apple's artwork CDN sends
        // ~6-month max-age, so repeat visits paint from disk instead of refetching.
        // Only the reader thread gets it, so one cache instance owns the folder.
        if (QThread::currentThread() != QCoreApplication::instance()->thread()) {
            auto *cache = new QNetworkDiskCache(nam);
            cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                                     + QStringLiteral("/http"));
            cache->setMaximumCacheSize(64LL * 1024 * 1024); // oldest entries go first
            nam->setCache(cache);
            coverDiskCache() = cache;
        }
        return nam;
    }
};
