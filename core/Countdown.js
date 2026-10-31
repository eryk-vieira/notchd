// Timer and pomodoro rules: durations, commands and the countdown state.
// Pure functions over plain state objects, with the time passed in, so Node
// tests them too (tests/countdown.test.mjs). The timer module binds them.
//
// A state is { status } plus, past "idle":
//   status    "idle" | "running" | "paused" | "done"
//   kind      "timer" | "pomodoro"
//   label     what it is for ("Tea", "Focus")
//   duration  its full length, ms
//   endsAt    when it ends (running), epoch ms
//   left      what was left when paused, ms
//   phase     pomodoro: "focus" | "short" | "long"
//   round     pomodoro: the focus round, from 1
//   next      done pomodoro: the phase to start next ({ phase, round }), if any

var IDLE = { status: "idle" }

var PHASE_LABELS = { focus: "Focus", short: "Short break", long: "Long break" }

// The pomodoro settings with their defaults filled in, minutes as ms.
function pomodoroConfig(cfg) {
  cfg = cfg || {}
  function minutes(v, d) { var n = Number(v); return (isFinite(n) && n > 0 ? n : d) * 60000 }
  return {
    focus: minutes(cfg.focus, 25),
    short: minutes(cfg.shortBreak, 5),
    long: minutes(cfg.longBreak, 15),
    rounds: Math.max(1, Math.round(Number(cfg.rounds) || 4)),
    autoAdvance: cfg.autoAdvance !== false
  }
}

// A duration as ms, or null: "25" (minutes), "90s", "25m", "1h", "1h30m",
// "1h 30m", "1:30" (m:ss), "1:00:00" (h:mm:ss).
function parseDuration(text) {
  var s = String(text === undefined || text === null ? "" : text).trim().toLowerCase()
  if (s === "") return null
  if (/^\d+(\.\d+)?$/.test(s)) return positive(Number(s) * 60000)
  if (/^\d+(:\d{1,2}){1,2}$/.test(s)) {
    var parts = s.split(":").map(Number)
    if (parts.slice(1).some(function(p) { return p >= 60 })) return null
    var secs = parts.reduce(function(acc, p) { return acc * 60 + p }, 0)
    return positive(secs * 1000)
  }
  var re = /(\d+(?:\.\d+)?)\s*(h|m|s)/g
  var rest = s.replace(re, "").trim()
  if (rest !== "") return null
  var total = 0, m
  while ((m = re.exec(s)) !== null)
    total += Number(m[1]) * (m[2] === "h" ? 3600000 : m[2] === "m" ? 60000 : 1000)
  return positive(total)
}
function positive(ms) { return isFinite(ms) && ms >= 1000 ? Math.round(ms) : null }

// What a `timer` IPC argument asks for: { action, ms?, label? } or { error }.
//   "" | "toggle"          toggle (pause, resume or start what's next)
//   "pause" | "resume" | "stop" | "skip" | "pomodoro"
//   "+5m"                  add time
//   "25m" | "25m Tea"      start a timer, with a label
function parseCommand(text) {
  var s = String(text === undefined || text === null ? "" : text).trim()
  var word = s.split(/\s+/)[0].toLowerCase()
  if (s === "" || word === "toggle") return { action: "toggle" }
  if (["pause", "resume", "stop", "skip", "pomodoro"].indexOf(word) !== -1 && s.split(/\s+/).length === 1)
    return { action: word }
  if (s.charAt(0) === "+") {
    var add = parseDuration(s.slice(1))
    return add ? { action: "add", ms: add } : { error: "not a duration: " + s.slice(1) }
  }
  // The duration may have spaces ("1h 30m"): the longest leading run of
  // words that parses is the duration, the rest the label.
  var words = s.split(/\s+/)
  for (var n = words.length; n >= 1; n--) {
    var ms = parseDuration(words.slice(0, n).join(" "))
    if (ms) return { action: "start", ms: ms, label: words.slice(n).join(" ") }
  }
  return { error: "usage: timer <duration> [label] | pomodoro | pause | resume | toggle | +<duration> | skip | stop" }
}

// Remaining time as "25:00", "0:05" or "1:02:03", seconds rounded up so it
// reads 0:00 only at the end.
function format(ms) {
  var total = Math.max(0, Math.ceil((Number(ms) || 0) / 1000))
  var h = Math.floor(total / 3600), m = Math.floor(total / 60) % 60, sec = total % 60
  function two(n) { return (n < 10 ? "0" : "") + n }
  return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec)
}

function start(now, ms, label) {
  return { status: "running", kind: "timer", label: String(label || ""), duration: ms, endsAt: now + ms }
}

