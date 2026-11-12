#pragma once

#include "library.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QString>

// Outcome of refreshing one feed.
struct FeedRefreshResult {
    enum Status { Updated, NotModified, NetworkError, ParseError, SaveError };
    Status status = NetworkError;
    QString error;
    bool decompressionFailed = false; // NetworkError: a gzip body Qt could not inflate
    qint64 showId = 0;
    QString title;
    QString imageUrl;
    // Diagnostics (tests, logs).
    bool conditional = false;   // validators were sent
    bool stoppedEarly = false;  // parsing ended at known episodes
    int items = 0;              // episodes parsed
};
Q_DECLARE_METATYPE(FeedRefreshResult)

// Refreshes one feed at a time, cheapest way first:
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
    // manual: bypass validators and early stop. plainEncoding: ask for an uncompressed body.
    void start(const QString &feedUrl, bool manual, bool plainEncoding = false);

signals:
    void finished(const QString &feedUrl, const FeedRefreshResult &result);

private:
    void done(const QString &feedUrl, const FeedRefreshResult &result);

    Library &m_library;
    QNetworkAccessManager &m_network;
    bool m_busy = false;
};
