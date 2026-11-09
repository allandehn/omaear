#!/usr/bin/env bash
# Mocked failure-path tests for scripts/release.sh. No network, no signing,
# no real gh, and no Qt. Run: bash scripts/release-flow-test.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RELEASE=$ROOT/scripts/release.sh
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1" >&2; }

REAL_GIT=$(command -v git)

new_case() {
  CASE=$1
  BASE=$(mktemp -d /tmp/omaear-reltest.XXXX)
  REPO=$BASE/repo
  MOCK=$BASE/mock
  LOG=$BASE/log
  mkdir -p "$REPO/packaging" "$REPO/scripts" "$MOCK/bin" "$LOG"
  cat >"$REPO/omaear.pro" <<'EOF'
VERSION = 0.3.1
EOF
  cat >"$REPO/packaging/PKGBUILD" <<'EOF'
pkgver=0.3.1
source=("omaear-$pkgver.tar.gz::https://example.invalid/omaear-$pkgver.tar.gz")
sha256sums=('SKIP')
EOF
  echo '# install' >"$REPO/packaging/omaear.install"
  cp "$RELEASE" "$REPO/scripts/release.sh"
  chmod +x "$REPO/scripts/release.sh"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  git -C "$REPO" add omaear.pro packaging scripts/release.sh
  git -C "$REPO" commit -q -m 'fixture'
  SHA=$(git -C "$REPO" rev-parse HEAD)
  export MOCK_DIR=$MOCK MOCK_LOG=$LOG REMOTE_MAIN=$SHA MOCK_VER=0.3.1
  unset MOCK_NO_KEY MOCK_BAD_SIG MOCK_BAD_LATEST
  cat >"$MOCK/bin/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/git"
case "$1" in
  commit|checkout|fetch|reset|clean|stash|merge|rebase)
    echo "forbidden git $*" >&2; exit 97 ;;
  push)
    case "$*" in
      *main*) echo "forbidden git $*" >&2; exit 97 ;;
    esac
    [[ -f $MOCK_DIR/push_fail ]] && { echo "push failed" >&2; exit 1; }
    printf '%s\n' "$*" >> "$MOCK_LOG/pushes"
    exit 0 ;;
  tag)
    case "$*" in
      *" -f "*|*" --force "*) echo "forbidden moving tag" >&2; exit 97 ;;
    esac
    printf '%s\n' "$*" >> "$MOCK_LOG/tags"
    exit 0 ;;
  ls-remote)
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
exec /usr/bin/git "$@"
EOF
  cat >"$MOCK/bin/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/gh"
[[ $1 == auth ]] && exit 0
if [[ $1 == release && $2 == view ]]; then
  name=$3
  [[ -f $MOCK_DIR/release_exists ]] && exit 0
  printf '%s\n' "$name" >> "$MOCK_LOG/views"
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
  printf 'existing-db' > "$dir/omaear.db"
  exit 0
fi
if [[ $1 == release && $2 == upload ]]; then
  printf '%s\n' "$*" >> "$MOCK_LOG/uploads"
  [[ -f $MOCK_DIR/upload_fail ]] && exit 1
  exit 0
fi
if [[ $1 == release && $2 == create ]]; then
  printf '%s\n' "$*" >> "$MOCK_LOG/creates"
  exit 0
fi
if [[ $1 == release && $2 == delete-asset ]]; then
  echo "forbidden delete-asset" >&2; exit 97
fi
echo "unmocked gh $*" >&2
exit 1
EOF
  cat >"$MOCK/bin/gpg" <<'EOF'
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
EOF
  cat >"$MOCK/bin/qmake6" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/qmake"
