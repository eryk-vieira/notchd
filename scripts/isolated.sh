#!/usr/bin/env bash
# Runs a command cut off from the user's desktop session, for offscreen
# renders: a private D-Bus, its own XDG_RUNTIME_DIR, no Wayland/X/Hyprland,
# no GTK platform theme (it needs a display) and no accessibility bridge.
#
#   scripts/isolated.sh <runtime-dir> <command> [args...]
#
# <runtime-dir> must be an empty scratch directory. Why it matters: services
# a bus activates (the AT-SPI launcher, portals) create their sockets under
# XDG_RUNTIME_DIR. Sharing the real one, a private bus's AT-SPI launcher
# replaced the session's /run/user/$UID/at-spi/bus_0 and broke accessibility
# for every app started afterwards.
set -euo pipefail

runtime=$1
shift
chmod 700 -- "$runtime"

exec env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
  -u DBUS_SESSION_BUS_ADDRESS -u QT_QPA_PLATFORMTHEME \
  XDG_RUNTIME_DIR="$runtime" NO_AT_BRIDGE=1 QT_QPA_PLATFORM=offscreen \
  dbus-run-session -- "$@"
