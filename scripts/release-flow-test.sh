#!/usr/bin/env bash
# Tests for scripts/release.sh and scripts/release-validate-tree.sh.
#
#   bash scripts/release-flow-test.sh               mocked git/gh/gpg/Qt tools only
#   bash scripts/release-flow-test.sh --real-tools  also: real makepkg, repo-add -s,
#                                                   gpg and git with a throwaway key
#
# Everything runs in temp dirs under /tmp. gh and curl are always mocked, so
# nothing is ever pushed, uploaded or released. No test reads or copies the
# real library, config, or signing key: the fixture library is built from
# tests/nav-feeds, the signing key in --real-tools mode is generated in a
# temporary GNUPGHOME, and a canary "real" library that nobody may read is
# planted to prove it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RELEASE=$ROOT/scripts/release.sh
VALIDATE=$ROOT/scripts/release-validate-tree.sh
REAL_TOOLS=0
[[ ${1:-} == --real-tools ]] && REAL_TOOLS=1
PASS=0
FAIL=0
SKIP=0

ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1" >&2; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP %s\n' "$1"; }

REAL_GIT=$(command -v git)
REAL_SQLITE3_BIN=$(command -v sqlite3 || true)
ORIG_PATH=$PATH
PKGNAME=omaear-0.3.1-1-x86_64.pkg.tar.zst
CLEANUP_DIRS=()
cleanup_all() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [[ -n $d && -d $d ]] && { chmod -R u+rwX "$d" 2>/dev/null || true; rm -rf "$d"; }
  done
  return 0
}
trap cleanup_all EXIT

# ---------------------------------------------------------------- mocks ----

