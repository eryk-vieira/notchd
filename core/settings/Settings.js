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
