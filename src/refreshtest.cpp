// Offline checks for the feed refresh path (FeedRefresher + Library): a mock HTTP
// server on localhost serves feeds with ETag / Last-Modified, a second SQLite
// connection watches the library file. Called from --self-test.
#include "feedrefresh.h"
#include "library.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QLocale>
#include <QStandardPaths>
#include <QEventLoop>
#include <QHostAddress>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTimeZone>
#include <QTimer>
#include <algorithm>

namespace {
int g_refreshFails = 0;
void check(bool ok, const char *what)
{
    if (ok)
        return;
    ++g_refreshFails;
    fprintf(stderr, "FAIL refresh: %s\n", what);
}

struct Item {
    QString guid;
    QString title;
    qint64 date = 0;
};

constexpr qint64 kBase = 1700000000;

// Newest first: g<hi> .. g<lo>, one hour apart.
QList<Item> newestFirst(int hi, int lo = 1)
{
    QList<Item> items;
    for (int i = hi; i >= lo; --i)
        items.append({QStringLiteral("g%1").arg(i), QStringLiteral("Episode %1").arg(i), kBase + i * 3600});
    return items;
}

// zone: text after the time, e.g. "GMT" or "PST" as some hosts write it (empty: the usual +0000).
QByteArray feedXml(const QList<Item> &items, bool authorLast = false, bool dated = true, const QString &zone = {})
{
    QString x = QStringLiteral(
        "<?xml version=\"1.0\"?><rss version=\"2.0\" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\">"
        "<channel><title>Mock show</title><itunes:image href=\"http://127.0.0.1/cover.png\"/>");
    if (!authorLast)
        x += QStringLiteral("<itunes:author>Mock Author</itunes:author>");
    for (const Item &it : items) {
        x += QStringLiteral("<item><title>%1</title><guid>%2</guid>").arg(it.title, it.guid);
        if (dated)
            x += QStringLiteral("<pubDate>%1</pubDate>")
                     .arg(zone.isEmpty()
                              ? QDateTime::fromSecsSinceEpoch(it.date, QTimeZone::utc()).toString(Qt::RFC2822Date)
                              : QLocale::c().toString(QDateTime::fromSecsSinceEpoch(it.date, QTimeZone::utc()),
                                                      QStringLiteral("ddd, dd MMM yyyy HH:mm:ss ")) + zone);
        x += QStringLiteral("<enclosure url=\"http://127.0.0.1/%1.mp3\" type=\"audio/mpeg\" length=\"1\"/></item>")
                 .arg(it.guid);
    }
    if (authorLast)
        x += QStringLiteral("<itunes:author>Mock Author</itunes:author>");
    x += QStringLiteral("</channel></rss>");
    return x.toUtf8();
}

struct Route {
    QByteArray body;
    QByteArray etag;
    QByteArray lastModified;
};
struct Request {
    QString path;
    QByteArray ifNoneMatch;
    QByteArray ifModifiedSince;
    int status = 0;
    int bodyBytes = 0;
};

struct MockServer : QTcpServer {
    QHash<QString, Route> routes;
    QList<Request> log;
    MockServer()
    {
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (QTcpSocket *s = nextPendingConnection()) {
                connect(s, &QTcpSocket::readyRead, this, [this, s]() {
                    QByteArray req = s->property("buf").toByteArray() + s->readAll();
                    s->setProperty("buf", req);
                    if (!req.contains("\r\n\r\n"))
                        return;
                    Request r;
                    const QList<QByteArray> lines = req.split('\n');
                    r.path = QString::fromLatin1(lines.value(0)).section(QLatin1Char(' '), 1, 1);
                    for (const QByteArray &line : lines) {
                        const QByteArray low = line.toLower();
                        if (low.startsWith("if-none-match:"))
                            r.ifNoneMatch = line.mid(14).trimmed();
                        else if (low.startsWith("if-modified-since:"))
                            r.ifModifiedSince = line.mid(18).trimmed();
                    }
                    QByteArray resp;
                    const auto route = routes.constFind(r.path);
                    if (route == routes.cend()) {
                        r.status = 404;
                        resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    } else if ((!route->etag.isEmpty() && r.ifNoneMatch == route->etag)
                               || (route->etag.isEmpty() && !route->lastModified.isEmpty()
                                   && r.ifModifiedSince == route->lastModified)) {
                        r.status = 304;
                        resp = "HTTP/1.1 304 Not Modified\r\nConnection: close\r\n\r\n";
                    } else {
                        r.status = 200;
                        r.bodyBytes = route->body.size();
                        resp = "HTTP/1.1 200 OK\r\nContent-Type: application/rss+xml\r\nConnection: close\r\n";
                        if (!route->etag.isEmpty())
                            resp += "ETag: " + route->etag + "\r\n";
                        if (!route->lastModified.isEmpty())
                            resp += "Last-Modified: " + route->lastModified + "\r\n";
                        resp += "Content-Length: " + QByteArray::number(route->body.size()) + "\r\n\r\n" + route->body;
                    }
                    log.append(r);
                    s->write(resp);
                    s->flush();
                    s->disconnectFromHost();
                });
                connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
            }
        });
    }
};
}

