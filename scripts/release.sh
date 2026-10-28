#!/usr/bin/env bash
# Release OmaEar: bump, build, test, commit, tag, push, sign the package,
# update the pacman repo (GitHub release "repo") and publish a GitHub release.
#
#   scripts/release.sh [--dry-run] X.Y.Z [NOTES_FILE]
#
# Release notes: NOTES_FILE, else $NOTES (text), else $EDITOR opens a template.
# --dry-run does everything locally (bump, build, tests, signed package and
# repo db from the working tree) but never commits, tags, pushes, uploads or
# publishes, and restores omaear.pro / PKGBUILD at the end.
#
# Tests are headless only: offscreen Qt, a private D-Bus (dbus-run-session)
# and a throwaway XDG_* copy of the user's library. The UI test needs shows
# in the library (an empty one fails the episode-menu steps), and the copy
# keeps the real library and the running app untouched. Nothing here sends
# input to the desktop.
set -euo pipefail

REPO=allandehn/omaear
KEY=AC6FF13C76D8916CCCF2DA05C3225162B5257DB4
export PACKAGER="${PACKAGER:-Allan Dehn <allandehn@proton.me>}"
DRY=0
[[ ${1:-} == --dry-run ]] && { DRY=1; shift; }
VER=${1:-}; NOTES_FILE=${2:-}

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR

