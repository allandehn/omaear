#include "iconprovider.h"
#include <QBuffer>
#include <QImageReader>
#include <QElapsedTimer>
#include <QDir>
#include "covercache.h"
#include <QPainter>
#include <QLinearGradient>
#include "theme.h"
#include "covercache.h"
#include "explore.h"
#include "feed.h"
#include "library.h"
#include "updates.h"
#include "growingmediadevice.h"

#include <QUrl>
#include <QUrlQuery>

#include <QCoreApplication>
#include <QEventLoop>
#include <QHostAddress>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QDateTime>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QLocale>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QTimer>
#include <QNetworkDiskCache>
#include "netaccess.h"

namespace {
int g_fails = 0;

void check(bool ok, const char *what)
{
    if (ok)
        return;
    ++g_fails;
    fprintf(stderr, "FAIL %s\n", what);
}
}

int runSelfTest(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("omaear-selftest"));

    {
        // OKLCH tints: zero nudge round-trips; hue survives lightness nudges.
        for (const char *hex : {"#1a1b26", "#7aa2f7", "#e0af68", "#ffffff", "#000000", "#fdf6e3"}) {
            const QColor c = QColor::fromString(QLatin1String(hex));
            const QColor rt = Theme::oklchNudge(c, 0);
            check(qAbs(rt.red() - c.red()) <= 1 && qAbs(rt.green() - c.green()) <= 1 && qAbs(rt.blue() - c.blue()) <= 1,
                  "oklch round-trip");
        }
        const QColor blue(QStringLiteral("#7aa2f7"));
        const QColor bluer = Theme::oklchNudge(blue, 0.08);
        check(bluer.lightnessF() > blue.lightnessF() && qAbs(bluer.hsvHue() - blue.hsvHue()) <= 6, "oklch blue stays blue");
        const QColor yellow(QStringLiteral("#e0af68"));
        const QColor yd = Theme::oklchNudge(yellow, -0.1);
        check(yd.value() < yellow.value() && qAbs(yd.hsvHue() - yellow.hsvHue()) <= 6, "oklch yellow darkens in hue");
    }
    {
        // Popup colours, read the way Omarchy's Color.qml reads shell.toml.
        check(Theme::parseShellColor(QStringLiteral("rgba(33ccffee)")) == QColor(QStringLiteral("#33ccff")), "shell colour: rgba()");
        check(Theme::parseShellColor(QStringLiteral("rgb(7aa2f7)")) == QColor(QStringLiteral("#7aa2f7")), "shell colour: rgb()");
        check(Theme::parseShellColor(QStringLiteral("#7aa2f7")) == QColor(QStringLiteral("#7aa2f7")), "shell colour: #hex");
        check(Theme::parseShellColor(QStringLiteral("0xee33ccff")) == QColor(QStringLiteral("#33ccff")), "shell colour: 0xAARRGGBB");
        check(!Theme::parseShellColor(QStringLiteral("")).isValid() && !Theme::parseShellColor(QStringLiteral("45deg")).isValid()
                  && !Theme::parseShellColor(QStringLiteral("hyprland.active-border")).isValid(),
              "shell colour: nothing usable is invalid");
        const QHash<QString, QString> sh = Theme::parseShellToml(QStringLiteral(
            "# comment\n[hyprland]\nactive-border            = \"rgba(33ccffee) rgba(00ff99ee) 45deg\"  # gradient\n"
            "[popups]\nbackground = \"#1a1b26\"\nbackground-alpha = 1.0\nborder = \"hyprland.active-border\"\nborder-alpha = 0.5\n"
            "# border-width = 2\n[font]\nbase-size = 12\n"));
        check(sh.value(QStringLiteral("popups.border")) == QLatin1String("hyprland.active-border")
                  && sh.value(QStringLiteral("hyprland.active-border")) == QLatin1String("rgba(33ccffee) rgba(00ff99ee) 45deg")
                  && sh.value(QStringLiteral("popups.border-alpha")) == QLatin1String("0.5")
                  && sh.value(QStringLiteral("font.base-size")) == QLatin1String("12")
                  && !sh.contains(QStringLiteral("popups.border-width")),
              "shell.toml parser: sections, quoted and bare values, comments");
        const QHash<QString, QColor> pal{{QStringLiteral("foreground"), QColor(QStringLiteral("#a9b1d6"))},
                                         {QStringLiteral("accent"), QColor(QStringLiteral("#7aa2f7"))},
                                         {QStringLiteral("background"), QColor(QStringLiteral("#1a1b26"))}};
        check(Theme::resolveShellColor(QStringLiteral("hyprland.active-border"), sh, pal) == QColor(QStringLiteral("#33ccff")),
              "shell colour: popups.border -> hyprland.active-border -> first gradient stop");
        check(Theme::resolveShellColor(QStringLiteral("accent"), sh, pal) == QColor(QStringLiteral("#7aa2f7"))
                  && Theme::resolveShellColor(QStringLiteral("text"), sh, pal) == QColor(QStringLiteral("#a9b1d6")),
              "shell colour: palette roles (accent, text = foreground)");
        const QHash<QString, QString> loop{{QStringLiteral("a.x"), QStringLiteral("b.y")}, {QStringLiteral("b.y"), QStringLiteral("a.x")}};
        check(!Theme::resolveShellColor(QStringLiteral("a.x"), loop, pal).isValid(), "shell colour: a role loop ends instead of hanging");
    }
    check(parseDuration(QStringLiteral("90")) == 90, "duration seconds");
    check(parseDuration(QStringLiteral("1:02:03")) == 3723, "duration hms");
    check(parseDuration(QStringLiteral("12:34")) == 754, "duration ms");
    check(parsePublished(QStringLiteral("Wed, 10 Jun 2026 12:00:00 +0000")) > 0, "rfc2822");
    check(parsePublished(QStringLiteral("2026-01-02T00:00:00Z")) > 0, "iso");

    const QByteArray rss = R"(<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:content="http://purl.org/rss/1.0/modules/content/"
     xmlns:media="http://search.yahoo.com/mrss/">
<channel>
<title>Sample Show</title>
<itunes:author>Ada</itunes:author>
<itunes:image href="https://example.com/cover.jpg"/>
<item>
  <title>Newest</title>
  <guid>n</guid>
  <pubDate>Wed, 10 Jun 2026 12:00:00 +0000</pubDate>
  <itunes:duration>1:02:03</itunes:duration>
  <description>Short blurb</description>
  <content:encoded><![CDATA[<p>Full <b>episode</b> notes.</p>]]></content:encoded>
  <itunes:image href="https://example.com/ep-n.jpg"/>
  <enclosure url="https://example.com/n.mp3" type="audio/mpeg"/>
</item>
<item>
  <title>Middle</title>
  <guid>m</guid>
  <pubDate>Wed, 03 Jun 2026 12:00:00 +0000</pubDate>
  <itunes:duration>90</itunes:duration>
  <itunes:summary>Middle summary only</itunes:summary>
  <media:thumbnail url="https://example.com/ep-m.jpg"/>
  <enclosure url="https://example.com/m.mp3" type="audio/mpeg"/>
</item>
<item>
  <title>Older</title>
  <guid>o</guid>
  <pubDate>Wed, 27 May 2026 12:00:00 +0000</pubDate>
  <enclosure url="https://example.com/o.m4a" type="audio/mp4"/>
</item>
<item>
  <title>Clip</title>
  <guid>v</guid>
  <pubDate>Fri, 01 May 2026 12:00:00 +0000</pubDate>
  <enclosure url="https://example.com/v.mp4" type="video/mp4"/>
