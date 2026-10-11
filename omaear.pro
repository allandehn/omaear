QT += quick quickcontrols2 sql network dbus multimedia
CONFIG += c++17
CONFIG -= app_bundle

TARGET = omaear
# Single source of the app version (--version, User-Agent strings, package).
VERSION = 0.1.7
DEFINES += OMAEAR_VERSION=\\\"$$VERSION\\\"
TEMPLATE = app

SOURCES += \
    src/main.cpp \
    src/library.cpp \
    src/feed.cpp \
    src/theme.cpp \
    src/models.cpp \
    src/covercache.cpp \
    src/backend.cpp \
    src/player.cpp \
    src/growingmediadevice.cpp \
    src/selftest.cpp \
    src/explore.cpp \
    src/updates.cpp

HEADERS += \
    src/library.h \
    src/feed.h \
    src/theme.h \
    src/models.h \
    src/covercache.h \
    src/backend.h \
    src/player.h \
    src/growingmediadevice.h \
    src/explore.h \
    src/netaccess.h \
    src/updates.h

RESOURCES += resources.qrc

# `make install`: default is the user prefix (~/.local, no root). Packaging:
#   qmake6 PREFIX=/usr && make && make INSTALL_ROOT="$pkgdir" install
isEmpty(PREFIX): PREFIX = $$(HOME)/.local
target.path = $$PREFIX/bin

# Desktop entry: plain `omaear` for a system install (/usr/bin is on PATH),
# the absolute path for the user prefix (launchers may not see ~/.local/bin).
equals(PREFIX, /usr): DESKTOP_EXEC = omaear
else: DESKTOP_EXEC = $$PREFIX/bin/omaear
QMAKE_SUBSTITUTES += com.github.allanjorch.omaear.desktop.in
desktop.files = $$OUT_PWD/com.github.allanjorch.omaear.desktop
desktop.CONFIG += no_check_exist
desktop.path = $$PREFIX/share/applications

license.files = LICENSE
license.path = $$PREFIX/share/licenses/omaear

# App icons (hicolor theme)
icon16.path = $$PREFIX/share/icons/hicolor/16x16/apps
icon16.extra = install -Dm644 $$PWD/assets/icons/omaear-16.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/16x16/apps/omaear.png
icon24.path = $$PREFIX/share/icons/hicolor/24x24/apps
icon24.extra = install -Dm644 $$PWD/assets/icons/omaear-24.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/24x24/apps/omaear.png
icon32.path = $$PREFIX/share/icons/hicolor/32x32/apps
icon32.extra = install -Dm644 $$PWD/assets/icons/omaear-32.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/32x32/apps/omaear.png
icon48.path = $$PREFIX/share/icons/hicolor/48x48/apps
icon48.extra = install -Dm644 $$PWD/assets/icons/omaear-48.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/48x48/apps/omaear.png
icon64.path = $$PREFIX/share/icons/hicolor/64x64/apps
icon64.extra = install -Dm644 $$PWD/assets/icons/omaear-64.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/64x64/apps/omaear.png
icon128.path = $$PREFIX/share/icons/hicolor/128x128/apps
icon128.extra = install -Dm644 $$PWD/assets/icons/omaear-128.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/128x128/apps/omaear.png
icon256.path = $$PREFIX/share/icons/hicolor/256x256/apps
icon256.extra = install -Dm644 $$PWD/assets/icons/omaear-256.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/256x256/apps/omaear.png
icon512.path = $$PREFIX/share/icons/hicolor/512x512/apps
icon512.extra = install -Dm644 $$PWD/assets/icons/omaear-512.png $(INSTALL_ROOT)$$PREFIX/share/icons/hicolor/512x512/apps/omaear.png
iconsvg.files = assets/icons/omaear.svg
iconsvg.path = $$PREFIX/share/icons/hicolor/scalable/apps
iconsym.files = assets/icons/omaear-symbolic.svg
iconsym.path = $$PREFIX/share/icons/hicolor/symbolic/apps
INSTALLS += target desktop icon16 icon24 icon32 icon48 icon64 icon128 icon256 icon512 iconsvg iconsym
equals(PREFIX, /usr): INSTALLS += license