exit 0
EOF
  cat >"$MOCK/bin/make" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/make"
{
  echo '#!/bin/sh'
  echo "if [ \"\$1\" = --version ]; then echo \"omaear ${MOCK_VER}\"; exit 0; fi"
  echo 'if [ "$1" = --self-test ]; then exit 0; fi'
  echo 'if [ -n "$OMAEAR_UI_TEST" ]; then echo "[uitest] ALL PASS"; exit 0; fi'
  echo 'exit 0'
} > omaear
chmod +x omaear
exit 0
EOF
  cat >"$MOCK/bin/makepkg" <<'EOF'
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
EOF
  cat >"$MOCK/bin/repo-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/repo-add"
case "$*" in
  *" -R "*|*-R*) echo "forbidden repo-add -R" >&2; exit 97 ;;
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
cp "$db" "${db%.tar.gz}.files.tar.gz" 2>/dev/null || cp "$db" omaear.files.tar.gz
# Signatures sit beside the db names repo-add would emit.
base=${db%.tar.gz}
# omaear.db.tar.gz -> omaear.db.tar.gz.sig and omaear.files.tar.gz.sig
printf 'sig' > "${db}.sig"
files=${db/omaear.db/omaear.files}
if [[ ! -f $files ]]; then printf 'files' > "$files"; fi
printf 'sig' > "${files}.sig"
rm -rf "$stage"
exit 0
EOF
  cat >"$MOCK/bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_LOG/curl"
if [[ "$*" == *releases/latest* ]]; then
  if [[ -n ${MOCK_BAD_LATEST:-} ]]; then echo '{"tag_name":"v0.0.0"}'; exit 0; fi
  echo '{"tag_name":"v0.3.1"}'
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
  stage=$(mktemp -d)
  mkdir -p "$stage/omaear-${MOCK_VER}-1"
  tar -czf "$out" -C "$stage" "omaear-${MOCK_VER}-1"
  rm -rf "$stage"
  exit 0
fi
echo "unmocked curl $*" >&2
exit 1
EOF
  cat >"$MOCK/bin/dbus-run-session" <<'EOF'
#!/bin/bash
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
[[ ${1:-} == -- ]] && shift
"$@"
EOF
  chmod +x "$MOCK/bin/"*
  export PATH="$MOCK/bin:$PATH"
  mkdir -p "$BASE/tmp"
}

run_rel() {
  ( cd "$REPO" && TMPDIR="$BASE/tmp" "$REPO/scripts/release.sh" "$@" ) >"$BASE/out" 2>"$BASE/err"
}

assert_preview_quiet() {
  local name=$1
  if [[ -f $LOG/qmake || -f $LOG/make || -f $LOG/makepkg || -f $LOG/uploads || -f $LOG/pushes || -f $LOG/tags ]]; then
    bad "$name invoked a write or build step"
    return
  fi
  if grep -E '^(archive|commit|checkout|fetch|tag|push) ' "$LOG/git" >/dev/null 2>&1; then
    bad "$name git log shows a mutating command"
    return
  fi
  if ! git -C "$REPO" diff --quiet && ! git -C "$REPO" diff --cached --quiet; then
    bad "$name edited tracked files"
    return
  fi
  ok "$name"
}

# --- static guards ---
if grep -nE '^[[:space:]]*(git commit|git checkout|git fetch)|delete-asset|repo-add[[:space:]]+-R|git push origin main' "$RELEASE" >/dev/null; then
  bad "release.sh still contains a forbidden operation"
else
  ok "script text has no commit, main push, fetch, checkout, delete-asset, or repo-add -R"
fi

# --- preview, no side effects ---
new_case preview-ok
sum_before=$(sha256sum "$REPO/omaear.pro" "$REPO/packaging/PKGBUILD")
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  sum_after=$(sha256sum "$REPO/omaear.pro" "$REPO/packaging/PKGBUILD")
  if [[ $sum_before == "$sum_after" ]]; then assert_preview_quiet "preview writes nothing and does not build"
  else bad "preview changed version files"; fi
else
  bad "preview happy path exited $?"; cat "$BASE/err" >&2
fi

# --- mismatches ---
new_case sha-mismatch
if run_rel --preview --sha 0123456789abcdef0123456789abcdef01234567 --version 0.3.1; then
  bad "sha mismatch was accepted"
