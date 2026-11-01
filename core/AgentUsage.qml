import QtQuick
import Quickshell
import Quickshell.Io
import "Usage.js" as Usage

// An agent's plan usage: how much of each window (5 hours, the week) is
// used, from the endpoint the agent's CLI calls (Usage.SOURCES), with the
// login the CLI keeps. That login is only read, never refreshed or written:
// when it lapses, the last limits stay, marked stale, until the agent
// renews it by running (the file changing asks again).
//
// It asks every `interval`, when `refresh()` is called (an agent that just
// finished), and after a 429 not before the time it was given. `alert` is
// emitted once per window as a limit passes `threshold` %, and at 100 %
// (Usage.alerts). The rules are in core/Usage.js.
Item {
  id: usage

  // "claude" or "codex" (Usage.SOURCES); "" asks nothing.
  property string provider: ""
  property bool enabled: true
  property int threshold: 80
  property int interval: 300000
  // Off in the tests: no file read, no request. They call apply().
  property bool live: true

  // Usage.limitsOf's limits, the tightest first in `tightest`.
  property var limits: []
  readonly property var tightest: Usage.tightest(usage.limits)
  // The limits are from an earlier answer: this one failed (`problem`).
  property bool stale: false
  property string problem: ""
  property real fetchedAt: 0
  // What was warned about, per window (Usage.alerts); null before the
  // first answer.
  property var warned: null
  signal alert(var limit)

  readonly property bool active: usage.enabled && usage.provider !== "" && !!Usage.SOURCES[usage.provider]

  // ~/.claude/.credentials.json (CLAUDE_CONFIG_DIR), ~/.codex/auth.json
  // (CODEX_HOME).
  readonly property string credentialsPath: {
    var src = Usage.SOURCES[usage.provider]
    if (!src) return ""
    var home = String(Quickshell.env("HOME") || "")
    var dir = usage.provider === "claude" ? (Quickshell.env("CLAUDE_CONFIG_DIR") || home + "/.claude")
                                          : (Quickshell.env("CODEX_HOME") || home + "/.codex")
    return String(dir).replace(/\/+$/, "") + "/" + src.credentials
  }

  FileView {
    id: creds
    path: usage.live && usage.active ? usage.credentialsPath : ""
    blockLoading: true
    printErrors: false
    watchChanges: true
    // The CLI renewed its login: ask again if the last try lacked it.
    onFileChanged: {
      creds.reload()
      if (usage.problem === "login expired" || usage.problem === "not signed in") usage.refresh(true)
    }
  }

  // ------------------------------------------------------------- asking
  property bool busy: false
  // Not before this (ms): after a 429.
  property real notBefore: 0
  property var xhr: null

  // Asks now; without `force` (an agent that finished a task), not within a
  // minute of the last answer.
  function refresh(force) {
    if (!usage.live || !usage.active || usage.busy) return
    var now = Date.now()
    if (now < usage.notBefore) return
    if (!force && now - usage.fetchedAt < 60000) return
    var req = Usage.request(usage.provider, creds.text(), now)
    if (req.error) {
      usage.fail(req.error)
      return
    }
    var x = new XMLHttpRequest()
    usage.xhr = x
    usage.busy = true
    x.onreadystatechange = function() {
      if (x.readyState !== XMLHttpRequest.DONE || usage.xhr !== x) return
      usage.finish(x.status, x.responseText, x.getResponseHeader("Retry-After"))
    }
    x.open("GET", req.url)
    for (var h in req.headers) x.setRequestHeader(h, req.headers[h])
    x.send()
    timeout.restart()
  }

  // Nothing back in 20 s: offline.
  Timer {
    id: timeout
    interval: 20000
    onTriggered: if (usage.xhr) { var x = usage.xhr; usage.xhr = null; x.abort(); usage.finish(0, "", "") }
  }

  function finish(status, body, retryAfter) {
    timeout.stop()
    usage.xhr = null
    usage.busy = false
    var next = Usage.afterStatus(status, retryAfter, usage.interval)
    if (status === 429) usage.notBefore = Date.now() + next.retryMs
    if (status === 200) {
      var data = null
      try { data = JSON.parse(body) } catch (e) {}
      if (!usage.apply(data)) next = { problem: "unexpected answer", stale: true }
    }
    usage.problem = next.problem
    usage.stale = next.stale && usage.limits.length > 0
  }

  function fail(problem) {
    usage.problem = problem
    usage.stale = usage.limits.length > 0
  }

  // An answer (the endpoint's JSON): its limits, and the warnings due.
  // False when it isn't one.
  function apply(data) {
    var limits = Usage.limitsOf(usage.provider, data, Date.now())
    if (limits === null) return false
    usage.limits = limits
    usage.fetchedAt = Date.now()
    usage.problem = ""
    usage.stale = false
    var r = Usage.alerts(limits, usage.warned, usage.threshold)
    usage.warned = r.warned
    for (var i = 0; i < r.alerts.length; i++) usage.alert(r.alerts[i])
    return true
  }

  Timer {
    interval: usage.interval
    running: usage.live && usage.active
    repeat: true
    triggeredOnStart: true
    onTriggered: usage.refresh(true)
  }
}
