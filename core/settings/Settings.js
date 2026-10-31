// Settings-window rules: pages, sections and list edits. Pure functions with
// no QML globals, so Node tests them too (tests/settings.test.mjs).

// The core pages with the host's applied: a host page with a core id
// replaces its label or icon, any other is appended.
function mergePages(core, host) {
  var out = core.map(function(p) { return Object.assign({}, p) })
  host = host || []
  for (var i = 0; i < host.length; i++) {
    var at = -1
    for (var j = 0; j < out.length; j++) if (out[j].id === host[i].id) at = j
    if (at === -1) out.push(Object.assign({}, host[i]))
    else out[at] = Object.assign(out[at], host[i])
  }
  return out
}

function pageOf(field) { return field.page || "general" }

// Pages with at least one field, in their declared order.
function visiblePages(pages, schema) {
  return pages.filter(function(p) {
    return schema.some(function(f) { return pageOf(f) === p.id })
  })
}

// The page to show: the wanted one if it is visible, else the first.
function resolvePage(pages, wanted) {
  for (var i = 0; i < pages.length; i++)
    if (pages[i].id === wanted) return wanted
  return pages.length ? pages[0].id : ""
}

// The page `delta` steps from `current`, wrapping around.
function cyclePage(pages, current, delta) {
  if (!pages.length) return ""
  var at = -1
  for (var i = 0; i < pages.length; i++) if (pages[i].id === current) at = i
  var n = pages.length
  return pages[((at + delta) % n + n) % n].id
}

// A page's fields grouped by section, sections in first-seen order.
function sections(schema, page) {
  var out = []
  var byName = {}
  for (var i = 0; i < schema.length; i++) {
    var f = schema[i]
    if (pageOf(f) !== page) continue
    var name = f.section || ""
    if (!Object.prototype.hasOwnProperty.call(byName, name)) {
      byName[name] = { name: name, fields: [] }
      out.push(byName[name])
    }
    byName[name].fields.push(f)
  }
  return out
}

// A list value as a plain array of strings. Values that went through a
// Repeater model arrive as sequences, which Array.isArray rejects.
function toList(value) {
  if (!value || typeof value === "string" || typeof value.length !== "number") return []
  return Array.prototype.map.call(value, String)
}

// `ids` with `id` added at the end, or removed if present.
function toggleId(ids, id) {
  var next = ids.slice()
  var at = next.indexOf(id)
  if (at === -1) next.push(id)
  else next.splice(at, 1)
  return next
}

// `ids` with `id` moved `delta` places; unchanged if it would leave the list.
function moveId(ids, id, delta) {
  var next = ids.slice()
  var at = next.indexOf(id)
  var to = at + delta
  if (at === -1 || to < 0 || to >= next.length) return next
  next.splice(at, 1)
  next.splice(to, 0, id)
  return next
}

// Every id to list: enabled ones in their order, then the rest available.
function allIds(enabled, available) {
  var out = enabled.slice()
  for (var i = 0; i < available.length; i++)
    if (out.indexOf(available[i]) === -1) out.push(available[i])
  return out
}

// A workspace as the config stores it: a number for a numbered one, else
// its name.
function workspaceValue(w) {
  var s = String(w)
  return /^[0-9]+$/.test(s) ? Number(s) : s
}

function sortWorkspaces(list) {
  return list.sort(function(a, b) {
    var an = typeof a === "number", bn = typeof b === "number"
    if (an && bn) return a - b
    if (an !== bn) return an ? -1 : 1
    return a < b ? -1 : a > b ? 1 : 0
  })
}

// The workspaces to offer: 1 to 10, the ones the compositor knows and the
// ones already picked; numbers in order, then names.
function workspaceChoices(known, picked) {
  var out = []
  function add(w) {
    if (String(w) === "") return
    var v = workspaceValue(w)
    if (out.indexOf(v) === -1) out.push(v)
  }
  for (var i = 1; i <= 10; i++) add(i)
  toList(known).forEach(add)
  toList(picked).forEach(add)
  return sortWorkspaces(out)
}

// `picked` with `w` added or removed, in order; undefined once empty, which
// removes the key (every workspace).
function toggleWorkspace(picked, w) {
  var list = toList(picked).map(workspaceValue)
  var v = workspaceValue(w)
  var at = list.indexOf(v)
  if (at === -1) list.push(v)
  else list.splice(at, 1)
  return list.length > 0 ? sortWorkspaces(list) : undefined
}