int runRefreshSelfTest()
{
    // Under the (throwaway) cache dir, never the shared /tmp.
    const QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(cache);
    QTemporaryDir dir(cache + QStringLiteral("/refreshtest-XXXXXX"));
    check(dir.isValid(), "temp dir");
    const QString dbPath = dir.filePath(QStringLiteral("library.db"));
    Library lib(dbPath);
    check(lib.isOpen(), "library opens");

    // A second connection: sees commits by data_version, reads rows, edits full_at.
    auto reader = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("refreshtest-reader"));
    reader.setDatabaseName(dbPath);
    check(reader.open(), "reader opens");
    auto scalar = [&](const QString &sql) {
        QSqlQuery q(reader);
        return q.exec(sql) && q.next() ? q.value(0) : QVariant();
    };
    auto dataVersion = [&]() { return scalar(QStringLiteral("PRAGMA data_version")).toLongLong(); };
    auto episodeCount = [&]() { return scalar(QStringLiteral("SELECT COUNT(*) FROM episodes")).toInt(); };
    auto titleOf = [&](const QString &guid, const QString &feed) {
        return scalar(QStringLiteral("SELECT e.title FROM episodes e JOIN shows s ON s.id = e.show_id"
                                     " WHERE e.guid = '%1' AND s.feed_url LIKE '%%2'").arg(guid, feed))
            .toString();
    };
    auto rowsDump = [&](const QString &feed) {
        QSqlQuery q(reader);
        QString out;
        q.exec(QStringLiteral("SELECT e.guid, e.title, e.description, e.audio_url, e.published_at, e.played FROM episodes e"
                              " JOIN shows s ON s.id = e.show_id WHERE s.feed_url LIKE '%%1' ORDER BY e.guid").arg(feed));
        while (q.next())
            for (int i = 0; i < 6; ++i)
                out += q.value(i).toString() + QLatin1Char('|');
        q.exec(QStringLiteral("SELECT title, author, image_url, etag, last_modified FROM shows WHERE feed_url LIKE '%%1'").arg(feed));
        while (q.next())
            for (int i = 0; i < 5; ++i)
                out += q.value(i).toString() + QLatin1Char('#');
        return out;
    };

    MockServer server;
    check(server.listen(QHostAddress::LocalHost, 0), "mock server listens");
    const QString origin = QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort());
    QNetworkAccessManager nam;
    FeedRefresher refresher(lib, nam);
    auto refresh = [&](const QString &path, bool manual = false) {
        FeedRefreshResult out;
        QEventLoop loop;
        QTimer timeout;
        timeout.setSingleShot(true);
        QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
        const auto conn = QObject::connect(&refresher, &FeedRefresher::finished, &loop,
                                           [&](const QString &, const FeedRefreshResult &r) {
                                               out = r;
                                               loop.quit();
                                           });
        timeout.start(15000);
        refresher.start(origin + path, manual);
        loop.exec();
        QObject::disconnect(conn);
        return out;
    };
    auto serve = [&](const QString &path, const QByteArray &body, const QByteArray &etag,
                     const QByteArray &lastModified = {}) { server.routes[path] = {body, etag, lastModified}; };
    using R = FeedRefreshResult;

    // 1. First refresh of a newest-first feed: whole feed, one transaction.
    serve(QStringLiteral("/main.xml"), feedXml(newestFirst(40)), "\"v1\"");
    qint64 dv = dataVersion();
    R r = refresh(QStringLiteral("/main.xml"));
    check(r.status == R::Updated && !r.conditional && !r.stoppedEarly && r.items == 40, "first refresh parses all 40");
    check(episodeCount() == 40, "first refresh stores 40 episodes");
    check(dataVersion() - dv == 1, "first refresh is one transaction");
    check(lib.feedState(origin + QStringLiteral("/main.xml")).etag == QStringLiteral("\"v1\""), "etag stored");

    // 2. Nothing changed: the stored ETag comes back, the server answers 304, the rows stay as they are.
    QSqlQuery(reader).exec(QStringLiteral("UPDATE shows SET checked_at = 1")); // so the new stamp is a real change
    const QString before = rowsDump(QStringLiteral("/main.xml"));
    dv = dataVersion();
    r = refresh(QStringLiteral("/main.xml"));
    check(r.status == R::NotModified && r.conditional, "unchanged feed: 304, skipped");
    check(server.log.last().status == 304 && server.log.last().ifNoneMatch == "\"v1\"" && server.log.last().bodyBytes == 0,
          "304: validator was sent, no body came back");
    check(rowsDump(QStringLiteral("/main.xml")) == before, "304 leaves shows and episodes unchanged");
    check(scalar(QStringLiteral("SELECT checked_at FROM shows LIMIT 1")).toLongLong() > 1, "304 stamps the check time");
    check(dataVersion() - dv == 1, "304 writes only the check time (one tiny transaction)");
    dv = dataVersion();
    check(refresh(QStringLiteral("/main.xml")).status == R::NotModified && dataVersion() == dv,
          "a second 304 right after writes nothing at all");

    // 3. New episodes on top: only they are added, parsing stops at the known ones, one transaction.
    serve(QStringLiteral("/main.xml"), feedXml(newestFirst(42)), "\"v2\"");
    dv = dataVersion();
    r = refresh(QStringLiteral("/main.xml"));
    check(r.status == R::Updated && r.conditional && r.stoppedEarly, "changed feed: 200, stopped at known episodes");
    check(r.items == 2 + FeedRefresher::kStopAfterKnown, "parse read 2 new + 20 known items, not all 42");
    check(episodeCount() == 42 && !titleOf(QStringLiteral("g42"), QStringLiteral("/main.xml")).isEmpty(),
          "changed feed adds exactly the new episodes");
    check(dataVersion() - dv == 1, "changed feed is one transaction");

    // 4. An edit inside the parsed head is picked up, old episodes are never dropped.
    QList<Item> v3 = newestFirst(43);
    v3[2].title = QStringLiteral("Edited title");
    serve(QStringLiteral("/main.xml"), feedXml(v3), "\"v3\"");
    r = refresh(QStringLiteral("/main.xml"));
    check(r.status == R::Updated && episodeCount() == 43, "edit + new item: 43 episodes, none lost");
    check(titleOf(v3[2].guid, QStringLiteral("/main.xml")) == QStringLiteral("Edited title"), "edit inside the head is applied");

    // 5. An edit deep in the old part waits for a whole parse, which a manual refresh does at once.
    QList<Item> v4 = newestFirst(43);
    v4[40].title = QStringLiteral("Deep edit");
    serve(QStringLiteral("/main.xml"), feedXml(v4), "\"v4\"");
    r = refresh(QStringLiteral("/main.xml"));
    check(r.status == R::Updated && r.stoppedEarly && episodeCount() == 43, "deep edit: early stop, nothing lost");
    check(titleOf(v4[40].guid, QStringLiteral("/main.xml")) != QStringLiteral("Deep edit"), "deep edit waits for a full parse");
    r = refresh(QStringLiteral("/main.xml"), true);
    check(r.status == R::Updated && !r.conditional && !r.stoppedEarly && r.items == 43, "manual refresh: no validators, whole feed");
    check(server.log.last().ifNoneMatch.isEmpty() && server.log.last().status == 200, "manual refresh sent no If-None-Match");
    check(titleOf(v4[40].guid, QStringLiteral("/main.xml")) == QStringLiteral("Deep edit"), "manual refresh applies the deep edit");

    // 6. Whole-parse clock: after a week the next automatic refresh is unconditional and complete.
    QList<Item> v5 = newestFirst(43);
    v5[41].title = QStringLiteral("Deep edit 2");
    serve(QStringLiteral("/main.xml"), feedXml(v5), "\"v5\"");
    QSqlQuery(reader).exec(QStringLiteral("UPDATE shows SET full_at = 1"));
    r = refresh(QStringLiteral("/main.xml"));
    check(r.status == R::Updated && !r.conditional && !r.stoppedEarly, "week-old full parse: unconditional, whole feed");
    check(titleOf(v5[41].guid, QStringLiteral("/main.xml")) == QStringLiteral("Deep edit 2"), "week-old full parse applies the edit");

    // 7. Oldest-first feed: a new item at the END must not be missed.
    QList<Item> asc = newestFirst(30);
    std::reverse(asc.begin(), asc.end());
    serve(QStringLiteral("/asc.xml"), feedXml(asc), "\"a1\"");
    refresh(QStringLiteral("/asc.xml"));
    asc.append({QStringLiteral("g31"), QStringLiteral("Episode 31"), kBase + 31 * 3600});
    serve(QStringLiteral("/asc.xml"), feedXml(asc), "\"a2\"");
    r = refresh(QStringLiteral("/asc.xml"));
    check(r.status == R::Updated && !r.stoppedEarly && r.items == 31, "oldest-first feed is parsed whole");
    check(!titleOf(QStringLiteral("g31"), QStringLiteral("/asc.xml")).isEmpty(), "oldest-first feed: new last item stored");

    // 8. Feed without dates: no ordering to trust, so no early stop.
    QList<Item> undated = newestFirst(30);
    serve(QStringLiteral("/undated.xml"), feedXml(undated, false, false), "\"u1\"");
    refresh(QStringLiteral("/undated.xml"));
    undated.append({QStringLiteral("g31"), QStringLiteral("Episode 31"), 0});
    serve(QStringLiteral("/undated.xml"), feedXml(undated, false, false), "\"u2\"");
    r = refresh(QStringLiteral("/undated.xml"));
    check(r.status == R::Updated && !r.stoppedEarly && r.items == 31, "undated feed is parsed whole");
    check(!titleOf(QStringLiteral("g31"), QStringLiteral("/undated.xml")).isEmpty(), "undated feed: new last item stored");

    // 8b. Dates written with a zone name (GMT, PST) parse now, so those feeds can stop early too.
    for (const char *zone : {"GMT", "PST"}) {
        const QString path = QStringLiteral("/zone-%1.xml").arg(QLatin1String(zone));
        serve(path, feedXml(newestFirst(30), false, true, QLatin1String(zone)), QByteArray("\"z1\""));
        refresh(path);
        serve(path, feedXml(newestFirst(31), false, true, QLatin1String(zone)), QByteArray("\"z2\""));
        r = refresh(path);
        check(r.status == R::Updated && r.stoppedEarly && r.items == 21,
              zone[0] == 'G' ? "GMT-dated feed stops early" : "PST-dated feed stops early");
    }

    // 9. Author listed after the items: an early stop keeps the stored author.
    serve(QStringLiteral("/late.xml"), feedXml(newestFirst(30), true), "\"l1\"");
    refresh(QStringLiteral("/late.xml"));
    serve(QStringLiteral("/late.xml"), feedXml(newestFirst(31), true), "\"l2\"");
    r = refresh(QStringLiteral("/late.xml"));
    check(r.status == R::Updated && r.stoppedEarly, "late-author feed stops early");
    check(scalar(QStringLiteral("SELECT author FROM shows WHERE feed_url LIKE '%/late.xml'")).toString()
              == QStringLiteral("Mock Author"),
          "early stop keeps the stored author");

    // 10. Last-Modified without an ETag works the same way.
    serve(QStringLiteral("/lm.xml"), feedXml(newestFirst(5)), {}, "Wed, 01 Jan 2025 00:00:00 GMT");
    refresh(QStringLiteral("/lm.xml"));
    r = refresh(QStringLiteral("/lm.xml"));
    check(r.status == R::NotModified && server.log.last().ifModifiedSince == "Wed, 01 Jan 2025 00:00:00 GMT",
          "Last-Modified is sent back as If-Modified-Since, 304 skipped");

    // 11. Failures leave the library alone.
    serve(QStringLiteral("/html.xml"), "<!DOCTYPE html><html></html>", {});
    const int shows = scalar(QStringLiteral("SELECT COUNT(*) FROM shows")).toInt();
    check(refresh(QStringLiteral("/html.xml")).status == R::ParseError, "html page is a parse error");
    check(refresh(QStringLiteral("/missing.xml")).status == R::NetworkError, "404 is a network error");
    check(scalar(QStringLiteral("SELECT COUNT(*) FROM shows")).toInt() == shows, "failed refreshes add no shows");

    // 12. Backoff: only quiet feeds, only shortly after a check; never a feed checked long ago or never.
    const qint64 now = 1800000000, day = 86400;
    FeedState st;
    st.checkedAt = now - 3600;
    st.newest = now - 5 * day;
    check(!FeedRefresher::backedOff(st, now), "active feed is never skipped");
    st.newest = now - 20 * day;
    check(FeedRefresher::backedOff(st, now), "quiet feed checked an hour ago is skipped");
    st.checkedAt = now - 7 * 3600;
    check(!FeedRefresher::backedOff(st, now), "quiet feed is checked again after 6 h");
    st.newest = now - 100 * day;
    check(FeedRefresher::backedOff(st, now), "older feed waits 24 h");
    st.newest = now - 400 * day;
    st.checkedAt = now - 2 * day;
    check(FeedRefresher::backedOff(st, now), "year-old feed waits 72 h");
    st.checkedAt = now - 4 * day;
    check(!FeedRefresher::backedOff(st, now), "year-old feed is checked after 72 h");
    st.checkedAt = 0;
    check(!FeedRefresher::backedOff(st, now), "a feed never checked is not skipped");
    st.checkedAt = now - 60;
    st.newest = 0;
    check(!FeedRefresher::backedOff(st, now), "a feed without dates is not skipped");

    reader.close();
    reader = QSqlDatabase();
    QSqlDatabase::removeDatabase(QStringLiteral("refreshtest-reader"));
    return g_refreshFails;
}
