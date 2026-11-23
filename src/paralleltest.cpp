// Offline checks for parallel refresh-all and its stop (Backend + FeedRefresher):
// up to Backend::kMaxFeedRefreshes feeds in flight, a slow feed does not hold the
// rest, the pill counts, the cover warning, the shelf order held during a run,
// and the safe stop: a stop mid-run (even from inside a running save) leaves an
// intact database where every show is either fully old or fully new, and the
// launch stamp follows today's rule (stamp if any feed succeeded).
// A local mock HTTP server only; the library is a throwaway file under the
// (throwaway) cache dir. Called from --self-test.
#include "backend.h"
#include "feedrefresh.h"
#include "library.h"
#include "models.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QHostAddress>
#include <QNetworkReply>
#include <QSemaphore>
#include <QSettings>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QThread>
#include <QTimeZone>

namespace {
int g_fails = 0;
void check(bool ok, const char *what)
{
    fprintf(stderr, "%s parallel: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++g_fails;
}

constexpr int kShows = 10;
// Recent dates, so no feed is backed off (FeedRefresher::backedOff) between runs.
qint64 kBase = 0;

QString showTitle(int i, int version) { return QStringLiteral("Show %1 v%2").arg(i).arg(version); }
QString episodeTitle(int i, int e, int version) { return QStringLiteral("S%1 E%2 v%3").arg(i).arg(e).arg(version); }
int episodeCount(int version) { return version == 1 ? 3 : 6; }
// v1: show i is newer the higher i is (Show 9 sorts first). v2 makes show 0 newest.
qint64 published(int i, int e, int version)
{
    return version == 1 ? kBase + i * 1000 + e : kBase + 100000 + (kShows - i) * 1000 + e;
}

QByteArray feedXml(const QString &origin, int i, int version)
{
    QString x = QStringLiteral(
        "<?xml version=\"1.0\"?><rss version=\"2.0\" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\">"
        "<channel><title>%1</title><itunes:author>Author v%2</itunes:author>"
        "<itunes:image href=\"%3/cover-%4.png\"/>").arg(showTitle(i, version)).arg(version).arg(origin).arg(i);
    for (int e = episodeCount(version); e >= 1; --e) {
        x += QStringLiteral("<item><title>%1</title><guid>s%2-e%3</guid><pubDate>%4</pubDate>"
                            "<enclosure url=\"%5/s%2-e%3.mp3\" type=\"audio/mpeg\" length=\"1\"/></item>")
                 .arg(episodeTitle(i, e, version))
                 .arg(i)
                 .arg(e)
                 .arg(QDateTime::fromSecsSinceEpoch(published(i, e, version), QTimeZone::utc()).toString(Qt::RFC2822Date))
                 .arg(origin);
    }
    x += QStringLiteral("</channel></rss>");
    return x.toUtf8();
}

// Routes: path -> body; "hold" paths keep the connection open until released.
struct HoldServer : QTcpServer {
    QHash<QString, QByteArray> bodies;
    QSet<QString> hold;
    QHash<QString, QTcpSocket *> held;
    QStringList requested;
    void respond(QTcpSocket *s, const QString &path)
    {
        QByteArray resp;
        if (!bodies.contains(path)) {
            resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        } else {
            const QByteArray &body = bodies[path];
            resp = "HTTP/1.1 200 OK\r\nContent-Type: application/rss+xml\r\nConnection: close\r\nContent-Length: "
                + QByteArray::number(body.size()) + "\r\n\r\n" + body;
        }
        s->write(resp);
        s->flush();
        s->disconnectFromHost();
    }
    void release(const QString &path)
    {
        if (QTcpSocket *s = held.take(path))
            respond(s, path);
    }
    HoldServer()
    {
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (QTcpSocket *s = nextPendingConnection()) {
                connect(s, &QTcpSocket::readyRead, this, [this, s]() {
                    const QByteArray req = s->property("buf").toByteArray() + s->readAll();
                    s->setProperty("buf", req);
                    if (!req.contains("\r\n\r\n"))
                        return;
                    const QString path = QString::fromLatin1(req.split('\n').value(0)).section(QLatin1Char(' '), 1, 1);
                    requested << path;
                    if (hold.contains(path))
                        held.insert(path, s);
                    else
                        respond(s, path);
                });
                connect(s, &QTcpSocket::disconnected, this, [this, s]() {
                    for (auto it = held.begin(); it != held.end(); ++it) {
                        if (it.value() == s) {
                            held.erase(it);
                            break;
                        }
                    }
                    s->deleteLater();
                });
            }
        });
    }
};

