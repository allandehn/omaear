#include <QIcon>
#include "backend.h"
#include "library.h"
#include "search.h"
#include <cstdio>
#include "covercache.h"
#include <QThreadPool>
#include "iconprovider.h"
#include "explore.h"
#include "netaccess.h"
#include "player.h"
#include "theme.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QEvent>
#include <QFont>
#include <QGuiApplication>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QDir>
#include <QFileInfo>
#include <pwd.h>
#include <unistd.h>
#include <cstdlib>
#include <climits>

// "?" is Shift+/ on a US layout and a different key elsewhere. Match the
// character, and Key_Question when the platform reports that instead of text.
bool isHelpQuestion(const QKeyEvent *key)
{
    if (key->isAutoRepeat())
        return false;
    if (key->modifiers() & (Qt::ControlModifier | Qt::MetaModifier))
        return false;
    return key->text() == QLatin1String("?") || key->key() == Qt::Key_Question;
}

class WindowInputFilter : public QObject {
public:
    QObject *window = nullptr;

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (!window || !eventIsOurs(watched))
            return false;

        // Page history: mouse side buttons (XButton1/2) anywhere in the window,
        // including over lists, text, the player bar and popups. The app-wide
        // filter sees them before any child MouseArea can accept them.
        if (event->type() == QEvent::MouseButtonPress
            || event->type() == QEvent::MouseButtonDblClick
            || event->type() == QEvent::MouseButtonRelease) {
            const auto *mouse = static_cast<const QMouseEvent *>(event);
            const Qt::MouseButton button = mouse->button();
            // Click-through for menus and popups: a press outside the open one
            // closes it here, before the window delivers the press, and is NOT
            // consumed, so it still reaches Back, another cover, … (Qt's own
            // CloseOnPressOutside lets the popup overlay swallow it).
            if (event->type() == QEvent::MouseButtonPress && watched == window
                && button != Qt::BackButton && button != Qt::ForwardButton) {
                const QPointF p = mouse->scenePosition();
                QMetaObject::invokeMethod(window, "closePopupsAt", Qt::DirectConnection,
                                          Q_ARG(QVariant, p.x()), Q_ARG(QVariant, p.y()),
                                          Q_ARG(QVariant, button == Qt::RightButton));
            }
            if (button != Qt::BackButton && button != Qt::ForwardButton)
                return false;
            // Act once per physical press; swallow the rest so nothing else reacts.
            if (event->type() != QEvent::MouseButtonRelease)
                QMetaObject::invokeMethod(window, button == Qt::BackButton ? "back" : "forward",
                                          Qt::DirectConnection);
            return true;
        }

        // Dedicated Back / Forward keys (multimedia keyboards, some mice).
        if (event->type() == QEvent::KeyPress) {
            const auto *key = static_cast<const QKeyEvent *>(event);
            if (key->key() == Qt::Key_Back || key->key() == Qt::Key_Forward) {
                if (!key->isAutoRepeat())
                    QMetaObject::invokeMethod(window, key->key() == Qt::Key_Back ? "back" : "forward",
                                              Qt::DirectConnection);
                return true;
            }
            // Shortcuts overlay. toggleHelp returns false while a text field has
            // focus so "?" is still typed into search and the add-feed box.
            if (isHelpQuestion(key)) {
                QVariant consumed;
                const bool called = QMetaObject::invokeMethod(
                    window, "toggleHelp", Qt::DirectConnection,
                    Q_RETURN_ARG(QVariant, consumed));
                return called && consumed.toBool();
            }
            return false;
        }

        if (event->type() != QEvent::Wheel)
            return false;
        const auto *wheel = static_cast<const QWheelEvent *>(event);
        if (!(wheel->modifiers() & Qt::ControlModifier))
            return false;
        int delta = wheel->angleDelta().y();
        if (delta == 0) {
            const int pixel = wheel->pixelDelta().y();
            if (pixel > 0)
                delta = 120;
            else if (pixel < 0)
                delta = -120;
        }
        if (delta == 0)
            return false;
        QVariant consumed;
        const QVariant deltaArg(delta);
        const bool called = QMetaObject::invokeMethod(
            window, "zoomFromWheel", Qt::DirectConnection,
            Q_RETURN_ARG(QVariant, consumed), Q_ARG(QVariant, deltaArg));
        return called && consumed.toBool();
    }

