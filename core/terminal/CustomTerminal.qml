import QtQuick
import ".."
import "../Terminal.js" as Terminal

// A terminal of your own, from the config's `terminals` (Config.terminals):
// its command in a terminal in the notch (TerminalModule). Every one loads
// this file; the service gives each its id, title and fields. The closed
// notch shows the title the program gives the terminal, else the module's;
// without a folder it starts in your home. The command is a shell script:
// "cd ~/app && npm run dev" runs both. Over IPC: `terminal <id> ...`.
TerminalModule {
  id: t
  appName: t.title || t.moduleId
  // Its entry's command (the page edits it there).
  defaultCommand: t.notch ? t.notch.terminalCommandLine(t.moduleId) : ""
  parseTitle: Terminal.plainTitle
  ownDir: false
  script: true
  ipcName: "terminal"
}