else
  grep -q "not the reviewed SHA" "$BASE/err" && assert_preview_quiet "sha mismatch fails closed" || bad "sha mismatch missing message"
fi

new_case version-mismatch
if run_rel --preview --sha "$SHA" --version 0.3.2; then
  bad "version mismatch was accepted"
else
  grep -q "version files" "$BASE/err" && assert_preview_quiet "version mismatch fails closed" || bad "version mismatch missing message"
fi

new_case dirty
echo x >>"$REPO/omaear.pro"
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  bad "dirty tree was accepted"
else
  grep -q "dirty" "$BASE/err" && ok "dirty tree fails closed" || bad "dirty tree missing message"
fi

new_case local-tag
"$REAL_GIT" -C "$REPO" tag v0.3.1
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  bad "existing local tag was accepted"
else
  grep -q "local tag" "$BASE/err" && ok "existing local tag fails closed" || bad "local tag missing message"
fi

new_case remote-tag
touch "$MOCK/remote_tag"
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  bad "existing remote tag was accepted"
else
  grep -q "remote tag" "$BASE/err" && ok "existing remote tag fails closed" || bad "remote tag missing message"
fi

new_case existing-release
touch "$MOCK/release_exists"
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  bad "existing release was accepted"
else
  grep -q "already exists" "$BASE/err" && ok "existing GitHub release fails closed" || bad "existing release missing message"
fi

new_case no-key
export MOCK_NO_KEY=1
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  bad "missing signing key was accepted"
else
  grep -q "signing key" "$BASE/err" && ok "missing signing key fails closed" || bad "missing key missing message"
fi
unset MOCK_NO_KEY

new_case not-main
"$REAL_GIT" -C "$REPO" checkout -q -b side
if run_rel --preview --sha "$SHA" --version 0.3.1; then
  bad "non-main branch was accepted"
else
  grep -q "local main" "$BASE/err" && ok "detached-or-side branch fails closed" || bad "branch check missing message"
fi

new_case short-sha
if run_rel --preview --sha abcdef --version 0.3.1; then
  bad "short sha was accepted"
else
  ok "short sha fails closed"
fi

# --- validate archives the reviewed SHA and does not publish ---
new_case validate
if run_rel --validate --sha "$SHA" --version 0.3.1; then
  if grep -q "^archive --format=tar.gz --prefix=omaear-0.3.1/ -o .* $SHA$" "$LOG/git" \
      && [[ ! -f $LOG/uploads && ! -f $LOG/pushes && ! -f $LOG/tags && ! -f $LOG/makepkg ]]; then
    ok "validate builds the exact SHA and does not tag or upload"
  else
    bad "validate did not archive only the reviewed SHA, or it published"
    cat "$LOG/git" >&2
  fi
else
  bad "validate failed"; cat "$BASE/err" >&2
fi

# --- publish: exact archive, no main push, explicit db replace, no deletion ---
new_case publish
notes=$BASE/notes.md
echo 'notes for review, not a published announcement' >"$notes"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db replace-with-only-this-package; then
  pkg_line=$(head -1 "$LOG/uploads")
  db_line=$(sed -n '2p' "$LOG/uploads")
  if grep -q "$SHA" "$LOG/tags" \
      && grep -q 'refs/tags/v0.3.1' "$LOG/pushes" \
      && ! grep -q main "$LOG/pushes" \
      && [[ $pkg_line != *--clobber* && $pkg_line == *omaear-0.3.1-1-x86_64.pkg.tar.zst* ]] \
      && [[ $db_line == *--clobber* && $db_line == *omaear.db* && $db_line != *.pkg.tar.zst* ]] \
      && [[ -f $LOG/creates ]] \
      && ! grep -q delete-asset "$LOG/gh"; then
    ok "publish signs the tag, uploads without deleting, and clobbers only the repo db"
  else
    bad "publish effects were not exact"
    echo "TAGS:"; cat "$LOG/tags" >&2
    echo "PUSHES:"; cat "$LOG/pushes" >&2
    echo "UPLOADS:"; cat "$LOG/uploads" >&2
  fi