private:
    bool eventIsOurs(QObject *watched) const
    {
        if (watched == window)
            return true;
        if (auto *item = qobject_cast<QQuickItem *>(watched))
            return item->window() == window;
        if (auto *view = qobject_cast<QWindow *>(watched))
            return view == window;
        return false;
    }
};

class UiBridge : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.github.allandehn.omaear.Ui")
public:
    explicit UiBridge(Backend *backend, QObject *parent = nullptr)
        : QObject(parent)
        , m_backend(backend)
    {
    }

public slots:
    void Raise() { m_backend->raiseWindow(); }

private:
    Backend *m_backend;
};

int runSelfTest(int argc, char **argv);
void startUiTest(QQmlApplicationEngine &engine);

// The UI test rewrites and deletes Omarchy theme files under $HOME
// (~/.local/state/omarchy/current/theme, ~/.config/omarchy/shell.toml) and
// uses the library in XDG_DATA_HOME. Refuse to run it unless HOME is a
// throwaway home: it must hold the marker file release-validate-tree.sh
// writes, and must not be the account's real home directory. Each of
// XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME, XDG_STATE_HOME and
// XDG_RUNTIME_DIR, if set, must resolve (canonical path) inside the
// throwaway root. The root is HOME's parent, matching the layout used
// by release-validate-tree.sh: HOME is $root/home, and the XDG dirs sit
// beside it as $root/{data,config,cache,run}. The root must hold the
// marker .omaear-ui-test-root and must not be empty, "/", the real home
// or an ancestor of it, or a shared dir (/tmp, /var/tmp, /dev/shm,
// /run/user/<uid>, $TMPDIR).
static QString uiTestResolvedPath(const QString &path)
{
    const QString abs = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    const QString canon = QFileInfo(abs).canonicalFilePath();
    if (!canon.isEmpty())
        return canon;
    // The path may not exist yet. Walk up to an existing ancestor so a
    // symlink such as /tmp/test-data -> ~/.local/share still resolves.
    QDir dir(abs);
    QString rest;
    while (!dir.exists() && !dir.isRoot()) {
        const QString name = dir.dirName();
        dir.cdUp();
        rest = rest.isEmpty() ? name : name + QLatin1Char('/') + rest;
    }
    const QString base = dir.canonicalPath();
    if (base.isEmpty())
        return abs;
    return rest.isEmpty() ? base : QDir::cleanPath(base + QLatin1Char('/') + rest);
}

static bool uiTestPathIsInside(const QString &path, const QString &root)
{
    if (path == root)
        return true;
    const QString prefix = root.endsWith(QLatin1Char('/')) ? root : root + QLatin1Char('/');
    return path.startsWith(prefix);
}

static bool uiTestHomeIsThrowaway(QString *why)
{
    const QString home = QDir::homePath();
    // Resolves even when HOME does not exist yet, so the root checks below
    // can refuse it before any file is looked at.
    const QString canon = uiTestResolvedPath(home);
    QString realHome;
    if (const passwd *pw = getpwuid(getuid())) {
        const QString real = QFileInfo(QString::fromLocal8Bit(pw->pw_dir)).canonicalFilePath();
        realHome = real;
        if (!real.isEmpty() && canon == real) {
            *why = QStringLiteral("HOME is your real home directory (%1)").arg(home);
            return false;
        }
    }
    const QString root = QFileInfo(canon).dir().canonicalPath();
    if (root.isEmpty() || root == QLatin1String("/")) {
        *why = QStringLiteral("the throwaway root for HOME (%1) is empty or /").arg(home);
        return false;
    }
    if (!realHome.isEmpty() && uiTestPathIsInside(realHome, root)) {
        *why = QStringLiteral("the throwaway root (%1) is your real home directory or contains it").arg(root);
        return false;
    }
    QStringList shared = {QStringLiteral("/tmp"), QStringLiteral("/var/tmp"), QStringLiteral("/dev/shm"),
                          QStringLiteral("/run/user/%1").arg(getuid())};
    if (const QString tmpdir = qEnvironmentVariable("TMPDIR"); !tmpdir.isEmpty())
        shared << tmpdir;
    for (const QString &dir : std::as_const(shared)) {
        const QString c = QFileInfo(dir).canonicalFilePath();
        if (!c.isEmpty() && root == c) {
            *why = QStringLiteral("the throwaway root (%1) is a shared directory").arg(root);
            return false;
        }
    }
    if (!QFileInfo::exists(home + QStringLiteral("/.omaear-ui-test-home"))) {
        *why = QStringLiteral("HOME (%1) has no .omaear-ui-test-home marker").arg(home);
        return false;
    }
    if (!QFileInfo::exists(root + QStringLiteral("/.omaear-ui-test-root"))) {
        *why = QStringLiteral("the throwaway root (%1) has no .omaear-ui-test-root marker").arg(root);
        return false;
    }
    static const char *const xdgVars[] = {
        "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
        "XDG_STATE_HOME", "XDG_RUNTIME_DIR"
    };
    for (const char *name : xdgVars) {
        const QString value = qEnvironmentVariable(name);
        if (value.isEmpty())
            continue;
        const QString resolved = uiTestResolvedPath(value);
        if (!uiTestPathIsInside(resolved, root)) {
            *why = QStringLiteral("%1 (%2) is outside the throwaway root (%3)")
                       .arg(QLatin1String(name), value, root);
            return false;
        }
    }
    return true;
}

