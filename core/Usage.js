// The plan limits of the coding agents (core/AgentUsage.qml reads them):
// how much of each window (5 hours, the week) is used and when it resets.
// The answers of the endpoints the agents' own CLIs call, made into one
// shape, and when to warn. Plain functions: QML imports this file as is and
// the Node tests load it in a vm.
//
// A limit: { id, label, percent (0..100), resetsAt (ms, 0 unknown),
// windowSecs (0 unknown) }. `id` stays the same from one answer to the
// next, so a warning is given once per window.

var WINDOW_SESSION = 18000     // 5 hours
var WINDOW_WEEK = 604800       // 7 days

// Where each agent's plan usage comes from: the endpoint its CLI calls,
// with the login the CLI keeps (read only: never refreshed or written
// here; the agent renews it when it runs).
var SOURCES = {
  claude: {
    url: "https://api.anthropic.com/api/oauth/usage",
    // Relative to CLAUDE_CONFIG_DIR, else ~/.claude.
    credentials: ".credentials.json"
  },
  codex: {
    url: "https://chatgpt.com/backend-api/wham/usage",
    // Relative to CODEX_HOME, else ~/.codex.
    credentials: "auth.json"
  }
}

function num(v) {
  if (v === null || v === undefined || v === "") return NaN
  var n = Number(v)
  return isFinite(n) ? n : NaN
}
function clampPercent(p) { return Math.max(0, Math.min(100, p)) }
function isoMs(s) {
  var t = Date.parse(String(s || ""))
  return isFinite(t) ? t : 0
}

// A window's name from its length: "5h", "Week", else in hours or days.
function windowLabel(secs) {
  if (secs === WINDOW_SESSION) return "5h"
  if (secs === WINDOW_WEEK) return "Week"
  if (secs > 0 && secs % 86400 === 0) return (secs / 86400) + "d"
  if (secs > 0 && secs % 3600 === 0) return (secs / 3600) + "h"
  return "Limit"
}

// Claude's answer (api/oauth/usage): its `limits` list, the session, the
// whole week and per-model weeks ("Fable week"); without the list, the
// `five_hour` and `seven_day` windows (utilization in percent). null when
// it is no answer at all: none of them there.
function claudeLimits(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null
  if (!Array.isArray(data.limits) && !("five_hour" in data) && !("seven_day" in data)) return null
  var out = []
  if (Array.isArray(data.limits) && data.limits.length > 0) {
    data.limits.forEach(function(l) {
      if (!l || typeof l !== "object") return
      var p = num(l.percent)
      if (isNaN(p)) return
      var group = String(l.group || "")
      var secs = group === "session" ? WINDOW_SESSION : group === "weekly" ? WINDOW_WEEK : 0
      var model = l.scope && l.scope.model && l.scope.model.display_name ? String(l.scope.model.display_name) : ""
      var label = windowLabel(secs)
      if (secs === 0 && l.kind) label = String(l.kind)
      if (model) label = model + " " + label.toLowerCase()
      out.push({ id: "claude:" + String(l.kind || group) + (model ? ":" + model : ""), label: label,
                 percent: clampPercent(p), resetsAt: isoMs(l.resets_at), windowSecs: secs })
    })
    return out
  }
  var windows = [["five_hour", WINDOW_SESSION], ["seven_day", WINDOW_WEEK]]
  windows.forEach(function(w) {
    var b = data[w[0]]
    if (!b || typeof b !== "object") return
    var p = num(b.utilization)
    if (isNaN(p)) return
    out.push({ id: "claude:" + w[0], label: windowLabel(w[1]), percent: clampPercent(p),
               resetsAt: isoMs(b.resets_at), windowSecs: w[1] })
  })
  return out
}

// Codex's answer (backend-api/wham/usage): `rate_limit`'s windows, told
// apart by their length, not their place (OpenAI has sent the week alone
// as the primary window). `now` (ms) for a reset given as seconds from
// now. null when it is no answer at all.
function codexLimits(data, now) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null
  var rl = data.rate_limit
  if (!rl || typeof rl !== "object") return null
  var out = []
  var seen = {}
  ;[rl.primary_window, rl.secondary_window].forEach(function(w) {
    if (!w || typeof w !== "object") return
    var p = num(w.used_percent)
    var secs = num(w.limit_window_seconds)
    if (isNaN(p) || isNaN(secs) || seen[secs]) return
    seen[secs] = true
    var reset = num(w.reset_at)
    var after = num(w.reset_after_seconds)
    var resetsAt = !isNaN(reset) ? reset * 1000 : !isNaN(after) ? Number(now || 0) + after * 1000 : 0
    out.push({ id: "codex:" + secs, label: windowLabel(secs), percent: clampPercent(p),
               resetsAt: resetsAt, windowSecs: secs })
  })
  out.sort(function(a, b) { return a.windowSecs - b.windowSecs })
  return out
}