else
  bad "publish happy path failed"; cat "$BASE/err" >&2
fi

new_case publish-no-db-choice
notes=$BASE/notes.md
echo notes >"$notes"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes"; then
  bad "publish without --repo-db was accepted"
else
  [[ ! -f $LOG/uploads ]] && grep -q "repo-db" "$BASE/err" && ok "publish without --repo-db does not upload" \
    || bad "publish without --repo-db still uploaded or missed the message"
fi

new_case publish-add-existing
notes=$BASE/notes.md
echo notes >"$notes"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db add-to-existing; then
  grep -q 'release download' "$LOG/gh" && ! grep -q ' -R ' "$LOG/repo-add" && ok "add-to-existing reads the current db and does not use repo-add -R" \
    || bad "add-to-existing did not download or used -R"
else
  bad "add-to-existing failed"; cat "$BASE/err" >&2
fi

new_case publish-download-fails
notes=$BASE/notes.md
echo notes >"$notes"
touch "$MOCK/download_fail"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db add-to-existing; then
  bad "failed db download still published"
else
  [[ ! -f $LOG/uploads && ! -f $LOG/pushes ]] && ok "failed db download stops before tag push and upload" \
    || bad "failed db download still tagged or uploaded"
fi

new_case tag-appears
notes=$BASE/notes.md
echo notes >"$notes"
touch "$MOCK/tag_on_second"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db replace-with-only-this-package; then
  bad "tag appearing mid-build was ignored"
else
  [[ ! -f $LOG/uploads && ! -f $LOG/pushes && ! -f $LOG/tags ]] && grep -q "appeared" "$BASE/err" \
    && ok "tag appearing mid-build stops before tag push and upload" \
    || bad "mid-build tag check did not stop cleanly"
fi

new_case upload-fails
notes=$BASE/notes.md
echo notes >"$notes"
touch "$MOCK/upload_fail"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db replace-with-only-this-package; then
  bad "failed upload was treated as success"
else
  n=$(wc -l < "$LOG/uploads")
  [[ $n -eq 1 && ! -f $LOG/creates ]] && grep -q "No retry" "$BASE/err" \
    && ok "failed package upload is not retried and does not create the release" \
    || bad "upload failure was retried or continued (lines=$n)"
fi

new_case push-fails
notes=$BASE/notes.md
echo notes >"$notes"
touch "$MOCK/push_fail"
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db replace-with-only-this-package; then
  bad "failed tag push was treated as success"
else
  [[ ! -f $LOG/uploads ]] && grep -q "will not be retried" "$BASE/err" \
    && ok "failed tag push does not upload" \
    || bad "failed tag push still uploaded"
fi

new_case bad-sig
notes=$BASE/notes.md
echo notes >"$notes"
export MOCK_BAD_SIG=1
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db replace-with-only-this-package; then
  bad "bad signature was published"
else
  [[ ! -f $LOG/uploads && ! -f $LOG/pushes ]] && grep -q "signature" "$BASE/err" \
    && ok "bad package signature stops before tag push and upload" \
    || bad "bad signature did not stop before publication"
fi
unset MOCK_BAD_SIG

new_case verify-fails
notes=$BASE/notes.md
echo notes >"$notes"
export MOCK_BAD_LATEST=1
if run_rel --publish --sha "$SHA" --version 0.3.1 --notes "$notes" --repo-db replace-with-only-this-package; then
  bad "wrong latest release was accepted"
else
  n=$(wc -l < "$LOG/uploads")
  [[ $n -eq 2 ]] && grep -q "No retry" "$BASE/err" && ok "public verification failure does not upload again" \
    || bad "verification failure retried or skipped uploads (lines=${n:-0})"
fi
unset MOCK_BAD_LATEST

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
