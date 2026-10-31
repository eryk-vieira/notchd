#!/usr/bin/env bash
# Runs a command cut off from the session (isolated.sh) with
# tests/visual/demo-player.py as the only MPRIS player on its private bus,
# so the media module shows a fixed, fictional track.
#
#   scripts/with-demo-player.sh <scratch-dir> <log> <command> [args...]
#
# <scratch-dir> must be empty: the track's cover and the runtime dir go
# there, and the private bus's own chatter in bus.log. The command's output
# goes to <log>. Exits with the command's status.
# Needs ImageMagick, python-dbus and python-gobject.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$1
log=$2
shift 2

# The demo track's cover: a sunset gradient with a sun and a horizon line.
magick -size 512x512 gradient:'#ffb36b'-'#6b3fd6' \
  -fill '#ffe2a8' -draw 'circle 256,300 256,190' \
  -fill '#2a1f4a' -draw 'rectangle 0,330 512,512' \
  -fill '#ff7a8a' -draw 'rectangle 0,326 512,334' \
  "$scratch/cover.png"

mkdir -- "$scratch/runtime"
"$root/scripts/isolated.sh" "$scratch/runtime" bash -c '
  python3 "$1" "$2" & player=$!
  sleep 0.5
  log=$3
  shift 3
  status=0
  "$@" > "$log" 2>&1 || status=$?
  kill "$player" 2>/dev/null || true
  exit "$status"
' _ "$root/tests/visual/demo-player.py" "$scratch/cover.png" "$log" "$@" \
  > "$scratch/bus.log" 2>&1