bool waitUntil(const std::function<bool()> &ready, int ms)
{
    QElapsedTimer t;
    t.start();
    while (!ready() && t.elapsed() < ms) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(2);
    }
    return ready();
}

void pump(int ms)
{
    QElapsedTimer t;
    t.start();
    while (t.elapsed() < ms) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(2);
    }
}

qint64 stamp()
{
    QSettings settings(Library::settingsPath(), QSettings::IniFormat);
    return settings.value(QStringLiteral("refresh/lastSuccessMs"), 0).toLongLong();
}

void setStamp(qint64 ms)
{
    QSettings settings(Library::settingsPath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("refresh/lastSuccessMs"), ms);
    settings.sync();
}

QList<qint64> order(ShowModel *m)
{
    QList<qint64> ids;
    for (int i = 0; i < m->rowCount(); ++i)
        ids << m->showIdAt(i);
    return ids;
}

QString refreshError(ShowModel *m, qint64 showId)
{
    const int row = m->rowOf(showId);
    return row < 0 ? QString() : m->data(m->index(row), ShowModel::RefreshErrorRole).toString();
}
} // namespace

int runParallelRefreshSelfTest()
{
    {
        // Badge wording: short plain words, never the technical string.
        using R = FeedRefreshResult;
        auto reason = [](R::Status status, QNetworkReply::NetworkError code, bool gzip = false) {
            R r;
            r.status = status;
            r.networkError = int(code);
            r.decompressionFailed = gzip;
            r.error = QStringLiteral("Error transferring http://example.test/feed.xml - server replied: Not Found");
            return Backend::refreshFailureReason(r);
        };
        const QString p = QStringLiteral("Couldn't refresh — ");
        check(reason(R::NetworkError, QNetworkReply::ContentNotFoundError) == p + "feed not found", "404: feed not found");
        check(reason(R::NetworkError, QNetworkReply::OperationCanceledError) == p + "server didn't respond",
              "transfer timeout: server didn't respond");
        check(reason(R::NetworkError, QNetworkReply::ConnectionRefusedError) == p + "server didn't respond",
              "refused: server didn't respond");
        check(reason(R::NetworkError, QNetworkReply::HostNotFoundError) == p + "server not found", "dns: server not found");
        check(reason(R::NetworkError, QNetworkReply::InternalServerError) == p + "server error", "500: server error");
        check(reason(R::NetworkError, QNetworkReply::UnknownContentError, true) == p + "couldn't read the feed",
              "bad gzip: couldn't read the feed");
        check(reason(R::ParseError, QNetworkReply::NoError) == p + "couldn't read the feed", "parse: couldn't read the feed");
        check(reason(R::SaveError, QNetworkReply::NoError) == p + "couldn't save the show", "save: couldn't save the show");
        R named;
        named.status = R::NetworkError;
        named.networkError = int(QNetworkReply::ContentNotFoundError);
        check(Backend::refreshFailureReason(named, QStringLiteral("Long Wave Radio"))
                  == QStringLiteral("Couldn't refresh Long Wave Radio — feed not found"),
              "pill wording with show name: Couldn't refresh Long Wave Radio — feed not found");
    }

    const QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(cache);
    QTemporaryDir dir(cache + QStringLiteral("/paralleltest-XXXXXX"));
    check(dir.isValid(), "temp dir");
    const QString dbPath = dir.filePath(QStringLiteral("library.db"));
    const qint64 savedStamp = stamp();
    kBase = QDateTime::currentSecsSinceEpoch() - 5 * 86400;

    HoldServer server;
    check(server.listen(QHostAddress::LocalHost, 0), "mock server listens");
    const QString origin = QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort());
    auto path = [](int i) { return QStringLiteral("/f%1.xml").arg(i); };
    auto feed = [&](int i) { return origin + path(i); };

    QHash<int, qint64> ids;
    {
        Library lib(dbPath);
        check(lib.isOpen(), "library opens");
        // v1 of every show, as if refreshed long ago (not backed off: checked_at 0).
        for (int i = 0; i < kShows; ++i) {
            ParsedShow show;
            show.title = showTitle(i, 1);
            show.author = QStringLiteral("Author v1");
            show.imageUrl = QStringLiteral("%1/cover-%2.png").arg(origin).arg(i);
            for (int e = 1; e <= episodeCount(1); ++e) {
                ParsedEpisode ep;
                ep.guid = QStringLiteral("s%1-e%2").arg(i).arg(e);
                ep.title = episodeTitle(i, e, 1);
                ep.audioUrl = QStringLiteral("%1/s%2-e%3.mp3").arg(origin).arg(i).arg(e);
                ep.published = published(i, e, 1);
                show.episodes.append(ep);
            }
            ids[i] = lib.upsertShow(feed(i), show);
        }
        check(ids.size() == kShows && !ids.values().contains(0), "10 v1 shows seeded");
        for (int i = 0; i < kShows; ++i)
            server.bodies[path(i)] = feedXml(origin, i, 2);
        server.bodies.remove(path(1)); // f1: 404, a failed feed

        // f0 answers at once, f1 fails, f2/f4/f5 stall on the network, f3's parse
        // is held on its worker thread. f6..f9 must stay queued (4 slots).
        for (int i : {2, 4, 5, 6, 7, 8, 9})
            server.hold.insert(path(i));
        QSemaphore parseGate;
        const QString heldParse = feed(3);
        FeedRefresher::testBeforeParse = [&parseGate, heldParse](const QString &url) {
            if (url == heldParse)
                parseGate.acquire();
        };

        setStamp(QDateTime::currentMSecsSinceEpoch()); // no launch refresh in the ctor
        {
            Backend backend(lib);
            QCoreApplication::processEvents();
            check(!backend.busy(), "launch refresh skipped (fresh stamp)");
            ShowModel *shows = backend.shows();
            const QList<qint64> before = order(shows);
            check(before.size() == kShows && before.first() == ids[9] && before.last() == ids[0],
                  "v1 order: show 9 first, show 0 last");
            setStamp(0);

            bool stoppedInsideSave = false;
            bool idleRightAfterStop = false;
            QString statusRightAfterStop;
            lib.testInsideUpsert = [&](qint64 showId) {
                if (showId != ids[2])
                    return;
                // A stop while this save's transaction is open: it must not undo or
                // cut it short. Saves run on this thread, so this is the only way
                // the two can meet at all.
                backend.stopRefresh();
                stoppedInsideSave = true;
                idleRightAfterStop = !backend.busy();
                statusRightAfterStop = backend.status();
            };

            backend.refreshAll();
            check(backend.busy(), "refresh-all is busy");
            check(backend.status() == QStringLiteral("Updating podcasts…"),
                  "no 0-of-N: Updating podcasts… until the first feed finishes");
            check(waitUntil([&]() {
                return server.held.size() == 3 && server.requested.contains(path(3))
                    && backend.status() == QStringLiteral("Updating 2 of 10 podcasts · 1 failed");
            }, 5000), "f0 done and f1 failed while f2/f4/f5 stall and f3 parses (parallel)");
            check(!server.requested.contains(path(6)), "no more than 4 feeds in flight");
            fprintf(stderr, "[safe-stop] mid-run status: %s\n", qPrintable(backend.status()));
            pump(Backend::kShelfFlushMs + 100);
            check(order(shows) == before, "shelf keeps its order during the run");
            const int row0 = shows->rowOf(ids[0]);
            check(row0 == kShows - 1 && shows->data(shows->index(row0), ShowModel::UnheardRole).toInt() == 6,
                  "f0's new episodes landed in place (batched), not moved");
            fprintf(stderr, "[safe-stop] badge reason: %s\n", qPrintable(refreshError(shows, ids[1])));
            check(refreshError(shows, ids[1]) == QStringLiteral("Couldn't refresh — feed not found"),
                  "failed show's warning says: Couldn't refresh — feed not found");
            check(refreshError(shows, ids[0]).isEmpty(), "updated show has no warning");

            // Stop from inside f2's save.
            server.release(path(2));
            check(waitUntil([&]() { return stoppedInsideSave; }, 5000), "stop arrived during f2's save");
            check(idleRightAfterStop, "stop ends the run at once (busy false immediately)");
            fprintf(stderr, "[safe-stop] status right after stop: %s\n", qPrintable(statusRightAfterStop));
            check(statusRightAfterStop == QStringLiteral("Stopped, 1 of 10 updated · 1 failed"),
                  "stopped pill: Stopped, 1 of 10 updated · 1 failed");
            lib.testInsideUpsert = nullptr;
            check(stamp() > 0, "stopped run with a success stamps the launch refresh");

            // Let everything wind down: f3's parse finishes after the stop, the
            // held sockets see their aborted clients go.
            parseGate.release();
            pump(400);
            for (int i : {4, 5, 6, 7, 8, 9})
                server.release(path(i));
            pump(200);
            check(!backend.busy(), "still idle after the stopped feeds wound down");
            check(!server.requested.contains(path(6)), "queued feeds never started after the stop");
            const QList<qint64> after = order(shows);
            check(after.size() == kShows && after.first() == ids[0], "sorted once at the end: show 0 first");

            // A stop where nothing succeeded leaves the stamp alone.
            setStamp(0);
            for (int i = 0; i < kShows; ++i)
                server.hold.insert(path(i));
            FeedRefresher::testBeforeParse = nullptr;
            backend.refreshAll();
            check(waitUntil([&]() { return server.held.size() == 4; }, 5000), "second run: 4 stalled feeds");
            backend.stopRefresh();
            check(!backend.busy() && backend.status() == QStringLiteral("Stopped, 0 of 10 updated"),
                  "second stop: Stopped, 0 of 10 updated");
            check(stamp() == 0, "stopped run with no success does not stamp");
            for (int i = 0; i < kShows; ++i)
                server.release(path(i));
            pump(200);
        }
        lib.testInsideUpsert = nullptr;
    }

    // The database after the stops: intact, and every show fully old or fully new.
    {
        auto db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("paralleltest-check"));
        db.setDatabaseName(dbPath);
        check(db.open(), "check connection opens");
        QSqlQuery q(db);
        const QString integrity = q.exec(QStringLiteral("PRAGMA integrity_check")) && q.next() ? q.value(0).toString() : QString();
        fprintf(stderr, "[safe-stop] PRAGMA integrity_check: %s\n", qPrintable(integrity));
        check(integrity == QStringLiteral("ok"), "integrity_check ok after the stops");
        bool allWhole = true;
        QStringList states;
        for (int i = 0; i < kShows; ++i) {
            QSqlQuery s(db);
            s.prepare(QStringLiteral("SELECT title, author FROM shows WHERE id = ?"));
            s.addBindValue(ids[i]);
            QString title, author;
            if (s.exec() && s.next()) {
                title = s.value(0).toString();
                author = s.value(1).toString();
            }
            QSqlQuery e(db);
            e.prepare(QStringLiteral("SELECT guid, title FROM episodes WHERE show_id = ? ORDER BY guid"));
            e.addBindValue(ids[i]);
            e.exec();
            QStringList got;
            while (e.next())
                got << e.value(0).toString() + QLatin1Char('=') + e.value(1).toString();
            auto expect = [&](int v) {
                QStringList want;
                for (int n = 1; n <= episodeCount(v); ++n)
                    want << QStringLiteral("s%1-e%2=%3").arg(i).arg(n).arg(episodeTitle(i, n, v));
                want.sort();
                return want;
            };
            const bool fullyOld = title == showTitle(i, 1) && author == QStringLiteral("Author v1") && got == expect(1);
            const bool fullyNew = title == showTitle(i, 2) && author == QStringLiteral("Author v2") && got == expect(2);
            allWhole = allWhole && (fullyOld != fullyNew);
            states << QStringLiteral("f%1=%2").arg(i).arg(fullyNew ? "new" : fullyOld ? "old" : "MIXED");
        }
        fprintf(stderr, "[safe-stop] shows: %s\n", qPrintable(states.join(QLatin1Char(' '))));
        check(allWhole, "every show is fully old or fully new");
        check(states.value(0) == QStringLiteral("f0=new"), "f0 (finished before the stop) kept its result");
        check(states.value(2) == QStringLiteral("f2=new"), "f2 (save running at the stop) completed");
        bool restOld = true;
        for (int i : {1, 3, 4, 5, 6, 7, 8, 9})
            restOld = restOld && states.value(i) == QStringLiteral("f%1=old").arg(i);
        check(restOld, "failed, aborted, parse-held and queued feeds left fully old");
        db.close();
    }
    QSqlDatabase::removeDatabase(QStringLiteral("paralleltest-check"));

    // A full run: end pills, the warning clears on the next good refresh,
    // and the launch refresh stays quiet.
    {
        Library lib(dbPath);
        server.hold.clear();
        setStamp(QDateTime::currentMSecsSinceEpoch());
        {
            Backend backend(lib);
            QCoreApplication::processEvents();
            backend.refreshAll();
            check(waitUntil([&]() { return !backend.busy(); }, 10000), "full run finishes");
            fprintf(stderr, "[safe-stop] full run end: %s\n", qPrintable(backend.status()));
            check(backend.status() == QStringLiteral("Updated 9 · 1 failed"), "end pill: Updated 9 · 1 failed");
            // One show's own refresh fails: plain reason with its name, no technical text.
            const QString name = lib.showTitle(ids[1]);
            backend.openShow(ids[1]);
            backend.refreshOpenShow(false);
            check(waitUntil([&]() { return !backend.busy(); }, 10000), "single-show refresh finishes");
            fprintf(stderr, "[safe-stop] single-show failure pill: %s\n", qPrintable(backend.status()));
            check(!name.isEmpty()
                      && backend.status() == QStringLiteral("Couldn't refresh %1 — feed not found").arg(name),
                  "single-show failure pill: Couldn't refresh <show> — feed not found");
            check(!backend.status().contains(QStringLiteral("127.0.0.1"))
                      && !backend.status().contains(QStringLiteral("Error transferring")),
                  "single-show failure pill has no technical error");
            check(refreshError(backend.shows(), ids[1]) == QStringLiteral("Couldn't refresh — feed not found"),
                  "badge keeps its short wording");
            server.bodies[path(1)] = feedXml(origin, 1, 2);
            backend.refreshAll();
            check(waitUntil([&]() { return !backend.busy(); }, 10000), "second full run finishes");
            check(backend.status() == QStringLiteral("All podcasts updated."), "end pill: All podcasts updated.");
            check(refreshError(backend.shows(), ids[1]).isEmpty(), "warning cleared by the next good refresh");
        }
        server.bodies.remove(path(1));
        setStamp(0);
        {
            QStringList seen;
            bool sawQuiet = false;
            Backend backend(lib);
            QObject::connect(&backend, &Backend::statusChanged, [&]() { seen << backend.status(); });
            QObject::connect(&backend, &Backend::busyChanged, [&]() { sawQuiet = sawQuiet || backend.refreshQuiet(); });
            check(waitUntil([&]() { return sawQuiet && !backend.busy(); }, 10000), "launch refresh ran quietly");
            bool anyUpdating = false;
            for (const QString &s : std::as_const(seen))
                anyUpdating = anyUpdating || s.startsWith(QStringLiteral("Updating"));
            check(!anyUpdating, "launch refresh shows no progress pill");
            fprintf(stderr, "[safe-stop] launch refresh end: %s\n", qPrintable(backend.status()));
            check(backend.status() == QStringLiteral("Updated 9 · 1 failed"), "launch refresh pill only on failure");
        }
        server.bodies[path(1)] = feedXml(origin, 1, 2);
        setStamp(0);
        {
            QStringList seen;
            Backend backend(lib);
            QObject::connect(&backend, &Backend::statusChanged, [&]() { seen << backend.status(); });
            pump(50);
            check(waitUntil([&]() { return !backend.busy(); }, 10000), "clean launch refresh finishes");
            check(backend.status().isEmpty() && seen.isEmpty(), "clean launch refresh shows no pill at all");
        }
    }

    server.close();
    setStamp(savedStamp);
    return g_fails;
}