write_mocks() {
  local MOCK=$1
  mkdir -p "$MOCK/bin"
  cat >"$MOCK/bin/git" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/git"
case "$1" in
  commit|checkout|fetch|reset|clean|stash|merge|rebase|add)
    echo "forbidden git $*" >&2; exit 97 ;;
  push)
    case "$*" in
      *main*) echo "forbidden git $*" >&2; exit 97 ;;
    esac
    [[ -f $MOCK_DIR/push_fail ]] && { echo "push failed" >&2; exit 1; }
    printf '%s\n' "$*" >> "$MOCK_LOG/pushes"
    [[ -n ${REAL_GIT_FOR_PUSH:-} ]] && exec "$REAL_GIT_FOR_PUSH" "$@"
    exit 0 ;;
  tag)
    case "$*" in
      *" -f "*|*" --force "*) echo "forbidden moving tag" >&2; exit 97 ;;
    esac
    printf '%s\n' "$*" >> "$MOCK_LOG/tags"
    [[ -n ${REAL_GIT_FOR_PUSH:-} ]] && exec "$REAL_GIT_FOR_PUSH" "$@"
    exit 0 ;;
  ls-remote)
    [[ -n ${REAL_GIT_FOR_PUSH:-} ]] && exec "$REAL_GIT_FOR_PUSH" "$@"
    if [[ "$*" == *refs/heads/main* ]]; then
      printf '%s\trefs/heads/main\n' "$REMOTE_MAIN"
      exit 0
    fi
    if [[ "$*" == *refs/tags/* ]]; then
      printf '%s\n' "$*" >> "$MOCK_LOG/tag_queries"
      n=$(wc -l < "$MOCK_LOG/tag_queries")
      if [[ -f $MOCK_DIR/tag_on_second && $n -ge 2 ]]; then
        printf '%s\trefs/tags/v0.3.1\n' deadbeef
        exit 0
      fi
      if [[ -f $MOCK_DIR/remote_tag ]]; then
        printf '%s\trefs/tags/v0.3.1\n' deadbeef
        exit 0
      fi
      if [[ "$*" == *--exit-code* ]]; then exit 2; fi
      exit 0
    fi
    echo "unmocked ls-remote $*" >&2
    exit 1 ;;
esac
exec "$REAL_GIT" "$@"
EOF2
  cat >"$MOCK/bin/gh" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/gh"
remote=$MOCK_DIR/remote
if [[ $1 == release && $2 == view ]]; then
  if [[ $3 == repo ]]; then
    [[ -f $MOCK_DIR/repo_missing ]] && { echo "release not found" >&2; exit 1; }
    [[ -f $MOCK_DIR/repo_unreadable ]] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    ls -1 "$remote"
    exit 0
  fi
  [[ -f $MOCK_DIR/release_exists ]] && exit 0
  [[ -f $MOCK_DIR/release_net_error ]] && { echo "error connecting to api.github.com" >&2; exit 1; }
  echo "release not found" >&2
  exit 1
fi
if [[ $1 == release && $2 == download ]]; then
  [[ -f $MOCK_DIR/download_fail ]] && exit 1
  dir=.
  prev=
  for a in "$@"; do
    if [[ $prev == --dir ]]; then dir=$a; fi
    prev=$a
  done
  mkdir -p "$dir"
  if [[ -f $remote/omaear.db ]]; then
    cp "$remote/omaear.db" "$dir/omaear.db"
    [[ -f $remote/omaear.files ]] && cp "$remote/omaear.files" "$dir/omaear.files"
  else
    printf 'existing-db' > "$dir/omaear.db"
  fi
  exit 0
fi
if [[ $1 == release && $2 == upload ]]; then
  printf '%s\n' "$*" >> "$MOCK_LOG/uploads"
  [[ -f $MOCK_DIR/upload_fail ]] && exit 1
  clobber=0
  files=()
  for a in "${@:4}"; do
    case "$a" in
      --clobber) clobber=1 ;;
      -R) ;;
      *) [[ -f $a ]] && files+=("$a") ;;
    esac
  done
  if [[ $clobber -eq 0 ]]; then
    for f in "${files[@]}"; do
      [[ -e $remote/$(basename "$f") ]] && { echo "asset under the same name already exists: $(basename "$f")" >&2; exit 1; }
    done
  fi
  for f in "${files[@]}"; do cp "$f" "$remote/$(basename "$f")"; done
  exit 0
fi
if [[ $1 == release && $2 == create ]]; then
  printf '%s\n' "$*" >> "$MOCK_LOG/creates"
  exit 0
fi
if [[ $1 == release && ( $2 == delete-asset || $2 == delete ) ]]; then
  echo "forbidden gh $*" >&2; exit 97
fi
echo "unmocked gh $*" >&2
exit 1
EOF2
  cat >"$MOCK/bin/gpg" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/gpg"
if [[ $1 == --list-secret-keys ]]; then
  [[ -n ${MOCK_NO_KEY:-} ]] && exit 1
  exit 0
fi
if [[ $1 == --verify ]]; then
  [[ -n ${MOCK_BAD_SIG:-} ]] && exit 1
  exit 0
fi
exit 0
EOF2
  cat >"$MOCK/bin/qmake6" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/qmake"
exit 0
EOF2
  cat >"$MOCK/bin/make" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/make"
[[ -f $MOCK_DIR/asset_on_make ]] && touch "$MOCK_DIR/remote/omaear-${MOCK_VER}-1-x86_64.pkg.tar.zst"
{
  echo '#!/bin/sh'
  echo "if [ \"\$1\" = --version ]; then echo \"omaear ${MOCK_VER}\"; exit 0; fi"
  echo "printf '%s|%s|%s|%s|%s\\n' \"\$HOME\" \"\$XDG_DATA_HOME\" \"\$DISPLAY\$WAYLAND_DISPLAY\" \"\$OMAEAR_UI_TEST_NAV\" \"\$(head -c 40 \"\$XDG_DATA_HOME/omaear/library.db\" 2>/dev/null | tr -d '\\n' | tr -c '[:print:]' '?')\" >> \"$MOCK_LOG/appenv\""
  echo "if [ -f \"$MOCK_DIR/dump_library\" ] && [ -f \"\$XDG_DATA_HOME/omaear/library.db\" ]; then sqlite3 \"\$XDG_DATA_HOME/omaear/library.db\" 'select feed_url from shows order by id' >> \"$MOCK_LOG/library-dump\"; fi"
  echo 'if [ "$1" = --self-test ]; then exit 0; fi'
  echo 'if [ -n "$OMAEAR_UI_TEST" ] && [ ! -f "$HOME/.omaear-ui-test-home" ]; then echo "omaear: refusing to run the UI test: no marker"; exit 3; fi'
  echo "if [ -f \"$MOCK_DIR/ui_fail\" ] && [ -n \"\$OMAEAR_UI_TEST\" ]; then echo '[uitest] FAIL fixture says so'; exit 1; fi"
  echo 'if [ -n "$OMAEAR_UI_TEST" ]; then echo "[uitest] PASS one"; echo "[uitest] ALL PASS"; exit 0; fi'
  echo 'exit 0'
} > omaear
chmod +x omaear
if [[ ${1:-} == install || ${*: -1} == install ]]; then
  for a in "$@"; do case "$a" in INSTALL_ROOT=*) r=${a#INSTALL_ROOT=} ;; esac; done
  mkdir -p "$r/usr/bin" && cp omaear "$r/usr/bin/omaear"
fi
exit 0
EOF2
  cat >"$MOCK/bin/sqlite3" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/sqlite3"
if [[ -n ${MOCK_USE_REAL_SQLITE3:-} ]]; then exec "$REAL_SQLITE3_BIN" "$@"; fi
cat >/dev/null
printf 'FIXTURE-LIBRARY' > "$1"
exit 0
EOF2
  cat >"$MOCK/bin/makepkg" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/makepkg"
grep -q SKIP PKGBUILD && { echo "PKGBUILD still has SKIP" >&2; exit 1; }
tarball=$(ls omaear-*.tar.gz | head -1)
sum=$(sha256sum "$tarball" | awk 'NR==1 { print $1 }')
grep -q "$sum" PKGBUILD || { echo "PKGBUILD checksum is not the archive" >&2; exit 1; }
ver=$(sed -n 's/^pkgver=//p' PKGBUILD)
printf 'pkg' > "omaear-${ver}-1-x86_64.pkg.tar.zst"
printf 'sig' > "omaear-${ver}-1-x86_64.pkg.tar.zst.sig"
exit 0
EOF2
  cat >"$MOCK/bin/repo-add" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/repo-add"
case " $* " in
  *" -R "*) echo "forbidden repo-add -R" >&2; exit 97 ;;
esac
db=""
for a in "$@"; do
  case "$a" in
    *.tar.gz|*.db) db=$a ;;
  esac
done
[[ -n $db ]] || { echo "no db arg" >&2; exit 1; }
stage=$(mktemp -d)
mkdir -p "$stage/omaear-${MOCK_VER}-1"
tar -czf "$db" -C "$stage" "omaear-${MOCK_VER}-1"
files=${db/omaear.db/omaear.files}
cp "$db" "$files"
printf 'sig' > "${db}.sig"
printf 'sig' > "${files}.sig"
rm -rf "$stage"
exit 0
EOF2
  cat >"$MOCK/bin/curl" <<'EOF2'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/curl"
if [[ "$*" == *releases/latest* ]]; then
  if [[ -n ${MOCK_BAD_LATEST:-} ]]; then echo '{"tag_name":"v0.0.0"}'; exit 0; fi
  echo "{\"tag_name\":\"v${MOCK_VER}\"}"
  exit 0
fi
if [[ "$*" == *omaear.db ]]; then
  out=""
  prev=
  for a in "$@"; do
    if [[ $prev == -o ]]; then out=$a; fi
    prev=$a
  done
  [[ -n $out ]] || { echo "curl db download has no -o" >&2; exit 1; }
  if [[ -f $MOCK_DIR/remote/omaear.db ]]; then cp "$MOCK_DIR/remote/omaear.db" "$out"; exit 0; fi
  stage=$(mktemp -d)
  mkdir -p "$stage/omaear-${MOCK_VER}-1"
  tar -czf "$out" -C "$stage" "omaear-${MOCK_VER}-1"
  rm -rf "$stage"
  exit 0
fi
echo "unmocked curl $*" >&2
exit 1
EOF2
  cat >"$MOCK/bin/dbus-run-session" <<'EOF2'
#!/bin/bash
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
[[ ${1:-} == -- ]] && shift
"$@"
EOF2
  chmod +x "$MOCK/bin/"*
}

# Fixture repo: a tiny git repo laid out like OmaEar for the files release.sh
# touches, plus the two scripts under test.
make_fixture_repo() {
  local repo=$1 ver=${2:-0.3.1}
  mkdir -p "$repo/packaging" "$repo/scripts" "$repo/tests/nav-feeds"
  printf 'VERSION = %s\n' "$ver" >"$repo/omaear.pro"
  cat >"$repo/packaging/PKGBUILD" <<EOF2
pkgver=$ver
source=("omaear-\$pkgver.tar.gz::https://example.invalid/omaear-\$pkgver.tar.gz")
sha256sums=('SKIP')
EOF2
  echo '# install' >"$repo/packaging/omaear.install"
  echo '<rss/>' >"$repo/tests/nav-feeds/a.xml"
  echo '<rss/>' >"$repo/tests/nav-feeds/b.xml"
  cp "$RELEASE" "$repo/scripts/release.sh"
  cp "$VALIDATE" "$repo/scripts/release-validate-tree.sh"
  chmod +x "$repo/scripts/"*.sh
  "$REAL_GIT" -C "$repo" init -q -b main
  "$REAL_GIT" -C "$repo" config user.email test@example.com
  "$REAL_GIT" -C "$repo" config user.name test
  "$REAL_GIT" -C "$repo" config commit.gpgsign false
  "$REAL_GIT" -C "$repo" add -A
  "$REAL_GIT" -C "$repo" commit -q -m fixture
}

new_case() {
  CASE=$1
  BASE=$(mktemp -d /tmp/omaear-reltest.XXXX)
  CLEANUP_DIRS+=("$BASE")
  REPO=$BASE/repo
  MOCK=$BASE/mock
  LOG=$BASE/log
  mkdir -p "$MOCK/remote" "$LOG" "$BASE/tmp"
  make_fixture_repo "$REPO"
  write_mocks "$MOCK"
  # Old release content already on the "repo" release.
  local f
  for f in omaear.db omaear.db.sig omaear.files omaear.files.sig omaear-0.2.0-1-x86_64.pkg.tar.zst omaear-0.2.0-1-x86_64.pkg.tar.zst.sig; do
    printf 'old-%s' "$f" >"$MOCK/remote/$f"
  done
  SHA=$("$REAL_GIT" -C "$REPO" rev-parse HEAD)
  # A canary "real" user library nobody may read. Any read or copy fails loudly.
  REALHOME=$BASE/realhome
  mkdir -p "$REALHOME/share/omaear"
  printf 'CANARY-REAL-LIBRARY' >"$REALHOME/share/omaear/library.db"
  CANARY_SUM=$(sha256sum "$REALHOME/share/omaear/library.db" | awk '{print $1}')
  chmod 000 "$REALHOME/share/omaear/library.db"
  export MOCK_DIR=$MOCK MOCK_LOG=$LOG REMOTE_MAIN=$SHA MOCK_VER=0.3.1 REAL_GIT REAL_SQLITE3_BIN
  unset MOCK_USE_REAL_SQLITE3
  unset MOCK_NO_KEY MOCK_BAD_SIG MOCK_BAD_LATEST REAL_GIT_FOR_PUSH
  export HOME=$REALHOME XDG_DATA_HOME=$REALHOME/share
  export DISPLAY=:99 WAYLAND_DISPLAY=wayland-canary
  export PATH="$MOCK/bin:$ORIG_PATH"
  NOTES=$BASE/notes.md
  echo 'notes for review, not a published announcement' >"$NOTES"
  BEFORE=
}

# Everything a failed or read-only run must leave exactly as it found it.
state() {
  {
    "$REAL_GIT" -C "$REPO" status --porcelain --untracked-files=all
    "$REAL_GIT" -C "$REPO" tag -l
    "$REAL_GIT" -C "$REPO" for-each-ref
    "$REAL_GIT" -C "$REPO" rev-parse HEAD
    "$REAL_GIT" -C "$REPO" branch --show-current
    ( cd "$REPO" && find . -path ./.git -prune -o -type f -exec sha256sum {} + | sort )
    ls -A "$BASE/tmp"
    ( cd "$MOCK/remote" && find . -type f -exec sha256sum {} + | sort )
  } 2>&1 | sha256sum
}

run_rel() {
  rm -f "$LOG"/*
  BEFORE=$(state)
  ( cd "$REPO" && TMPDIR="$BASE/tmp" "$REPO/scripts/release.sh" "$@" ) >"$BASE/out" 2>"$BASE/err"
}

# Prints the first thing a read-only run did that it must not have done.
preview_problem() {
  local f
  for f in qmake make makepkg repo-add sqlite3 gpg uploads pushes tags creates curl appenv; do
    [[ -f $LOG/$f ]] && { echo "ran or logged '$f'"; return; }
  done
  if grep -E '^(archive|commit|checkout|fetch|tag|push|add|reset|stash|clean|merge|rebase|init|config|update-ref) ' "$LOG/git" >/dev/null 2>&1; then
    echo "git log shows a mutating command"; return
  fi
  if [[ -f $LOG/gh ]] && grep -vE '^release view ' "$LOG/gh" >/dev/null; then
    echo "gh was called with something other than 'release view'"; return
  fi
  [[ -n $BEFORE && $(state) == "$BEFORE" ]] || echo "repo, temp dir or remote state changed"
}

assert_preview_quiet() {
  local p
  p=$(preview_problem)
  if [[ -z $p ]]; then ok "$1"; else bad "$1: $p"; fi
}

# Failure before any write: nothing remote happened and nothing local changed.
assert_nothing_written() {
  local name=$1 f
  for f in uploads pushes tags creates; do
    if [[ -f $LOG/$f ]]; then bad "$name: '$f' happened ($(head -1 "$LOG/$f"))"; return; fi
  done
  if [[ -f $LOG/gh ]] && grep -E '^release (upload|create|delete)' "$LOG/gh" >/dev/null; then
    bad "$name: gh wrote to the release"; return
  fi
  if [[ -n $BEFORE && $(state) != "$BEFORE" ]]; then bad "$name: files, tags, temp dirs or release assets changed"; return; fi
  ok "$name"
}

expect_fail() { # name, message regex, early-failure assertion type (quiet|nothing)
  local name=$1 re=$2 kind=$3
  shift 3
  if run_rel "$@"; then
    bad "$name was accepted"
    return
  fi
  if ! grep -qE "$re" "$BASE/err"; then bad "$name: missing message /$re/: $(tail -2 "$BASE/err" | tr '\n' ' ')"; return; fi
  if [[ $kind == quiet ]]; then assert_preview_quiet "$name"; else assert_nothing_written "$name"; fi
}

pub_args() { printf '%s\n' --publish --sha "$SHA" --version 0.3.1 --notes "$NOTES" --repo-db "${1:-replace-with-only-this-package}"; }

# --------------------------------------------------------- static guards ----

if grep -nE '^[[:space:]]*(git commit|git checkout|git fetch)|delete-asset|repo-add[[:space:]]+(-[a-zA-Z]+ )*-R|git push origin main' "$RELEASE" >/dev/null; then
  bad "release.sh still contains a forbidden operation"
else
  ok "script text has no commit, main push, fetch, checkout, delete-asset, or repo-add -R"
fi
if grep -nE 'library\.db|XDG_DATA_HOME:-|\.local/share' "$RELEASE" >/dev/null; then
  bad "release.sh mentions the real library"
else
  ok "release.sh never names the user library"
fi
if grep -nE '\.local/share|XDG_DATA_HOME:-|cp .*library\.db|\.backup' "$VALIDATE" >/dev/null; then
  bad "release-validate-tree.sh reads or copies a library"
else
  ok "release-validate-tree.sh builds its own fixture library, never copies one"
fi

# ------------------------------------------------ preview, no side effects ----

new_case preview-ok
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  assert_preview_quiet "preview writes nothing, builds nothing, never touches gpg"
  grep -q "Preview OK" "$BASE/out" && ok "preview says it wrote nothing" || bad "preview did not report OK"
else
  bad "preview happy path exited $?"; cat "$BASE/err" >&2
fi

# The quiet check itself must fail when a read-only run did something.
mutation_caught() { # name, command that simulates a write
  local name=$1 cmd=$2 p
  eval "$cmd"
  p=$(preview_problem)
  if [[ -n $p ]]; then ok "quiet check catches: $name"; else bad "quiet check missed: $name"; fi
}
cp "$REPO/omaear.pro" "$BASE/omaear.pro.orig"
mutation_caught "an upload" ': >"$LOG/uploads"'; rm -f "$LOG/uploads"
mutation_caught "a tag push" ': >"$LOG/pushes"'; rm -f "$LOG/pushes"
mutation_caught "a build" ': >"$LOG/make"'; rm -f "$LOG/make"
mutation_caught "a gpg call" ': >"$LOG/gpg"'; rm -f "$LOG/gpg"
mutation_caught "a git commit" 'echo "commit -m x" >>"$LOG/git"'; run_rel --preview --sha "$SHA" --version 0.3.1
mutation_caught "a gh write" 'echo "release create v0.3.1" >>"$LOG/gh"'; run_rel --preview --sha "$SHA" --version 0.3.1
mutation_caught "an edited tracked file" 'echo x >>"$REPO/omaear.pro"'; cp "$BASE/omaear.pro.orig" "$REPO/omaear.pro"
mutation_caught "a staged-only edit" 'echo x >>"$REPO/omaear.pro"; "$REAL_GIT" -C "$REPO" add omaear.pro'; "$REAL_GIT" -C "$REPO" reset -q HEAD omaear.pro; cp "$BASE/omaear.pro.orig" "$REPO/omaear.pro"
mutation_caught "a new untracked file" 'echo x >"$REPO/new-file"'; rm -f "$REPO/new-file"
mutation_caught "a leftover temp dir" 'mkdir "$BASE/tmp/omaear-validate.leftover"'; rmdir "$BASE/tmp/omaear-validate.leftover"
mutation_caught "a new local tag" '"$REAL_GIT" -C "$REPO" tag v9.9.9'; "$REAL_GIT" -C "$REPO" tag -d v9.9.9 >/dev/null
mutation_caught "a changed release asset" 'echo x >>"$MOCK/remote/omaear.db"'

new_case preview-dry-run-alias
if run_rel --dry-run --sha "$SHA" --version 0.3.1; then
  assert_preview_quiet "--dry-run is read-only too"
else
  bad "--dry-run happy path failed"; cat "$BASE/err" >&2
fi

# ---------------------------------------- gap d: no secret key for preview ----

new_case preview-no-key
export MOCK_NO_KEY=1
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  assert_preview_quiet "preview needs no secret signing key and never calls gpg"
else
  bad "preview required the signing key"; cat "$BASE/err" >&2
fi
if run_rel --dry-run --sha "$SHA" --version 0.3.1; then
  assert_preview_quiet "dry-run needs no secret signing key"
else
  bad "dry-run required the signing key"
fi
unset MOCK_NO_KEY

new_case publish-no-key
export MOCK_NO_KEY=1
mapfile -t A < <(pub_args)
expect_fail "publish without the signing key fails before any write" "signing key" nothing "${A[@]}"
unset MOCK_NO_KEY

# ------------------------------------------------ argument and state errors ----

new_case sha-mismatch
expect_fail "sha mismatch fails closed" "not the reviewed SHA" quiet --preview --sha 0123456789abcdef0123456789abcdef01234567 --version 0.3.1

new_case version-mismatch
expect_fail "version mismatch fails closed" "version files" quiet --preview --sha "$SHA" --version 0.3.2

new_case dirty
echo x >>"$REPO/omaear.pro"
expect_fail "dirty tree fails closed and is left as found" "dirty" nothing --preview --sha "$SHA" --version 0.3.1

new_case local-tag
"$REAL_GIT" -C "$REPO" tag v0.3.1
expect_fail "existing local tag fails closed" "local tag" quiet --preview --sha "$SHA" --version 0.3.1

new_case remote-tag
touch "$MOCK/remote_tag"
expect_fail "existing remote tag fails closed" "remote tag" quiet --preview --sha "$SHA" --version 0.3.1

new_case existing-release
touch "$MOCK/release_exists"
expect_fail "existing GitHub release fails closed" "already exists" quiet --preview --sha "$SHA" --version 0.3.1

new_case release-net-error
touch "$MOCK/release_net_error"
expect_fail "gh failing for another reason is not treated as 'release absent'" "cannot check GitHub release" quiet --preview --sha "$SHA" --version 0.3.1

new_case not-main
"$REAL_GIT" -C "$REPO" checkout -q -b side
expect_fail "side branch fails closed" "local main" quiet --preview --sha "$SHA" --version 0.3.1

new_case short-sha
expect_fail "short sha fails closed" "40-hex" quiet --preview --sha abcdef --version 0.3.1

new_case bad-version
expect_fail "malformed version fails closed" "X.Y.Z" quiet --preview --sha "$SHA" --version v0.3

new_case repo-db-on-preview
expect_fail "--repo-db is refused outside --publish" "only valid with --publish" quiet --preview --sha "$SHA" --version 0.3.1 --repo-db add-to-existing

new_case two-modes
expect_fail "two modes at once is a usage error" "usage" quiet --preview --publish --sha "$SHA" --version 0.3.1

new_case missing-notes-file
expect_fail "publish with a missing notes file fails before any write" "notes" nothing --publish --sha "$SHA" --version 0.3.1 --notes "$BASE/nope.md" --repo-db add-to-existing

new_case empty-notes-file
: >"$NOTES"
expect_fail "publish with an empty notes file fails before any write" "notes" nothing --publish --sha "$SHA" --version 0.3.1 --notes "$NOTES" --repo-db add-to-existing

new_case publish-no-db-choice
mapfile -t A < <(pub_args); A=("${A[@]:0:${#A[@]}-2}")
expect_fail "publish without --repo-db fails before any write" "repo-db" nothing "${A[@]}"

new_case publish-bad-db-choice
mapfile -t A < <(pub_args merge-somehow)
expect_fail "publish with an unknown --repo-db value fails before any write" "repo-db" nothing "${A[@]}"

# ---------------------- gap e: existing package asset is found before writes ----

new_case asset-exists
touch "$MOCK/remote/$PKGNAME"
expect_fail "preview reports a package already on the repo release" "already on the 'repo' release" quiet --preview --sha "$SHA" --version 0.3.1
mapfile -t A < <(pub_args)
expect_fail "publish refuses before tag push or upload when the package exists" "already on the 'repo' release" nothing "${A[@]}"
[[ ! -f $LOG/make && ! -f $LOG/qmake ]] && ok "...and it did not even start the build" || bad "build started although the package exists"

new_case asset-sig-exists
touch "$MOCK/remote/$PKGNAME.sig"
mapfile -t A < <(pub_args add-to-existing)
expect_fail "publish refuses when only the package signature exists" "already on the 'repo' release" nothing "${A[@]}"

new_case repo-release-missing
touch "$MOCK/repo_missing"
mapfile -t A < <(pub_args)
expect_fail "publish refuses when the repo release cannot be found" "cannot read the assets" nothing "${A[@]}"

new_case repo-release-unreadable
touch "$MOCK/repo_unreadable"
expect_fail "preview fails closed when the asset list cannot be read" "cannot read the assets" quiet --preview --sha "$SHA" --version 0.3.1

new_case asset-appears-mid-build
touch "$MOCK/asset_on_make"
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  bad "package appearing mid-build was ignored"
else
  if grep -q "already on the 'repo' release" "$BASE/err" && [[ ! -f $LOG/pushes && ! -f $LOG/tags && ! -f $LOG/uploads && ! -f $LOG/creates ]] \
      && [[ $(cat "$MOCK/remote/omaear.db") == old-omaear.db && ! -s $MOCK/remote/$PKGNAME ]]; then
    ok "package appearing mid-build stops before tag push, upload and db change"
  else
    bad "package appearing mid-build was not stopped cleanly: $(tail -2 "$BASE/err" | tr '\n' ' ')"
  fi
fi

new_case tag-appears
touch "$MOCK/tag_on_second"
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  bad "tag appearing mid-build was ignored"
else
  [[ ! -f $LOG/uploads && ! -f $LOG/pushes && ! -f $LOG/tags ]] && grep -q "appeared" "$BASE/err" \
    && [[ $(cat "$MOCK/remote/omaear.db") == old-omaear.db ]] \
    && ok "tag appearing mid-build stops before tag push, upload and db change" \
    || bad "mid-build tag check did not stop cleanly"
fi

new_case publish-download-fails
touch "$MOCK/download_fail"
mapfile -t A < <(pub_args add-to-existing)
if run_rel "${A[@]}"; then
  bad "failed db download still published"
else
  [[ ! -f $LOG/uploads && ! -f $LOG/pushes && ! -f $LOG/tags && $(cat "$MOCK/remote/omaear.db") == old-omaear.db ]] \
    && ok "failed db download stops before tag push, upload and db change" \
    || bad "failed db download still tagged or uploaded"
fi

new_case bad-sig
export MOCK_BAD_SIG=1
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  bad "bad signature was published"
else
  [[ ! -f $LOG/uploads && ! -f $LOG/pushes && ! -f $LOG/tags && $(cat "$MOCK/remote/omaear.db") == old-omaear.db ]] && grep -q "signature" "$BASE/err" \
    && ok "bad package signature stops before tag push, upload and db change" \
    || bad "bad signature did not stop before publication"
fi
unset MOCK_BAD_SIG

new_case ui-test-fails
touch "$MOCK/ui_fail"
mapfile -t A < <(pub_args)
expect_fail "failing UI test stops publish before any write" "UI test 'default' failed|build or tests failed" nothing "${A[@]}"

# ---------------- validate: exact SHA, fixtures only, never the real library ----

new_case validate
if run_rel --validate --sha "$SHA" --version 0.3.1; then
  if grep -q "^archive --format=tar.gz --prefix=omaear-0.3.1/ -o .* $SHA$" "$LOG/git" \
      && [[ ! -f $LOG/uploads && ! -f $LOG/pushes && ! -f $LOG/tags && ! -f $LOG/makepkg && ! -f $LOG/gpg && ! -f $LOG/creates ]]; then
    ok "validate builds the exact SHA; no tag, signature, gpg call or upload"
  else
    bad "validate did not archive only the reviewed SHA, or it published"
  fi
  [[ -z $(ls -A "$BASE/tmp") ]] && ok "validate removed its scratch dir" || bad "validate left scratch: $(ls "$BASE/tmp")"
  n=$(wc -l <"$LOG/appenv")
  if [[ $n -eq 4 ]] \
      && ! grep -q "$REALHOME" "$LOG/appenv" \
      && awk -F'|' -v t="$BASE/tmp/" 'index($1, t) != 1 || index($2, t) != 1 { exit 1 }' "$LOG/appenv"; then
    ok "self-test, UI test guard, UI test and nav test each ran with their own throwaway HOME and XDG_DATA_HOME"
  else
    bad "app runs did not all use throwaway dirs"; cat "$LOG/appenv" >&2
  fi
  if ! awk -F'|' '$3 != "" { exit 1 }' "$LOG/appenv"; then bad "display variables leaked into the app run"; else ok "DISPLAY and WAYLAND_DISPLAY are unset for the app"; fi
  if grep -q CANARY "$LOG/appenv" || grep -rq CANARY "$LOG" 2>/dev/null; then bad "the real library was read"; else ok "the real library was never read or copied"; fi
  chmod 600 "$REALHOME/share/omaear/library.db"
  [[ $(sha256sum "$REALHOME/share/omaear/library.db" | awk '{print $1}') == "$CANARY_SUM" ]] && ok "the real library is unchanged" || bad "the real library changed"
  chmod 000 "$REALHOME/share/omaear/library.db"
  grep -q 'FIXTURE-LIBRARY' "$LOG/appenv" && ok "the default UI run saw the fixture library" || bad "UI run did not see a fixture library"
  n=$(grep -c 'tests/nav-feeds\|library.db' "$LOG/sqlite3" 2>/dev/null || true)
  [[ $n -ge 1 ]] && ok "the fixture library is created with sqlite3 inside the throwaway dir" || bad "no fixture library was created"
  ! grep -q "$REALHOME" "$LOG/sqlite3" && ok "sqlite3 was never pointed at the real library" || bad "sqlite3 touched the real library path"
else
  bad "validate failed"; cat "$BASE/err" >&2
fi

if [[ -n $REAL_SQLITE3_BIN ]]; then
  new_case validate-real-sqlite
  export MOCK_USE_REAL_SQLITE3=1
  touch "$MOCK/dump_library"
  if run_rel --validate --sha "$SHA" --version 0.3.1 \
      && [[ $(wc -l <"$LOG/library-dump") -eq 2 ]] && ! grep -v '^file://.*/tests/nav-feeds/[ab]\.xml$' "$LOG/library-dump" >/dev/null; then
    ok "the real sqlite3 loads the fixture library: 2 shows, file:// feeds from tests/nav-feeds"
  else
    bad "fixture library has the wrong shows"; cat "$LOG/library-dump" >&2 || true
  fi
else
  skip "fixture library check with the real sqlite3 (sqlite3 not installed here)"
fi

new_case validate-missing-sqlite-is-reported
# A PATH without sqlite3 must fail early with a clear message, not half-run.
rm -f "$MOCK/bin/sqlite3"
SAFE=$BASE/safebin; mkdir -p "$SAFE"
for t in bash env git gh gpg qmake6 make tar gzip dbus-run-session timeout nproc sha256sum awk sed grep cat ls head tr mktemp rm mkdir cp date dirname basename sort wc find id cut tee; do
  for src in "$MOCK/bin/$t" "$(PATH=$ORIG_PATH command -v $t 2>/dev/null || true)"; do [[ -x $src ]] && { ln -sf "$src" "$SAFE/$t"; break; }; done
done
PATH=$SAFE
if run_rel --validate --sha "$SHA" --version 0.3.1; then bad "validate ran without sqlite3"
else grep -q "missing tool: sqlite3" "$BASE/err" && assert_nothing_written "validate without sqlite3 fails early" || bad "missing-sqlite3 message absent"; fi
PATH=$ORIG_PATH

# ------------- publish: exact archive, no main push, explicit db replace ----

new_case publish
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  pkg_line=$(head -1 "$LOG/uploads")
  db_line=$(sed -n '2p' "$LOG/uploads")
  if grep -q "$SHA" "$LOG/tags" \
      && grep -q 'refs/tags/v0.3.1' "$LOG/pushes" \
      && ! grep -q main "$LOG/pushes" \
      && [[ $pkg_line != *--clobber* && $pkg_line == *$PKGNAME* ]] \
      && [[ $db_line == *--clobber* && $db_line == *omaear.db* && $db_line != *.pkg.tar.zst* ]] \
      && [[ -f $LOG/creates ]] \
      && ! grep -E 'delete' "$LOG/gh" >/dev/null; then
    ok "publish signs the tag, uploads without deleting, and clobbers only the repo db"
  else
    bad "publish effects were not exact"
  fi
  # Remote end state: old package kept, new package added, four db assets replaced.
  if [[ -f $MOCK/remote/omaear-0.2.0-1-x86_64.pkg.tar.zst && -f $MOCK/remote/$PKGNAME && -f $MOCK/remote/$PKGNAME.sig \
        && $(cat "$MOCK/remote/omaear.db.sig") == sig && $(ls "$MOCK/remote" | wc -l) -eq 8 ]]; then
    ok "publish end state: old package kept, new package and signature added, no asset deleted"
  else
    bad "publish end state wrong: $(ls "$MOCK/remote" | tr '\n' ' ')"
  fi
else
  bad "publish happy path failed"; cat "$BASE/err" >&2
fi

new_case publish-add-existing
mapfile -t A < <(pub_args add-to-existing)
if run_rel "${A[@]}"; then
  grep -q 'release download' "$LOG/gh" && ! grep -qE '(^| )-R( |$)' "$LOG/repo-add" && ok "add-to-existing reads the current db and does not use repo-add -R" \
    || bad "add-to-existing did not download or used -R"
else
  bad "add-to-existing failed"; cat "$BASE/err" >&2
fi

new_case upload-fails
touch "$MOCK/upload_fail"
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  bad "failed upload was treated as success"
else
  n=$(wc -l < "$LOG/uploads")
  [[ $n -eq 1 && ! -f $LOG/creates ]] && grep -q "No retry" "$BASE/err" \
    && ok "failed package upload is not retried and does not create the release" \
    || bad "upload failure was retried or continued (lines=$n)"
fi

new_case push-fails
touch "$MOCK/push_fail"
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  bad "failed tag push was treated as success"
else
  [[ ! -f $LOG/uploads && $(cat "$MOCK/remote/omaear.db") == old-omaear.db ]] && grep -q "will not be retried" "$BASE/err" \
    && ok "failed tag push does not upload" \
    || bad "failed tag push still uploaded"
fi

new_case verify-fails
export MOCK_BAD_LATEST=1
mapfile -t A < <(pub_args)
if run_rel "${A[@]}"; then
  bad "wrong latest release was accepted"
else
  n=$(wc -l < "$LOG/uploads")
  [[ $n -eq 2 ]] && grep -q "No retry" "$BASE/err" && ok "public verification failure does not upload again" \
    || bad "verification failure retried or skipped uploads (lines=${n:-0})"
fi
unset MOCK_BAD_LATEST

# ------------------------------------------------------------ real tools ----
# gap f: the real PKGBUILD packaging, the checksum sed one-liner, and
# repo-add -s signing with a throwaway key. Only with --real-tools.

real_tools() {
  local missing=() t
  for t in makepkg repo-add gpg git tar bsdtar qmake6 make sqlite3 dbus-run-session timeout; do
    command -v "$t" >/dev/null || missing+=("$t")
  done
  local FR=${OMAEAR_TEST_FAKEROOT_DIR:-}
  if ! command -v fakeroot >/dev/null && [[ -z $FR ]]; then missing+=(fakeroot); fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    skip "real-tools tests: missing ${missing[*]} (set OMAEAR_TEST_FAKEROOT_DIR to a dir with a test-only fakeroot stand-in if only fakeroot is missing)"
    return 0
  fi

  local H G FPR
  H=$(mktemp -d /tmp/omaear-realtools.XXXX); CLEANUP_DIRS+=("$H")
  # Leave the mocked environment of the cases above: real tools, throwaway HOME.
  export PATH=$ORIG_PATH HOME=$H
  unset DISPLAY WAYLAND_DISPLAY XDG_DATA_HOME MOCK_DIR MOCK_LOG MOCK_VER REMOTE_MAIN
  G=$(mktemp -d /tmp/omaear-gnupg.XXXX); CLEANUP_DIRS+=("$G"); chmod 700 "$G"
  export GNUPGHOME=$G
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
      --quick-generate-key 'OmaEar Throwaway Test <throwaway@invalid>' rsa2048 sign never >/dev/null 2>&1 \
    || { bad "could not create a throwaway key"; return 0; }
  FPR=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
  if [[ -n $FPR && $FPR != AC6FF13C* ]] && ! gpg --list-secret-keys AC6FF13C76D8916CCCF2DA05C3225162B5257DB4 >/dev/null 2>&1; then
    ok "real-tools: throwaway key $FPR is the only secret key in the temp GNUPGHOME (not Allan's)"
  else
    bad "real-tools: GNUPGHOME is not isolated"; return 0
  fi
  export OMAEAR_SIGNING_KEY=$FPR

  # --- checksum sed one-liner, against the real packaging/PKGBUILD ---
  local d=$H/pin sum line
  mkdir -p "$d"
  cp "$ROOT/packaging/PKGBUILD" "$ROOT/packaging/omaear.install" "$d/"
  printf 'tarball bytes' >"$d/omaear-0.3.1.tar.gz"
  sum=$(sha256sum "$d/omaear-0.3.1.tar.gz" | awk 'NR==1 { print $1 }')
  line=$(grep -F 'sed -i "s/^sha256sums=' "$RELEASE")
  cp "$d/PKGBUILD" "$d/PKGBUILD.orig"
  ( dest=$d; eval "$line" )
  if [[ -n $line && $(bash -c "source '$d/PKGBUILD'; echo \${sha256sums[0]}") == "$sum" && $(bash -c "source '$d/PKGBUILD'; echo \${#sha256sums[@]}") == 1 ]] \
      && ! grep -q SKIP "$d/PKGBUILD" && [[ $(cat "$d/PKGBUILD") != "$(cat "$d/PKGBUILD.orig")" ]] \
      && [[ $(grep -c . "$d/PKGBUILD") == $(grep -c . "$d/PKGBUILD.orig") ]]; then
    ok "real-tools: the checksum sed one-liner pins exactly the archive hash in the real PKGBUILD (one line, no SKIP)"
  else
    bad "real-tools: checksum sed one-liner did not produce the expected PKGBUILD"
  fi
  # makepkg itself must accept the pin and reject a tampered archive.
  if ( cd "$d" && makepkg --verifysource -f >"$d/vs.log" 2>&1 ); then
    ok "real-tools: makepkg --verifysource accepts the pinned checksum"
  else
    bad "real-tools: makepkg rejected the pinned checksum"; tail -5 "$d/vs.log" >&2
  fi
  printf 'tampered' >>"$d/omaear-0.3.1.tar.gz"
  if ( cd "$d" && makepkg --verifysource -f >"$d/vs2.log" 2>&1 ); then
    bad "real-tools: makepkg accepted a tampered archive"
  else
    grep -qi 'FAILED\|checksum' "$d/vs2.log" && ok "real-tools: makepkg rejects an archive that does not match the pin" || bad "real-tools: tamper check failed for another reason"
  fi

  # --- end to end publish against a local bare origin, real tools, mocked gh/curl ---
  local SRC=$H/src ORIGIN=$H/origin.git MOCKD=$H/mock LOGD=$H/log
  mkdir -p "$SRC" "$MOCKD/remote" "$LOGD"
  ( cd "$ROOT" && "$REAL_GIT" ls-files -z | tar --null -T - -cf - | tar -x -C "$SRC" )
  [[ -f $SRC/omaear.pro && -f $SRC/packaging/PKGBUILD ]] || { bad "real-tools: could not copy the tracked tree"; return 0; }
  cp "$RELEASE" "$SRC/scripts/release.sh"; cp "$VALIDATE" "$SRC/scripts/release-validate-tree.sh"
  "$REAL_GIT" -C "$SRC" init -q -b main
  "$REAL_GIT" -C "$SRC" config user.email test@example.com
  "$REAL_GIT" -C "$SRC" config user.name test
  "$REAL_GIT" -C "$SRC" config commit.gpgsign false
  "$REAL_GIT" -C "$SRC" add -A && "$REAL_GIT" -C "$SRC" commit -q -m 'tree under test'
  "$REAL_GIT" init -q --bare -b main "$ORIGIN"
  "$REAL_GIT" -C "$SRC" remote add origin "$ORIGIN"
  "$REAL_GIT" -C "$SRC" push -q origin main
  local SHA1; SHA1=$("$REAL_GIT" -C "$SRC" rev-parse HEAD)
  local ver; ver=$(sed -n 's/^VERSION = //p' "$SRC/omaear.pro")

  write_mocks "$MOCKD"
  # Only gh and curl stay mocked: remove every other mock from this PATH.
  local keep=$H/bin; mkdir -p "$keep"
  cp "$MOCKD/bin/gh" "$MOCKD/bin/curl" "$keep/"
  [[ -n $FR ]] && ln -sf "$FR/fakeroot" "$keep/fakeroot"
  printf 'ship notes\n' >"$H/notes.md"
  rel_run() { # version sha mode notes...
    ( cd "$SRC" && env PATH="$keep:$ORIG_PATH" MOCK_DIR="$MOCKD" MOCK_LOG="$LOGD" MOCK_VER="$1" TMPDIR="$H" \
        "$SRC/scripts/release.sh" --publish --sha "$2" --version "$1" --notes "$H/notes.md" --repo-db "$3" ) >"$H/pub.out" 2>"$H/pub.err"
  }
  if [[ $ver != 0.3.1 ]]; then skip "real-tools publish: tree version is $ver, not 0.3.1"; return 0; fi
  if rel_run 0.3.1 "$SHA1" replace-with-only-this-package; then
    ok "real-tools: release.sh --publish end to end with real makepkg, repo-add -s, gpg and git (throwaway key, local bare origin, gh mocked)"
  else
    bad "real-tools: publish failed: $(tail -5 "$H/pub.err" | tr '\n' ' ')"; return 0
  fi
  local R=$MOCKD/remote f
  local tagsha; tagsha=$("$REAL_GIT" -C "$ORIGIN" rev-parse 'v0.3.1^{commit}')
  [[ $tagsha == "$SHA1" && $("$REAL_GIT" -C "$ORIGIN" rev-parse main) == "$SHA1" ]] \
    && ok "real-tools: signed tag v0.3.1 points at the reviewed SHA; origin main untouched" || bad "real-tools: tag or main wrong"
  "$REAL_GIT" -C "$SRC" tag -v v0.3.1 >/dev/null 2>&1 && ok "real-tools: the tag signature verifies with the throwaway key" || bad "real-tools: tag signature does not verify"
  local allsig=1
  for f in omaear.db omaear.files "$PKGNAME"; do
    [[ -s $R/$f && -s $R/$f.sig ]] && gpg --verify "$R/$f.sig" "$R/$f" >/dev/null 2>&1 || allsig=0
  done
  [[ $allsig -eq 1 ]] && ok "real-tools: package, db and files signatures all verify (repo-add -s and makepkg --sign)" || bad "real-tools: a signature is missing or invalid"
  if bsdtar -tf "$R/$PKGNAME" | grep -q '^usr/bin/omaear$' && bsdtar -xOf "$R/$PKGNAME" .PKGINFO | grep -qx 'pkgver = 0.3.1-1'; then
    ok "real-tools: the package contains usr/bin/omaear and pkgver 0.3.1-1 (real build from the archive)"
  else
    bad "real-tools: package contents wrong"
  fi
  bsdtar -tf "$R/omaear.db" | grep -q '^omaear-0.3.1-1/' && ok "real-tools: repo db lists omaear-0.3.1-1" || bad "real-tools: repo db does not list omaear-0.3.1-1"
  [[ -z $(ls -A "$H" | grep -E '^omaear-(publish|validate)') ]] && ok "real-tools: scratch dir removed" || bad "real-tools: scratch left behind"
  # The same version again must be refused (the local tag exists now).
  if rel_run 0.3.1 "$SHA1" replace-with-only-this-package; then bad "real-tools: a second publish of the same version was accepted"
  else grep -q 'already exists\|already on the' "$H/pub.err" && ok "real-tools: publishing the same version again is refused before any write" || bad "real-tools: second publish failed for another reason"; fi

  # add-to-existing: put a second package into the published db, then publish a
  # 0.3.2 commit (mocked compile, but real makepkg, repo-add -s and gpg).
  local dd=$H/dummy
  mkdir -p "$dd"
  cat >"$dd/PKGBUILD" <<'EOF2'
pkgname=omaear-dummy
pkgver=1
pkgrel=1
arch=('any')
options=('!debug')
package() { install -Dm644 /dev/null "$pkgdir/usr/share/omaear-dummy"; }
EOF2
  ( cd "$dd" && env PATH="$keep:$ORIG_PATH" makepkg -f --nodeps >"$dd/mk.log" 2>&1 ) || { bad "real-tools: could not build the dummy package"; return 0; }
  cp "$R/omaear.db" "$dd/omaear.db.tar.gz"
  ( cd "$dd" && repo-add -q -s -k "$FPR" omaear.db.tar.gz omaear-dummy-1-1-any.pkg.tar.zst ) || { bad "real-tools: could not add the dummy to the db"; return 0; }
  cp "$dd/omaear.db.tar.gz" "$R/omaear.db"; cp "$dd/omaear.db.tar.gz.sig" "$R/omaear.db.sig"
  cp "$dd/omaear.files.tar.gz" "$R/omaear.files"; cp "$dd/omaear.files.tar.gz.sig" "$R/omaear.files.sig"
  sed -i 's/^VERSION = .*/VERSION = 0.3.2/' "$SRC/omaear.pro"
  sed -i 's/^pkgver=.*/pkgver=0.3.2/' "$SRC/packaging/PKGBUILD"
  "$REAL_GIT" -C "$SRC" commit -q -am 'bump to 0.3.2' && "$REAL_GIT" -C "$SRC" push -q origin main
  local SHA2; SHA2=$("$REAL_GIT" -C "$SRC" rev-parse HEAD)
  cp "$MOCKD/bin/qmake6" "$MOCKD/bin/make" "$MOCKD/bin/dbus-run-session" "$keep/"
  if rel_run 0.3.2 "$SHA2" add-to-existing; then
    ok "real-tools: add-to-existing publish of 0.3.2 with the real repo-add -s"
    local dbl; dbl=$(bsdtar -tf "$R/omaear.db")
    if grep -q '^omaear-dummy-1-1/' <<<"$dbl" && grep -q '^omaear-0.3.2-1/' <<<"$dbl" && ! grep -q '^omaear-0.3.1-1/' <<<"$dbl" \
        && [[ -f $R/$PKGNAME && -f $R/omaear-0.3.2-1-x86_64.pkg.tar.zst ]] \
        && gpg --verify "$R/omaear.db.sig" "$R/omaear.db" >/dev/null 2>&1 && gpg --verify "$R/omaear.files.sig" "$R/omaear.files" >/dev/null 2>&1; then
      ok "real-tools: add-to-existing keeps the other db entries, updates omaear to 0.3.2, keeps the 0.3.1 package file, and both db signatures verify"
    else
      bad "real-tools: add-to-existing result is wrong. db: $(tr '\n' ' ' <<<"$dbl") assets: $(ls "$R" | tr '\n' ' ')"
    fi
  else
    bad "real-tools: add-to-existing failed: $(tail -5 "$H/pub.err" | tr '\n' ' ')"
  fi
  unset GNUPGHOME OMAEAR_SIGNING_KEY
}

if [[ $REAL_TOOLS -eq 1 ]]; then
  real_tools
else
  skip "real-tools tests (run with --real-tools): real makepkg, checksum one-liner, repo-add -s with a throwaway key"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[[ $FAIL -eq 0 ]]
