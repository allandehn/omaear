#include "feedrefresh.h"

#include "feed.h"

#include <QDateTime>
#include <QFutureWatcher>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPromise>
#include <QThreadPool>
#include <memory>

namespace {
struct Parsed {
    std::optional<ParsedShow> show;
    QString error;
    bool stoppedEarly = false;
};
}

FeedRefresher::FeedRefresher(Library &library, QNetworkAccessManager &network, QObject *parent)
    : QObject(parent)
    , m_library(library)
    , m_network(network)
{
    qRegisterMetaType<FeedRefreshResult>();
}

bool FeedRefresher::backedOff(const FeedState &state, qint64 nowSecs)
{
    if (state.checkedAt <= 0 || state.newest <= 0)
        return false;
    const qint64 quietFor = nowSecs - state.newest;
    constexpr qint64 day = 24 * 3600;
    if (quietFor < 14 * day)
        return false;
    const qint64 wait = quietFor < 60 * day ? 6 * 3600 : quietFor < 365 * day ? day : 3 * day;
    const qint64 since = nowSecs - state.checkedAt;
    return since >= 0 && since < wait;
}

void FeedRefresher::done(const QString &feedUrl, const FeedRefreshResult &result)
{
    m_busy = false;
    emit finished(feedUrl, result);
}

void FeedRefresher::start(const QString &feedUrl, bool manual, bool plainEncoding)
{
    m_busy = true;
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const FeedState state = m_library.feedState(feedUrl);
    const bool full = manual || state.showId == 0 || state.fullAt <= 0 || state.fullAt > now
        || now - state.fullAt >= kFullParseEverySecs;

    QNetworkRequest request{QUrl(feedUrl)};
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("omaear/" OMAEAR_VERSION " (Omarchy; +https://github.com/allandehn/omaear)"));
    request.setTransferTimeout(20000);
    if (plainEncoding)
        request.setRawHeader("Accept-Encoding", "identity");
    bool conditional = false;
    if (!full) {
        if (!state.etag.isEmpty()) {
            request.setRawHeader("If-None-Match", state.etag.toUtf8());
            conditional = true;
        }
        if (!state.lastModified.isEmpty()) {
            request.setRawHeader("If-Modified-Since", state.lastModified.toUtf8());
            conditional = true;
        }
    }

    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, feedUrl, state, full, conditional]() {
        reply->deleteLater();
        FeedRefreshResult result;
        result.conditional = conditional;
        if (reply->error() != QNetworkReply::NoError) {
            result.status = FeedRefreshResult::NetworkError;
            result.error = reply->errorString();
            result.decompressionFailed = result.error.startsWith(QStringLiteral("Decompression failed"));
            done(feedUrl, result);
            return;
        }
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 304 && state.showId != 0) {
            m_library.noteFeedChecked(state.showId, QDateTime::currentSecsSinceEpoch());
            result.status = FeedRefreshResult::NotModified;
            result.showId = state.showId;
            result.title = state.title;
            result.imageUrl = state.imageUrl;
            done(feedUrl, result);
            return;
        }

        const QByteArray body = reply->readAll();
        const QUrl base = reply->url();
        FeedFetchMeta meta;
        meta.etag = QString::fromLatin1(reply->rawHeader("ETag")).trimmed();
        meta.lastModified = QString::fromLatin1(reply->rawHeader("Last-Modified")).trimmed();
        meta.full = full;
        QSet<QString> known;
        if (!full)
            known = m_library.knownGuids(state.showId);

        // Parse off the GUI thread; the result comes back through the watcher.
        auto promise = std::make_shared<QPromise<Parsed>>();
        QFuture<Parsed> future = promise->future();
        promise->start();
        QThreadPool::globalInstance()->start([promise, body, base, known, full]() {
            Parsed out;
            FeedParseOptions options;
            options.knownGuids = &known;
            options.stopAfterKnown = kStopAfterKnown;
            out.show = parseFeed(body, base, &out.error, full ? nullptr : &options, &out.stoppedEarly);
            promise->addResult(std::move(out));
            promise->finish();
        });
        auto *watcher = new QFutureWatcher<Parsed>(this);
        connect(watcher, &QFutureWatcher<Parsed>::finished, this,
                [this, watcher, feedUrl, meta, conditional]() mutable {
            watcher->deleteLater();
            Parsed parsed = watcher->result();
            FeedRefreshResult result;
            result.conditional = conditional;
            if (!parsed.show) {
                result.status = FeedRefreshResult::ParseError;
                result.error = parsed.error;
                done(feedUrl, result);
                return;
            }
            meta.now = QDateTime::currentSecsSinceEpoch();
            meta.partial = parsed.stoppedEarly;
            result.stoppedEarly = parsed.stoppedEarly;
            result.items = parsed.show->episodes.size();
            result.showId = m_library.upsertShow(feedUrl, *parsed.show, &meta);
            result.title = parsed.show->title;
            result.imageUrl = parsed.show->imageUrl;
            result.status = result.showId == 0 ? FeedRefreshResult::SaveError : FeedRefreshResult::Updated;
            done(feedUrl, result);
        });
        watcher->setFuture(future);
    });
}
