// Coding agents in the notch, each in its own terminal UI (TerminalModule:
// modules/codex.qml, modules/claude.qml). What the closed notch shows comes
// from the terminal's title, which the agent sets itself; each agent has
// its own way. Plain functions: QML imports this file as is and the Node
// tests load it in a vm.

var ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function text(raw) {
  return String(raw === undefined || raw === null ? "" : raw).trim()
}

// Codex, with its default `tui.terminal_title` (spinner, thread, project):
// a braille spinner and a space while it works, then "<thread> | <project>",
// or just the project until Codex has named the thread (it does, in a few
// words, after the first message). No options are passed for it: any `-c`
// runs Codex without its shared background server.
function codexTitle(raw) {
  var t = text(raw)
  var working = false
  var first = t.charCodeAt(0)
  if (first >= 0x2800 && first <= 0x28FF) {
    working = true
    t = t.slice(1).trim()
  }
  var parts = t.split(" | ")
  var title = parts.length > 1 ? parts.slice(0, -1).join(" | ").trim() : ""
  if (ID.test(title)) title = ""
  return { working: working, title: title }
}

// Claude Code: "✳ <title>" while idle, a turning half circle (◐◑◒◓) in
// place of the ✳ while it works. The title is "Claude Code" until Claude
// Code has named the conversation (it does, after the first message).
function claudeTitle(raw) {
  var t = text(raw)
  var working = false
  var first = t.charCodeAt(0)
  if (first === 0x2733) {
    t = t.slice(1).trim()
  } else if ((first >= 0x25D0 && first <= 0x25D3) || (first >= 0x2800 && first <= 0x28FF)) {
    working = true
    t = t.slice(1).trim()
  }
  return { working: working, title: t === "Claude Code" ? "" : t }
}

// Whether to say the agent is done (a peek): it stopped working while no
// view was open, after you had typed to it. Agents also spin while they
// start, before anything was asked.
function donePeek(s) {
  return !!s.wasWorking && !s.working && !s.open && !!s.typed
}

// An IPC command: "new" starts a new session, "ask <text>" opens the notch
// and types the text in, followed by Enter ("ask" alone only opens it).
// { action: "new" | "ask" | "usage", text }. The text is one line: a line
// break would send it early.
function parseCommand(raw) {
  var cmd = text(raw)
  if (cmd === "new") return { action: "new", text: "" }
  if (cmd === "ask" || cmd.indexOf("ask ") === 0)
    return { action: "ask", text: cmd.slice(3).replace(/\s*[\r\n]+\s*/g, " ").trim() }
  return { action: "usage", text: "" }
}