function startPhase(now, cfg, phase, round) {
  cfg = pomodoroConfig(cfg)
  var ms = cfg[phase]
  return { status: "running", kind: "pomodoro", label: PHASE_LABELS[phase], phase: phase, round: round,
           rounds: cfg.rounds, duration: ms, endsAt: now + ms }
}

// The pomodoro phase after `phase`: focus rounds with a short break between
// them, a long break after the last; null after the long break (the cycle
// is over).
function nextPhase(phase, round, rounds) {
  if (phase === "focus") return round >= rounds ? { phase: "long", round: round } : { phase: "short", round: round }
  if (phase === "short") return { phase: "focus", round: round + 1 }
  return null
}

function remaining(s, now) {
  if (!s) return 0
  if (s.status === "running") return Math.max(0, s.endsAt - now)
  if (s.status === "paused") return s.left
  return 0
}

// Milliseconds until the clock `format` shows changes (5 ms past it, so the
// rounded-up second has turned), which also lands on the end; 1 once the
// time is up. Not running, nothing changes: 1000. The module wakes only
// then: every wake-up redraws the notch.
function untilChange(s, now) {
  if (!s || s.status !== "running") return 1000
  var left = s.endsAt - now
  if (left <= 0) return 1
  return (left % 1000 || 1000) + 5
}

// How far along, 0 to 1.
function progress(s, now) {
  if (!s || !s.duration) return 0
  if (s.status === "done") return 1
  return Math.max(0, Math.min(1, 1 - remaining(s, now) / s.duration))
}

function with_(s, changes) {
  var out = {}
  for (var k in s) out[k] = s[k]
  for (var c in changes) out[c] = changes[c]
  return out
}

function pause(s, now) {
  if (!s || s.status !== "running") return s
  return with_(s, { status: "paused", left: remaining(s, now), endsAt: undefined })
}

function resume(s, now) {
  if (!s || s.status !== "paused") return s
  return with_(s, { status: "running", endsAt: now + s.left, left: undefined })
}

// Pause or resume; a done pomodoro starts its next phase; idle or a done
// timer stays as it is.
function toggle(s, now, cfg) {
  if (!s) return IDLE
  if (s.status === "running") return pause(s, now)
  if (s.status === "paused") return resume(s, now)
  if (s.status === "done" && s.next) return startPhase(now, cfg, s.next.phase, s.next.round)
  return s
}

function add(s, now, ms) {
  if (!s) return s
  if (s.status === "running") return with_(s, { endsAt: s.endsAt + ms, duration: s.duration + ms })
  if (s.status === "paused") return with_(s, { left: s.left + ms, duration: s.duration + ms })
  return s
}

// The state once its time is up: a timer is done; a pomodoro moves on to
// its next phase (running with `autoAdvance`, else done and waiting for it),
// or is done after the long break.
function finish(s, now, cfg) {
  if (s.kind !== "pomodoro") return with_(s, { status: "done", endsAt: undefined, left: undefined })
  var c = pomodoroConfig(cfg)
  var next = nextPhase(s.phase, s.round, c.rounds)
  if (next && c.autoAdvance) return startPhase(now, cfg, next.phase, next.round)
  return with_(s, { status: "done", endsAt: undefined, left: undefined, next: next })
}

// Skip to what comes after: a pomodoro's next phase, running; anything else
// stops.
function skip(s, now, cfg) {
  if (!s || s.kind !== "pomodoro" || s.status === "idle") return IDLE
  var next = s.status === "done" ? s.next : nextPhase(s.phase, s.round, pomodoroConfig(cfg).rounds)
  return next ? startPhase(now, cfg, next.phase, next.round) : IDLE
}

// The state at `now`: { state, finished } where `finished` says its time
// just ran out (the module peeks and notifies then).
function tick(s, now, cfg) {
  if (s && s.status === "running" && now >= s.endsAt) return { state: finish(s, now, cfg), finished: true }
  return { state: s || IDLE, finished: false }
}

// Applies a parsed command. `cfg` holds the pomodoro settings.
function apply(s, cmd, now, cfg) {
  switch (cmd.action) {
  case "start": return start(now, cmd.ms, cmd.label)
  case "pomodoro": return startPhase(now, cfg, "focus", 1)
  case "pause": return pause(s, now)
  case "resume": return resume(s, now)
  case "toggle": return toggle(s, now, cfg)
  case "add": return add(s, now, cmd.ms)
  case "skip": return skip(s, now, cfg)
  case "stop": return IDLE
  }
  return s
}

// The title for a state: its label, a pomodoro's round, or "Timer".
function title(s) {
  if (!s || s.status === "idle") return "Timer"
  if (s.kind === "pomodoro") return s.label + (s.phase === "focus" ? " · " + s.round + " of " + s.rounds : "")
  return s.label || "Timer"
}
