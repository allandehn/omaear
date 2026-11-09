#!/usr/bin/env bash
# Publish one already-merged OmaEar revision. This script does not commit,
# does not push main, and does not bypass branch protection.
#
#   scripts/release.sh --preview  --sha <40-hex> --version X.Y.Z [--notes FILE]
#   scripts/release.sh --validate --sha <40-hex> --version X.Y.Z [--notes FILE]
#   scripts/release.sh --publish  --sha <40-hex> --version X.Y.Z --notes FILE \
#       --repo-db replace-with-only-this-package|add-to-existing
#
# --preview is read-only: it checks the worktree, the given SHA and version,
# whether the tag or GitHub release already exists, and whether the package
# is already on the "repo" release. It does not edit version files, archive,
# build, sign, tag, upload, or delete, and it does not need the secret
# signing key.
# --dry-run is the same as --preview and still requires --sha and --version.
#
# --validate builds and runs the headless tests from a git archive of that
# exact SHA in a temporary directory (scripts/release-validate-tree.sh, with
# throwaway fixture data only), then deletes it. It does not sign, tag, or
# upload, and it does not need the secret signing key.
#
# --publish is the only mode that needs the secret signing key. It does the
# validation, signs the package from the same archive, signs and pushes tag
# vX.Y.Z at that SHA (never main), and uploads. It does not delete release
# assets and does not retry a failed upload. It stops before any write if the
# package or its signature is already on the "repo" release. Replacing the
# pacman db on the "repo" GitHub release requires --repo-db. Old package
# files are left in place.
#
# OMAEAR_SIGNING_KEY overrides the signing key id. It exists so the tests can
# use a throwaway key; leave it unset for a real release.
#
# The version must already be committed on the SHA (omaear.pro and PKGBUILD).
# Release notes are not invented here; --publish requires --notes.
set -euo pipefail

REPO=allandehn/omaear
KEY=${OMAEAR_SIGNING_KEY:-AC6FF13C76D8916CCCF2DA05C3225162B5257DB4}
export PACKAGER="${PACKAGER:-Allan Dehn <allandehn@proton.me>}"

MODE=
SHA=
VER=
NOTES=
REPO_DB=
ROOT=
WORK=

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/release.sh --preview  --sha <40-hex> --version X.Y.Z [--notes FILE]
  scripts/release.sh --validate --sha <40-hex> --version X.Y.Z [--notes FILE]
  scripts/release.sh --publish  --sha <40-hex> --version X.Y.Z --notes FILE \
      --repo-db replace-with-only-this-package|add-to-existing