</item>
</channel>
</rss>)";

    QString error;
    const auto parsed = parseFeed(rss, QUrl(QStringLiteral("https://example.com/feed.xml")), &error);
    check(parsed.has_value(), "parse rss");
    if (parsed) {
        check(parsed->title == QStringLiteral("Sample Show"), "show title");
        check(parsed->author == QStringLiteral("Ada"), "author");
        check(parsed->imageUrl == QStringLiteral("https://example.com/cover.jpg"), "cover");
        check(parsed->episodes.size() == 3, "audio episodes only");
        if (parsed->episodes.size() == 3) {
            check(parsed->episodes.at(0).title == QStringLiteral("Newest"), "newest title");
            check(parsed->episodes.at(0).durationSecs == 3723, "newest duration");
            check(parsed->episodes.at(0).published > parsed->episodes.at(1).published, "date order");
            check(parsed->episodes.at(0).description.contains(QStringLiteral("Full episode notes")),
                  "content:encoded preferred");
            check(parsed->episodes.at(0).imageUrl == QStringLiteral("https://example.com/ep-n.jpg"),
                  "itunes episode image");
            check(parsed->episodes.at(1).description == QStringLiteral("Middle summary only"),
                  "itunes summary");
            check(parsed->episodes.at(1).imageUrl == QStringLiteral("https://example.com/ep-m.jpg"),
                  "media thumbnail");
            check(parsed->episodes.at(2).description.isEmpty(), "missing description stays empty");
            check(parsed->episodes.at(2).audioUrl.endsWith(QStringLiteral("o.m4a")), "m4a kept");
        }
    }

    const auto html = parseFeed("<!DOCTYPE html><html></html>", QUrl(), &error);
    check(!html.has_value(), "reject html");

    const auto atom = parseFeed(R"(<feed xmlns="http://www.w3.org/2005/Atom">
<title>Atom Show</title>
<entry>
<title>One</title>
<id>one</id>
<published>2026-01-02T00:00:00Z</published>
<link rel="enclosure" type="audio/mpeg" href="https://example.com/one.mp3"/>
</entry>
</feed>)",
                                QUrl(QStringLiteral("https://example.com/atom")), &error);
    check(atom.has_value() && atom->episodes.size() == 1, "atom enclosure");

    const QStringList opml = parseOpml(R"(<opml version="2.0"><body>
<outline text="A" xmlUrl="https://example.com/a.xml"/>
<outline text="Folder">
  <outline text="B" xmlUrl="https://example.com/b.xml"/>
</outline>
<outline text="A again" xmlUrl="https://example.com/a.xml"/>
</body></opml>)",
                                        &error);
    check(opml.size() == 2, "opml dedupes and nests");

    QTemporaryDir dir;
    check(dir.isValid(), "temp dir");
    Library library(dir.filePath(QStringLiteral("library.db")));
    check(library.isOpen(), "open library");
    if (parsed && library.isOpen()) {
        const qint64 showId = library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
        check(showId != 0, "insert show");
        const auto again = library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
        check(again == showId, "refresh keeps the show");
        {
            const QString coverPath = dir.filePath(QStringLiteral("cover.jpg"));
            QFile cover(coverPath);
            check(cover.open(QIODevice::WriteOnly) && cover.write("fake-cover-bytes-for-cache-test") > 0,
                  "write fake cover");
            cover.close();
            library.setShowImage(showId, parsed->imageUrl, coverPath);
            check(library.showImage(showId) == coverPath, "show image path stored");
            library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
            check(library.showImage(showId) == coverPath, "same cover URL keeps image_path");
            ParsedShow moved = *parsed;
            moved.imageUrl = QStringLiteral("https://example.com/cover-v2.jpg");
            library.upsertShow(QStringLiteral("https://example.com/feed.xml"), moved);
            check(library.showImage(showId).isEmpty(), "new cover URL clears image_path");
            check(!QFileInfo::exists(coverPath), "stale cover file removed");
            // Restore original URL for later episode checks.
            library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
        }
        const auto episodes = library.episodes(showId);
        check(episodes.size() == 3, "stored episodes");
        if (episodes.size() == 3) {
            check(episodes.at(0).description.contains(QStringLiteral("Full episode notes")),
                  "stored description");
            check(episodes.at(0).imageUrl == QStringLiteral("https://example.com/ep-n.jpg"),
                  "stored episode image");
            {
                const qint64 epId = episodes.at(0).id;
                const QString epCover = dir.filePath(QStringLiteral("ep-n.jpg"));
                QFile epFile(epCover);
                check(epFile.open(QIODevice::WriteOnly) && epFile.write("episode-cover-bytes") > 0,
                      "write episode cover");
                epFile.close();
                library.setEpisodeImage(epId, episodes.at(0).imageUrl, epCover);
                check(library.episode(epId).imagePath == epCover, "episode image path stored");
                library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
                check(library.episode(epId).imagePath == epCover,
                      "same episode image URL keeps image_path");
                check(QFileInfo::exists(epCover), "episode cover file kept");
                ParsedShow movedEp = *parsed;
                movedEp.episodes[0].imageUrl = QStringLiteral("https://example.com/ep-n-v2.jpg");
                library.upsertShow(QStringLiteral("https://example.com/feed.xml"), movedEp);
                check(library.episode(epId).imagePath.isEmpty(),
                      "new episode image URL clears image_path");
                check(!QFileInfo::exists(epCover), "stale episode cover file removed");
                library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
            }
            {
                // Force-reload contract: drop the file and image_path, keep the URL,
                // and a same-URL upsert must not put the cached path back.
                const QString coverPath = dir.filePath(QStringLiteral("cover-force.jpg"));
                QFile cover(coverPath);
                check(cover.open(QIODevice::WriteOnly) && cover.write("force-show-cover") > 0,
                      "write show cover to force-clear");
                cover.close();
                library.setShowImage(showId, parsed->imageUrl, coverPath);
                check(library.showImageUrl(showId) == parsed->imageUrl, "show image url stored");
                library.clearShowImagePath(showId);
                check(library.showImage(showId).isEmpty(), "force-clear drops show image_path");
                check(library.showImageUrl(showId) == parsed->imageUrl, "force-clear keeps show image url");
                check(!QFileInfo::exists(coverPath), "force-clear removes show cover file");
                library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
                check(library.showImage(showId).isEmpty(), "same cover URL stays empty after force-clear");

                const qint64 epId = episodes.at(0).id;
                const QString epCover = dir.filePath(QStringLiteral("ep-force.jpg"));
                QFile epFile(epCover);
                check(epFile.open(QIODevice::WriteOnly) && epFile.write("force-episode-cover") > 0,
                      "write episode cover to force-clear");
                epFile.close();
                const QString epUrl = library.episode(epId).imageUrl;
                library.setEpisodeImage(epId, epUrl, epCover);
                library.clearEpisodeImagePath(epId);
                check(library.episode(epId).imagePath.isEmpty(), "force-clear drops episode image_path");
                check(library.episode(epId).imageUrl == epUrl, "force-clear keeps episode image url");
                check(!QFileInfo::exists(epCover), "force-clear removes episode cover file");
                library.upsertShow(QStringLiteral("https://example.com/feed.xml"), *parsed);
                check(library.episode(epId).imagePath.isEmpty(),
                      "same episode image URL stays empty after force-clear");
            }
            const qint64 newest = episodes.at(0).id;
            const qint64 middle = episodes.at(1).id;
            const qint64 older = episodes.at(2).id;
            check(library.markOlderPlayed(middle) == 1, "mark older");
            check(!library.episode(newest).played, "newest stays unplayed");
            check(!library.episode(middle).played, "chosen episode stays unplayed");
            check(library.episode(older).played, "older is played");
            check(library.markNewerPlayed(middle) == 1, "mark newer");
            check(library.episode(newest).played, "newer is played");
            check(library.markPlayed(middle, true) == 1, "mark one");
            check(library.markAllPlayed(showId) == 0, "mark all finds nothing left");
            check(library.markPlayed(middle, false) == 1, "mark unplayed");
            check(library.markAllPlayed(showId) == 1, "mark all");
            check(library.episode(middle).played, "all played");
            check(library.adjacent(middle, true, false) == older, "adjacent older");
            check(library.adjacent(middle, false, false) == newest, "adjacent newer");
            library.setPosition(middle, 123456);
            check(library.episode(middle).positionMs == 123456, "persist position_ms");
            library.setPosition(middle, 0);
            check(library.episode(middle).positionMs == 0, "clear position_ms");
            // Resume clamp: near-end progress restarts; mid progress is kept for Load.
            library.setPosition(newest, 3723 * 1000 - 1000);
            check(library.episode(newest).positionMs == 3723 * 1000 - 1000, "near-end position stored");
            library.setPosition(newest, 900000);
            check(library.episode(newest).positionMs == 900000, "mid position stored for resume");
            library.setLastPlayedEpisodeId(middle);
            check(library.lastPlayedEpisodeId() == middle, "persist lastPlayed episode id");
            library.setLastPlayedEpisodeId(0);
            check(library.exploreCountry().isEmpty(), "explore country defaults to automatic");
            library.setExploreCountry(QStringLiteral("GB"));
            check(library.exploreCountry() == QStringLiteral("gb"), "explore country persists");
            library.setExploreCountry(QString());
            check(library.exploreCountry().isEmpty(), "explore country back to automatic");
            check(library.updateCheckEnabled(), "updates.check defaults on");
            library.setUpdateCache(QStringLiteral("failed"), QString(), QString(), 10);
            check(library.updateResult() == QStringLiteral("failed"), "update failure cached");
            check(library.updateCheckedAt() == 10, "update check time cached");
            check(library.updateLatest().isEmpty() && library.updateUrl().isEmpty(), "failed check clears version");
            library.setUpdateCache(QStringLiteral("available"), QStringLiteral("0.2.0"),
                                   QStringLiteral("https://github.com/allandehn/omaear/releases/tag/v0.2.0"), 20);
            check(library.updateLatest() == QStringLiteral("0.2.0"), "update version cached");
            check(library.updateUrl().endsWith(QStringLiteral("v0.2.0")), "update url cached");
            check(library.updateCheckedAt() == 20, "update check time replaced");
            check(library.updateCheckEnabled(), "cache write leaves updates.check on");
            check(library.lastPlayedEpisodeId() == 0, "clear lastPlayed episode id");
            library.setLastPlayedEpisodeId(newest);
            check(library.lastPlayedEpisodeId() == newest, "set lastPlayed for restore");
            {
                // A long-lived player notices its library file was replaced (fresh install).
                {
                    // Force refresh: cover URLs leave the HTTP disk cache, other entries stay.
                    QTemporaryDir dir;
                    QNetworkDiskCache cache;
                    cache.setCacheDirectory(dir.path());
                    auto put = [&cache](const QString &u) {
                        QNetworkCacheMetaData md;
                        md.setUrl(QUrl(u));
                        md.setSaveToDisk(true);
                        md.setExpirationDate(QDateTime::currentDateTimeUtc().addDays(30));
                        md.setLastModified(QDateTime::currentDateTimeUtc().addDays(-1));
                        md.setRawHeaders({{"Content-Type", "image/jpeg"}, {"Cache-Control", "max-age=14204435"}});
                        if (QIODevice *d = cache.prepare(md)) { d->write("jpeg"); cache.insert(d); }
                    };
                    const QString cover = QStringLiteral("https://is1-ssl.mzstatic.com/image/thumb/a/b/600x600bb.jpg");
                    const QString tile = QStringLiteral("https://is1-ssl.mzstatic.com/image/thumb/a/b/400x400bb.jpg");
                    const QString other = QStringLiteral("https://is1-ssl.mzstatic.com/image/thumb/c/d/400x400bb.jpg");
                    put(tile); put(other);
                    const bool stored = cache.metaData(QUrl(tile)).isValid() && cache.metaData(QUrl(other)).isValid();
                    const QStringList v = coverUrlVariants(cover);
                    check(v.contains(tile) && v.contains(cover), "cover URL variants include the 400px tile URL");
                    const int removed = removeFromCache(&cache, v);
                    check(stored && removed == 1 && !cache.metaData(QUrl(tile)).isValid() && cache.metaData(QUrl(other)).isValid(),
                          "force refresh removes only the listed cover URLs from the disk cache");
                }
                const QString probe = QDir::tempPath() + QStringLiteral("/omaear-identity-probe");
                QFile::remove(probe);
                check(Library::fileIdentity(probe).isEmpty(), "file identity: missing file has none");
                { QFile f(probe); if (f.open(QIODevice::WriteOnly)) f.write("a"); }
                const QString first = Library::fileIdentity(probe);
                QFile keep(probe);
                const bool held = keep.open(QIODevice::ReadOnly); // like an open sqlite handle
                QFile::remove(probe);
                { QFile f(probe); if (f.open(QIODevice::WriteOnly)) f.write("b"); }
                check(held && !first.isEmpty() && Library::fileIdentity(probe) != first,
                      "file identity: deleted and recreated file differs");
                QFile::remove(probe);
            }
        }

        ParsedShow caughtUp = *parsed;
        caughtUp.title = QStringLiteral("Caught Up");
        for (auto &episode : caughtUp.episodes)
            episode.guid += QStringLiteral("-b");
        const qint64 caughtId = library.upsertShow(QStringLiteral("https://example.com/caught.xml"), caughtUp);
        library.markAllPlayed(caughtId);

        ParsedShow fresh = *parsed;
        fresh.title = QStringLiteral("Fresh");
        fresh.episodes[0].published = parsed->episodes.at(0).published + 86400;
        for (auto &episode : fresh.episodes)
            episode.guid += QStringLiteral("-c");
        library.upsertShow(QStringLiteral("https://example.com/fresh.xml"), fresh);

        if (!library.episodes(showId).isEmpty())
            library.markPlayed(library.episodes(showId).at(0).id, false);
        const auto shelf = library.shows();
        check(shelf.size() == 3, "three shows");
        if (shelf.size() == 3) {
            check(shelf.at(0).title == QStringLiteral("Fresh"), "unheard newest first");
            check(shelf.at(0).unheard > 0, "fresh is unheard");
            check(shelf.at(2).unheard == 0, "caught up is last");
        }
        check(library.shelfView() == QStringLiteral("gallery"), "shelf starts as gallery");
        check(library.shelfColumns() == 6, "shelf starts at six columns");
        library.setShelfView(QStringLiteral("list"));
        library.setShelfColumns(0);
        check(library.shelfView() == QStringLiteral("list"), "shelf list");
        check(library.shelfColumns() == 1, "columns stay at least one");
        library.setShelfColumns(1);
        check(library.shelfColumns() == 1, "one column is allowed");
        library.setShelfColumns(20);
        check(library.shelfColumns() == 10, "columns stay at most ten");
        library.setShelfColumns(10);
        check(library.shelfColumns() == 10, "ten columns is allowed");
        check(library.listCoverSize() == 2, "list cover starts two steps up (Episodes template)");
        // Older libraries kept separate keys (Episodes first, then Shelf); a saved 1 stands in for one.
        library.markCacheMigrationDone(QStringLiteral("shelf.listSize"));
        check(library.listCoverSize() == 1, "an old saved list size carries over to the shared one");
        library.setListCoverSize(3);
        check(library.listCoverSize() == 3, "the shared size wins over the old keys once set");
        library.setListCoverSize(-3);
        check(library.listCoverSize() == 0, "list cover stays at least the smallest");
        library.setListCoverSize(9);
        check(library.listCoverSize() == 4, "list cover stays at most the largest");
        check(library.shelfShowAll(), "shelf eye starts open");
        check(library.episodeShowAll(), "episode eye starts open");
        library.setShelfShowAll(false);
        library.setEpisodeShowAll(false);
        check(!library.shelfShowAll(), "shelf eye closes");
        check(!library.episodeShowAll(), "episode eye closes");
        library.setShelfShowAll(true);
        library.setEpisodeShowAll(true);
        check(library.shelfShowAll(), "shelf eye reopens");
        check(library.episodeShowAll(), "episode eye reopens");
        int unplayed = 0;
        for (const auto &show : library.shows()) {
            for (const auto &episode : library.episodes(show.id)) {
                if (!episode.played)
                    ++unplayed;
            }
        }
        check(unplayed > 0, "library still has unplayed episodes");
        check(library.markLibraryPlayed() == unplayed, "mark every show and episode played");
        for (const auto &show : library.shows()) {
            check(show.unheard == 0, "show is caught up after library mark");
            for (const auto &episode : library.episodes(show.id))
                check(episode.played, "episode is played after library mark");
        }
        check(library.markLibraryPlayed() == 0, "mark library again finds nothing left");
    }

    {
        QTemporaryDir qdir;
        Library qlib(qdir.filePath(QStringLiteral("queue.db")));
        QString qerr;
        const auto parsed = parseFeed(rss, QUrl(QStringLiteral("https://example.com/q.xml")), &qerr);
        if (parsed) {
            const qint64 showId = qlib.upsertShow(QStringLiteral("https://example.com/q.xml"), *parsed);
            const auto eps = qlib.episodes(showId);
            check(eps.size() >= 3, "queue fixture episodes");
            if (eps.size() >= 3) {
                const qint64 a = eps.at(0).id, b = eps.at(1).id, c = eps.at(2).id;
                check(qlib.queueIds().isEmpty(), "queue starts empty");
                qlib.addToQueue(a, false);
                qlib.addToQueue(b, false);
                qlib.addToQueue(c, true);
                check(qlib.queueIds() == QList<qint64>({c, a, b}), "queue add / play next order");
                check(qlib.isQueued(a) && qlib.queueHead() == c, "queue head and membership");
                qlib.addToQueue(a, false);
                check(qlib.queueIds() == QList<qint64>({c, b, a}), "re-add moves to end, no duplicate");
                qlib.setQueueOrder({a, c, b});
                check(qlib.queueIds() == QList<qint64>({a, c, b}), "queue reorder persists");
                check(qlib.removeFromQueue(c) && !qlib.isQueued(c), "queue remove");
                check(!qlib.removeFromQueue(c), "queue remove twice is a no-op");
                // Lifetime: queue is now {a, b}.
                qlib.markPlayed(a, true);
                check(qlib.isQueued(a), "library mark alone keeps it queued");
                check(qlib.queueAfter(a) == b, "next after a queued item is the one after it");
                check(qlib.queueAfter(b) == 0, "nothing after the last queued item");
                check(qlib.queueAfter(c) == a, "unqueued current goes to the queue top");
                qlib.addToQueue(c, false); // {a, b, c}
                check(qlib.finishQueued(b) == c, "finishing b plays c (picked before removal)");
                check(qlib.queueIds() == QList<qint64>({a, c}), "finish removes only the finished one");
                check(qlib.finishQueued(b) == a, "finishing an unqueued episode plays the top");
                check(qlib.queueIds() == QList<qint64>({a, c}), "finishing an unqueued episode removes nothing");
                check(qlib.finishQueued(c) == 0 && qlib.queueIds() == QList<qint64>({a}),
                      "finishing the last item falls back (0) and removes it");
                qlib.addToQueue(b, false); // {a, b}
                const auto rows = qlib.queue();
                check(rows.size() == 2 && rows.at(0).showTitle == QStringLiteral("Sample Show"), "queue rows carry show title");
                qlib.removeShow(showId);
                check(qlib.queueIds().isEmpty(), "removing a show drops its queued episodes");
                qlib.clearQueue();
            }
        }
    }

    {
        QTemporaryDir covers;
        const QString path = covers.filePath(QStringLiteral("episode art.jpg"));
        QFile file(path);
        check(file.open(QIODevice::WriteOnly) && file.write("x") > 0, "write cover for url");
        file.close();
        const QString src = localCoverSource(path);
        check(src.startsWith(QStringLiteral("image://covers/")), "cover url scheme");
        // Same slash-stripping QQuick applies when it asks the image provider.
        QString id = QUrl(src).toString(QUrl::RemoveScheme | QUrl::RemoveAuthority).mid(1);
        id = QUrl::fromPercentEncoding(id.toUtf8());
        if (!id.startsWith(QLatin1Char('/')) && QFileInfo::exists(QLatin1Char('/') + id))
            id.prepend(QLatin1Char('/'));
        check(id == path, "cover url round trip");
        check(localCoverSource(QString()).isEmpty(), "missing cover has no url");
    }

    {
        check(Explore::normalizeFeedUrl(QStringLiteral("https://www.Example.com/feed/"))
                  == Explore::normalizeFeedUrl(QStringLiteral("http://example.com/feed")), "explore url normalize");
        check(Explore::normalizeFeedUrl(QStringLiteral("https://a.com/x?format=xml"))
                  != Explore::normalizeFeedUrl(QStringLiteral("https://a.com/x")), "explore url keeps query");
        const QByteArray search = R"({"resultCount":1,"results":[{"wrapperType":"track","kind":"podcast",
            "collectionId":173001861,"artistName":"Dan Carlin","collectionName":"Hardcore History",
            "collectionViewUrl":"https://podcasts.apple.com/x","feedUrl":"https://feeds.example.com/h",
            "artworkUrl600":"https://img/600.jpg","releaseDate":"2026-07-31T18:02:00Z","trackCount":13,
            "primaryGenreName":"History"}]})";
        const auto rows = Explore::parseSearch(search);
        check(rows.size() == 1 && rows.at(0).id == 173001861 && rows.at(0).feedUrl == QStringLiteral("https://feeds.example.com/h")
                  && rows.at(0).trackCount == 13 && rows.at(0).released > 0 && rows.at(0).genre == QStringLiteral("History"),
              "explore parse search");
        const QByteArray top = R"({"feed":{"entry":[{"im:name":{"label":"Mørkeland"},"im:artist":{"label":"A"},
            "im:image":[{"label":"https://x/55x55bb.png"},{"label":"https://x/170x170bb.png"}],
            "id":{"label":"https://podcasts.apple.com/dk/podcast/id1","attributes":{"im:id":"1"}},
            "category":{"attributes":{"label":"True Crime"}}}]}})";
        const auto chart = Explore::parseTopChart(top);
        check(chart.size() == 1 && chart.at(0).id == 1 && chart.at(0).cover == QStringLiteral("https://x/600x600bb.png")
                  && chart.at(0).genre == QStringLiteral("True Crime") && chart.at(0).feedUrl.isEmpty(),
              "explore parse top chart");
        int unknown = 0;
        for (const QString &code : Explore::storefronts())
            unknown += QLocale::codeToTerritory(code) == QLocale::AnyTerritory ? 1 : 0;
        check(unknown == 0 && Explore::storefronts().size() >= 40, "explore storefront codes map to territories");
    }

    {
        // Region swap: visit 1 shows the chart cover; visit 2 reads the cache
        // after lookup. The lookup URL must not replace a cover already shown.
        const QByteArray top = R"({"feed":{"entry":[
            {"im:name":{"label":"One"},"im:artist":{"label":"A"},
             "im:image":[{"label":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/mza_1.jpg/55x55bb.png"},
                         {"label":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/mza_1.jpg/170x170bb.png"}],
             "id":{"label":"https://podcasts.apple.com/sg/podcast/id11","attributes":{"im:id":"11"}},
             "category":{"attributes":{"label":"Society"}}},
            {"im:name":{"label":"Two"},"im:artist":{"label":"B"},
             "im:image":[{"label":"https://feeds.example.com/covers/two.png"}],
             "id":{"label":"https://podcasts.apple.com/sg/podcast/id12","attributes":{"im:id":"12"}}},
            {"im:name":{"label":"Three"},"im:artist":{"label":"C"},
             "id":{"label":"https://podcasts.apple.com/sg/podcast/id13","attributes":{"im:id":"13"}}},
            {"im:name":{"label":"Four"},"im:artist":{"label":"D"},
             "im:image":[{"label":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/cd/mza_4.jpg/170x170bb.png"}],
             "id":{"label":"https://podcasts.apple.com/sg/podcast/id14","attributes":{"im:id":"14"}},
             "category":{"attributes":{"label":"News"}}},
            {"im:name":{"label":"Five"},"im:artist":{"label":"E"},
             "im:image":[{"label":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ef/mza_5.jpg/170x170bb.png"}],
             "im:releaseDate":{"label":"2020-01-01T00:00:00Z"},
             "id":{"label":"https://podcasts.apple.com/sg/podcast/id15","attributes":{"im:id":"15"}},
             "category":{"attributes":{"label":"History"}}}
        ]}})";
        const QByteArray lookup = R"({"resultCount":5,"results":[
            {"wrapperType":"track","kind":"podcast","collectionId":11,"artistName":"A","collectionName":"One",
             "artworkUrl600":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/mza_1.jpg/600x600bb.jpg",
             "feedUrl":"https://feeds.example.com/one","trackCount":40,
             "releaseDate":"2026-07-31T18:02:00Z","primaryGenreName":"News"},
            {"wrapperType":"track","kind":"podcast","collectionId":12,"artistName":"B","collectionName":"Two",
             "artworkUrl600":"https://cdn.example.com/two-art.jpg",
             "feedUrl":"https://feeds.example.com/two","trackCount":2,"primaryGenreName":"Comedy"},
            {"wrapperType":"track","kind":"podcast","collectionId":13,"artistName":"C","collectionName":"Three",
             "artworkUrl600":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/gh/mza_3.jpg/600x600bb.jpg",
             "feedUrl":"https://feeds.example.com/three","trackCount":7,"primaryGenreName":"Business"},
            {"wrapperType":"track","kind":"podcast","collectionId":15,"artistName":"E","collectionName":"Five",
             "artworkUrl600":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ef/mza_5.jpg/600x600bb.jpg",
             "feedUrl":"https://feeds.example.com/five","trackCount":9,
             "releaseDate":"2026-08-01T00:00:00Z","primaryGenreName":"Society"},
            {"wrapperType":"track","kind":"podcast","collectionId":99,"artistName":"Z","collectionName":"Extra",
             "artworkUrl600":"https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/zz/mza_9.jpg/600x600bb.jpg",
             "feedUrl":"https://feeds.example.com/extra","trackCount":1}
        ]})";
        auto chart = Explore::parseTopChart(top);
        const auto looked = Explore::parseSearch(lookup);
        check(chart.size() == 5 && looked.size() == 5, "cover identity fixture parses");
        if (chart.size() == 5 && looked.size() == 5) {
            auto byId = [](const QList<ExploreResult> &rows, qint64 id) {
                for (const auto &r : rows)
                    if (r.id == id)
                        return r;
                return ExploreResult{};
            };
            chart[4].feedUrl = QStringLiteral("https://old.example/five.xml");
            const QString applePng = QStringLiteral(
                "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/mza_1.jpg/600x600bb.png");
            const QString appleJpg = QStringLiteral(
                "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/mza_1.jpg/600x600bb.jpg");
            check(chart.at(0).cover == applePng && byId(looked, 11).cover == appleJpg
                      && applePng.left(applePng.size() - 3) == appleJpg.left(appleJpg.size() - 3),
                  "fixture: Apple chart png and lookup jpg differ only by extension");
            auto merged = chart;
            Explore::mergeLookup(merged, looked);
            int shownChanged = 0, emptyFilled = 0;
            bool sameRows = merged.size() == chart.size();
            for (int i = 0; i < chart.size() && i < merged.size(); ++i) {
                sameRows = sameRows && merged.at(i).id == chart.at(i).id && merged.at(i).title == chart.at(i).title;
                if (chart.at(i).cover.isEmpty())
                    emptyFilled += merged.at(i).cover.isEmpty() ? 0 : 1;
                else if (merged.at(i).cover != chart.at(i).cover)
                    ++shownChanged;
            }
            check(sameRows && shownChanged == 0 && emptyFilled == 1,
                  "second visit reuses every cover the first visit showed");
            check(merged.at(0).cover == applePng && merged.at(0).feedUrl == QStringLiteral("https://feeds.example.com/one")
                      && merged.at(0).trackCount == 40 && merged.at(0).genre == QStringLiteral("Society")
                      && merged.at(0).released == byId(looked, 11).released && merged.at(0).released > 0,
                  "lookup fills feed, count and date and leaves the chart cover and genre");
            check(merged.at(1).cover == QStringLiteral("https://feeds.example.com/covers/two.png")
                      && byId(looked, 12).cover == QStringLiteral("https://cdn.example.com/two-art.jpg")
                      && merged.at(1).genre == QStringLiteral("Comedy")
                      && merged.at(1).feedUrl == QStringLiteral("https://feeds.example.com/two")
                      && merged.at(1).trackCount == 2,
                  "a non-Apple cover is not replaced by the lookup URL");
            check(chart.at(2).cover.isEmpty() && merged.at(2).cover == byId(looked, 13).cover
                      && merged.at(2).feedUrl == QStringLiteral("https://feeds.example.com/three")
                      && merged.at(2).genre == QStringLiteral("Business") && merged.at(2).trackCount == 7,
                  "a chart row with no art takes the lookup cover");
            check(merged.at(3).cover == chart.at(3).cover && merged.at(3).feedUrl.isEmpty()
                      && merged.at(3).trackCount == 0 && merged.at(3).genre == QStringLiteral("News"),
                  "a chart row the lookup missed is unchanged");
            check(merged.at(4).cover == chart.at(4).cover
                      && merged.at(4).feedUrl == QStringLiteral("https://feeds.example.com/five")
                      && merged.at(4).trackCount == 9 && merged.at(4).genre == QStringLiteral("History")
                      && chart.at(4).released > 0 && merged.at(4).released == byId(looked, 15).released
                      && merged.at(4).released != chart.at(4).released,
                  "lookup replaces feed and date; chart cover and genre stay");
            {
                QList<ExploreResult> clearFeed = chart.mid(0, 1);
                QList<ExploreResult> emptyLookup = QList<ExploreResult>{byId(looked, 11)};
                clearFeed[0].feedUrl = QStringLiteral("https://old.example/feed");
                emptyLookup[0].feedUrl.clear();
                Explore::mergeLookup(clearFeed, emptyLookup);
                check(clearFeed.at(0).feedUrl.isEmpty() && clearFeed.at(0).cover == applePng,
                      "an empty lookup feed still clears, and the cover stays");
            }
            // Force refresh drops the URL on screen (600 and the 400px tile rewrite),
            // not a sibling extension and not some other host's file.
            const QString shown = merged.at(0).cover;
            QString tile = shown;
            tile.replace(QStringLiteral("/600x600bb."), QStringLiteral("/400x400bb."));
            const QStringList variants = coverUrlVariants(shown);
            const QString plain = merged.at(1).cover;
            check(tile == QStringLiteral("https://is1-ssl.mzstatic.com/image/thumb/Podcasts/v4/ab/mza_1.jpg/400x400bb.png")
                      && variants.contains(shown) && variants.contains(tile) && !variants.contains(appleJpg)
                      && coverUrlVariants(plain) == QStringList{plain},
                  "cover variants follow the shown extension and do not invent another");
            QTemporaryDir dir;
            QNetworkDiskCache cache;
            cache.setCacheDirectory(dir.path());
            auto put = [&cache](const QString &u) {
                QNetworkCacheMetaData md;
                md.setUrl(QUrl(u));
                md.setSaveToDisk(true);
                md.setExpirationDate(QDateTime::currentDateTimeUtc().addDays(30));
                md.setLastModified(QDateTime::currentDateTimeUtc().addDays(-1));
                md.setRawHeaders({{"Content-Type", "image/jpeg"}, {"Cache-Control", "max-age=14204435"}});
                if (QIODevice *d = cache.prepare(md)) { d->write("jpeg"); cache.insert(d); }
            };
            const QString other = QStringLiteral("https://is1-ssl.mzstatic.com/image/thumb/c/d/400x400bb.jpg");
            put(tile);
            put(shown);
            put(appleJpg);
            put(other);
            put(plain);
            const bool stored = cache.metaData(QUrl(tile)).isValid() && cache.metaData(QUrl(shown)).isValid()
                && cache.metaData(QUrl(appleJpg)).isValid() && cache.metaData(QUrl(plain)).isValid();
            const int removed = removeFromCache(&cache, variants);
            const int removedPlain = removeFromCache(&cache, coverUrlVariants(plain));
            check(stored && removed == 2 && removedPlain == 1
                      && !cache.metaData(QUrl(tile)).isValid() && !cache.metaData(QUrl(shown)).isValid()
                      && !cache.metaData(QUrl(plain)).isValid()
                      && cache.metaData(QUrl(appleJpg)).isValid() && cache.metaData(QUrl(other)).isValid(),
                  "force refresh drops the shown cover URLs and leaves other ones");
        }
    }

    {
        // Cover fetches: a local mock counts HTTP requests. Tiles use the 400px
        // rewrite of the cover URL, the same way ExploreView does. No real network.
        QByteArray jpeg;
        {
            QImage img(8, 8, QImage::Format_RGB32);
            img.fill(Qt::red);
            QBuffer buf(&jpeg);
            check(buf.open(QIODevice::WriteOnly) && img.save(&buf, "JPEG", 90) && jpeg.size() > 32,
                  "cover probe jpeg encodes");
        }
        struct CoverProbeServer : QTcpServer {
            QByteArray body;
            int hits = 0;
            QStringList paths;
            QByteArray leftover;
            CoverProbeServer()
            {
                connect(this, &QTcpServer::newConnection, this, [this]() {
                    while (QTcpSocket *s = nextPendingConnection()) {
                        connect(s, &QTcpSocket::readyRead, this, [this, s]() {
                            leftover += s->readAll();
                            const int end = leftover.indexOf("\r\n\r\n") >= 0 ? leftover.indexOf("\r\n\r\n")
                                                                               : leftover.indexOf("\n\n");
                            if (end < 0)
                                return;
                            const QByteArray req = leftover;
                            leftover.clear();
                            const QString first = QString::fromLatin1(req.split('\n').value(0)).trimmed();
                            const QString path = first.section(QLatin1Char(' '), 1, 1);
                            ++hits;
                            paths << path;
                            const QString now = QLocale::c().toString(QDateTime::currentDateTimeUtc(),
                                                                     QStringLiteral("ddd, dd MMM yyyy hh:mm:ss"))
                                + QStringLiteral(" GMT");
                            const QString exp = QLocale::c().toString(QDateTime::currentDateTimeUtc().addDays(30),
                                                                     QStringLiteral("ddd, dd MMM yyyy hh:mm:ss"))
                                + QStringLiteral(" GMT");
                            QByteArray resp = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nCache-Control: public, max-age=14204435\r\nDate: ";
                            resp += now.toLatin1();
                            resp += "\r\nExpires: ";
                            resp += exp.toLatin1();
                            resp += "\r\nLast-Modified: Thu, 01 Jan 2026 00:00:00 GMT\r\nETag: \"cover-probe\"\r\nConnection: close\r\nContent-Length: ";
                            resp += QByteArray::number(body.size());
                            resp += "\r\n\r\n";
                            resp += body;
                            s->write(resp);
                            s->flush();
                            s->disconnectFromHost();
                        });
                        connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
                    }
                });
            }
        };
        CoverProbeServer server;
        server.body = jpeg;
        check(server.listen(QHostAddress::LocalHost, 0), "cover probe server listens");
        const QString origin = QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort());
        auto art = [&](const char *id, const char *ext) {
            return origin + QStringLiteral("/image/thumb/%1/600x600bb.%2").arg(QLatin1String(id), QLatin1String(ext));
        };
        auto tileOf = [](QString cover) {
            cover.replace(QStringLiteral("/600x600bb."), QStringLiteral("/400x400bb."));
            return cover;
        };
        auto tilesOf = [&](const QList<ExploreResult> &rows) {
            QStringList urls;
            for (const auto &r : rows)
                if (!r.cover.isEmpty())
                    urls << tileOf(r.cover);
            return urls;
        };
        auto overwriteCovers = [](QList<ExploreResult> rows, const QList<ExploreResult> &lookup) {
            QHash<qint64, QString> cover;
            for (const auto &r : lookup)
                if (!r.cover.isEmpty())
                    cover.insert(r.id, r.cover);
            for (auto &r : rows) {
                const auto it = cover.constFind(r.id);
                if (it != cover.constEnd())
                    r.cover = it.value();
            }
            return rows;
        };
        auto fetchAll = [](QNetworkAccessManager &nam, const QStringList &urls) {
            int ok = 0;
            for (const QString &u : urls) {
                QNetworkRequest req{QUrl(u)};
                QNetworkReply *reply = nam.get(req);
                QEventLoop loop;
                QTimer::singleShot(4000, &loop, &QEventLoop::quit);
                QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
                loop.exec();
                const QByteArray body = reply->readAll();
                if (reply->isFinished() && reply->error() == QNetworkReply::NoError
                    && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200
                    && !body.isEmpty())
                    ++ok;
                reply->deleteLater();
                QCoreApplication::processEvents();
            }
            return ok;
        };
        auto attachCache = [](QNetworkAccessManager &nam, const QString &path) {
            auto *cache = new QNetworkDiskCache(&nam);
            cache->setCacheDirectory(path);
            cache->setMaximumCacheSize(64LL * 1024 * 1024);
            nam.setCache(cache);
        };
        auto takeHits = [&]() {
            const int n = server.hits;
            server.hits = 0;
            server.paths.clear();
            return n;
        };
        takeHits();

        auto chartA = Explore::parseTopChart(QStringLiteral(R"({"feed":{"entry":[
            {"im:name":{"label":"A1"},"im:artist":{"label":"A"},
             "im:image":[{"label":"%1"}],
             "id":{"label":"u","attributes":{"im:id":"11"}}},
            {"im:name":{"label":"A2"},"im:artist":{"label":"A"},
             "im:image":[{"label":"%2"}],
             "id":{"label":"u","attributes":{"im:id":"12"}}},
            {"im:name":{"label":"A3"},"im:artist":{"label":"A"},
             "im:image":[{"label":"%3"}],
             "id":{"label":"u","attributes":{"im:id":"13"}}},
            {"im:name":{"label":"A4"},"im:artist":{"label":"A"},
             "im:image":[{"label":"%4"}],
             "id":{"label":"u","attributes":{"im:id":"14"}}}
        ]}})").arg(art("a1", "png"), art("a2", "png"), art("a3", "png"), art("a4", "png")).toUtf8());
        const auto lookA = Explore::parseSearch(QStringLiteral(R"({"results":[
            {"wrapperType":"track","kind":"podcast","collectionId":11,"collectionName":"A1","artistName":"A","artworkUrl600":"%1"},
            {"wrapperType":"track","kind":"podcast","collectionId":12,"collectionName":"A2","artistName":"A","artworkUrl600":"%2"},
            {"wrapperType":"track","kind":"podcast","collectionId":13,"collectionName":"A3","artistName":"A","artworkUrl600":"%3"},
            {"wrapperType":"track","kind":"podcast","collectionId":14,"collectionName":"A4","artistName":"A","artworkUrl600":"%4"}
        ]})").arg(art("a1", "jpg"), art("a2", "jpg"), art("a3", "jpg"), art("a4", "jpg")).toUtf8());
        auto chartB = Explore::parseTopChart(QStringLiteral(R"({"feed":{"entry":[
            {"im:name":{"label":"B1"},"im:artist":{"label":"B"},
             "im:image":[{"label":"%1"}],
             "id":{"label":"u","attributes":{"im:id":"21"}}},
            {"im:name":{"label":"B2"},"im:artist":{"label":"B"},
             "im:image":[{"label":"%2"}],
             "id":{"label":"u","attributes":{"im:id":"22"}}},
            {"im:name":{"label":"B3"},"im:artist":{"label":"B"},
             "im:image":[{"label":"%3"}],
             "id":{"label":"u","attributes":{"im:id":"23"}}}
        ]}})").arg(art("b1", "png"), art("b2", "png"), art("b3", "png")).toUtf8());
        const auto lookB = Explore::parseSearch(QStringLiteral(R"({"results":[
            {"wrapperType":"track","kind":"podcast","collectionId":21,"collectionName":"B1","artistName":"B","artworkUrl600":"%1"},
            {"wrapperType":"track","kind":"podcast","collectionId":22,"collectionName":"B2","artistName":"B","artworkUrl600":"%2"},
            {"wrapperType":"track","kind":"podcast","collectionId":23,"collectionName":"B3","artistName":"B","artworkUrl600":"%3"}
        ]})").arg(art("b1", "jpg"), art("b2", "jpg"), art("b3", "jpg")).toUtf8());
        check(chartA.size() == 4 && lookA.size() == 4 && chartB.size() == 3 && lookB.size() == 3,
              "cover probe charts parse");

        int beforeFirst = -1, beforeSecond = -1, afterFirst = -1, afterSecond = -1;
        int abaFirst = -1, abaSecond = -1, abaRevisit = -1;
        if (chartA.size() == 4 && lookA.size() == 4 && chartB.size() == 3 && lookB.size() == 3) {
            {
                QTemporaryDir dir;
                QNetworkAccessManager nam;
                attachCache(nam, dir.filePath(QStringLiteral("http")));
                const int got = fetchAll(nam, tilesOf(chartA));
                beforeFirst = takeHits();
                const auto overwritten = overwriteCovers(chartA, lookA);
                const int got2 = fetchAll(nam, tilesOf(overwritten));
                beforeSecond = takeHits();
                check(got == 4 && got2 == 4 && beforeFirst == 4 && beforeSecond == 4,
                      "before: overwriting the cover refetches every tile on the second visit");
            }
            {
                QTemporaryDir dir;
                QNetworkAccessManager nam;
                attachCache(nam, dir.filePath(QStringLiteral("http")));
                const int got = fetchAll(nam, tilesOf(chartA));
                afterFirst = takeHits();
                auto merged = chartA;
                Explore::mergeLookup(merged, lookA);
                const int got2 = fetchAll(nam, tilesOf(merged));
                afterSecond = takeHits();
                check(got == 4 && got2 == 4 && afterFirst == 4 && afterSecond == 0
                          && tilesOf(merged) == tilesOf(chartA),
                      "after: mergeLookup reuses the chart tiles, second visit is a cache hit");
            }
            {
                QTemporaryDir dir;
                QNetworkAccessManager nam;
                attachCache(nam, dir.filePath(QStringLiteral("http")));
                auto mergedA = chartA, mergedB = chartB;
                Explore::mergeLookup(mergedA, lookA);
                Explore::mergeLookup(mergedB, lookB);
                const int gotA = fetchAll(nam, tilesOf(mergedA));
                abaFirst = takeHits();
                const int gotB = fetchAll(nam, tilesOf(mergedB));
                abaSecond = takeHits();
                const int gotA2 = fetchAll(nam, tilesOf(mergedA));
                abaRevisit = takeHits();
                check(gotA == 4 && gotB == 3 && gotA2 == 4
                          && abaFirst == 4 && abaSecond == 3 && abaRevisit == 0,
                      "region A then B then A: revisit fetches no covers");
            }
        }
        fprintf(stderr,
                "cover cache requests: before A=%d A2=%d; after A=%d A2=%d; A/B/A=%d/%d/%d\n",
                beforeFirst, beforeSecond, afterFirst, afterSecond, abaFirst, abaSecond, abaRevisit);
        server.close();
    }

    check(versionIsNewer(QStringLiteral("v0.2.0"), QStringLiteral("0.1.0")), "0.2.0 is newer than 0.1.0");
    check(versionIsNewer(QStringLiteral("0.1.10"), QStringLiteral("0.1.9")), "0.1.10 is newer than 0.1.9");
    check(versionIsNewer(QStringLiteral("0.2"), QStringLiteral("0.1.9")), "0.2 is newer than 0.1.9");
    check(versionIsNewer(QStringLiteral("1.0.0"), QStringLiteral("0.9.9")), "1.0.0 is newer than 0.9.9");
    check(!versionIsNewer(QStringLiteral("v0.1.0"), QStringLiteral("0.1.0")), "same version is not newer");
    check(!versionIsNewer(QStringLiteral("V0.1.0"), QStringLiteral("0.1.0")), "capital V is the same version");
    check(!versionIsNewer(QStringLiteral("0.1.0"), QStringLiteral("v0.2.0")), "older tag is not newer");
    check(!versionIsNewer(QStringLiteral("0.1.0"), QStringLiteral("0.1.0.0")), "trailing zero is the same version");
    check(!versionIsNewer(QString(), QStringLiteral("0.1.0")), "empty tag is not newer");
    {
        const QByteArray newer = R"({"tag_name":"v0.2.0","html_url":"https://github.com/allandehn/omaear/releases/tag/v0.2.0"})";
        const UpdateOffer offer = parseLatestRelease(newer, 200, QStringLiteral("0.1.0"));
        check(offer.kind == UpdateKind::Available && offer.latest == QStringLiteral("0.2.0"), "release json strips v");
        check(offer.url.endsWith(QStringLiteral("v0.2.0")), "release json keeps html_url");
        const UpdateOffer same = parseLatestRelease(newer, 200, QStringLiteral("0.2.0"));
        check(same.kind == UpdateKind::Current, "matching release is up to date");
        const UpdateOffer ahead = parseLatestRelease(newer, 200, QStringLiteral("0.3.0"));
        check(ahead.kind == UpdateKind::Current, "local build ahead of the release is up to date");
        check(parseLatestRelease(QByteArray("{\"message\":\"Not Found\"}"), 404, QStringLiteral("0.1.0")).kind
                  == UpdateKind::Failed,
              "404 release check fails");
        check(parseLatestRelease(QByteArray("{\"message\":\"rate limit\"}"), 403, QStringLiteral("0.1.0")).kind
                  == UpdateKind::Failed,
              "rate limit release check fails");
        check(parseLatestRelease(QByteArray(), 0, QStringLiteral("0.1.0")).kind == UpdateKind::Failed,
              "offline release check fails");
        check(parseLatestRelease(QByteArray("not-json"), 200, QStringLiteral("0.1.0")).kind == UpdateKind::Failed,
              "bad release json fails");
    }

    {
        // OPML export round-trips through the import parser (escaping included).
        QList<ShowRow> rows;
        ShowRow a; a.feedUrl = QStringLiteral("https://example.com/a.xml?x=1&y=2"); a.title = QStringLiteral("A & <B> \"C\"");
        ShowRow b; b.feedUrl = QStringLiteral("https://example.com/b.rss"); b.title = QStringLiteral("Bé");
        rows << a << b;
        const QByteArray xml = writeOpml(rows);
        QString err;
        check(parseOpml(xml, &err) == QStringList({a.feedUrl, b.feedUrl}), "opml round trip");
        check(xml.contains("version=\"2.0\"") && xml.contains("title=\"A &amp; &lt;B&gt;"), "opml 2.0 title");
        // Optional: a copy of a real library (never the live one).
        const QString libPath = qEnvironmentVariable("OMAEAR_SELFTEST_LIBRARY");
        if (!libPath.isEmpty()) {
            Library lib(libPath);
            const QList<ShowRow> shows = lib.shows();
            QStringList want;
            for (const auto &row : shows) want << row.feedUrl;
            const QStringList got = parseOpml(writeOpml(shows), &err);
            check(!want.isEmpty() && QSet<QString>(got.begin(), got.end()) == QSet<QString>(want.begin(), want.end()),
                  "opml round trip (library copy)");
            fprintf(stderr, "opml library copy: %lld shows, %lld round-tripped\n", (long long)want.size(), (long long)got.size());
        }
    }

    {
        // Pre-rounded artwork detection.
        auto art = [](bool rounded, QColor bg, bool border) {
            QImage img(200, 200, QImage::Format_ARGB32_Premultiplied);
            img.fill(bg);
            QPainter p(&img);
            p.setRenderHint(QPainter::Antialiasing);
            QLinearGradient grad(0, 0, 200, 200);
            grad.setColorAt(0, QColor(30, 90, 200)); grad.setColorAt(1, QColor(200, 40, 90));
            const QRectF r = border ? QRectF(30, 30, 140, 140) : QRectF(0, 0, 200, 200);
            if (rounded) p.setBrush(grad), p.setPen(Qt::NoPen), p.drawRoundedRect(r, 20, 20);
            else p.fillRect(r, grad);
            return img;
        };
        check(hasFlatRoundedCorners(art(true, Qt::white, false)), "corners: rounded on white");
        check(hasFlatRoundedCorners(art(true, Qt::black, false)), "corners: rounded on black");
        check(hasFlatRoundedCorners(art(true, Qt::transparent, false)), "corners: rounded on transparent");
        check(!hasFlatRoundedCorners(art(false, Qt::white, false)), "corners: square art");
        check(!hasFlatRoundedCorners(art(false, Qt::white, true)), "corners: white border");
        check(!hasFlatRoundedCorners(art(true, Qt::white, true)), "corners: small rounded inset");
        QImage flat(200, 200, QImage::Format_ARGB32_Premultiplied); flat.fill(Qt::gray);
        check(!hasFlatRoundedCorners(flat), "corners: flat colour");
        check(!hasFlatRoundedCorners(QImage()), "corners: null image");
        // Optional: report which covers in a directory are flagged (a copy, never live).
        const QString coverDir = qEnvironmentVariable("OMAEAR_SELFTEST_COVERS");
        if (!coverDir.isEmpty()) {
            QElapsedTimer t; t.start();
            int n = 0, hits = 0;
            for (const QFileInfo &fi : QDir(coverDir).entryInfoList(QDir::Files)) {
                const QImage img(fi.absoluteFilePath());
                if (img.isNull()) continue;
                ++n;
                const QImage conv = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
                if (hasFlatRoundedCorners(conv)) { ++hits; fprintf(stderr, "pre-rounded: %s\n", qPrintable(fi.fileName())); }
            }
            fprintf(stderr, "covers: %d scanned, %d pre-rounded, %.2f ms total (decode + check)\n", n, hits, t.nsecsElapsed() / 1e6);
        }
    }

    {
        // App icons: currentColor, 1.5 stroke, square joins in source; round at runtime.
        const QStringList icons = QDir(QStringLiteral(":/icons")).entryList({QStringLiteral("*-symbolic.svg")});
        check(icons.size() >= 12, "icons: found in qrc");
        for (const QString &name : icons) {
            const QByteArray sq = iconSvg(name, false), rd = iconSvg(name, true);
            const QByteArray what = name.toUtf8();
            check(!sq.contains("#2e3436") && sq.contains("currentColor"), ("icon currentColor: " + what).constData());
            check(!sq.contains("stroke-width") || sq.contains("stroke-width=\"1.5\""), ("icon 1.5 stroke: " + what).constData());
            check(!sq.contains("linejoin=\"round\"") && !rd.contains("linejoin=\"miter\""), ("icon joins: " + what).constData());
            QBuffer buf; buf.setData(rd); QImageReader reader(&buf, "svg"); reader.setScaledSize(QSize(32, 32));
            const QImage img = reader.read();
            int ink = 0;
            for (int y = 0; y < img.height(); ++y) for (int x = 0; x < img.width(); ++x) ink += qAlpha(img.pixel(x, y)) > 0;
            check(ink > 20, ("icon renders: " + what).constData());
        }
        check(iconSvg(QStringLiteral("../x.svg"), false).isEmpty(), "icons: no path escape");
    }

    {
        // AdsWizz / Simplecast AIS: strip campaign query, keep Lavf, leave
        // other hosts (including a Flightcast-style path) unchanged. A local
        // mock server returns a short "plain" body without aw* params and a
        // longer "stitched" body with them. No real network.
        const QUrl ads = QUrl(QStringLiteral(
            "https://pdrl.fm/f3efd0/dts.podtrac.com/redirect.mp3/arttrk.com/p/ST44R/"
            "claritaspod.com/measure/stitcher.simplecastaudio.com/show/episodes/ep/"
            "audio/128/default.mp3?aid=rss_feed&awCollectionId=col&awEpisodeId=ep&feed=dHoohVNH"));
        check(HttpFileBuffer::isAdsWizzAudioUrl(ads), "ads: tracker enclosure is recognised");
        const QUrl adsPlain = HttpFileBuffer::withoutAdsWizzQuery(ads);
        check(adsPlain != ads, "ads: campaign query is dropped");
        check(!QUrlQuery(adsPlain).hasQueryItem(QStringLiteral("awCollectionId"))
                  && !QUrlQuery(adsPlain).hasQueryItem(QStringLiteral("awEpisodeId"))
                  && !QUrlQuery(adsPlain).hasQueryItem(QStringLiteral("aid")),
              "ads: awCollectionId, awEpisodeId and aid are gone");
        check(QUrlQuery(adsPlain).queryItemValue(QStringLiteral("feed")) == QStringLiteral("dHoohVNH"),
              "ads: other query items are kept");
        check(adsPlain.host() == QStringLiteral("pdrl.fm")
                  && adsPlain.path().contains(QStringLiteral("simplecastaudio.com")),
              "ads: tracker prefix and path stay");
        check(HttpFileBuffer::isAdsWizzAudioUrl(adsPlain),
              "ads: path still recognised after the strip");

        const QUrl byQuery(QStringLiteral("https://cdn.example.com/ep.mp3?awCollectionId=x&keep=1"));
        check(HttpFileBuffer::isAdsWizzAudioUrl(byQuery), "ads: awCollectionId alone is recognised");
        check(QUrlQuery(HttpFileBuffer::withoutAdsWizzQuery(byQuery)).queryItemValue(QStringLiteral("keep"))
                  == QStringLiteral("1"),
              "ads: non-campaign query on a plain host is kept");

        const QUrl normal(QStringLiteral("https://cdn.example.com/ep.mp3?keep=1"));
        check(!HttpFileBuffer::isAdsWizzAudioUrl(normal), "ads: ordinary host is not recognised");
        check(HttpFileBuffer::withoutAdsWizzQuery(normal) == normal, "ads: ordinary URL is unchanged");

        const QUrl flight(QStringLiteral("https://m.flightcast.com/listen/episode.mp3?token=1"));
        check(!HttpFileBuffer::isAdsWizzAudioUrl(flight), "ads: Flightcast-style URL is not recognised");
        check(HttpFileBuffer::withoutAdsWizzQuery(flight) == flight,
              "ads: Flightcast-style URL is unchanged");

        struct AudioProbeServer : QTcpServer {
            QByteArray plain = QByteArray(80, 'P');
            QByteArray stitched = QByteArray(160, 'S');
            QByteArray other = QByteArray(40, 'O');
            struct Hit {
                QByteArray ua;
                QString target;
            };
            QList<Hit> hits;
            QHash<QTcpSocket *, QByteArray> buf;
            AudioProbeServer()
            {
                connect(this, &QTcpServer::newConnection, this, [this]() {
                    while (QTcpSocket *s = nextPendingConnection()) {
                        connect(s, &QTcpSocket::readyRead, this, [this, s]() {
                            buf[s] += s->readAll();
                            QByteArray &raw = buf[s];
                            int end = raw.indexOf("\r\n\r\n");
                            int skip = 4;
                            if (end < 0) {
                                end = raw.indexOf("\n\n");
                                skip = 2;
                            }
                            if (end < 0)
                                return;
                            const QByteArray req = raw.left(end);
                            raw.remove(0, end + skip);
                            const QList<QByteArray> lines = req.split('\n');
                            const QString first = QString::fromLatin1(lines.value(0)).trimmed();
                            const QString target = first.section(QLatin1Char(' '), 1, 1);
                            QByteArray ua;
                            for (const QByteArray &line : lines) {
                                const QByteArray low = line.toLower();
                                if (low.startsWith("user-agent:"))
                                    ua = line.mid(line.indexOf(':') + 1).trimmed();
                            }
                            hits.append({ua, target});

                            const QUrl got(QStringLiteral("http://localhost") + target);
                            const bool adsPath = target.contains(QStringLiteral("simplecastaudio.com"))
                                || target.contains(QStringLiteral("/default.mp3"));
                            const QUrlQuery q(got);
                            auto has = [&](const char *k) {
                                const QString key = QLatin1String(k);
                                return q.hasQueryItem(key) || q.hasQueryItem(key.toLower());
                            };
                            const bool campaign = has("awCollectionId") || has("awEpisodeId");

                            QByteArray body;
                            int status = 200;
                            QByteArray ctype = "audio/mpeg";
                            QByteArray loc;
                            if (target.startsWith(QLatin1String("/tracker/"))) {
                                status = 302;
                                ctype = "text/plain";
                                body = "tracker-hop";
                                const QString rest = target.mid(QStringLiteral("/tracker").size());
                                loc = "http://";
                                loc += s->localAddress().toString().toLatin1();
                                loc += ':';
                                loc += QByteArray::number(serverPort());
                                loc += rest.toUtf8();
                            } else if (adsPath) {
                                body = campaign ? stitched : plain;
                            } else {
                                body = other;
                            }

                            QByteArray resp = "HTTP/1.1 ";
                            resp += status == 302 ? "302 Found" : "200 OK";
                            resp += "\r\nContent-Type: ";
                            resp += ctype;
                            if (!loc.isEmpty()) {
                                resp += "\r\nLocation: ";
                                resp += loc;
                            }
                            resp += "\r\nConnection: close\r\nContent-Length: ";
                            resp += QByteArray::number(body.size());
                            resp += "\r\n\r\n";
                            resp += body;
                            s->write(resp);
                            s->flush();
                            s->disconnectFromHost();
                        });
                        connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
                    }
                });
            }
        };
        AudioProbeServer server;
        check(server.listen(QHostAddress::LocalHost, 0), "ads: probe server listens");
        const QString origin = QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort());

        QTemporaryDir cacheHome;
        check(cacheHome.isValid(), "ads: throwaway cache dir");
        const QByteArray oldCache = qgetenv("XDG_CACHE_HOME");
        qputenv("XDG_CACHE_HOME", cacheHome.path().toUtf8());

        auto waitDone = [](HttpFileBuffer *buf, int ms = 5000) {
            if (buf->isComplete() || buf->isFailed())
                return;
            QEventLoop loop;
            QObject::connect(buf, &HttpFileBuffer::completed, &loop, &QEventLoop::quit);
            QObject::connect(buf, &HttpFileBuffer::failed, &loop, &QEventLoop::quit);
            QTimer::singleShot(ms, &loop, &QEventLoop::quit);
            loop.exec();
        };
        auto readFinished = [](const QString &path) {
            QFile f(path);
            return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
        };
        auto sidecarOf = [](qint64 id) {
            QFile f(HttpFileBuffer::mediaDir() + QStringLiteral("/.%1.ua").arg(id));
            return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
        };

        const QByteArray lavf(kAudioGenericUserAgent);

        // AdsWizz-style enclosure behind a tracker hop that answers 302 text/plain
        // (claritaspod). The campaign query must be gone before the first request,
        // so the mock serves the plain body, and the User-Agent stays Lavf.
        {
            server.hits.clear();
            const QUrl enc(origin
                           + QStringLiteral("/tracker/dts.podtrac.com/redirect.mp3/"
                                            "stitcher.simplecastaudio.com/show/episodes/ep/"
                                            "audio/128/default.mp3"
                                            "?aid=rss_feed&awCollectionId=col&awEpisodeId=ep&feed=dHoohVNH"));
            HttpFileBuffer buf(910001, enc);
            buf.start();
            waitDone(&buf);
            const QString path = buf.existingFinishedPath();
            const QByteArray body = readFinished(path);
            check(buf.isComplete() && !buf.isFailed() && body == server.plain,
                  "ads: enclosure is fetched as the plain body");
            check(buf.preferredUserAgent(enc) == lavf, "ads: preferred UA stays generic");
            check(server.hits.size() >= 2, "ads: tracker hop is followed");
            bool allLavf = !server.hits.isEmpty();
            bool sawCampaign = false;
            bool sawFeed = false;
            for (const auto &h : server.hits) {
                if (h.ua != lavf)
                    allLavf = false;
                const QUrl u(QStringLiteral("http://x") + h.target);
                const QUrlQuery q(u);
                if (q.hasQueryItem(QStringLiteral("awCollectionId"))
                    || q.hasQueryItem(QStringLiteral("awEpisodeId"))
                    || q.hasQueryItem(QStringLiteral("aid")))
                    sawCampaign = true;
                if (q.queryItemValue(QStringLiteral("feed")) == QStringLiteral("dHoohVNH"))
                    sawFeed = true;
            }
            check(allLavf, "ads: every hop uses the generic player identity");
            check(!sawCampaign, "ads: campaign query never reaches the host");
            check(sawFeed, "ads: feed= is kept on the request");
            const QByteArray side = sidecarOf(910001);
            // Sidecar is removed after a successful finalize; a mid-download
            // peek is enough: if it is already gone, the finished file is plain.
            if (!side.isEmpty())
                check(side.contains("variant=noaw"), "ads: sidecar records variant noaw");
            Q_UNUSED(side);
        }

        // Ordinary host: URL and query stay as given, UA is still Lavf.
        {
            server.hits.clear();
            const QUrl enc(origin + QStringLiteral("/normal/ep.mp3?keep=1"));
            HttpFileBuffer buf(910002, enc);
            buf.start();
            waitDone(&buf);
            const QByteArray body = readFinished(buf.existingFinishedPath());
            check(buf.isComplete() && body == server.other, "ads: ordinary host downloads");
            check(server.hits.size() == 1 && server.hits.at(0).ua == lavf,
                  "ads: ordinary host uses the generic player identity");
            check(server.hits.at(0).target.contains(QStringLiteral("keep=1")),
                  "ads: ordinary URL is requested unchanged");
        }

        // Flightcast-style path (the host that first needed Lavf): untouched.
        {
            server.hits.clear();
            const QUrl enc(origin + QStringLiteral("/m.flightcast.com/listen/episode.mp3?token=1"));
            check(!HttpFileBuffer::isAdsWizzAudioUrl(enc), "ads: Flightcast path is not AdsWizz");
            HttpFileBuffer buf(910003, enc);
            buf.start();
            waitDone(&buf);
            const QByteArray body = readFinished(buf.existingFinishedPath());
            check(buf.isComplete() && body == server.other, "ads: Flightcast-style download");
            check(server.hits.size() == 1 && server.hits.at(0).ua == lavf,
                  "ads: Flightcast-style host uses the generic player identity");
            check(server.hits.at(0).target.contains(QStringLiteral("token=1")),
                  "ads: Flightcast-style URL is requested unchanged");
        }

        // A .part recorded as variant=default must not be spliced onto a noaw fetch.
        {
            server.hits.clear();
            const QUrl enc(origin
                           + QStringLiteral("/stitcher.simplecastaudio.com/show/episodes/ep/"
                                            "audio/128/default.mp3?awCollectionId=col&awEpisodeId=ep"));
            const qint64 id = 910004;
            const QString part = HttpFileBuffer::mediaDir() + QStringLiteral("/%1.part").arg(id);
            const QString sidePath = HttpFileBuffer::mediaDir() + QStringLiteral("/.%1.ua").arg(id);
            QDir().mkpath(HttpFileBuffer::mediaDir());
            QFile partFile(part);
            check(partFile.open(QIODevice::WriteOnly) && partFile.write(QByteArray(24, 'X')) == 24,
                  "ads: stale stitched .part written");
            partFile.close();
            QFile side(sidePath);
            check(side.open(QIODevice::WriteOnly)
                      && side.write(lavf + "\nvariant=default\n") > 0,
                  "ads: stale default sidecar written");
            side.close();
            HttpFileBuffer buf(id, enc);
            buf.start();
            waitDone(&buf);
            const QByteArray body = readFinished(buf.existingFinishedPath());
            check(buf.isComplete() && body == server.plain,
                  "ads: default .part is not spliced onto a noaw download");
            check(!body.contains('X'), "ads: stale stitched bytes are gone");
        }

        qputenv("XDG_CACHE_HOME", oldCache);
        server.close();
    }

    if (g_fails == 0) {
        printf("ok\n");
        return 0;
    }
    fprintf(stderr, "%d failed\n", g_fails);
    return 1;
}
