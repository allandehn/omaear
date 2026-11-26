#!/usr/bin/env bash
# Run a command on a private D-Bus session that cannot activate desktop
# services such as xdg-desktop-portal. Use this instead of a bare
# dbus-run-session on a real desktop: the default session config has service
# directories, so Qt or GTK can start xdg-desktop-portal and
# xdg-desktop-portal-hyprland on the private bus. When the session ends,
# those processes die and Omarchy shows "Process crashed:
# xdg-desktop-portal-hyprland".
#
# Usage:
#   scripts/isolated-session.sh [--work-dir DIR] [--] command...
#
# The bus socket lives in DIR/bus (created if needed). If --work-dir is
# omitted, a temporary directory is used and removed afterwards.
# Exports GSETTINGS_BACKEND=memory so GTK/GLib does not try to activate
# ca.desrt.dconf on the private bus.
# This script does not change HOME or XDG_RUNTIME_DIR, and it does not
# unset WAYLAND_DISPLAY, so a window can still appear on the real desktop.
set -euo pipefail

usage() {
  echo "usage: $0 [--work-dir DIR] [--] command..." >&2
  exit 2
}

WORK=
OWN_WORK=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --work-dir)
      [[ $# -ge 2 ]] || usage
      WORK=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage
      ;;
    *)
      break
      ;;
  esac
done
[[ $# -gt 0 ]] || usage

command -v dbus-run-session >/dev/null || {
  echo "$0: missing tool: dbus-run-session" >&2
  exit 1
}

if [[ -z $WORK ]]; then
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/omaear-isolated-XXXXXX")
  OWN_WORK=1
  trap 'rm -rf "$WORK"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi
mkdir -p "$WORK/bus"
WORK=$(cd "$WORK" && pwd)

CONF=$WORK/dbus-session.conf
cat >"$CONF" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=$WORK/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF

export GSETTINGS_BACKEND=memory

if [[ $OWN_WORK -eq 1 ]]; then
  rc=0
  dbus-run-session --config-file="$CONF" -- "$@" || rc=$?
  exit $rc
fi
exec dbus-run-session --config-file="$CONF" -- "$@"
