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

// The arguments of /bin/sh that run `command` (a command line as typed in
// the settings, "codex --search") with `extra` after its own arguments. The
// shell parses the command, so it can be anything a shell takes; `extra`
// reaches the program as given, never parsed again. TERM says what the
// widget emulates (it sets plain "xterm" for every session; it does 256
// colors).
function shellArgs(command, extra) {
  var cmd = String(command || "").trim()
  return ["-c", "TERM=xterm-256color; export TERM; exec " + cmd + " \"$@\"", "sh"].concat(extra || [])
}

// The built-in color scheme behind the ANSI colors; the view sets the
// theme's background and foreground over it. The widget only reads schemes
// from its own package's folder, so the theme can't bring a palette of its
// own. Tango, on any theme: its bright black (ANSI 8) is a dark gray, and
// Codex, which can't ask this terminal for its background (the widget
// doesn't answer OSC 11), paints your messages with it. Breeze's is orange.
var SCHEME = "Tango"