// --self-test writes QSettings (refresh/lastSuccessMs and anything else using
// Library::settingsPath) under XDG_CONFIG_HOME, and may use the data and cache
// locations too. Refuse unless all three are set and none resolves to the
// account's real defaults, or to a path inside them. The check uses POSIX
// realpath rather than Qt file APIs, so it can run before QCoreApplication
// exists (Qt path helpers can hang in that state when HOME is a throwaway
// directory). The UI test has its own, stricter throwaway-HOME guard. Set
// OMAEAR_SELFTEST_ALLOW_REAL_XDG=1 only for a deliberate run that is allowed
// to touch the real XDG dirs.
static QByteArray selfTestAbsPath(const QByteArray &path)
{
    if (path.startsWith('/'))
        return path;
    char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd)))
        return path;
    if (path.isEmpty())
        return QByteArray(cwd);
    return QByteArray(cwd) + '/' + path;
}

// Canonicalize path, including one that does not exist yet: resolve the
// longest existing ancestor with realpath and join the rest, so a symlink
// such as /tmp/test-data -> ~/.local/share still resolves.
static QByteArray selfTestResolvedPath(const QByteArray &path)
{
    const QByteArray abs = selfTestAbsPath(path);
    char buf[PATH_MAX];
    if (realpath(abs.constData(), buf))
        return QByteArray(buf);

    QByteArray cur = abs;
    QByteArray rest;
    while (!cur.isEmpty() && cur != "/") {
        if (realpath(cur.constData(), buf)) {
            const QByteArray base(buf);
            return rest.isEmpty() ? base : base + '/' + rest;
        }
        const int slash = cur.lastIndexOf('/');
        const QByteArray name = slash >= 0 ? cur.mid(slash + 1) : cur;
        rest = rest.isEmpty() ? name : name + '/' + rest;
        if (slash <= 0)
            cur = QByteArray("/");
        else
            cur = cur.left(slash);
        // Collapse repeated slashes left by odd input such as "//foo".
        while (cur.size() > 1 && cur.endsWith('/'))
            cur.chop(1);
    }
    if (realpath("/", buf))
        return rest.isEmpty() ? QByteArray("/") : QByteArray(buf) + '/' + rest;
    return abs;
}

static bool selfTestPathIsInside(const QByteArray &path, const QByteArray &root)
{
    if (path == root)
        return true;
    const QByteArray prefix = root.endsWith('/') ? root : root + '/';
    return path.startsWith(prefix);
}

