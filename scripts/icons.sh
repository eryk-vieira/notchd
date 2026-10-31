#!/bin/sh
# Renders the app icon, assets/icons/hicolor/scalable/apps/notchd.svg, into
# PNGs at every hicolor size and a multi-size notchd.ico. `make icons`; rerun
# after editing the SVG and commit the result.
set -eu
cd "$(dirname "$0")/.."

icons=assets/icons
svg=$icons/hicolor/scalable/apps/notchd.svg

for size in 16 22 24 32 48 64 96 128 256 512 1024; do
  dir=$icons/hicolor/${size}x${size}/apps
  mkdir -p "$dir"
  rsvg-convert -w "$size" -h "$size" "$svg" -o "$dir/notchd.png"
done

magick $(for size in 16 24 32 48 64 128 256; do
  printf '%s ' "$icons/hicolor/${size}x${size}/apps/notchd.png"; done) "$icons/notchd.ico"

echo "icons: $icons"