function limitsOf(provider, data, now) {
  if (provider === "claude") return claudeLimits(data)
  if (provider === "codex") return codexLimits(data, now)
  return null
}

// The request for `provider`'s usage, from the text of its credentials
// file: { url, headers } to send, or { error } to show. The token goes in
// a header only, and nothing of it is kept. `now` (ms): an expired Claude
// login isn't sent; the agent renews it the next time it runs.
function request(provider, credentialsText, now) {
  var src = SOURCES[provider]
  if (!src) return { error: "no usage for " + provider }
  var data
  try { data = JSON.parse(String(credentialsText || "")) } catch (e) { return { error: "not signed in" } }
  if (!data || typeof data !== "object") return { error: "not signed in" }
  if (provider === "claude") {
    var o = data.claudeAiOauth
    if (!o || !o.accessToken) return { error: "not signed in" }
    var exp = num(o.expiresAt)
    if (!isNaN(exp) && exp <= Number(now || 0)) return { error: "login expired", expired: true }
    return { url: src.url, headers: { "Authorization": "Bearer " + o.accessToken,
                                      "anthropic-beta": "oauth-2025-04-20" } }
  }
  var t = data.tokens
  if (!t || !t.access_token) return { error: "not signed in" }
  var headers = { "Authorization": "Bearer " + t.access_token }
  if (t.account_id) headers["ChatGPT-Account-Id"] = String(t.account_id)
  return { url: src.url, headers: headers }
}

// What an HTTP status means for the next try: { problem, stale, retryMs }.
// 200: nothing wrong, again in `interval`. 401/403: the login lapsed or was
// revoked; the agent renews it when it runs. 429: left alone for
// `Retry-After` seconds (`retryAfter`), at least 5 minutes. Anything else
// (0 is no answer: offline, DNS): the last limits stay, marked stale.
function afterStatus(status, retryAfter, interval) {
  interval = Math.max(60000, Number(interval) || 300000)
  if (status === 200) return { problem: "", stale: false, retryMs: interval }
  if (status === 401 || status === 403) return { problem: "login expired", stale: true, retryMs: interval }
  if (status === 429) {
    var ra = num(retryAfter)
    return { problem: "rate limited", stale: true, retryMs: Math.max(300000, isNaN(ra) ? 0 : ra * 1000) }
  }
  if (status === 0) return { problem: "offline", stale: true, retryMs: interval }
  return { problem: "HTTP " + status, stale: true, retryMs: interval }
}

// The warning a limit is due: 100 at the limit, `threshold` past it, else 0.
function level(limit, threshold) {
  var t = Number(threshold) || 0
  if (limit.percent >= 100) return 100
  if (t > 0 && t < 100 && limit.percent >= t) return t
  return 0
}

// Which limits to warn about now. `warned` ({ "<id>@<resetsAt>": level })
// holds what was already said in each window; a new window (a new reset
// time) starts over. `warned` null is the first answer: what it already
// shows is taken as seen, so a restart doesn't warn again. Returns
// { alerts: [limit, with `level`], warned }, `warned` only the current
// windows'.
function alerts(limits, warned, threshold) {
  var seed = warned === null || warned === undefined
  var next = {}
  var out = []
  Array.prototype.forEach.call(limits || [], function(l) {
    var key = l.id + "@" + l.resetsAt
    var had = seed ? 0 : Number(warned[key]) || 0
    var lv = level(l, threshold)
    next[key] = Math.max(had, lv)
    if (!seed && lv > had) out.push(Object.assign({ level: lv }, l))
  })
  return { alerts: out, warned: next }
}

// Time until `resetsAt` (ms), short: "45m", "3h 20m", "2d 4h"; "" unknown.
function resetIn(resetsAt, now) {
  if (!resetsAt) return ""
  var mins = Math.max(0, Math.round((resetsAt - Number(now || 0)) / 60000))
  if (mins < 60) return mins + "m"
  var h = Math.floor(mins / 60)
  if (h < 24) return h + "h" + (mins % 60 ? " " + (mins % 60) + "m" : "")
  var d = Math.floor(h / 24)
  return d + "d" + (h % 24 ? " " + (h % 24) + "h" : "")
}

// The limit to show first: the most used, the shorter window on a tie.
function tightest(limits) {
  var best = null
  Array.prototype.forEach.call(limits || [], function(l) {
    if (!best || l.percent > best.percent || (l.percent === best.percent && l.windowSecs < best.windowSecs)) best = l
  })
  return best
}
