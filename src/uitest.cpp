// Headless UI self-test (OMAEAR_UI_TEST=1, offscreen, temp library only).
// Drives the real window with synthetic mouse events delivered to THIS
// process's QQuickWindow, then quits with 0 (pass) or 1 (fail).
#include <QDir>
#include <QElapsedTimer>
#include <QCursor>
#include <QGuiApplication>
#include <QImage>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPointer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <functional>

namespace {
struct UiTest {
    QQuickWindow *win = nullptr;
    QQmlApplicationEngine *engine = nullptr;
    int fails = 0;
    int dwellMs = qEnvironmentVariableIntValue("OMAEAR_UI_TEST_DWELL");
    QList<std::pair<int, std::function<void()>>> steps;
    QElapsedTimer settleClock;
    bool sawBusy = false;

    QVariant eval(const QString &js)
    {
        QQmlExpression e(qmlContext(win), win, js);
        const QVariant v = e.evaluate();
        if (e.hasError())
            fprintf(stderr, "[uitest] eval error: %s -> %s\n", qPrintable(js), qPrintable(e.error().toString()));
        return v.canConvert<QJSValue>() ? v.value<QJSValue>().toVariant() : v;
    }
    QPointF centerOf(const QString &js)
    {
        auto *item = qvariant_cast<QQuickItem *>(eval(js));
        if (!item) {
            fprintf(stderr, "[uitest] no item for %s\n", qPrintable(js));
            return {};
        }
        return item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
    }
    // Hover only: a mouse move to p, no buttons.
    void hover(QPointF p)
    {
        QCursor::setPos(win->mapToGlobal(p).toPoint());
        QMouseEvent move(QEvent::MouseMove, p, win->mapToGlobal(p), Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(win, &move);
    }
    // Realistic: move there (hover), press, hold ~90 ms (mid-fade), release.
    void click(QPointF p, Qt::MouseButton b)
    {
        const QPointF g = win->mapToGlobal(p);
        QCursor::setPos(g.toPoint()); // menus open at the cursor
        fprintf(stderr, "[uitest] click %s at %.0f,%.0f\n", b == Qt::RightButton ? "right" : "left", p.x(), p.y());
        listPopups();
        QMouseEvent move(QEvent::MouseMove, p, g, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(win, &move);
        // Dwell like a person does (hover tooltips get time to appear), then press, hold, release.
        QPointer<QQuickWindow> w = win;
        QTimer::singleShot(dwellMs, win, [this, w, p, g, b]() {
            if (!w) return;
            listPopups();
            QMouseEvent press(QEvent::MouseButtonPress, p, g, b, b, Qt::NoModifier);
            QCoreApplication::sendEvent(w, &press);
            QTimer::singleShot(90, w, [w, p, g, b]() {
                if (!w) return;
                QMouseEvent release(QEvent::MouseButtonRelease, p, g, b, Qt::NoButton, Qt::NoModifier);
                QCoreApplication::sendEvent(w, &release);
            });
        });
    }
    void listPopups()
    {
        const auto all = engine->rootObjects().constFirst()->findChildren<QObject *>();
        for (QObject *o : all) {
            if (!o->inherits("QQuickPopup"))
                continue;
            if (o->property("visible").toBool())
            {
                QQuickItem *first = nullptr;
                QMetaObject::invokeMethod(o, "itemAt", Q_RETURN_ARG(QQuickItem *, first), Q_ARG(int, 0));
                fprintf(stderr, "[uitest]   visible popup: %s modal=%d opened=%d x=%.0f y=%.0f w=%.0f h=%.0f first=%s\n", o->metaObject()->className(),
                        o->property("modal").toBool(), o->property("opened").toBool(),
                        o->property("x").toDouble(), o->property("y").toDouble(), o->property("width").toDouble(), o->property("height").toDouble(),
                        first ? qPrintable(first->property("text").toString()) : "-");
            }
        }
    }
    // A key press + release delivered to the window (like a real keyboard).
    void key(int k, const QString &text = QString())
    {
        QKeyEvent press(QEvent::KeyPress, k, Qt::NoModifier, text);
        QCoreApplication::sendEvent(win, &press);
        QKeyEvent release(QEvent::KeyRelease, k, Qt::NoModifier, text);
        QCoreApplication::sendEvent(win, &release);
    }
    void expect(bool ok, const char *what)
    {
        fprintf(stderr, "[uitest] %s %s\n", ok ? "PASS" : "FAIL", what);
        if (!ok)
            ++fails;
    }
    // Launch refresh is a singleShot(0) from the Backend constructor, and the
    // release dry-run's empty XDG_CONFIG_HOME has no refresh stamp, so that
    // callback always calls refreshAll(). Sampling busy before the event loop
    // sees that callback reports idle, then the refresh reorders the shelf
    // under the clicks. A 30s cap that continues anyway does the same once a
    // real library outlasts it. Wait until busy is false and the visible show
    // ids plus the first two cover delegates have stayed put for one poll, or
    // fail. Do not start the script either way.
    QString shelfSignature(bool busy, int count)
    {
        QString sig = QString::number(busy) + QLatin1Char('|') + QString::number(count);
        if (busy || count <= 0)
            return sig;
        sig += QLatin1Char('|');
        sig += eval(QStringLiteral(
            "(function(){"
            " var ids = [];"
            " for (var i = 0; i < shelfView.navCount; ++i) ids.push(backend.shows.showIdAt(i));"
            " function box(i) {"
            "   var it = shelfView.coverItemAt(i);"
            "   if (!it || it.width < 1 || it.height < 1) return 'missing';"
            "   return Math.round(it.x) + ',' + Math.round(it.y) + ',' + Math.round(it.width) + ',' + Math.round(it.height);"
            " }"
            " return ids.join(',') + '|' + box(0) + '|' + (shelfView.navCount > 1 ? box(1) : '-');"
            " })()")).toString();
        return sig;
    }
    void failUnsettled(bool busy, int count)
    {
        fprintf(stderr, "[uitest] FAIL shelf did not settle within 150s (busy=%d shows=%d)\n",
                busy, count);
        ++fails;
        fprintf(stderr, "[uitest] FAILED\n");
        QCoreApplication::exit(1);
    }
    // stable counts consecutive matching quiet observations. previous is the last signature.
    void waitSettled(int stable = 0, const QString &previous = QString())
    {
        if (!settleClock.isValid())
            settleClock.start();
        const bool busy = eval("backend.busy").toBool();
        const int count = eval("shelfView.navCount").toInt();
        if (busy && !sawBusy) {
            sawBusy = true;
            fprintf(stderr, "[uitest] launch refresh running (shows=%d)\n", count);
        }
        const QString sig = shelfSignature(busy, count);
        const bool quiet = !busy && !sig.contains(QLatin1String("missing"));
        if (quiet && sig == previous)
            ++stable;
        else
            stable = quiet ? 1 : 0;
        if (stable >= 2) {
            fprintf(stderr, "[uitest] shelf settled (busy=0 shows=%d)%s\n", count,
                    sawBusy ? " after launch refresh" : "");
            runFrom(0);
            return;
        }
        if (settleClock.elapsed() > 150000) {
            failUnsettled(busy, count);
            return;
        }
        // While feeds are in flight, wake sparingly so their replies run. Once
        // busy drops, poll often enough to see the post-reset layout, and
        // start the script on the next unchanged sample rather than after a
        // fixed pause.
        const int delay = busy ? 200 : 50;
        QTimer::singleShot(delay, win, [this, stable, sig]() { waitSettled(stable, sig); });
    }
    void run(int i)
    {
        if (i == 0) {
            // Queued behind Backend's own singleShot(0) launch refresh.
            QTimer::singleShot(0, win, [this]() { waitSettled(); });
            return;
        }
        runFrom(i);
    }
    void runFrom(int i)
    {
        if (i >= steps.size()) {
            fprintf(stderr, "[uitest] %s\n", fails ? "FAILED" : "ALL PASS");
            QCoreApplication::exit(fails ? 1 : 0);
            return;
        }
        QTimer::singleShot(steps[i].first, win, [this, i]() { steps[i].second(); runFrom(i + 1); });
    }
};
}

void startUiTest(QQmlApplicationEngine &engine)
{
    auto *t = new UiTest;
    t->engine = &engine;
    t->win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    t->win->resize(1400, 900);
    QPointF row;
    // OMAEAR_UI_TEST_SHOTS=<dir>: grab the dialogs, the player bar (autoplay on
    // and off), the shelf (gallery and list), Now Playing, the episode,
    // queue, show, Explore and Search pages into <dir> for design review. Pair it with
    // OMAEAR_ROUNDING=<R> to pin the corner radius.
    const QString shots = qEnvironmentVariable("OMAEAR_UI_TEST_SHOTS");
    if (!shots.isEmpty()) {
        QDir().mkpath(shots);
        const QString r = QStringLiteral("-r") + QString::number(t->eval("theme.rounding").toInt());
        auto grab = [t, shots, r](const char *name) {
            const QString path = shots + QLatin1Char('/') + QLatin1String(name) + r + QStringLiteral(".png");
            t->expect(t->win->grabWindow().save(path), name);
        };
        t->steps = {
            {2500, [grab]() { grab("shelf"); }},
            {200, [t]() { t->eval("backend.setShelfView('grid')"); }},
            {900, [grab]() { grab("shelf-gallery"); }},
            {200, [t]() { t->eval("backend.setShelfView('list')"); }},
            {1200, [grab]() { grab("shelf-list"); }},
            {200, [t]() { t->hover(t->centerOf("shelfView.coverItemAt(1)")); }},
            {700, [grab]() { grab("row-highlight-shelf-list"); }},
            {200, [t]() { t->hover(QPointF(2, 2)); t->eval("backend.setShelfView('grid')"); }},
            {200, [t]() { t->eval("win.confirmUnsubscribe(backend.shows.showIdAt(0), backend.shows.titleAt ? backend.shows.titleAt(0) : 'this podcast')"); }},
            {700, [grab]() { grab("unsubscribe"); }},
            {200, [t]() { t->eval("win.closeModals(); win.confirmUnsubscribeAll()"); }},
            {700, [grab]() { grab("unsubscribe-all-step1"); }},
            {200, [t]() { t->eval("dialog.accepted()"); }},
            {700, [t, grab]() {
                t->expect(t->eval("confirmUnsubAll2 && dialog.selectedIndex === 0").toBool(), "step 2 starts on Cancel");
                t->expect(t->eval("dialog.title === 'Unsubscribe from all ' + unsubAllCount + (unsubAllCount === 1 ? ' podcast?' : ' podcasts?')"
                                  " && dialog.detail === \"This can't be undone.\"").toBool(), "step 2 title has the count");
                grab("unsubscribe-all-step2");
            }},
            {200, [t]() { t->eval("win.closeModals(); feedField.text = ''; win.addOpen = true"); }},
            {700, [grab]() { grab("add-feed"); }},
            {200, [t]() { t->eval("win.closeModals(); if (!backend.queueAutoplay) backend.toggleQueueAutoplay()"); }},
            {700, [grab]() { grab("playerbar-autoplay-on"); }},
            {200, [t]() { t->eval("backend.toggleQueueAutoplay()"); }},
            {700, [grab]() { grab("playerbar-autoplay-off"); }},
            {200, [t]() { t->eval("backend.toggleQueueAutoplay(); win.openNowPlayingPage()"); }},
            {1200, [grab]() { grab("now-playing"); }},
            {200, [t]() { t->eval("win.openEpisodePage(backend.playerEpisodeId)"); }},
            {1200, [grab]() { grab("episode"); }},
            {200, [t]() { t->eval("win.openQueuePage()"); }},
            {1200, [t, grab]() { t->expect(t->eval("pageKind").toString() == "queue", "queue page opened"); grab("queue"); }},
            {200, [t]() { t->hover(t->centerOf("queuePage.rowItemAt(1)")); }},
            {700, [grab]() { grab("row-highlight-queue"); }},
            {200, [t]() { t->hover(QPointF(2, 2)); }},
            {200, [t]() { t->eval("win.openShowPage(backend.shows.showIdAt(0))"); }},
            {1500, [grab]() { grab("show"); }},
            {200, [t]() { t->eval("win.openExplorePage()"); }},
            {1500, [grab]() { grab("explore"); }},
            {200, [t]() { t->eval("win.openSearchPage()"); }},
            {1200, [grab]() { grab("search"); }},
        };
        t->run(0);
        return;
    }
    // OMAEAR_UI_TEST_MOTION=<dir>: frame strips of the motion try-out (keyboard ring
    // gliding one cover right, then a cover lifting on hover). Pair with OMAEAR_ROUNDING.
    const QString motion = qEnvironmentVariable("OMAEAR_UI_TEST_MOTION");
    if (!motion.isEmpty()) {
        QDir().mkpath(motion);
        const QString r = QStringLiteral("-r") + QString::number(t->eval("theme.rounding").toInt());
        auto grab = [t, motion, r](const QString &name) {
            const QString path = motion + QLatin1Char('/') + name + r + QStringLiteral(".png");
            t->expect(t->win->grabWindow().save(path), qPrintable(name));
        };
        t->steps = {
            {2500, [t]() { t->eval("if (!backend.motionTryout) backend.toggleMotionTryout(); backend.setShelfView('grid');"
                                   " shelfView.kbdRing = true; shelfView.kbdIndex = 0"); }},
            {900, [grab]() { grab(QStringLiteral("ring-0ms")); }},
            {0, [t]() { t->eval("shelfView.kbdIndex = 1"); }},
            {40, [grab]() { grab(QStringLiteral("ring-40ms")); }},
            {40, [grab]() { grab(QStringLiteral("ring-80ms")); }},
            {80, [grab]() { grab(QStringLiteral("ring-160ms")); }},
            {200, [t]() { t->eval("shelfView.kbdRing = false"); t->hover(t->centerOf("shelfView.coverItemAt(2)")); }},
            {40, [grab]() { grab(QStringLiteral("lift-40ms")); }},
            {40, [grab]() { grab(QStringLiteral("lift-80ms")); }},
            {120, [grab]() { grab(QStringLiteral("lift-200ms")); }},
            {0, [t]() { t->hover(QPointF(2, 2)); }},
            {50, [grab]() { grab(QStringLiteral("settle-50ms")); }},
            {150, [grab]() { grab(QStringLiteral("settle-200ms")); }},
        };
        t->run(0);
        return;
    }
    // OMAEAR_UI_TEST_NAV=1: input mode (keyboard vs mouse) and absolute grid wrap.
    // OMAEAR_UI_TEST_FEEDS=<dir of .xml feeds> (tests/nav-feeds): added via file:// on start;
    // the last one has no episodes. Run with a throwaway XDG library.
    if (qEnvironmentVariableIntValue("OMAEAR_UI_TEST_NAV") == 1) {
        const QString feeds = qEnvironmentVariable("OMAEAR_UI_TEST_FEEDS");
        // Grid math on a stand-in grid: 7 items, 3 columns (rows 0-2, 3-5, 6).
        auto gk = [t](int n, int c, int from, const char *k, bool full = false) {
            return t->eval(QStringLiteral("(function(){ var keep = backend.gridWrapFull;"
                " if (keep !== %5) backend.toggleGridWrap();"
                " var g = { navCount: %1, navColumns: %2, kbdIndex: %3, setNavIndex: function(j) { this.kbdIndex = j } };"
                " win.navGridKey(g, Qt.%4); if (backend.gridWrapFull !== keep) backend.toggleGridWrap(); return g.kbdIndex })()")
                .arg(n).arg(c).arg(from).arg(QLatin1String(k)).arg(full ? "true" : "false")).toInt();
        };
        t->steps = {
            {500, [t, feeds]() {
                int delay = 0;
                for (const QString &f : QDir(feeds).entryList({QStringLiteral("*.xml")}, QDir::Files, QDir::Name)) {
                    QTimer::singleShot(delay, t->win, [t, feeds, f]() {
                        t->eval(QStringLiteral("backend.addFeed('file://%1/%2')").arg(feeds, f));
                    });
                    delay += 700;
                }
            }},
            {4000, [t, gk]() {
                fprintf(stderr, "[uitest] status=%s shows=%d busy=%d\n", qPrintable(t->eval("backend.status").toString()),
                        t->eval("shelfView.navCount").toInt(), t->eval("backend.busy").toBool());
                t->expect(gk(7, 3, 4, "Key_Down") == 1, "rows: Down past the bottom of column 1 wraps to its top (no clamp)");
                t->expect(gk(7, 3, 1, "Key_Up") == 4, "rows: Up past the top of column 1 wraps to its own bottom, not the last item");
                t->expect(gk(7, 3, 0, "Key_Up") == 6, "rows: Up from the top of column 0 wraps to the short last row");
                t->expect(gk(7, 3, 6, "Key_Down") == 0, "rows: Down from the short last row wraps to the top of column 0");
                t->expect(gk(7, 3, 2, "Key_Down") == 5 && gk(7, 3, 5, "Key_Down") == 2, "rows: column 2 cycles 2 -> 5 -> 2");
                t->expect(gk(7, 3, 5, "Key_Right") == 3 && gk(7, 3, 3, "Key_Left") == 5, "rows: Left/Right wrap within the row");
                t->expect(gk(7, 3, 6, "Key_Right") == 6, "rows: a one-item row stays put on Left/Right");
                t->expect(gk(7, 3, 4, "Key_Down", true) == 2, "full mode unchanged: Down past column 1's bottom goes to the top of column 2");
                t->expect(t->eval("shelfView.navCount >= 2").toBool(), "test library has at least 2 shows");
                t->expect(!t->eval("win.keyboardMode").toBool(), "starts in mouse mode");
                t->expect(!t->eval("shelfView.kbdRing").toBool(), "mouse mode: no key ring on the shelf");
                t->key(Qt::Key_Down);
            }},
            {300, [t]() {
                t->expect(t->eval("win.keyboardMode").toBool(), "a key press switches to keyboard mode");
                t->expect(t->eval("shelfView.kbdRing").toBool(), "keyboard mode: ring shows on the shelf");
                t->eval("win.openShowPage(backend.shows.showIdAt(0))");
            }},
            {1500, [t]() {
                t->expect(t->eval("pageKind").toString() == "show", "show page opened");
                t->expect(t->eval("activeShow().navCount > 0").toBool(), "show 0 has episodes");
                t->expect(t->eval("win.navArea === 'grid' && activeShow().kbdIndex === 0 && activeShow().kbdCol === 0"
                                  " && activeShow().kbdRing").toBool(), "keyboard mode: Episodes starts on the first episode's cover");
                t->key(Qt::Key_Down);
            }},
            {300, [t]() {
                t->expect(t->eval("activeShow().kbdIndex === 1 || activeShow().navCount === 1").toBool(), "first key on a fresh page moves straight away");
                t->key(Qt::Key_Escape);
            }},
            {800, [t]() {
                t->eval("win.openShowPage(backend.shows.showIdAt(shelfView.navCount - 1))");
            }},
            {1500, [t]() {
                t->expect(t->eval("activeShow().navCount === 0").toBool(), "last show has no episodes");
                t->expect(t->eval("win.navArea === 'top' && win.navBarIndex('top') === 0 && activeShow().backItem.kbdFocus").toBool(),
                          "keyboard mode, no episodes: focus on Back");
                t->hover(QPointF(300, 300));
            }},
            {100, [t]() { t->hover(QPointF(340, 330)); }},
            {300, [t]() {
                t->expect(!t->eval("win.keyboardMode").toBool(), "a real mouse move switches to mouse mode");
                t->expect(!t->eval("activeShow().backItem.kbdFocus").toBool(), "mouse mode: ring hidden");
                t->eval("win.back(); win.openShowPage(backend.shows.showIdAt(0))");
            }},
            {1500, [t]() {
                t->expect(!t->eval("activeShow().kbdRing").toBool() && !t->eval("win.navShown").toBool(),
                          "mouse mode: entering a page shows no key ring");
                t->key(Qt::Key_Down);
            }},
            {300, [t]() {
                t->expect(t->eval("win.keyboardMode && activeShow().kbdRing").toBool(), "key press after mouse: ring back");
                // Issue A: a library refresh (play/pause re-emits openShowChanged) must not
                // move focus from the cover to the text column.
                t->eval("win.navArea = 'grid'; activeShow().kbdCol = 0; backend.openShowChanged()");
                t->expect(t->eval("activeShow().kbdCol === 0").toBool(), "refresh keeps focus on the cover (Enter no longer jumps right)");
                // Enter acts on the focused episode by id, even if the row index went stale.
                t->eval("var s = activeShow(); s.kbdCol = 1; s.kbdEpisodeId = s.navCount > 1 ? (s.episodeModel !== null ? s.episodeModel : backend.episodes).episodeIdAt(1) : 0");
            }},
            {200, [t]() {
                const double want = t->eval("activeShow().kbdEpisodeId").toDouble();
                if (want != 0) {
                    t->eval("activeShow().kbdIndex = 0; activeShow().openNavItem()");
                }
            }},
            {800, [t]() {
                t->expect(t->eval("backend.openEpisodeId === activeShow().kbdEpisodeId || pageKind === 'episode'").toBool()
                          && t->eval("pageKind").toString() == "episode", "Enter opens the episode by id, not by a stale row");
                t->eval("win.openExplorePage()");
            }},
            {1200, [t]() {
                // Issue C: Find Tab order, wrapping.
                t->eval("win.keyboardMode = true; win.navShown = true; win.navArea = 'top'; win.navSetBar('top', 0)");
                QStringList seen;
                for (int i = 0; i < 6; ++i) {
                    seen << t->eval("win.navArea").toString();
                    t->eval("win.navStep(1)");
                }
                const QString got = seen.join(QLatin1Char(','));
                fprintf(stderr, "[uitest] find tab order: %s\n", qPrintable(got));
                const bool info = t->eval("explorePage.infoItem.visible").toBool();
                const bool grid = t->eval("explorePage.navCount > 0").toBool();
                QStringList cyc = {QStringLiteral("top"), QStringLiteral("search"), QStringLiteral("region")};
                if (info) cyc << QStringLiteral("info");
                if (grid) cyc << QStringLiteral("grid");
                QStringList exp;
                for (int i = 0; i < 6; ++i) exp << cyc.at(i % cyc.size());
                t->expect(got == exp.join(QLatin1Char(',')), "Find: Tab walks back, search, region, info, results and wraps");
                t->eval("win.navArea = 'search'; win.navStep(-1)");
                t->expect(t->eval("win.navArea").toString() == "top", "Find: Shift+Tab from search goes back to Back");
                // Kept covers: RAM-sized budget, and a force refresh drops them at once.
                const double avail = t->eval("backend.memAvailable()").toDouble();
                const double total = t->eval("backend.memTotal()").toDouble();
                const double budget = t->eval("explorePage.coverBudget()").toDouble();
                fprintf(stderr, "[uitest] meminfo avail=%.0f total=%.0f cover budget=%.0f\n", avail, total, budget);
                const double want = avail < total * 0.10 ? 0 : qBound(8.0 * 1048576, avail * 0.02, 32.0 * 1048576);
                t->expect(avail > 0 && total >= avail && budget == want, "Find: kept-covers budget = clamp(2% MemAvailable, 8 MB, 32 MB)");
                const char *seed = "explorePage.heldCovers = [{ s: 'file:///nonexistent-a.jpg', w: 32, h: 32 }, { s: 'file:///nonexistent-b.jpg', w: 32, h: 32 }]; explorePage.heldCovers.length";
                const bool seeded = t->eval(seed).toInt() == 2;
                t->eval("backend.refreshAll(true)");
                t->expect(seeded && t->eval("explorePage.heldCovers.length").toInt() == 0, "Find: force refresh (all) drops the kept previous-region covers");
                t->eval(seed);
                t->eval("backend.refreshOpenShow(true)");
                t->expect(t->eval("explorePage.heldCovers.length").toInt() == 0, "Find: force refresh (open show) drops the kept covers too");
            }},
        };
        t->run(0);
        return;
    }
    const QString shot = qEnvironmentVariable("OMAEAR_UI_TEST_SHOT");
    if (!shot.isEmpty()) {
        t->steps = {
            {1500, [t]() { t->eval("helpOpen = true"); }},
            {800, [t, shot]() { t->expect(t->win->grabWindow().save(shot), "saved screenshot"); }},
        };
        t->run(0);
        return;
    }
    t->steps = {
        {1500, [t]() {
            t->expect(t->eval("pageKind").toString() == "shelf", "starts on shelf");
            // The copied library keeps the user's shelf view and column count.
            // Menu.popup() anchors its top-left at the cursor, so in list view
            // (and in a dense gallery) the center of cover 1 lies inside the
            // menu opened on cover 0. closePopupsAt only click-throughs a
            // press that misses the panel. Pin a wide gallery before any click.
            t->eval("backend.setShelfView('gallery'); backend.setShelfColumns(4)");
            t->expect(t->eval("shelfView.navCount >= 2").toBool(), "shelf shows at least 2 covers");
            t->eval("win.openShowPage(backend.shows.showIdAt(0))");
        }},
        {1300 + t->dwellMs, [t]() {
            t->expect(t->eval("pageKind").toString() == "show", "show page opened");
            // Right-click an episode row (its description area: left part of the row).
            t->click(t->centerOf("activeShow().rowItemAt(0)"), Qt::RightButton);
        }},
        {900 + t->dwellMs, [t]() {
            t->expect(t->eval("activeShow().episodeMenuOpen").toBool(), "episode menu open after right-click");
            t->click(t->centerOf("activeShow().backItem"), Qt::LeftButton);
        }},
        {1000 + t->dwellMs, [t]() {
            t->expect(t->eval("pageKind").toString() == "shelf", "one click on Back closes menu AND goes back");
            t->click(t->centerOf("shelfView.coverItemAt(0)"), Qt::RightButton);
        }},
        {900 + t->dwellMs, [t]() {
            t->expect(t->eval("shelfView.coverMenuOpen").toBool()
                      && t->eval("shelfView.coverMenuShow").toDouble() == t->eval("backend.shows.showIdAt(0)").toDouble(),
                      "cover menu open on cover 0");
            const QPointF cover1 = t->centerOf("shelfView.coverItemAt(1)");
            const bool outside = !t->eval(QStringLiteral("shelfView.coverMenuContains(%1, %2)")
                                               .arg(cover1.x(), 0, 'f', 1)
                                               .arg(cover1.y(), 0, 'f', 1)).toBool();
            fprintf(stderr, "[uitest] cover 1 center %.1f,%.1f is %s the open menu\n",
                    cover1.x(), cover1.y(), outside ? "outside" : "INSIDE");
            t->expect(outside, "cover 1 center is outside the menu opened for cover 0");
            t->click(cover1, Qt::RightButton);
        }},
        {1000 + t->dwellMs, [t]() {
            t->expect(t->eval("shelfView.coverMenuOpen").toBool()
                      && t->eval("shelfView.coverMenuShow").toDouble() == t->eval("backend.shows.showIdAt(1)").toDouble(),
                      "right-click on cover 1 reopens the menu for cover 1");
            t->click(QPointF(700, 450), Qt::LeftButton); // somewhere on the shelf
        }},
        {900 + t->dwellMs, [t]() {
            t->expect(!t->eval("shelfView.coverMenuOpen").toBool(), "left-click elsewhere closes the menu");
        }},
    };
    t->run(0);
}