[[ $VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: $0 [--dry-run] X.Y.Z [NOTES_FILE]"
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
ROOT=$PWD
PKG=omaear-$VER-1-x86_64.pkg.tar.zst
WORK=$(mktemp -d /tmp/omaear-rel.XXXX)
TESTHOME=$(mktemp -d /tmp/omaear-test.XXXX)
cleanup() {
  rm -rf "$WORK" "$TESTHOME"
  if (( DRY )); then git -C "$ROOT" checkout -q -- omaear.pro packaging/PKGBUILD; fi
}
trap cleanup EXIT

step "Preflight"
[[ -z $(git status --porcelain) ]] || die "working tree not clean (commit or stash first)"
[[ $(git branch --show-current) == main ]] || die "not on main"
git fetch -q origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main is not in sync with origin/main (pull/push first)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"
gpg --list-secret-keys "$KEY" >/dev/null 2>&1 || die "signing key $KEY not in gpg"
git rev-parse -q --verify "refs/tags/v$VER" >/dev/null && die "tag v$VER exists locally"
git ls-remote --exit-code --tags origin "v$VER" >/dev/null 2>&1 && die "tag v$VER exists on origin"
for t in qmake6 make makepkg repo-add dbus-run-session curl; do command -v $t >/dev/null || die "missing tool: $t"; done

step "Release notes"
NOTES_OUT=$WORK/notes.md
if [[ -n $NOTES_FILE ]]; then [[ -f $NOTES_FILE ]] || die "notes file not found: $NOTES_FILE"; cp "$NOTES_FILE" "$NOTES_OUT"
elif [[ -n ${NOTES:-} ]]; then printf '%s\n' "$NOTES" > "$NOTES_OUT"
elif (( DRY )); then echo "(dry run notes)" > "$NOTES_OUT"
else printf 'OmaEar %s\n\n- \n\nUpdate with `omarchy update`.\n' "$VER" > "$NOTES_OUT"; ${EDITOR:-nvim} "$NOTES_OUT"
fi
[[ -s $NOTES_OUT ]] || die "release notes are empty"

step "Bump version to $VER"
sed -i "s/^VERSION = .*/VERSION = $VER/" omaear.pro
sed -i "s/^pkgver=.*/pkgver=$VER/; s/^pkgrel=.*/pkgrel=1/" packaging/PKGBUILD

step "Build"
qmake6 >/dev/null && make clean >/dev/null && make -j"$(nproc)" >/dev/null
[[ $(./omaear --version) == "omaear $VER" ]] || die "built binary reports $(./omaear --version)"

step "Headless tests (offscreen, private D-Bus, throwaway library copy)"
mkdir -p "$TESTHOME"/{data/omaear,config,cache}
LIB=${XDG_DATA_HOME:-$HOME/.local/share}/omaear/library.db
if [[ -f $LIB ]]; then
  if command -v sqlite3 >/dev/null; then sqlite3 "$LIB" ".backup '$TESTHOME/data/omaear/library.db'"
  else cp "$LIB"* "$TESTHOME/data/omaear/"; fi
else echo "warning: no library at $LIB; the UI test needs shows and may fail"; fi
run() { env XDG_DATA_HOME="$TESTHOME/data" XDG_CONFIG_HOME="$TESTHOME/config" XDG_CACHE_HOME="$TESTHOME/cache" \
  QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 "$@" timeout 180 dbus-run-session -- ./omaear "${ARGS[@]}"; }
ARGS=(--self-test); run || die "self-test failed"
ARGS=(); run OMAEAR_UI_TEST=1 > "$WORK/uitest.log" 2>&1 || { grep -E 'FAIL' "$WORK/uitest.log" >&2 || true; die "UI test failed (log above)"; }
grep -q 'ALL PASS' "$WORK/uitest.log" || die "UI test did not report ALL PASS"

if (( DRY )); then
  step "[dry-run] skip commit, tag and push; package the working tree instead"
  SNAP=$(git stash create); SNAP=${SNAP:-HEAD}
  git archive --format=tar.gz --prefix="omaear-$VER/" -o "$WORK/omaear-$VER.tar.gz" "$SNAP"
else
  step "Commit, tag v$VER, push"
  git commit -qam "Release $VER"
  git tag -a "v$VER" -m "OmaEar $VER"
  git push -q origin main
  git push -q origin "v$VER"
fi

step "Build and sign the package (makepkg --sign)"
cp packaging/PKGBUILD packaging/omaear.install "$WORK/"
( cd "$WORK" && makepkg --sign --key "$KEY" -f --noconfirm >"$WORK/makepkg.log" 2>&1 ) \
  || { tail -20 "$WORK/makepkg.log" >&2; die "makepkg failed (if gpg asked for a passphrase, unlock the key with: echo | gpg --clearsign -u $KEY >/dev/null, then rerun)"; }

step "Signed repo database"
mkdir -p "$WORK/r" "$WORK/up"
cp "$WORK/$PKG" "$WORK/$PKG.sig" "$WORK/r/"
( cd "$WORK/r" && repo-add -q -s -k "$KEY" omaear.db.tar.gz "$PKG" )
for f in db files; do
  cp "$WORK/r/omaear.$f.tar.gz" "$WORK/up/omaear.$f"
  cp "$WORK/r/omaear.$f.tar.gz.sig" "$WORK/up/omaear.$f.sig"
done
cp "$WORK/$PKG" "$WORK/$PKG.sig" "$WORK/up/"
for f in omaear.db omaear.files "$PKG"; do gpg --verify "$WORK/up/$f.sig" "$WORK/up/$f" 2>/dev/null || die "bad signature on $f"; done
tar tzf "$WORK/up/omaear.db" | grep -q "^omaear-$VER-1/" || die "repo db does not list omaear-$VER-1"

if (( DRY )); then
  step "[dry-run] would upload to release 'repo': $(cd "$WORK/up" && echo *)"
  step "[dry-run] would create release 'OmaEar $VER' (latest). Notes:"; cat "$NOTES_OUT"
  step "Dry run OK. Version files restored; nothing pushed or published."
  exit 0
fi

step "Upload to the 'repo' release"
OLD=$(gh release view repo -R "$REPO" --json assets -q '.assets[].name' | grep -E '^omaear-.*\.pkg\.tar\.zst(\.sig)?$' | grep -v "^$PKG" || true)
gh release upload repo -R "$REPO" --clobber "$WORK"/up/*
for a in $OLD; do gh release delete-asset repo "$a" -R "$REPO" -y; done

step "Publish release OmaEar $VER"
gh release create "v$VER" -R "$REPO" --title "OmaEar $VER" --notes-file "$NOTES_OUT" --latest --verify-tag

step "Public verification"
sleep 3
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
[[ $TAG == "v$VER" ]] || die "latest release is '$TAG', expected v$VER"
curl -fsSL "https://github.com/$REPO/releases/download/repo/omaear.db" | tar tz | grep -q "^omaear-$VER-1/" \
  || die "public repo db does not list omaear-$VER-1"
step "Released OmaEar $VER: https://github.com/$REPO/releases/tag/v$VER"
