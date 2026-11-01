// The terminal a module shows in its expanded view (core/terminal/
// TerminalView.qml, used by modules/codex.qml): whether the widget is
// installed, the command line it runs, its colors. Plain functions: QML
// imports this file as is and the Node tests load it in a vm.

// The view imports QMLTermWidget, from the optional qmltermwidget package
// (the QML port of qtermwidget). Without it, loading the view fails with a
// warning; this loads only that import, and Qt.createQmlObject throws on it
// quietly. The module tries it first.
var PROBE = "import QtQuick\nimport QMLTermWidget\nItem {}\n"

// "~" and "~/x" under `home`; "" is the home itself; anything else as given.
function expandHome(path, home) {
  var p = String(path === undefined || path === null ? "" : path).trim()
  var h = String(home || "").replace(/\/+$/, "")
  if (p === "" || p === "~") return h || "/"
  if (p.indexOf("~/") === 0) return h + p.slice(1)
  return p
}

// notchd's own folder for agents, where one without a folder of its own
// starts: notchd in the documents folder (xdg-user-dir, which says the home
// when there is none: then ~/Documents), made first. If it can't be made,
// the agent starts where the shell is.
var OWN_DIR = "d=$(xdg-user-dir DOCUMENTS 2>/dev/null); "
  + "if [ -z \"$d\" ] || [ \"$d\" = \"$HOME\" ]; then d=\"$HOME/Documents\"; fi; "
  + "d=\"$d/notchd\"; mkdir -p -- \"$d\" && cd -- \"$d\"; "

// The arguments of /bin/sh that run `command` (a command line as typed in
// the settings, "codex --search") with `extra` after its own arguments, in
// notchd's own folder with `ownDir` (OWN_DIR). The shell parses the
// command, so it can be anything a shell takes; `extra` reaches the program
// as given, never parsed again. TERM says what the widget emulates (it sets
// plain "xterm" for every session; it does 256 colors).
function shellArgs(command, extra, ownDir) {
  var cmd = String(command || "").trim()
  return ["-c", (ownDir ? OWN_DIR : "") + "TERM=xterm-256color; export TERM; exec " + cmd + " \"$@\"", "sh"].concat(extra || [])
}

// The key that leaves the terminal (the notch closes, the program goes on):
// Ctrl+Escape, which neither Claude Code nor Codex binds; plain Escape is
// theirs (it interrupts them). `key` and `modifiers` as Qt gives them
// (Qt.Key_Escape is 0x01000000, Qt.ControlModifier 0x04000000); Shift,
// Alt or Super with it make another key. The keypad flag doesn't count.
var KEY_ESCAPE = 0x01000000
var MOD_CONTROL = 0x04000000
var MOD_KEYPAD = 0x20000000
function isLeaveKey(key, modifiers) {
  return key === KEY_ESCAPE && ((modifiers || 0) & ~MOD_KEYPAD) === MOD_CONTROL
}

// The built-in color scheme behind the ANSI colors; the view sets the
// theme's background and foreground over it. The widget only reads schemes
// from its own package's folder, so the theme can't bring a palette of its
// own. Tango, on any theme: its bright black (ANSI 8) is a dark gray, and
// Codex, which can't ask this terminal for its background (the widget
// doesn't answer OSC 11), paints your messages with it. Breeze's is orange.
var SCHEME = "Tango"
