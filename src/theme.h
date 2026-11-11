#pragma once

#include <QDBusVariant>
#include <QColor>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariant>
#include <functional>

class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor background READ background NOTIFY changed)
    Q_PROPERTY(QColor foreground READ foreground NOTIFY changed)
    Q_PROPERTY(QColor accent READ accent NOTIFY changed)
    Q_PROPERTY(QColor blue READ blue NOTIFY changed)
    Q_PROPERTY(QColor selection READ selection NOTIFY changed)
    Q_PROPERTY(QColor muted READ muted NOTIFY changed)
    Q_PROPERTY(QColor dim READ dim NOTIFY changed)
    Q_PROPERTY(QColor urgent READ urgent NOTIFY changed)
    // Popup surfaces (menus, popups), read the way Omarchy's shell/Commons/Color.qml reads
    // them: [popups] background / text / border (+ -alpha) from the generated theme
    // shell.toml, with ~/.config/omarchy/shell.toml on top. border is normally
    // "hyprland.active-border" (the theme's Hyprland border, first gradient stop,
    // which Omarchy writes from colors.toml hyprland_active_border, else the accent).
    // Unset or unreadable: background / foreground / accent.
    Q_PROPERTY(QColor popupBackground READ popupBackground NOTIFY changed)
    Q_PROPERTY(QColor popupText READ popupText NOTIFY changed)
    Q_PROPERTY(QColor border READ border NOTIFY changed)
    // Tints derived from the live theme in OKLCH (recomputed in loadColors()).
    Q_PROPERTY(QColor barBackground READ barBackground NOTIFY changed)
    Q_PROPERTY(QColor pillBackground READ pillBackground NOTIFY changed)
    // Live Hyprland decoration:rounding (R) and the radius scale derived from it.
    Q_PROPERTY(int rounding READ rounding NOTIFY roundingChanged)
    Q_PROPERTY(int rCard READ rounding NOTIFY roundingChanged)
    Q_PROPERTY(int rButton READ rButton NOTIFY roundingChanged)
    Q_PROPERTY(int rIcon READ rIcon NOTIFY roundingChanged)
    // Prefix for the app's own icons: joins follow the live rounding.
    Q_PROPERTY(QString iconBase READ iconBase NOTIFY roundingChanged)
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY changed)
    Q_PROPERTY(qreal textScale READ textScale NOTIFY changed)
    Q_PROPERTY(int caption READ caption NOTIFY changed)
    Q_PROPERTY(int bodySmall READ bodySmall NOTIFY changed)
    Q_PROPERTY(int body READ body NOTIFY changed)
    Q_PROPERTY(int subtitle READ subtitle NOTIFY changed)
    Q_PROPERTY(int titleSize READ titleSize NOTIFY changed)
    Q_PROPERTY(int heading READ heading NOTIFY changed)
    Q_PROPERTY(int display READ display NOTIFY changed)

public:
    explicit Theme(QObject *parent = nullptr);

    QColor background() const { return m_background; }
    QColor foreground() const { return m_foreground; }
    QColor accent() const { return m_accent; }
    QColor blue() const { return m_blue; }
    QColor selection() const { return m_selection; }
    QColor muted() const { return m_muted; }
    QColor dim() const { return m_dim; }
    QColor urgent() const { return m_urgent; }
    QColor popupBackground() const { return m_popupBackground; }
    QColor popupText() const { return m_popupText; }
    QColor border() const { return m_border; }
    // One colour token as Omarchy writes them: "rgba(33ccffee)", "rgb(7aa2f7)",
    // "#7aa2f7", "0xee33ccff", "transparent"; opaque RGB, invalid when it is none of these.
    static QColor parseShellColor(const QString &token);
    // A shell.toml colour value, after Color.qml's flatColor: the first token that is not an
    // angle ("rgba(a) rgba(b) 45deg" -> the first stop); a role name looks up shell.toml
    // ("hyprland.active-border") or the palette (foreground, text, background, accent,
    // urgent, muted). Invalid when nothing resolves.
    static QColor resolveShellColor(const QString &value, const QHash<QString, QString> &shell,
                                    const QHash<QString, QColor> &palette);
    // shell.toml as a flat "section.key" -> string dictionary (Color.qml parseShell).
    static QHash<QString, QString> parseShellToml(const QString &text);
    QColor barBackground() const { return m_barBackground; }
    QColor pillBackground() const { return m_pillBackground; }
    // Shift a colour's OKLCH lightness by dL and scale its chroma by cScale,
    // keeping hue and alpha. Out-of-gamut results are pulled in by lowering C.
    static qreal oklchLightness(const QColor &c);
    static QColor oklchNudge(const QColor &c, qreal dL, qreal cScale = 1.0);
    int rounding() const { return m_rounding; }
    int rButton() const { return qMin(m_rounding, 4); }
    int rIcon() const { return qMin(qRound(m_rounding / 4.0), 2); }
    QString iconBase() const { return m_rounding > 0 ? QStringLiteral("image://icons/round/") : QStringLiteral("image://icons/square/"); }
    // Radius for an element inset by p inside a card: max(R - p, 0).
    Q_INVOKABLE int rInner(qreal p) const { return qMax(qRound(m_rounding - p), 0); }
    // Re-read rounding now (called on window focus; also polled every second).
    Q_INVOKABLE void refreshRounding();
    bool darkMode() const { return m_darkMode; }
    qreal textScale() const { return m_textScale; }
    int caption() const { return m_caption; }
    int bodySmall() const { return m_bodySmall; }
    int body() const { return m_body; }
    int subtitle() const { return m_subtitle; }
    int titleSize() const { return m_titleSize; }
    int heading() const { return m_heading; }
    int display() const { return m_display; }

signals:
    void changed();
    void roundingChanged();

private slots:
    void handlePortalSettingChanged(const QString &nameSpace, const QString &key,
                                    const QDBusVariant &value);

private:
    void loadColors();
    void loadType();
    void watchColors();
    void requestPortalSetting(const QString &nameSpace, const QString &key,
                              const std::function<void(const QVariant &)> &handler);
    void requestTextScale();
    void applyTextScale(qreal scale);

    QColor m_background = QColor("#101010");
    QColor m_foreground = QColor("#eeeeee");
    QColor m_accent = QColor("#5584aa");
    QColor m_blue = QColor("#5584aa");
    QColor m_selection = QColor("#186a9a");
    QColor m_muted = QColor("#8a8a8a");
    QColor m_dim = QColor("#9a9a9a");
    bool m_darkMode = true;
    qreal m_textScale = 1.0;
    int m_caption = 14;
    int m_bodySmall = 15;
    int m_body = 14;
    int m_subtitle = 13;
    int m_titleSize = 14;
    int m_heading = 16;
    int m_display = 24;
    QFileSystemWatcher m_watcher;
    QColor m_urgent = QColor("#e06c75");
    QColor m_border = QColor("#5584aa");
    QColor m_popupBackground = QColor("#101010");
    QColor m_popupText = QColor("#eeeeee");
    QColor m_barBackground = QColor("#0d0d0d");
    QColor m_pillBackground = QColor("#0b0b0b");
    int m_rounding = 0;          // last good value; Omarchy default is square
    bool m_roundingFixed = false; // OMAEAR_ROUNDING override (tests, screenshots)
    QProcess m_roundingProc;
    QTimer m_roundingPoll;
};
