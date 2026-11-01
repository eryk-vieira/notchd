import QtQuick
import ".."
import "../Agent.js" as Agent

// Claude Code in the notch, in its own terminal UI (TerminalModule). The
// closed notch shows the conversation's title, which Claude Code makes
// after the first message, and a dot while it works: both read from the
// title Claude Code gives the terminal (Agent.claudeTitle). The logo is
// claude.svg (see NOTICE).
TerminalModule {
  appName: "Claude"
  defaultCommand: "claude"
  parseTitle: Agent.claudeTitle
  logoSource: Qt.resolvedUrl("claude.svg")
}
