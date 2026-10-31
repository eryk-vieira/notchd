#!/usr/bin/env bash
# Renders the README image (docs/images/hero.webp, or $1) from
# tests/visual/hero.qml: the real notch in four states, offscreen, on a
# private D-Bus where the only media player is tests/visual/demo-player.py.
#
# The tiles show WALLPAPER, by default Omarchy's Gruvbox "The Backwater"
# (the wallpaper is not in the repo; only the rendered image is). Without
# it they fall back to a gradient.
# Needs quickshell, ImageMagick, python-dbus, python-gobject and
# JetBrainsMono Nerd Font.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-"$root/docs/images/hero.webp"}
wallpaper=${WALLPAPER:-"${OMARCHY_PATH:-/usr/share/omarchy}/themes/gruvbox/backgrounds/1-the-backwater.jpg"}
if [[ ! -r $wallpaper ]]; then
  echo "wallpaper not found ($wallpaper); using a gradient. Set WALLPAPER=<image>." >&2
  wallpaper=""
fi
export NOTCHD_HERO_WALLPAPER=$wallpaper

for tool in quickshell magick dbus-run-session python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done

scratch=$(mktemp -d "${TMPDIR:-/tmp}/notchd-hero.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -- "$scratch/config" "$scratch/out"
ln -s -- "$root/core" "$scratch/config/core"
ln -s -- "$root/hosts" "$scratch/config/hosts"
ln -s -- "$root/tests/visual/hero.qml" "$scratch/config/shell.qml"

# The demo track's cover: a sunset gradient with a sun and a horizon line.
magick -size 512x512 gradient:'#ffb36b'-'#6b3fd6' \
  -fill '#ffe2a8' -draw 'circle 256,300 256,190' \
  -fill '#2a1f4a' -draw 'rectangle 0,330 512,512' \
  -fill '#ff7a8a' -draw 'rectangle 0,326 512,334' \
  "$scratch/cover.png"

# Cut off from the session (see isolated.sh), with the demo player as the
# only MPRIS player on the private bus.
mkdir -- "$scratch/runtime"
"$root/scripts/isolated.sh" "$scratch/runtime" bash -c '
  python3 "$1" "$2" & player=$!
  sleep 0.5
  NOTCHD_VISUAL_DIR="$3" NOTCHD_HERO_FILE="$3/hero.png" \
    timeout 30 quickshell -p "$4" --no-color > "$5" 2>&1 || true
  kill "$player" 2>/dev/null || true
' _ "$root/tests/visual/demo-player.py" "$scratch/cover.png" "$scratch/out" "$scratch/config" "$scratch/log" \
  > "$scratch/bus.log" 2>&1   # the private bus's own chatter

# Only Quickshell's own log lines; GLib/AT-SPI chatter about the private bus
# starts with "** (" and is not ours.
problems=$(grep -E '^\s*(WARN|ERROR)' "$scratch/log" | grep -vE 'window masks|outside of the config folder' || true)
if [[ -n $problems ]]; then
  echo "QML warnings while rendering:" >&2
  echo "$problems" >&2
  exit 1
fi
[[ -s "$scratch/out/hero.png" ]] || { echo "no image; log:" >&2; cat "$scratch/log" >&2; exit 1; }

mkdir -p -- "$(dirname -- "$out")"
# WebP: the painted wallpaper makes a PNG weigh ~1.7 MB; at quality 90 this
# is ~400 KB with text as crisp. The image is committed.
magick "$scratch/out/hero.png" -strip -quality 90 "$out"
echo "hero image: $out"
