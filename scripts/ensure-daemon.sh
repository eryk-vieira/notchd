#!/usr/bin/env bash
# Makes sure the notchd daemon runs and prints its socket path: what a host
# (Service.qml, shell.qml) runs at startup. docs/architecture.md, "Distribution".
#
# The binary, first hit wins: $NOTCHD_BIN, `notchd` on PATH (both the user's
# choice, used as they are), $XDG_DATA_HOME/notchd/bin/notchd. That last one
# is the plugin's: scripts/fetch-daemon.py runs every time and puts the
# release of manifest.json's version there (it keeps a binary that already
# reports it), so an updated plugin gets its own daemon, and `daemon --ensure`
# replaces a running one of another version. When the fetch fails (offline,
# no pin for this version) a binary already there is used as it is. The
# instance and config come
# from the environment (NOTCHD_INSTANCE, NOTCHD_CONFIG, NOTCHD_SOCKET), as for
# `notchd` itself; `make dev` sets them so it never meets the user's daemon.
#
# Success: the socket path on stdout, exit 0. Failure: one line of JSON,
# {"error": "..."}, on stdout, exit 1, for the host to show.
set -u

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}/notchd/bin

fail() {
  local msg=${1//\\/\\\\}
  msg=${msg//\"/\\\"}
  msg=${msg//$'\n'/ }
  printf '{"error":"%s"}\n' "$msg"
  exit 1
}

# The plugin's binary, fetched (or kept, when it is the right version).
# Run in $(...): a failure is the JSON error on stdout and status 1.
plugin_bin() {
  local fetched="" last msg
  if [ -f "$here/fetch-daemon.py" ]; then
    if fetched=$(python3 "$here/fetch-daemon.py" --dest "$data" 2>&1); then
      fetched=$(printf '%s\n' "$fetched" | tail -n 1)
      [ -x "$fetched" ] || fail "fetched notchd is not executable: $fetched"
      printf '%s\n' "$fetched"
      return 0
    fi
  fi
  [ -x "$data/notchd" ] && { printf '%s\n' "$data/notchd"; return 0; }
  [ -n "$fetched" ] || fail "notchd not found"
  # fetch-daemon.py's error, {"error": <code>, "message": ...}: its message.
  last=$(printf '%s\n' "$fetched" | tail -n 1)
  msg=$(printf '%s' "$last" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d.get("message") or d["error"])' 2>/dev/null) || msg=$last
  fail "$msg"
}

if [ -n "${NOTCHD_BIN:-}" ]; then
  [ -x "$NOTCHD_BIN" ] || fail "NOTCHD_BIN is not executable: $NOTCHD_BIN"
  bin=$NOTCHD_BIN
elif bin=$(command -v notchd 2>/dev/null); then
  :
else
  bin=$(plugin_bin) || { printf '%s\n' "$bin"; exit 1; }
fi

out=$("$bin" daemon --ensure 2>&1) || fail "${out##*$'\n'}"
printf '%s\n' "${out##*$'\n'}"
