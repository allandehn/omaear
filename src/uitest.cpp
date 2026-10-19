// Headless UI self-test (OMAEAR_UI_TEST=1, offscreen, temp library only).
// Drives the real window with synthetic mouse events delivered to THIS
// process's QQuickWindow, then quits with 0 (pass) or 1 (fail).
#include <QCursor>
#include <QGuiApplication>
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
    // Realistic: move there (hover), press, hold ~90 ms (mid-fade), release.
    void click(QPointF p, Qt::MouseButton b, std::function<void()> after = {})
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
                QObject *first = nullptr;
                QMetaObject::invokeMethod(o, "itemAt", Q_RETURN_ARG(QQuickItem *, *reinterpret_cast<QQuickItem **>(&first)), Q_ARG(int, 0));
                fprintf(stderr, "[uitest]   visible popup: %s modal=%d opened=%d x=%.0f y=%.0f w=%.0f h=%.0f first=%s\n", o->metaObject()->className(),
                        o->property("modal").toBool(), o->property("opened").toBool(),
                        o->property("x").toDouble(), o->property("y").toDouble(), o->property("width").toDouble(), o->property("height").toDouble(),
                        first ? qPrintable(first->property("text").toString()) : "-");
            }
        }
    }
    void expect(bool ok, const char *what)
    {
        fprintf(stderr, "[uitest] %s %s\n", ok ? "PASS" : "FAIL", what);
        if (!ok)
            ++fails;
    }
    // Wait for the launch refresh to finish: a shelf reload mid-click recreates
    // the cover delegates and cancels the press (test noise, not a menu bug).
    void waitIdle(std::function<void()> then, int triesLeft = 120)
    {
        if (triesLeft <= 0 || !eval("backend.busy").toBool()) {
            fprintf(stderr, "[uitest] library idle (busy=%d)\n", eval("backend.busy").toBool());
            QTimer::singleShot(800, win, then);
            return;
        }
        QTimer::singleShot(250, win, [this, then, triesLeft]() { waitIdle(then, triesLeft - 1); });
    }
    void run(int i)
    {
        if (i == 0) {
            waitIdle([this]() { runFrom(0); });
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
    t->steps = {
        {1500, [t]() {
            t->expect(t->eval("pageKind").toString() == "shelf", "starts on shelf");
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
            t->click(t->centerOf("shelfView.coverItemAt(1)"), Qt::RightButton);
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
