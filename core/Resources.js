// System resources rules: reading /proc and df output, usage fractions and
// when a resource counts as under pressure. Pure functions, so Node tests
// them too (tests/resources.test.mjs). The resources module binds them.

// CPU time counters from /proc/stat's aggregate "cpu" line: `idle` (idle
// plus iowait) and `total`, in jiffies; null when the line is missing.
function cpuTimes(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts[0] !== "cpu") continue
    var n = parts.slice(1, 9).map(Number)
    if (n.length < 4 || n.some(function(x) { return !isFinite(x) })) return null
    var total = n.reduce(function(a, b) { return a + b }, 0)
    return { idle: n[3] + (n[4] || 0), total: total }
  }
  return null
}

// How many CPUs /proc/stat lists (its "cpu0", "cpu1"... lines).
function cpuCount(text) {
  return String(text || "").split("\n").filter(function(l) { return /^cpu\d+\s/.test(l) }).length
}

// The busy fraction (0 to 1) between two cpuTimes samples; null without a
// previous sample or when no time passed.
function cpuUsage(prev, next) {
  if (!prev || !next) return null
  var total = next.total - prev.total
  if (total <= 0) return null
  var busy = total - (next.idle - prev.idle)
  return Math.max(0, Math.min(1, busy / total))
}

// Memory from /proc/meminfo: used is what can't be reclaimed (MemTotal
// minus MemAvailable), in bytes. null when the keys are missing.
function memory(text) {
  var kb = {}
  String(text || "").split("\n").forEach(function(line) {
    var m = /^(\w+):\s+(\d+)/.exec(line)
    if (m) kb[m[1]] = Number(m[2])
  })
  if (!kb.MemTotal || kb.MemAvailable === undefined) return null
  var total = kb.MemTotal * 1024
  var used = (kb.MemTotal - kb.MemAvailable) * 1024
  return { used: used, total: total, fraction: Math.max(0, Math.min(1, used / total)) }
}

// A filesystem from `df -P -B1 <path>`: used and total in bytes. Its fraction
// is used over used plus available, as df's own Capacity: the space reserved
// for root doesn't count as free. null when the output has no data line.
function disk(text) {
  var lines = String(text || "").trim().split("\n")
  for (var i = lines.length - 1; i >= 1; i--) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 6) continue
    var total = Number(parts[1]), used = Number(parts[2]), avail = Number(parts[3])
    if (!isFinite(total) || !isFinite(used) || !isFinite(avail) || used + avail <= 0) continue
    return { used: used, total: total, fraction: used / (used + avail) }
  }
  return null
}

// Bytes as a short binary size: "512 MiB", "7.8 GiB", "1.2 TiB".
function formatBytes(bytes) {
  var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  var v = Math.max(0, Number(bytes) || 0)
  var u = 0
  while (v >= 1024 && u < units.length - 1) { v /= 1024; u++ }
  var digits = u >= 3 && v < 100 ? 1 : 0
  return v.toFixed(digits) + " " + units[u]
}

// "7.8 of 31.2 GiB": both in the total's unit, so they read as one.
function formatUsage(used, total) {
  var t = formatBytes(total)
  var unit = t.split(" ")[1]
  var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  var v = Math.max(0, Number(used) || 0) / Math.pow(1024, units.indexOf(unit))
  var digits = unit === "GiB" || unit === "TiB" || unit === "PiB" ? (v < 100 ? 1 : 0) : 0
  return v.toFixed(digits) + " of " + t
}

// The next pressure state of one resource, from the previous one ({ hot,
// streak }), the latest fraction and its rule ({ warn, hold, clear }): it
// turns hot after `hold` samples in a row at or above `warn`, and cools once
// below `warn - clear`, so a value hovering at the line doesn't flicker.
// A missing value keeps the state.
function nextPressure(prev, value, rule) {
  prev = prev || { hot: false, streak: 0 }
  if (value === null || value === undefined || !isFinite(value)) return prev
  var warn = rule.warn, hold = Math.max(1, rule.hold || 1), clear = rule.clear || 0
  if (prev.hot) return value < warn - clear ? { hot: false, streak: 0 } : { hot: true, streak: prev.streak }
  var streak = value >= warn ? prev.streak + 1 : 0
  return { hot: streak >= hold, streak: streak }
}
