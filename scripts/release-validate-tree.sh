#!/usr/bin/env bash
# Build one extracted OmaEar source tree and run its headless tests against
# throwaway fixtures only. Called by release.sh --validate and --publish on a
# git archive of the reviewed commit; it can also be run by hand:
#
#   scripts/release-validate-tree.sh SRC_DIR X.Y.Z WORK_DIR
#
# SRC_DIR is built in place (qmake6 + make). WORK_DIR gets the build log, one
# throwaway HOME/XDG tree per test run, and the UI test logs. Nothing here
# reads or writes the user's real library, config, cache or session: each run
# gets its own HOME and XDG dirs, the compositor and display variables are
# unset, the app runs offscreen under its own private D-Bus session, and the
# library it sees is built from tests/nav-feeds by this script.
set -euo pipefail

die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $# -eq 3 ]] || { echo "usage: $0 SRC_DIR X.Y.Z WORK_DIR" >&2; exit 2; }
SRC=$(cd "$1" && pwd)
VER=$2
WORK=$3
[[ $VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z"
[[ -d $WORK ]] || die "work dir does not exist: $WORK"
FEEDS=$SRC/tests/nav-feeds
[[ -f $FEEDS/a.xml && -f $FEEDS/b.xml ]] || die "missing UI test feeds in $FEEDS"
for t in qmake6 make sqlite3 dbus-run-session timeout; do
  command -v "$t" >/dev/null || die "missing tool: $t"
done

# The desktop's theme variables are dropped too: with QT_QPA_PLATFORMTHEME=gtk3
# (or a desktop that picks it) Qt loads GTK, which has no display here and
# breaks the run. The private bus has no service directories, so nothing on it
# can activate desktop services such as xdg-desktop-portal.
DBUS_CONF=$WORK/dbus-session.conf
cat >"$DBUS_CONF" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=@WORK@/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
# The bus socket lives in the work dir, never in the real /tmp.
mkdir -p "$WORK/bus"
sed -i "s|@WORK@|$WORK|" "$DBUS_CONF"

# A desktop session (Omarchy, for one) exports XDG_STATE_HOME and friends.
# Every run below must still get its own throwaway dir for each XDG_* the UI
# test guard checks, so pretend we inherited real-home values for all of them.
# If run_app ever stops overriding one, the UI test guard refuses and this
# script fails here instead of on a real release.
export XDG_DATA_HOME="$WORK/inherited-real-home/.local/share" XDG_CONFIG_HOME="$WORK/inherited-real-home/.config" \
  XDG_CACHE_HOME="$WORK/inherited-real-home/.cache" XDG_STATE_HOME="$WORK/inherited-real-home/.local/state" \
  XDG_RUNTIME_DIR="$WORK/inherited-real-home/run"

# One isolated run of the app. $1 = home dir (made fresh by the caller), the
# rest is the command inside dbus-run-session.
run_app() {
  local home=$1; shift
  ( cd "$SRC" && env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u SWAYSOCK -u NIRI_SOCKET \
      -u DBUS_SESSION_BUS_ADDRESS -u QT_QPA_PLATFORMTHEME -u QT_STYLE_OVERRIDE -u QT_QUICK_CONTROLS_STYLE \
      -u XDG_CURRENT_DESKTOP -u XDG_SESSION_DESKTOP -u DESKTOP_SESSION -u XDG_SESSION_TYPE -u GTK_MODULES -u GDK_BACKEND \
      HOME="$home/home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" XDG_STATE_HOME="$home/state" XDG_RUNTIME_DIR="$home/run" \
      QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 "$@" )
}

new_home() {
  local h=$WORK/home-$1
  rm -rf "$h"
  mkdir -p "$h"/{home,data/omaear,config,cache,state} && mkdir -m 700 "$h/run"
  : >"$h/home/.omaear-ui-test-home"   # lets the UI test run here (see uiTestHomeIsThrowaway)
  : >"$h/.omaear-ui-test-root"        # marks $h, HOME's parent, as the throwaway root
  printf '%s\n' "$h"
}

# Throwaway library: two shows whose feeds are local files from the tree. The
# schema is the one src/library.cpp creates. No network is involved.
seed_library() {
  local db=$1/data/omaear/library.db
  sqlite3 "$db" <<SQL
PRAGMA foreign_keys = ON;
CREATE TABLE shows (
  id INTEGER PRIMARY KEY,
  feed_url TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  image_url TEXT NOT NULL DEFAULT '',
  image_path TEXT NOT NULL DEFAULT '');
CREATE TABLE episodes (
  id INTEGER PRIMARY KEY,
  show_id INTEGER NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
  guid TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  audio_url TEXT NOT NULL,
  image_url TEXT NOT NULL DEFAULT '',
  image_path TEXT NOT NULL DEFAULT '',
  published_at INTEGER NOT NULL DEFAULT 0,
  duration_secs INTEGER NOT NULL DEFAULT 0,
  played INTEGER NOT NULL DEFAULT 0,
  position_ms INTEGER NOT NULL DEFAULT 0,
  UNIQUE(show_id, guid));
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE queue (
  episode_id INTEGER PRIMARY KEY REFERENCES episodes(id) ON DELETE CASCADE,
  position INTEGER NOT NULL);
INSERT INTO shows (id, feed_url, title) VALUES
  (1, 'file://$FEEDS/a.xml', 'Alpha Show'),
  (2, 'file://$FEEDS/b.xml', 'Beta Show');
INSERT INTO episodes (show_id, guid, title, description, audio_url, published_at, duration_secs, played) VALUES
  (1, 'a-1', 'Episode 1', 'seed', 'file:///nonexistent/a.mp3', 2000, 60, 0),
  (2, 'b-1', 'Episode 1', 'seed', 'file:///nonexistent/b.mp3', 1000, 60, 0);
INSERT INTO settings (key, value) VALUES
  ('shelf.view', 'list'),
  ('shelf.columns', '6'),
  ('shelf.showAll', '1'),
  ('updates.check', '0');
SQL
}

ui_run() {
  local name=$1 home=$2 limit=$3; shift 3
  local log=$WORK/uitest-$name.log
  if ! run_app "$home" "$@" timeout "$limit" dbus-run-session --config-file="$DBUS_CONF" -- ./omaear >"$log" 2>&1; then
    grep -E 'FAIL' "$log" >&2 || tail -15 "$log" >&2
    die "UI test '$name' failed (log: $log)"
  fi
  grep -q 'ALL PASS' "$log" || die "UI test '$name' did not report ALL PASS (log: $log)"
  printf 'UI test %s: %s checks passed\n' "$name" "$(grep -c '\[uitest\] PASS' "$log")"
}

printf 'Build %s\n' "$SRC"
( cd "$SRC" && qmake6 >/dev/null && make -j"$(nproc)" >"$WORK/build.log" 2>&1 ) \
  || { tail -20 "$WORK/build.log" >&2; die "build failed"; }
reported=$(cd "$SRC" && ./omaear --version)
[[ $reported == "omaear $VER" ]] || die "built binary reports '$reported', not 'omaear $VER'"

H=$(new_home self)
run_app "$H" timeout 180 dbus-run-session --config-file="$DBUS_CONF" -- ./omaear --self-test >"$WORK/selftest.log" 2>&1 \
  || { tail -15 "$WORK/selftest.log" >&2; die "self-test failed (log: $WORK/selftest.log)"; }
echo "Self-test: ok"

# The UI test must refuse a HOME without the throwaway marker and leave it alone.
H=$(new_home guard); rm -f "$H/home/.omaear-ui-test-home"
mkdir -p "$H/home/.local/state/omarchy/current/theme" "$H/home/.config/omarchy"
printf 'accent = "#123456"\n' >"$H/home/.local/state/omarchy/current/theme/colors.toml"
printf '[popups]\n' >"$H/home/.config/omarchy/shell.toml"
guard_sum() { (cd "$H/home" && find . -type f | sort | xargs sha256sum); }
before=$(guard_sum)
rc=0; run_app "$H" timeout 60 dbus-run-session --config-file="$DBUS_CONF" -- env OMAEAR_UI_TEST=1 ./omaear >"$WORK/uitest-guard.log" 2>&1 || rc=$?
[[ $rc -eq 3 ]] && grep -q 'refusing to run the UI test' "$WORK/uitest-guard.log" && [[ $(guard_sum) == "$before" ]] \
  || { cat "$WORK/uitest-guard.log" >&2; die "UI test did not refuse a HOME without the marker (exit $rc)"; }
echo "UI test guard: refuses a normal HOME"

# A root without its marker must be refused. The canary library must survive.
H=$(new_home guard-noroot); rm -f "$H/.omaear-ui-test-root"
printf 'canary\n' >"$H/data/omaear/library.db"
root_sum() { (cd "$1" && find . -type f | sort | xargs sha256sum); }
before=$(root_sum "$H")
rc=0; run_app "$H" timeout 60 dbus-run-session --config-file="$DBUS_CONF" -- env OMAEAR_UI_TEST=1 ./omaear >"$WORK/uitest-guard-noroot.log" 2>&1 || rc=$?
if ! { [[ $rc -eq 3 ]] && grep -q 'refusing to run the UI test' "$WORK/uitest-guard-noroot.log" && grep -q 'no .omaear-ui-test-root marker' "$WORK/uitest-guard-noroot.log" && [[ $(root_sum "$H") == "$before" ]]; }; then
  cat "$WORK/uitest-guard-noroot.log" >&2
  die "UI test did not refuse a root without the root marker (exit $rc)"
fi
echo "UI test guard: refuses a root without the marker"

# Roots that must be refused although they carry markers. These cases write only
# inside $WORK: never to the real home and never to the real /tmp.
# (1) A shared dir as the root: TMPDIR is on the refused list, so a marked
# throwaway root that is also $TMPDIR stands in for /tmp.
H=$(new_home guard-shared)
printf 'canary\n' >"$H/data/omaear/library.db"
before=$(root_sum "$H")
rc=0; run_app "$H" timeout 60 dbus-run-session --config-file="$DBUS_CONF" -- env OMAEAR_UI_TEST=1 TMPDIR="$H" ./omaear >"$WORK/uitest-guard-shared.log" 2>&1 || rc=$?
if ! { [[ $rc -eq 3 ]] && grep -q 'refusing to run the UI test' "$WORK/uitest-guard-shared.log" && grep -q 'is a shared directory' "$WORK/uitest-guard-shared.log" && [[ $(root_sum "$H") == "$before" ]]; }; then
  cat "$WORK/uitest-guard-shared.log" >&2
  die "UI test did not refuse a shared directory as the root (exit $rc)"
fi
echo "UI test guard: refuses a shared directory as the root"

# (2) A HOME directly under /tmp (root = /tmp), write-free: HOME is a path in
# /tmp that does not exist. The root check runs before any marker is looked
# at, so the app refuses with "shared directory", and the path must still not
# exist afterwards.
NOHOME=/tmp/omaear-guard-nonexistent-$$-$RANDOM
[[ ! -e $NOHOME ]] || die "$NOHOME exists"
H=$(new_home guard-tmp)
rc=0; run_app "$H" timeout 60 dbus-run-session --config-file="$DBUS_CONF" -- env OMAEAR_UI_TEST=1 HOME="$NOHOME" ./omaear >"$WORK/uitest-guard-tmp.log" 2>&1 || rc=$?
if ! { [[ $rc -eq 3 ]] && grep -q 'refusing to run the UI test' "$WORK/uitest-guard-tmp.log" && grep -q 'is a shared directory' "$WORK/uitest-guard-tmp.log" && [[ ! -e $NOHOME ]]; }; then
  cat "$WORK/uitest-guard-tmp.log" >&2
  die "UI test did not refuse a HOME directly under /tmp (exit $rc)"
fi
echo "UI test guard: refuses a HOME directly under /tmp"

# (3) A HOME directly under the real home (root = the real home). An existing
# subdirectory of the real home is used as HOME and nothing is written there:
# the root checks run before the HOME marker check, so the app refuses while
# the root is the real home, and would refuse anyway because that directory
# has no marker. XDG dirs and the canary are in $WORK.
REAL_HOME=$(getent passwd "$(id -u)" | cut -d: -f6)
RH_SUB=
[[ -n $REAL_HOME && -d $REAL_HOME ]] && RH_SUB=$(find "$REAL_HOME" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -n1)
if [[ -z $RH_SUB ]]; then
  echo "UI test guard: HOME under real home: skipped (no existing directory in the real home to use)"
else
  H=$(new_home guard-realhome)
  printf 'canary\n' >"$H/data/omaear/library.db"
  before=$(root_sum "$H")
  rc=0; run_app "$H" timeout 60 dbus-run-session --config-file="$DBUS_CONF" -- env OMAEAR_UI_TEST=1 HOME="$RH_SUB" ./omaear >"$WORK/uitest-guard-realhome.log" 2>&1 || rc=$?
  if ! { [[ $rc -eq 3 ]] && grep -q 'refusing to run the UI test' "$WORK/uitest-guard-realhome.log" && grep -q 'real home directory or contains it' "$WORK/uitest-guard-realhome.log" && [[ $(root_sum "$H") == "$before" ]]; }; then
    cat "$WORK/uitest-guard-realhome.log" >&2
    die "UI test did not refuse a HOME directly under the real home (exit $rc)"
  fi
  echo "UI test guard: refuses a HOME directly under the real home"
fi

# An XDG dir that points outside the throwaway root (HOME's parent) must also
# be refused, even when HOME has the marker. A separate directory stands in
# for the real home or library.
H=$(new_home guard-xdg)
OUT=$(mktemp -d "$WORK/xdg-outside.XXXX")
mkdir -p "$OUT/omaear"
printf 'canary\n' >"$OUT/omaear/library.db"
xdg_sum() { (cd "$OUT" && find . -type f | sort | xargs sha256sum); }
xdg_before=$(xdg_sum)
rc=0; run_app "$H" timeout 60 dbus-run-session --config-file="$DBUS_CONF" -- env OMAEAR_UI_TEST=1 XDG_DATA_HOME="$OUT" ./omaear >"$WORK/uitest-guard-xdg.log" 2>&1 || rc=$?
if ! { [[ $rc -eq 3 ]] && grep -q 'refusing to run the UI test' "$WORK/uitest-guard-xdg.log" && grep -q 'XDG_DATA_HOME' "$WORK/uitest-guard-xdg.log" && [[ $(xdg_sum) == "$xdg_before" ]]; }; then
  cat "$WORK/uitest-guard-xdg.log" >&2
  die "UI test did not refuse an XDG dir outside the throwaway root (exit $rc)"
fi
echo "UI test guard: refuses an XDG dir outside the throwaway root"

H=$(new_home ui); seed_library "$H"
ui_run default "$H" 200 OMAEAR_UI_TEST=1

H=$(new_home nav)
ui_run nav "$H" 180 OMAEAR_UI_TEST=1 OMAEAR_UI_TEST_NAV=1 OMAEAR_UI_TEST_FEEDS="$FEEDS"
echo "Tree validated: build, self-test, UI test guard, UI test, nav UI test."