static bool selfTestXdgIsThrowaway(QString *why)
{
    if (qEnvironmentVariableIntValue("OMAEAR_SELFTEST_ALLOW_REAL_XDG") == 1)
        return true;

    static const struct {
        const char *name;
        const char *relative;
    } vars[] = {
        {"XDG_CONFIG_HOME", ".config"},
        {"XDG_DATA_HOME", ".local/share"},
        {"XDG_CACHE_HOME", ".cache"},
    };

    QList<QByteArray> homes;
    const QByteArray envHome = qgetenv("HOME").trimmed();
    if (!envHome.isEmpty())
        homes << selfTestResolvedPath(envHome);
    if (const passwd *pw = getpwuid(getuid())) {
        if (pw->pw_dir && pw->pw_dir[0]) {
            const QByteArray real = selfTestResolvedPath(QByteArray(pw->pw_dir));
            if (!real.isEmpty() && !homes.contains(real))
                homes << real;
        }
    }

    for (const auto &v : vars) {
        const QByteArray value = qgetenv(v.name).trimmed();
        if (value.isEmpty()) {
            *why = QStringLiteral("%1 is not set").arg(QLatin1String(v.name));
            return false;
        }
        const QByteArray resolved = selfTestResolvedPath(value);
        for (const QByteArray &home : std::as_const(homes)) {
            const QByteArray def = selfTestResolvedPath(home + '/' + v.relative);
            if (resolved == def || selfTestPathIsInside(resolved, def)) {
                *why = QStringLiteral("%1 (%2) is the real default or inside it (%3)")
                           .arg(QLatin1String(v.name),
                                QString::fromLocal8Bit(value),
                                QString::fromLocal8Bit(def));
                return false;
            }
        }
    }
    return true;
}

