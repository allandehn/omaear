#pragma once

#include <QDBusVariant>
#include <QColor>
#include <QFileSystemWatcher>
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
    int m_rounding = 0;          // last good value; Omarchy default is square
    bool m_roundingFixed = false; // OMAEAR_ROUNDING override (tests, screenshots)
    QProcess m_roundingProc;
    QTimer m_roundingPoll;
};
