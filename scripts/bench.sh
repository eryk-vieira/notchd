#!/usr/bin/env bash
# Measures what notchd costs: CPU, wakeups and memory of the standalone host
# on your real Wayland session, scenario by scenario (idle, a timer running,
# music playing; closed and open), next to an empty Quickshell as the floor.
# A second notch shows on your screen while it runs (about two minutes).
#
#   scripts/bench.sh [out]     # out: build/bench.md by default
#   BENCH_SECONDS=20 scripts/bench.sh
#
# Offscreen can't do this: PanelWindow needs a compositor, and the cost that
# matters is rendering real frames. So it runs on your display, but on a
# private D-Bus that activates nothing (no portals, no AT-SPI) and whose only
# MPRIS player is tests/visual/demo-player.py, with its own short
# XDG_RUNTIME_DIR (the IPC socket path must fit in ~108 bytes) that links in
# the Wayland socket and Hyprland's. The config is a scratch file, never
# ~/.config/notchd.
#
# Each scenario samples the process for BENCH_SECONDS (10 by default) from
# /proc: CPU time (% of one core), context switches per second over all
# threads (a stand-in for frames and timer wakeups) and PSS/RSS. Keep the
# pointer away from the notch and the machine otherwise quiet; repeat a run
# before trusting a difference of a point or two.
#
# Needs quickshell, dbus-daemon, python-dbus, python-gobject and ImageMagick.
set -euo pipefail