int main(int argc, char **argv)
{
    startupTimer().start();
    QStringList args;
    for (int i = 1; i < argc; ++i)
        args << QString::fromLocal8Bit(argv[i]);
    if (args.contains(QStringLiteral("--version"))) {
        printf("omaear %s\n", OMAEAR_VERSION);
        return 0;
    }
    if (args.contains(QStringLiteral("--player")))
        return runPlayer(argc, argv);
    if (args.contains(QStringLiteral("--self-test"))) {
        QString why;
        if (!selfTestXdgIsThrowaway(&why)) {
            fprintf(stderr,
                    "omaear: refusing to run --self-test: %s. "
                    "Set XDG_CONFIG_HOME, XDG_DATA_HOME and XDG_CACHE_HOME to throwaway "
                    "directories, not ~/.config, ~/.local/share or ~/.cache.\n",
                    qPrintable(why));
            return 3;
        }
        return runSelfTest(argc, argv);
    }
    if (qEnvironmentVariableIntValue("OMAEAR_UI_TEST") == 1) {
        QString why;
        if (!uiTestHomeIsThrowaway(&why)) {
            fprintf(stderr, "omaear: refusing to run the UI test: %s.\n"
                            "It rewrites Omarchy theme files under HOME and uses the library "
                            "in XDG_DATA_HOME. Run it through scripts/release-validate-tree.sh, "
                            "which gives it a throwaway HOME and XDG dirs.\n",
                    qPrintable(why));
            return 3;
        }
    }

    // Launch "jump": with wp_fractional_scale Qt renders the first frame at the
    // output's integer scale (2), drops to 1 when the surface enters the output,
    // then re-renders at the fractional scale (1.6) ~0.5 s later. Each switch
    // re-lays out text and art, so the whole interior visibly shifts. Without the
    // protocol Qt stays at the integer scale from the first frame and the
    // compositor scales it down (as GTK3 apps do). OMAEAR_FRACTIONAL_SCALE=1 opts out.
    if (qEnvironmentVariable("OMAEAR_FRACTIONAL_SCALE") != QLatin1String("1")) {
        QByteArray disabled = qgetenv("QT_WAYLAND_DISABLED_INTERFACES");
        if (!disabled.contains("wp_fractional_scale_manager_v1")) {
            if (!disabled.isEmpty())
                disabled.append(',');
            disabled.append("wp_fractional_scale_manager_v1");
            qputenv("QT_WAYLAND_DISABLED_INTERFACES", disabled);
        }
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("omaear"));
    app.setApplicationDisplayName(QStringLiteral("OmaEar"));
    app.setDesktopFileName(QStringLiteral("com.github.allandehn.omaear"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/omaear.svg")));
    QFont uiFont(QStringLiteral("monospace"));
    uiFont.setStyleHint(QFont::Monospace);
    uiFont.setWeight(QFont::Normal);
    app.setFont(uiFont);
    QQuickStyle::setStyle(QStringLiteral("Material"));

    auto bus = QDBusConnection::sessionBus();
    const QString uiService = QStringLiteral("com.github.allandehn.omaear");
    if (bus.interface()->isServiceRegistered(uiService)) {
        QDBusInterface ui(uiService, QStringLiteral("/com/github/allandehn/omaear/Ui"),
                          QStringLiteral("com.github.allandehn.omaear.Ui"), bus);
        ui.call(QStringLiteral("Raise"));
        return 0;
    }
    // Pre-rename build still running: it has the library open at the old path.
    if (bus.interface()->isServiceRegistered(QStringLiteral("com.github.allanjorch.podcast"))
        || bus.interface()->isServiceRegistered(QStringLiteral("com.github.allanjorch.podcast.Player"))) {
        const char *msg = "OmaEar: the old Podcasts app is still running. Quit it first (pkill -f podcast), then start OmaEar.";
        fprintf(stderr, "%s\n", msg);
        QProcess::startDetached(QStringLiteral("notify-send"), {QStringLiteral("OmaEar"),
            QStringLiteral("Quit the old Podcasts app first (pkill -f podcast), then start OmaEar.")});
        return 1;
    }
    {
        QString moved;
        Library::migrateLegacyLocations(&moved);
        if (!moved.isEmpty())
            qInfo("[omaear] rename migration:\n%s", qPrintable(moved));
    }

    Library library;
    if (!library.isOpen())
        return 1;
    {
        // Shelf covers into memory while QML loads, so they paint with the first frame.
        QStringList paths;
        for (const ShowRow &row : library.shows())
            if (!row.imagePath.isEmpty())
                paths << row.imagePath;
        prewarmCovers(paths, {kCoverTileSide, kCoverRowSide});
    }

    Theme theme;
    Backend backend(library);
    Explore explore(library, backend);
    LibrarySearch librarySearch(library);
    QObject::connect(&backend, &Backend::libraryChanged, &librarySearch, &LibrarySearch::libraryChanged);
    UiBridge bridge(&backend);
    bus.registerObject(QStringLiteral("/com/github/allandehn/omaear/Ui"), &bridge,
                       QDBusConnection::ExportAllSlots);
    bus.registerService(uiService);


    CoverCache coverCache;
    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(new AppNetworkAccessManagerFactory);
    engine.addImageProvider(QStringLiteral("covers"), new CoverImageProvider);
    engine.addImageProvider(QStringLiteral("icons"), new IconProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("theme"), &theme);
    engine.rootContext()->setContextProperty(QStringLiteral("coverCache"), &coverCache);
    engine.rootContext()->setContextProperty(QStringLiteral("explore"), &explore);
    engine.rootContext()->setContextProperty(QStringLiteral("librarySearch"), &librarySearch);
    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    if (startupTiming()) {
        fprintf(stderr, "timing: qml loaded %lld ms\n", qint64(startupTimer().elapsed()));
        if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst())) {
            // Single-shot: frameSwapped is queued from the render thread and can be
            // delivered twice before a manual disconnect runs.
            QObject::connect(win, &QQuickWindow::frameSwapped, win, []() {
                fprintf(stderr, "timing: first frame %lld ms\n", qint64(startupTimer().elapsed()));
            }, Qt::SingleShotConnection);
        }
        // Harness: grow the window (bigger tiles) to check resizes never reload covers.
        if (qEnvironmentVariableIntValue("OMAEAR_TIMING_RESIZE") == 1) {
            if (auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst())) {
                QTimer::singleShot(1500, win, [win]() {
                    fprintf(stderr, "timing: resize %lld ms\n", qint64(startupTimer().elapsed()));
                    win->resize(2560, 1440);
                    QTimer::singleShot(500, win, [win]() { fprintf(stderr, "timing: window now %dx%d\n", win->width(), win->height()); });
                });
            }
        }
        const int quitMs = qEnvironmentVariableIntValue("OMAEAR_TIMING_QUIT_MS");
        if (quitMs > 0)
            QTimer::singleShot(quitMs, &app, &QCoreApplication::quit);
    }
    if (qEnvironmentVariableIntValue("OMAEAR_UI_TEST") == 1)
        startUiTest(engine);
    WindowInputFilter inputFilter;
    inputFilter.window = engine.rootObjects().constFirst();
    app.installEventFilter(&inputFilter);
    const int rc = app.exec();
    // Let an in-flight cover warm (at most 2) finish before statics go away;
    // queued ones are dropped.
    coverWarmPool()->clear();
    coverWarmPool()->waitForDone();
    return rc;
}

#include "main.moc"
