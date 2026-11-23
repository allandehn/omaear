#pragma once

#include "library.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QString>
#include <atomic>
#include <functional>
#include <memory>

class QNetworkReply;

// Outcome of refreshing one feed.
struct FeedRefreshResult {
    // Cancelled: stopped before its save started; the library is untouched.
    enum Status { Updated, NotModified, NetworkError, ParseError, SaveError, Cancelled };
    Status status = NetworkError;
    QString error;
    bool decompressionFailed = false; // NetworkError: a gzip body Qt could not inflate
    int networkError = 0;             // NetworkError: the QNetworkReply::NetworkError code
    qint64 showId = 0;
    QString title;
    QString imageUrl;
    // Diagnostics (tests, logs).
    bool conditional = false;   // validators were sent
    bool stoppedEarly = false;  // parsing ended at known episodes
    int items = 0;              // episodes parsed
};
Q_DECLARE_METATYPE(FeedRefreshResult)

// Refreshes one feed per instance, cheapest way first (Backend runs a few
// instances side by side, see Backend::kMaxFeedRefreshes):
//  - sends the stored ETag / Last-Modified, and does nothing more on a 304;
//  - parses a changed feed on a worker thread, stopping at known episodes
//    (see FeedParseOptions for when that is allowed);
//  - writes the show and its new episodes in one SQLite transaction.
// A manual refresh, a feed never fully parsed yet, and a feed whose last whole
// parse is a week old all skip the validators and parse everything.
// Library access stays on the calling (GUI) thread.
class FeedRefresher : public QObject {
    Q_OBJECT
public:
    static constexpr qint64 kFullParseEverySecs = 7 * 24 * 3600;
    static constexpr int kStopAfterKnown = 20; // consecutive known guids

    FeedRefresher(Library &library, QNetworkAccessManager &network, QObject *parent = nullptr);

    // For automatic and refresh-all runs only: a feed that has had no new episode
    // for 14 days is not asked again within 6 h (60 days: 24 h; a year: 72 h) of
    // its last successful check. Recently active feeds are never skipped.
    static bool backedOff(const FeedState &state, qint64 nowSecs);

    bool busy() const { return m_busy; }
    bool cancelled() const { return m_cancel && m_cancel->load(); }
    // manual: bypass validators and early stop. plainEncoding: ask for an uncompressed body.
    void start(const QString &feedUrl, bool manual, bool plainEncoding = false);
    // Stop this feed. A download is aborted now; a parse on the worker is told to
    // give up and its result is dropped; a save that has not started is skipped.
    // A save never runs concurrently with this (both are on the GUI thread), so a
    // running save always completes. finished() still comes, with Cancelled.
    void cancel();

    // Self-test only: runs on the worker thread right before a feed is parsed
    // (lets a test hold a parse mid-flight). Empty in the app.
    static std::function<void(const QString &feedUrl)> testBeforeParse;

signals:
    void finished(const QString &feedUrl, const FeedRefreshResult &result);

private:
    void done(const QString &feedUrl, const FeedRefreshResult &result);

    Library &m_library;
    QNetworkAccessManager &m_network;
    bool m_busy = false;
    QPointer<QNetworkReply> m_reply;
    // Per run, shared with the worker so a stop reaches a parse in progress.
    std::shared_ptr<std::atomic_bool> m_cancel;
};