# Inside the private session: start, wait for the IPC, run the steps.
if [[ ${1:-} == --inner ]]; then
  shift
  dir=$1 player=$2 scratch=$3 secs=$4
  shift 4
  sample() {
    local pid=$1 name=$2 t0 t1 c0 c1 x0 x1
    cpu() { sed 's/.*) //' "/proc/$pid/stat" | awk '{ print $12 + $13 }'; }
    ctx() { cat /proc/"$pid"/task/*/status 2>/dev/null | awk '/ctxt_switches/ { s += $2 } END { print s }'; }
    t0=$(date +%s.%N); c0=$(cpu); x0=$(ctx)
    sleep "$secs"
    t1=$(date +%s.%N); c1=$(cpu); x1=$(ctx)
    awk -v n="$name" -v t0="$t0" -v t1="$t1" -v c0="$c0" -v c1="$c1" -v x0="$x0" -v x1="$x1" \
        -v hz="$(getconf CLK_TCK)" \
        -v pss="$(awk '/^Pss:/ { print $2 }' "/proc/$pid/smaps_rollup")" \
        -v rss="$(awk '/^Rss:/ { print $2 }' "/proc/$pid/smaps_rollup")" \
        -v thr="$(awk '/^Threads:/ { print $2 }' "/proc/$pid/status")" \
        'BEGIN { dt = t1 - t0
                 printf "| %s | %.1f | %d | %.0f | %.0f | %d |\n", n, (c1 - c0) * 100 / hz / dt,
                        (x1 - x0) / dt, pss / 1024, rss / 1024, thr }' >> "$scratch/results"
  }
  if [[ $player == 1 ]]; then
    python3 "$(dirname -- "${BASH_SOURCE[0]}")/../tests/visual/demo-player.py" "$scratch/cover.png" &
    player_pid=$!
    sleep 0.5
  fi
  quickshell -p "$dir" --no-color > "$scratch/$(basename -- "$dir").$player.log" 2>&1 &
  qs_pid=$!
  if [[ $dir == "$scratch/empty" ]]; then
    sleep 3
  else
    for _ in $(seq 50); do
      qs -p "$dir" ipc call notchd state >/dev/null 2>&1 && break
      sleep 0.2
    done
    qs -p "$dir" ipc call notchd state >/dev/null 2>&1 \
      || { echo "notchd did not start; log:" >&2; cat "$scratch/$(basename -- "$dir").$player.log" >&2; exit 1; }
  fi
  sleep 2
  for step in "$@"; do
    case $step in
      "sample "*) sample "$qs_pid" "${step#sample }" ;;
      *) read -ra call <<< "$step"; qs -p "$dir" ipc call notchd "${call[@]}" >/dev/null; sleep 2 ;;
    esac
  done
  kill "$qs_pid" 2>/dev/null || true
  wait "$qs_pid" 2>/dev/null || true
  [[ -n ${player_pid:-} ]] && kill "$player_pid" 2>/dev/null
  exit 0
fi

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-"$root/build/bench.md"}
secs=${BENCH_SECONDS:-10}

for tool in quickshell qs dbus-run-session python3 magick; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "needs a Wayland session (WAYLAND_DISPLAY is unset)" >&2; exit 1; }
session_runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/notchd-bench.XXXXXX")
# Short on purpose: the IPC socket lives under it.
runtime=$(mktemp -d /tmp/nb.XXXXXX)
cleanup() {
  pkill -P $$ 2>/dev/null || true
  rm -rf -- "$scratch" "$runtime"
}
trap cleanup EXIT
chmod 700 -- "$runtime"
case $WAYLAND_DISPLAY in
  /*) ;;
  *) ln -s -- "$session_runtime/$WAYLAND_DISPLAY" "$runtime/$WAYLAND_DISPLAY" ;;
esac
[[ -d $session_runtime/hypr ]] && ln -s -- "$session_runtime/hypr" "$runtime/hypr"

# A session bus with no service dirs: nothing gets activated on it.
cat > "$scratch/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$runtime</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF

magick -size 512x512 gradient:'#ffb36b'-'#6b3fd6' "$scratch/cover.png"
mkdir -- "$scratch/empty"
printf 'import Quickshell\nShellRoot {}\n' > "$scratch/empty/shell.qml"
printf '{ "modules": ["activities", "timer", "media"] }\n' > "$scratch/base.json"
: > "$scratch/results"

# Runs one quickshell, then each step: "sample <name>" measures, anything
# else is an IPC call to the notch (followed by a moment to settle).
#   run <config dir> <player 0|1> <steps...>
run() {
  local dir=$1 player=$2
  shift 2
  cp -- "$scratch/base.json" "$scratch/config.json"
  env -u DBUS_SESSION_BUS_ADDRESS -u QT_QPA_PLATFORMTHEME \
    XDG_RUNTIME_DIR="$runtime" NO_AT_BRIDGE=1 NOTCHD_CONFIG="$scratch/config.json" \
    dbus-run-session --config-file="$scratch/bus.conf" -- \
    bash "$root/scripts/bench.sh" --inner "$dir" "$player" "$scratch" "$secs" "$@" \
    >> "$scratch/bus.log" 2>&1
}


echo "notchd bench: ${secs}s per scenario; a second notch shows while it runs" >&2
run "$scratch/empty" 0 "sample quickshell, empty config (floor)"
run "$root" 0 "sample idle, closed" "open" "sample idle, open" "close" \
  "timer 25m" "sample timer running, closed" "open" "sample timer running, open" "close" "timer stop"
run "$root" 1 "sample music playing, closed" "open" "sample music playing, open" "close"

{
  echo "# notchd bench"
  echo
  echo "$(date -Iseconds) · $(git -C "$root" describe --always --dirty 2>/dev/null || echo unknown)" \
    "· ${secs}s per scenario · $(hyprctl monitors -j 2>/dev/null \
      | python3 -c 'import json,sys; print(", ".join(f"{m["name"]} {m["width"]}x{m["height"]}@{round(m["refreshRate"])}" for m in json.load(sys.stdin)))' \
      2>/dev/null || echo "monitors unknown")"
  echo
  echo "| Scenario | CPU % (one core) | Context switches/s | PSS MB | RSS MB | Threads |"
  echo "|---|---:|---:|---:|---:|---:|"
  cat "$scratch/results"
} > "$scratch/report"

mkdir -p -- "$(dirname -- "$out")"
cp -- "$scratch/report" "$out"
cat "$out"
expected=7
if (( $(wc -l < "$scratch/results") != expected )); then
  echo "only $(wc -l < "$scratch/results") of $expected scenarios ran; bus log:" >&2
  tail -20 "$scratch/bus.log" >&2
  exit 1
fi
