#!/usr/bin/env bash
# Renders the settings window's scenarios (tests/visual/shell.qml) with Qt's
# offscreen backend and copies the PNGs to build/visual/ (or $1). Fails if a
# scenario is missing or the QML logged a warning, so it doubles as a load
# check of the core. Needs quickshell and dbus-run-session; no display, no
# running shell.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-"$root/build/visual"}

command -v quickshell >/dev/null 2>&1 || { echo "quickshell is required" >&2; exit 1; }

scratch=$(mktemp -d "${TMPDIR:-/tmp}/notchd-visual.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -- "$scratch/config" "$scratch/shots"
ln -s -- "$root/core" "$scratch/config/core"
ln -s -- "$root/tests/visual/shell.qml" "$scratch/config/shell.qml"

# Cut off from the session, so nothing here touches its sockets (isolated.sh).
mkdir -- "$scratch/runtime"
NOTCHD_VISUAL_DIR="$scratch/shots" "$root/scripts/isolated.sh" "$scratch/runtime" \
  timeout 30 quickshell -p "$scratch/config" --no-color > "$scratch/log" 2>&1 || true

# Only Quickshell's own log lines count; the offscreen backend's lack of
# window masks is expected.
problems=$(grep -E '^\s*(WARN|ERROR)' "$scratch/log" | grep -vE 'window masks' || true)
if [[ -n $problems ]]; then
  echo "QML warnings while rendering:" >&2
  echo "$problems" >&2
  exit 1
fi

scenarios=$(grep -oE 'name: "[a-z-]+"' "$root/tests/visual/shell.qml" | cut -d'"' -f2)
mkdir -p -- "$out"
for name in $scenarios; do
  if [[ ! -s "$scratch/shots/$name.png" ]]; then
    echo "scenario $name produced no image; log:" >&2
    cat "$scratch/log" >&2
    exit 1
  fi
  install -m 0644 -- "$scratch/shots/$name.png" "$out/$name.png"
done
echo "visual scenarios in $out"
