import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../Claude.js" as Claude
import "../Markdown.js" as Markdown

// A quick chat with Claude, for everyday questions: the notch is one Claude
// Code session, run on the user's own login (`claude -p` over stream-json,
// see Claude.command), and "new chat" starts another, clearing the context.
// Meant for a notch of its own: closed, it shows the chat's title (Haiku
// names the chat after its first answer); open, the chat and a field to type
// in (wantsKeyboard). A button hands the session to a terminal (`claude
// --resume`); back in the notch, the chat is read again, with what was said
// there. Over IPC:
//
//   <notch-ipc> claude new                 # a new chat
//   <notch-ipc> claude "ask <question>"    # open the chat and ask
//
// The process starts when the chat opens, so it is ready by the time you
// have typed, and stops after `idleMinutes` closed (it takes ~175 MB); the
// next message resumes the session. The session id is kept in
// $XDG_STATE_HOME/notchd/claude/session.json and the chat is read back from
// Claude Code's own transcript, so a restart keeps it. The rules live in
// core/Claude.js.
NotchModule {
  id: m
  priority: 40
  active: true
  wantsKeyboard: true
  expandedWidth: 560

  // ----------------------------------------------------------------- state
  property var chat: Claude.EMPTY
  readonly property string chatTitle: Claude.title(m.chat, 40)

  readonly property string home: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/notchd/claude"
  readonly property string claudeDir: Quickshell.env("CLAUDE_CONFIG_DIR") || (Quickshell.env("HOME") + "/.claude")

  // How the process is started; a change applies from its next start.
  readonly property var launch: ({ model: m.setting("model"), web: m.setting("web") !== false,
                                   systemPrompt: m.setting("systemPrompt") })
  onLaunchChanged: if (proc.running && !m.chat.busy) m.stop()

  // Open expanded views: while one is, the process stays up.
  property int viewsOpen: 0

  // ------------------------------------------------------------- the chat
  function send(text) {
    if (m.chat.busy) return
    var next = Claude.send(m.chat, text)
    if (next === m.chat) return
    m.chat = next
    m.queue = m.queue.concat([Claude.inputLine(text)])
    m.ensureRunning()
  }

  function newChat() {
    m.queue = []
    m.chat = Claude.EMPTY
    m.handedOff = false
    m.saveSession()
    m.stop()
  }

  // Opens the chat's notch and asks `text` (just opens it without). "ok",
  // or why not.
  function ask(text) {
    var question = String(text || "").trim()
    if (question !== "" && m.chat.busy) return "busy: an answer is on its way"
    if (!m.openNotch()) return "no notch shows claude"
    if (question !== "") m.send(question)
    return "ok"
  }

  // Hands the session to a terminal: `claude --resume` there, with the
  // whole of Claude Code. The process here stops, so the two don't write to
  // the session at once, and the notch closes, so the terminal gets the
  // keyboard. Back in the notch, the chat is read again (handedOff).
  property bool handedOff: false
  function continueInTerminal() {
    if (m.chat.sessionId === "" || m.chat.busy) return
    m.stop()
    terminal.command = Claude.terminalCommand(m.setting("terminal"), m.home, m.chat.sessionId)
    terminal.startDetached()
    m.handedOff = true
    m.closeNotch()
  }
  Process { id: terminal; workingDirectory: m.home }

  function copyLastAnswer() {
    var text = Claude.lastAnswer(m.chat)
    if (text !== "") Quickshell.clipboardText = text
  }

  // The chat opened: start the process now, so the first answer doesn't
  // wait for it.
  function warm() { m.ensureRunning() }

  // An IPC `claude` argument; "ok" or what was wrong.
  function command(text) {
    var cmd = String(text || "").trim()
    if (cmd === "new") { m.newChat(); return "ok" }
    if (cmd === "ask" || cmd.indexOf("ask ") === 0) return m.ask(cmd.slice(3))
    return "usage: claude new | claude \"ask <question>\""
  }

  // -------------------------------------------------------------- process
  // Lines for stdin, written once the process has started.
  property var queue: []
  property bool started: false
  // It started at all since the last start(): a missing `claude` never does.
  property bool everStarted: false
  // Stopped on purpose (new chat, settings, idle): its exit is no error.
  property bool stopping: false
  property string stderrTail: ""

  function ensureRunning() {
    if (m.stopping) return            // starts again on exit, with the queue
    if (proc.running) { m.flush(); return }
    ensureHome.running = true
  }
  function start() {
    m.started = false
    m.everStarted = false
    m.stderrTail = ""
    proc.command = Claude.command({ model: m.launch.model, web: m.launch.web,
                                    systemPrompt: m.launch.systemPrompt, sessionId: m.chat.sessionId })
    proc.running = true
  }
  function stop() {
    if (!proc.running) return
    m.stopping = true
    proc.running = false
  }
  function flush() {
    if (!m.started || m.queue.length === 0) return
    for (var i = 0; i < m.queue.length; i++) proc.write(m.queue[i])
    m.queue = []
  }

  function handleLine(line) {
    // A process on its way out (new chat) must not bring its session back.
    if (m.stopping) return
    var ev = Claude.parseLine(line)
    if (!ev) return
    var before = m.chat
    m.chat = Claude.apply(m.chat, ev)
    if (m.chat.sessionId !== before.sessionId) m.saveSession()
    // The session was gone: this process exits; the next one starts a new
    // session and asks the last question again.
    if (m.chat.retry) {
      var again = Claude.resend(m.chat)
      m.chat = again.state
      m.queue = [again.line]
      m.stop()
      return
    }
    if (!before.busy || m.chat.busy) return
    // The answer came while the chat was closed: say so.
    if (m.viewsOpen === 0) m.requestPeek(5000)
    if (m.setting("titles") !== false && Claude.wantsTitle(m.chat)) m.requestTitle()
  }

  // ---------------------------------------------------------------- title
  // After the first answer Haiku names the chat, on its own (no session
  // kept). A title for a chat that has moved on since is dropped.
  property string titleFor: ""
  function requestTitle() {
    if (titler.running) return
    m.titleFor = m.chat.sessionId
    titler.command = Claude.titleCommand(m.chat)
    titler.running = true
  }
  Process {
    id: titler
    workingDirectory: m.home
    stdout: StdioCollector {
      onStreamFinished: {
        var t = Claude.cleanTitle(text)
        if (t === "" || m.chat.title !== "" || m.chat.sessionId !== m.titleFor) return
        m.chat = Object.assign({}, m.chat, { title: t })
        m.saveSession()
      }
    }
  }

  Process {
    id: ensureHome
    command: ["mkdir", "-p", m.home]
    onExited: function(code) {
      if (code !== 0) { m.chat = Claude.fail(m.chat, "could not create " + m.home); return }
      if (!proc.running) m.start()
    }
  }

  Process {
    id: proc
    workingDirectory: m.home
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { m.handleLine(line) } }
    stderr: SplitParser {
      onRead: function(line) { m.stderrTail = (m.stderrTail + "\n" + line).slice(-400) }
    }
    onStarted: { m.started = true; m.everStarted = true; m.flush() }
    onRunningChanged: {
      if (proc.running || m.everStarted || m.stopping || !m.chat.busy) return
      m.chat = Claude.fail(m.chat, "could not start claude: is Claude Code installed and on PATH?")
      m.queue = []
    }
    onExited: function(code) {
      var wanted = m.stopping
      m.started = false
      m.stopping = false
      if (!wanted && m.chat.busy) {
        var why = m.stderrTail.trim() || ("claude exited with code " + code)
        m.chat = Claude.fail(m.chat, why)
        m.queue = []
      }
      if (m.queue.length > 0) m.ensureRunning()
    }
  }

  // Closed this long and idle, the process stops; the next message resumes.
  Timer {
    interval: Math.max(1, Number(m.setting("idleMinutes")) || 0) * 60000
    running: proc.running && !m.chat.busy && m.viewsOpen === 0 && Number(m.setting("idleMinutes")) > 0
    onTriggered: m.stop()
  }

  // ------------------------------------------------------------- session
  function saveSession() {
    ensureHomeForSave.running = true
  }
  Process {
    id: ensureHomeForSave
    command: ["mkdir", "-p", m.home]
    onExited: sessionFile.setText(JSON.stringify({ sessionId: m.chat.sessionId, title: m.chat.title }) + "\n")
  }
  FileView {
    id: sessionFile
    path: m.home + "/session.json"
    printErrors: false
    onLoaded: {
      var saved = {}
      try { saved = JSON.parse(text()) || {} } catch (e) { saved = {} }
      var id = String(saved.sessionId || "")
      if (id !== "" && m.chat.messages.length === 0) {
        m.chat = Object.assign({}, Claude.EMPTY, { sessionId: id, title: String(saved.title || "") })
        transcript.path = Claude.transcriptPath(m.claudeDir, m.home, id)
      }
    }
  }
  // The chat read from the transcript: at start, and back from a terminal
  // (`reloading`), with what was said there.
  property bool reloading: false
  function reloadTranscript() {
    m.handedOff = false
    if (m.chat.sessionId === "" || m.chat.busy) return
    m.reloading = true
    var path = Claude.transcriptPath(m.claudeDir, m.home, m.chat.sessionId)
    if (transcript.path === path) transcript.reload()
    else transcript.path = path
  }
  FileView {
    id: transcript
    printErrors: false
    onLoaded: {
      if (m.chat.messages.length > 0 && !m.reloading) return
      m.reloading = false
      if (m.chat.busy) return
      var read = Claude.fromTranscript(text(), m.chat.sessionId)
      if (read.title === "") read.title = m.chat.title
      m.chat = read
    }
    // Gone (cleaned up by Claude Code): start over rather than resume
    // something that isn't there.
    onLoadFailed: {
      m.reloading = false
      if (m.chat.messages.length === 0) m.chat = Claude.EMPTY
    }
  }

  // ----------------------------------------------------------------- views
  // How answers are drawn (Markdown.toHtml): theme colors as CSS, so links
  // and code read on any theme.
  function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")" }
  readonly property var markdownStyle: ({
    accent: m.css(Theme.accent), muted: m.css(Theme.muted), line: m.css(Theme.line), code: m.css(Theme.selected),
    quote: m.css(Theme.hover),
    body: Theme.font.body, heading: Theme.font.heading, gap: Theme.space(10), lineHeight: 140
  })

  // Closed: [Claude's logo] [title] [a green dot while an answer is on its
  // way]. Nothing in it changes size while answering: a spinner of glyphs of
  // different widths kept the closed notch resizing, and the dot's place is
  // kept while it is off.
  readonly property string activityText: m.chat.activity === "searching" ? "Searching the web…"
    : m.chat.activity === "writing" ? "Writing…" : m.chat.activity === "thinking" ? "Thinking…" : ""

  compact: Component {
    Row {
      spacing: Theme.space(8)
      Logo { anchors.verticalCenter: parent.verticalCenter }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Theme.space(220))
        textFormat: Text.PlainText
        text: m.chatTitle || "Claude"
        elide: Text.ElideRight
        color: m.chatTitle ? Theme.foreground : Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
      Working { anchors.verticalCenter: parent.verticalCenter }
    }
  }
  verticalCompact: Component {
    Column {
      spacing: Theme.space(6)
      Logo { anchors.horizontalCenter: parent.horizontalCenter }
      Working { anchors.horizontalCenter: parent.horizontalCenter }
    }
  }

  peek: Component {
    Row {
      spacing: Theme.space(12)
      Logo { anchors.verticalCenter: parent.verticalCenter; size: Theme.font.heading * 1.5 }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          textFormat: Text.PlainText
          text: m.chat.error !== "" ? "Claude failed" : "Answer ready"
          color: m.chat.error !== "" ? Theme.danger : Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Text {
          width: Math.min(implicitWidth, Theme.space(260))
          textFormat: Text.PlainText
          text: m.chatTitle
          elide: Text.ElideRight
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
    }
  }

  expanded: Component {
    ColumnLayout {
      id: view
      spacing: Theme.space(10)
      Component.onCompleted: {
        view.sync()
        m.viewsOpen++
        if (m.handedOff) m.reloadTranscript()
        m.warm()
        field.forceActiveFocus()
      }
      Component.onDestruction: m.viewsOpen--

      // The rows the history shows, kept in step with m.chat without being
      // rebuilt: a streaming answer only changes the last one.
      ListModel { id: rows }
      function sync() {
        var list = m.chat.messages
        while (rows.count > list.length) rows.remove(rows.count - 1)
        for (var i = 0; i < list.length; i++) {
          var row = { role: list[i].role, text: list[i].text, tools: list[i].tools.join(",") }
          if (i >= rows.count) rows.append(row)
          else if (rows.get(i).text !== row.text || rows.get(i).tools !== row.tools || rows.get(i).role !== row.role) rows.set(i, row)
        }
      }
      Connections { target: m; function onChatChanged() { view.sync() } }

      // Header: the mark, the title, new chat and copy.
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space(10)
        Logo { size: Theme.font.heading }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: m.chatTitle || "New chat"
          elide: Text.ElideRight
          color: m.chatTitle ? Theme.foreground : Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Working { visible: m.chat.busy }
        IconButton {
          visible: Claude.lastAnswer(m.chat) !== ""
          glyph: 0xF018F  // nf-md-content_copy
          onActivated: m.copyLastAnswer()
        }
        IconButton {
          visible: m.chat.sessionId !== "" && !m.chat.busy
          glyph: 0xF018D  // nf-md-console
          onActivated: m.continueInTerminal()
        }
        IconButton {
          visible: m.chat.messages.length > 0
          glyph: 0xF0709  // nf-md-restart
          onActivated: { m.newChat(); field.forceActiveFocus() }
        }
      }

      // The history, scrolled to the latest answer.
      Flickable {
        id: history
        visible: rows.count > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(historyColumn.implicitHeight, Theme.space(420))
        contentHeight: historyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Follows the answer as it grows, unless you scrolled up.
        property bool pinnedToEnd: true
        onMovementEnded: history.pinnedToEnd = history.contentY >= history.contentHeight - history.height - Theme.space(8)
        onContentHeightChanged: if (history.pinnedToEnd) history.contentY = Math.max(0, history.contentHeight - history.height)
        onHeightChanged: if (history.pinnedToEnd) history.contentY = Math.max(0, history.contentHeight - history.height)

        Column {
          id: historyColumn
          width: history.width
          spacing: Theme.space(20)
          Repeater {
            model: rows
            delegate: Item {
              id: entry
              required property string role
              required property string text
              required property string tools
              width: historyColumn.width
              implicitHeight: entry.role === "user" ? bubble.height : answer.implicitHeight

              // A question: on the right, in a bubble.
              Rectangle {
                id: bubble
                visible: entry.role === "user"
                anchors.right: parent.right
                width: Math.min(question.implicitWidth, entry.width * 0.8) + Theme.space(20)
                height: question.implicitHeight + Theme.space(12)
                radius: Theme.radius
                color: Theme.selected
                Text {
                  id: question
                  anchors.centerIn: parent
                  width: Math.min(implicitWidth, entry.width * 0.8)
                  textFormat: Text.PlainText
                  text: entry.text
                  wrapMode: Text.Wrap
                  color: Theme.foreground
                  font.family: Theme.font.family
                  font.pixelSize: Theme.font.body
                }
              }

              // An answer: Markdown, selectable, with the tools it used.
              Column {
                id: answer
                visible: entry.role === "assistant"
                width: entry.width
                spacing: Theme.space(8)
                Text {
                  visible: entry.tools !== ""
                  textFormat: Text.PlainText
                  text: String.fromCodePoint(0xF0349) + " " + (entry.tools.indexOf("WebFetch") !== -1 ? "Read the web" : "Searched the web")
                  color: Theme.muted
                  font.family: Theme.font.family
                  font.pixelSize: Theme.font.caption
                }
                TextEdit {
                  visible: entry.text !== ""
                  width: parent.width
                  readOnly: true
                  selectByMouse: true
                  textFormat: TextEdit.RichText
                  text: Markdown.toHtml(entry.text, m.markdownStyle)
                  wrapMode: TextEdit.Wrap
                  color: Theme.foreground
                  selectionColor: Theme.selected
                  selectedTextColor: Theme.foreground
                  font.family: Theme.font.family
                  font.pixelSize: Theme.font.body
                  onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                  HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor }
                }
              }
            }
          }
        }
      }

      // Before the first question: how to use it.
      Text {
        visible: rows.count === 0 && m.chat.error === ""
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: "Ask anything. Enter sends, Shift+Enter starts a new line, Esc closes."
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }

      // Something to know, no error (the earlier chat was gone).
      Text {
        visible: m.chat.notice !== ""
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: m.chat.notice
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }

      // What it is doing, or why it failed.
      Text {
        visible: text !== ""
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: m.chat.busy ? m.activityText : m.chat.error
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        color: m.chat.busy ? Theme.muted : Theme.danger
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }

      // The field.
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.min(field.implicitHeight, Theme.space(120)) + Theme.space(16)
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: field.activeFocus ? Theme.muted : Theme.line

        Flickable {
          id: fieldScroll
          anchors.fill: parent
          anchors.margins: Theme.space(8)
          contentHeight: field.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          TextEdit {
            id: field
            width: fieldScroll.width
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: Theme.foreground
            selectionColor: Theme.selected
            selectedTextColor: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
            onCursorRectangleChanged: {
              if (cursorRectangle.y < fieldScroll.contentY) fieldScroll.contentY = cursorRectangle.y
              else if (cursorRectangle.y + cursorRectangle.height > fieldScroll.contentY + fieldScroll.height)
                fieldScroll.contentY = cursorRectangle.y + cursorRectangle.height - fieldScroll.height
            }
            // Enter sends, Shift+Enter breaks the line; nothing is sent while
            // an answer is on its way (the text stays).
            function submit(event) {
              if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
              if (m.chat.busy || field.text.trim() === "") return
              m.send(field.text)
              field.text = ""
              history.pinnedToEnd = true
            }
            Keys.onReturnPressed: function(event) { field.submit(event) }
            Keys.onEnterPressed: function(event) { field.submit(event) }
            Text {
              visible: field.text === ""
              textFormat: Text.PlainText
              text: m.chat.messages.length > 0 ? "Ask a follow-up…" : "Ask Claude…"
              color: Theme.faint
              font: field.font
            }
          }
        }
        // A press on the field pins the notch, so it gets the keyboard; the
        // press goes on to the field.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onPressed: function(mouse) { m.requestKeyboard(); field.forceActiveFocus(); mouse.accepted = false }
        }
      }
    }
  }

  // ------------------------------------------------------------ components
  // Claude's logo (core/modules/claude.svg, see NOTICE), drawn at `size`
  // px. mipmap keeps it out of the window-sized texture atlas (modules.md).
  component Logo: Item {
    id: logo
    property real size: Theme.font.body * 1.25
    // Its size from `size` alone: from its own width, a layout feeding the
    // image's implicit size back doubled it each pass.
    implicitWidth: Math.round(logo.size)
    implicitHeight: implicitWidth
    Image {
      anchors.fill: parent
      source: Qt.resolvedUrl("claude.svg")
      sourceSize.width: Math.round(logo.size) * 2
      sourceSize.height: Math.round(logo.size) * 2
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }
  // A green dot while an answer is on its way; its place stays while off.
  component Working: Item {
    implicitWidth: Theme.space(7)
    implicitHeight: implicitWidth
    Rectangle {
      anchors.fill: parent
      visible: m.chat.busy
      radius: width / 2
      color: Theme.success
    }
  }
  component IconButton: Item {
    id: btn
    property int glyph: 0
    signal activated()
    implicitWidth: Theme.space(28)
    implicitHeight: implicitWidth
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: btnMouse.containsMouse ? Theme.selected : "transparent"
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: String.fromCodePoint(btn.glyph)
      color: Theme.foreground
      font.family: Theme.font.family
      font.pixelSize: Theme.font.heading
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }
}
