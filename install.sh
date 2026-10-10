#!/bin/bash
# OmaEar installer for Omarchy: trusts the OmaEar signing key, adds the [omaear]
# pacman repo, and installs the app. Updates then arrive with `omarchy update`.
set -euo pipefail
KEY=AC6FF13C76D8916CCCF2DA05C3225162B5257DB4
REPO=https://github.com/allanjorch/omaear/releases/download/repo
curl -fsSL "$REPO/omaear.asc" | sudo pacman-key --add -
sudo pacman-key --lsign-key "$KEY"
if ! grep -q '^\[omaear\]' /etc/pacman.conf; then
    printf '\n[omaear]\nServer = %s\n' "$REPO" | sudo tee -a /etc/pacman.conf >/dev/null
fi
sudo pacman -Sy
omarchy pkg add omaear
echo "OmaEar is installed. Open it from the app launcher."
