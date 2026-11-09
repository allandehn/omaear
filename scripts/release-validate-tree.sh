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

# One isolated run of the app. $1 = home dir (made fresh by the caller), the
# rest is the command inside dbus-run-session.
run_app() {
  local home=$1; shift
  ( cd "$SRC" && env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u SWAYSOCK -u NIRI_SOCKET \
      -u DBUS_SESSION_BUS_ADDRESS \
      HOME="$home/home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" XDG_RUNTIME_DIR="$home/run" \
      QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 "$@" )
}

new_home() {
  local h=$WORK/home-$1
  rm -rf "$h"
  mkdir -p "$h"/{home,data/omaear,config,cache} && mkdir -m 700 "$h/run"
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
  if ! run_app "$home" "$@" timeout "$limit" dbus-run-session -- ./omaear >"$log" 2>&1; then
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
run_app "$H" timeout 180 dbus-run-session -- ./omaear --self-test >"$WORK/selftest.log" 2>&1 \
  || { tail -15 "$WORK/selftest.log" >&2; die "self-test failed (log: $WORK/selftest.log)"; }
echo "Self-test: ok"

H=$(new_home ui); seed_library "$H"
ui_run default "$H" 200 OMAEAR_UI_TEST=1

H=$(new_home nav)
ui_run nav "$H" 180 OMAEAR_UI_TEST=1 OMAEAR_UI_TEST_NAV=1 OMAEAR_UI_TEST_FEEDS="$FEEDS"
echo "Tree validated: build, self-test, UI test, nav UI test."
