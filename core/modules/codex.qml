import QtQuick
import ".."
import "../Agent.js" as Agent

// Codex (OpenAI's coding agent) in the notch, in its own terminal UI
// (TerminalModule). The closed notch shows the thread's title, which Codex
// makes after the first message, and a dot while it works: both read from
// the title Codex gives the terminal (Agent.codexTitle).
TerminalModule {
  appName: "Codex"
  parseTitle: Agent.codexTitle
}