--dry-run is an alias of --preview. It does not build, edit versions, or need the signing key.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preview|--dry-run) [[ -z $MODE ]] || usage; MODE=preview; shift ;;
    --validate)          [[ -z $MODE ]] || usage; MODE=validate; shift ;;
    --publish)           [[ -z $MODE ]] || usage; MODE=publish; shift ;;
    --sha)               [[ $# -ge 2 ]] || usage; SHA=$2; shift 2 ;;
    --version)           [[ $# -ge 2 ]] || usage; VER=$2; shift 2 ;;
    --notes)             [[ $# -ge 2 ]] || usage; NOTES=$2; shift 2 ;;
    --repo-db)           [[ $# -ge 2 ]] || usage; REPO_DB=$2; shift 2 ;;
    -h|--help)           usage ;;
    *)                   usage ;;
  esac
done
[[ -n $MODE && -n $SHA && -n $VER ]] || usage
[[ $SHA =~ ^[0-9a-f]{40}$ ]] || die "--sha must be the full 40-hex commit, not a branch or short id"
[[ $VER =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must be X.Y.Z"
if [[ $MODE == publish ]]; then
  [[ -n $NOTES && -f $NOTES && -s $NOTES ]] || die "--publish requires a non-empty --notes file (notes are not invented here)"
  case "$REPO_DB" in
    replace-with-only-this-package|add-to-existing) ;;
    *) die "--publish requires --repo-db replace-with-only-this-package or add-to-existing" ;;
  esac
elif [[ -n $REPO_DB ]]; then
  die "--repo-db is only valid with --publish"
fi
if [[ -n $NOTES ]]; then
  [[ -f $NOTES && -s $NOTES ]] || die "notes file missing or empty: $NOTES"
fi

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
ROOT=$PWD
PKG=omaear-$VER-1-x86_64.pkg.tar.zst
DB_ASSETS=(omaear.db omaear.db.sig omaear.files omaear.files.sig)

cleanup() {
  if [[ -n ${WORK:-} && -d $WORK ]]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT

# Prints exists, absent, or error for a GitHub release tag. gh exits 1 both
# for "release not found" and for network or auth failures, so absence is only
# accepted when gh says so.
release_state() {
  local rc=0 err
  err=$(gh release view "$1" -R "$REPO" 2>&1 >/dev/null) || rc=$?
  if [[ $rc -eq 0 ]]; then echo exists
  elif [[ $rc -eq 1 && $err == *"release not found"* ]]; then echo absent
  else echo error; fi
}

# Dies if the package or its signature is already an asset of the "repo"
# release (or if the asset list cannot be read). Read-only. Called before the
# tag is pushed or anything is uploaded, so a failure here leaves no partial
# state.
check_package_not_published() {
  local names
  names=$(gh release view repo -R "$REPO" --json assets --jq '.assets[].name' 2>/dev/null) \
    || die "cannot read the assets of the 'repo' release; refusing to continue"
  local n
  for n in "$PKG" "$PKG.sig"; do
    if printf '%s\n' "$names" | grep -qxF -- "$n"; then
      die "$n is already on the 'repo' release; refusing to overwrite it. Nothing was pushed or uploaded."
    fi
  done
}

# Read-only. A non-zero git/gh exit that is not the expected "absent" code
# fails closed. This does not fetch, checkout, or write a ref.
preflight() {
  step "Preflight $MODE for $VER at $SHA"
  [[ -z $(git status --porcelain) ]] || die "working tree is dirty"
  local branch head remote remote_sha
  branch=$(git branch --show-current)
  [[ $branch == main ]] || die "must be on local main (now: ${branch:-detached})"
  head=$(git rev-parse HEAD)
  [[ $head == "$SHA" ]] || die "HEAD $head is not the reviewed SHA $SHA"
  remote=$(git ls-remote origin refs/heads/main) || die "cannot read origin/main"
  remote_sha=${remote%%$'\t'*}
  [[ $remote_sha == "$SHA" ]] || die "origin/main is ${remote_sha:-empty}, not the reviewed SHA $SHA"

  local ver_pro ver_pkg
  ver_pro=$(sed -n 's/^VERSION = //p' omaear.pro)
  ver_pkg=$(sed -n 's/^pkgver=//p' packaging/PKGBUILD)
  [[ $ver_pro == "$VER" && $ver_pkg == "$VER" ]] || die "version files are omaear.pro=$ver_pro PKGBUILD=$ver_pkg, not $VER"

  git rev-parse -q --verify "refs/tags/v$VER" >/dev/null && die "local tag v$VER already exists; refusing to move or reuse it"
  local tag_rc=0
  set +e
  git ls-remote --exit-code origin "refs/tags/v$VER" >/dev/null 2>&1
  tag_rc=$?
  set -e
  if [[ $tag_rc -eq 0 ]]; then die "remote tag v$VER already exists; refusing to move or reuse it"
  elif [[ $tag_rc -ne 2 ]]; then die "cannot check remote tag v$VER (git ls-remote exit $tag_rc)"; fi

  case "$(release_state "v$VER")" in
    exists) die "GitHub release v$VER already exists; refusing to reuse it" ;;
    absent) ;;
    *) die "cannot check GitHub release v$VER (gh failed for a reason other than 'release not found')" ;;
  esac
  check_package_not_published

  # Only --publish signs, so only --publish needs the secret key.
  if [[ $MODE == publish ]]; then
    gpg --list-secret-keys "$KEY" >/dev/null 2>&1 || die "signing key $KEY is not available; refusing to continue"
  fi
  if [[ $MODE != preview ]]; then
    local t
    for t in qmake6 make tar sqlite3 dbus-run-session timeout; do command -v "$t" >/dev/null || die "missing tool: $t"; done
  fi
  if [[ $MODE == publish ]]; then
    local t
    for t in makepkg repo-add curl; do command -v "$t" >/dev/null || die "missing tool: $t"; done
  fi
}

# Archive SHA only. Caller checks VERSION inside the result.
archive_sha() {
  local out=$1
  git archive --format=tar.gz --prefix="omaear-$VER/" -o "$out" "$SHA"
  local got
  got=$(tar -xOzf "$out" "omaear-$VER/omaear.pro" | sed -n 's/^VERSION = //p')
  [[ $got == "$VER" ]] || die "archive of $SHA has VERSION=$got, not $VER"
  local pkg
  pkg=$(tar -xOzf "$out" "omaear-$VER/packaging/PKGBUILD" | sed -n 's/^pkgver=//p')
  [[ $pkg == "$VER" ]] || die "archive of $SHA has pkgver=$pkg, not $VER"
}

# Builds and tests the extracted archive with throwaway fixtures only (see
# scripts/release-validate-tree.sh). The copy inside the archive is used, so
# the code that runs is the code of the reviewed SHA.
build_tree() {
  local src=$1
  [[ -f $src/scripts/release-validate-tree.sh ]] || die "archive of $SHA has no scripts/release-validate-tree.sh"
  mkdir -p "$WORK/validate"
  bash "$src/scripts/release-validate-tree.sh" "$src" "$VER" "$WORK/validate" || die "build or tests failed for $SHA"
}

pin_pkgbuild() {
  local dest=$1 archive=$2
  cp "$ROOT/packaging/PKGBUILD" "$ROOT/packaging/omaear.install" "$dest/"
  local sum
  sum=$(sha256sum "$archive" | awk 'NR==1 { print $1 }')
  [[ $sum =~ ^[0-9a-f]{64}$ ]] || die "could not hash the source archive"
  # Scratch copy only. The file in the repo is not edited.
  sed -i "s/^sha256sums=.*/sha256sums=('$sum')/" "$dest/PKGBUILD"
  grep -q "SKIP" "$dest/PKGBUILD" && die "scratch PKGBUILD still has SKIP; refusing to package unverified source"
  grep -q "$sum" "$dest/PKGBUILD" || die "scratch PKGBUILD is missing the archive checksum"
}

preview() {
  preflight
  step "Preview only"
  cat <<EOF
No archive, build, version edit, tag, signature, upload, or deletion was performed.
Reviewed source: $SHA
Version:         $VER (already in omaear.pro and packaging/PKGBUILD on that commit)
Tag:             v$VER would be signed and pushed at that SHA. main would not be pushed.
Package:         $PKG built only from a git archive of $SHA, with a scratch checksum (not SKIP).
Tests:           headless self-test and UI test in that scratch tree (--validate or --publish).
Repo db:         not chosen. --publish must pass
                 --repo-db replace-with-only-this-package
                 or --repo-db add-to-existing.
                 Either mode replaces GitHub release assets omaear.db, omaear.db.sig,
                 omaear.files, and omaear.files.sig. No other asset is replaced or deleted.
                 The new package is uploaded only if that filename is not already there.
Latest:          the v$VER GitHub release would be marked Latest.
EOF
  if [[ -n $NOTES ]]; then echo "Notes file: $NOTES"; else echo "Notes: not supplied (required before --publish)."; fi
  step "Preview OK. Nothing was written."
}

validate() {
  preflight
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/omaear-validate.XXXX")
  step "Archive $SHA"
  archive_sha "$WORK/omaear-$VER.tar.gz"
  tar -xzf "$WORK/omaear-$VER.tar.gz" -C "$WORK"
  step "Build and test scratch tree"
  build_tree "$WORK/omaear-$VER"
  step "Validate OK. Scratch deleted on exit. No tag, signature, or upload."
}

publish_repo_db() {
  local up=$1
  mkdir -p "$WORK/r" "$up"
  local db_src
  if [[ $REPO_DB == add-to-existing ]]; then
    step "Read current repo database (no upload yet)"
    mkdir -p "$WORK/olddb"
    gh release download repo -R "$REPO" --dir "$WORK/olddb" --pattern 'omaear.db' --pattern 'omaear.files' \
      || die "cannot download the current repo database; refusing to publish a database that drops packages already in it"
    [[ -f $WORK/olddb/omaear.db ]] || die "downloaded repo assets did not include omaear.db"
    cp "$WORK/olddb/omaear.db" "$WORK/r/omaear.db.tar.gz"
    if [[ -f $WORK/olddb/omaear.files ]]; then cp "$WORK/olddb/omaear.files" "$WORK/r/omaear.files.tar.gz"; fi
  fi
  step "Build signed repo database ($REPO_DB)"
  # No -R: do not delete package files. replace-with-only-this-package starts
  # from an empty db; add-to-existing updates the downloaded db.
  ( cd "$WORK/r" && repo-add -q -s -k "$KEY" omaear.db.tar.gz "$WORK/$PKG" ) \
    || die "repo-add failed; if gpg needs a passphrase, unlock the key and start again. Nothing was retried."
  local f
  for f in db files; do
    cp "$WORK/r/omaear.$f.tar.gz" "$up/omaear.$f"
    cp "$WORK/r/omaear.$f.tar.gz.sig" "$up/omaear.$f.sig"
  done
  tar tzf "$up/omaear.db" | grep -q "^omaear-$VER-1/" || die "repo db does not list omaear-$VER-1"
}

publish() {
  preflight
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/omaear-publish.XXXX")
  step "Archive $SHA"
  archive_sha "$WORK/omaear-$VER.tar.gz"
  tar -xzf "$WORK/omaear-$VER.tar.gz" -C "$WORK"
  step "Build and test scratch tree"
  build_tree "$WORK/omaear-$VER"
  step "Package that same archive"
  # makepkg looks beside the PKGBUILD for the source filename.
  mkdir -p "$WORK/pkg"
  cp "$WORK/omaear-$VER.tar.gz" "$WORK/pkg/omaear-$VER.tar.gz"
  pin_pkgbuild "$WORK/pkg" "$WORK/pkg/omaear-$VER.tar.gz"
  ( cd "$WORK/pkg" && makepkg --sign --key "$KEY" -f --noconfirm >"$WORK/makepkg.log" 2>&1 ) \
    || { tail -20 "$WORK/makepkg.log" >&2; die "makepkg failed. Nothing was uploaded and the tag was not pushed."; }
  [[ -f $WORK/pkg/$PKG && -f $WORK/pkg/$PKG.sig ]] || die "makepkg did not produce $PKG and its signature"
  cp "$WORK/pkg/$PKG" "$WORK/pkg/$PKG.sig" "$WORK/"
  gpg --verify "$WORK/$PKG.sig" "$WORK/$PKG" >/dev/null 2>&1 || die "package signature does not verify"

  local up=$WORK/up
  publish_repo_db "$up"
  cp "$WORK/$PKG" "$WORK/$PKG.sig" "$up/"
  local f
  for f in omaear.db omaear.files "$PKG"; do
    gpg --verify "$up/$f.sig" "$up/$f" >/dev/null 2>&1 || die "bad signature on $f; nothing was uploaded"
  done

  step "Re-check tag and release before any write"
  local tag_rc=0
  set +e
  git ls-remote --exit-code origin "refs/tags/v$VER" >/dev/null 2>&1
  tag_rc=$?
  set -e
  [[ $tag_rc -eq 2 ]] || die "remote tag v$VER appeared during the build (ls-remote exit $tag_rc); refusing to continue"
  [[ $(release_state "v$VER") == absent ]] || die "GitHub release v$VER appeared during the build, or could not be read; refusing to continue"
  check_package_not_published
  local remote_sha
  remote_sha=$(git ls-remote origin refs/heads/main) || die "cannot re-read origin/main"
  remote_sha=${remote_sha%%$'\t'*}
  [[ $remote_sha == "$SHA" ]] || die "origin/main changed during the build (now $remote_sha); refusing to publish"

  step "Sign and push tag v$VER at $SHA (not main)"
  git tag -s -u "$KEY" -m "OmaEar $VER" "v$VER" "$SHA" \
    || die "could not sign tag v$VER. Nothing was pushed."
  git push origin "refs/tags/v$VER" \
    || die "pushing tag v$VER failed. main was not pushed. The upload was not started and will not be retried."

  step "Upload package without replacing it if it already exists"
  gh release upload repo -R "$REPO" "$up/$PKG" "$up/$PKG.sig" \
    || die "package upload failed. Tag v$VER is already on origin. No retry and no asset deletion."

  step "Replace only the four repo-db assets ($REPO_DB)"
  printf 'Replacing exactly: %s\n' "${DB_ASSETS[*]}"
  gh release upload repo -R "$REPO" --clobber \
      "$up/omaear.db" "$up/omaear.db.sig" "$up/omaear.files" "$up/omaear.files.sig" \
    || die "repo database upload failed. No retry and no asset deletion. Package upload already happened."

  step "Create GitHub release v$VER"
  gh release create "v$VER" -R "$REPO" --title "OmaEar $VER" --notes-file "$NOTES" --latest --verify-tag \
    || die "creating the GitHub release failed. Tag and uploaded assets were left as they are. No retry."

  step "Public verification (no retry on failure)"
  local tag
  tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") || die "could not read the latest GitHub release"
  tag=$(printf '%s\n' "$tag" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
  [[ $tag == "v$VER" ]] || die "latest release is '$tag', expected v$VER. No retry."
  curl -fsSL -o "$WORK/public-omaear.db" "https://github.com/$REPO/releases/download/repo/omaear.db" \
    || die "could not download the published repo database"
  tar tzf "$WORK/public-omaear.db" | grep -q "^omaear-$VER-1/" \
    || die "published repo db does not list omaear-$VER-1. No retry."
  step "Published OmaEar $VER from $SHA: https://github.com/$REPO/releases/tag/v$VER"
}

case "$MODE" in
  preview)  preview ;;
  validate) validate ;;
  publish)  publish ;;
  *)        usage ;;
esac
