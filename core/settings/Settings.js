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

// A page whose id has a "/" is a sub-page of the part before it
// ("modules/media" of "modules"): it has no sidebar entry of its own, and
// the sidebar marks its parent while it shows.
function parentPage(id) {
  var s = String(id || "")
  var at = s.indexOf("/")
  return at === -1 ? s : s.slice(0, at)
}

function isSubPage(page) { return parentPage(page.id) !== page.id }

// Pages with at least one field, in their declared order.
function visiblePages(pages, schema) {
  return pages.filter(function(p) {
    return schema.some(function(f) { return pageOf(f) === p.id })
  })
}

// The pages the sidebar lists: the visible ones that are not sub-pages.
function navPages(pages) {
  return pages.filter(function(p) { return !isSubPage(p) })
}

function findPage(pages, id) {
  for (var i = 0; i < pages.length; i++) if (pages[i].id === id) return pages[i]
  return null
}

// The page to show: the wanted one if it is visible, else its parent (a
// module's page once the module unloads), else the first.
function resolvePage(pages, wanted) {
  if (findPage(pages, wanted)) return wanted
  var parent = parentPage(wanted)
  if (findPage(pages, parent)) return parent
  var nav = navPages(pages)
  return nav.length ? nav[0].id : (pages.length ? pages[0].id : "")
}

// The sidebar page `delta` steps from the one `current` sits under,
// wrapping around.
function cyclePage(pages, current, delta) {
  var nav = navPages(pages)
  if (!nav.length) return ""
  var here = parentPage(current)
  var at = -1
  for (var i = 0; i < nav.length; i++) if (nav[i].id === here) at = i
  var n = nav.length
  return nav[((at + delta) % n + n) % n].id
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

// A module's own page, under Modules.
function modulePageId(moduleId) { return "modules/" + moduleId }

// A module's JSON file (media.json next to media.qml): its `title`,
// `settings` fields and whether it is `standalone` (no notch shows it; it
// has a place of its own). Anything malformed is dropped, so a bad file costs
// the module its page and nothing else; `error` says why.
function parseModuleInfo(text) {
  var info = { title: "", settings: [] }
  var data
  try { data = JSON.parse(text) } catch (e) { info.error = String(e.message || e); return info }
  if (!data || typeof data !== "object" || Array.isArray(data)) { info.error = "not an object"; return info }
  if (typeof data.title === "string") info.title = data.title
  if (data.standalone === true) info.standalone = true
  if (Array.isArray(data.settings))
    info.settings = data.settings.filter(function(f) { return f && typeof f === "object" && !Array.isArray(f) && typeof f.type === "string" })
  return info
}

// The JSON file of the module at `url` (its .qml): the same path, .json.
// Quickshell names files under the shell's folder `qs:@/qs/<path>`, which
// resolve against `shellDir`, and others `qs:///<absolute path>` (the
// Omarchy shell, for a plugin's core); "" for anything else.
function moduleInfoPath(url, shellDir) {
  var s = String(url || "")
  if (!/\.qml$/.test(s)) return ""
  var path = ""
  if (s.indexOf("file://") === 0) path = s.slice(7)
  else if (s.indexOf("qs:@/qs/") === 0 && shellDir) path = String(shellDir).replace(/\/$/, "") + "/" + s.slice(8)
  else if (s.indexOf("qs:///") === 0) path = s.slice(5)
  else return ""
  return decodeURIComponent(path).replace(/\.qml$/, ".json")
}

// A module setting's default, from its fields.
function settingDefault(fields, key) {
  fields = fields || []
  for (var i = 0; i < fields.length; i++)
    if (fields[i] && fields[i].key === key) return fields[i]["default"]
  return undefined
}

// What a standalone module's page has before its own fields: a switch, and
// where it shows. Keys under its id: "<id>.enabled", "<id>.position".
// `edgePreview`: the url of the edge cards' picture.
function standaloneFields(id, edgePreview) {
  var page = modulePageId(id)
  return [
    { page: page, key: id + ".enabled", type: "boolean", label: "Enabled", "default": true,
      help: "Off, it does not load at all." },
    { page: page, section: "Position", key: id + ".position.edge", type: "choice", display: "cards",
      label: "Edge", "default": "top",
      help: "Where it shows, on the screen you work on. No notch shows it: it has a place of its own, over any notch that hangs there.",
      options: ["top", "bottom", "left", "right"].map(function(e) {
        return { value: e, label: e.charAt(0).toUpperCase() + e.slice(1), preview: edgePreview }
      }) },
    { page: page, section: "Position", key: id + ".position.offset", type: "number", display: "percent",
      label: "Along the edge", "default": 0.5, min: 0, max: 1, step: 0.01,
      help: "0 % is its left (or top) end, 50 % the middle." }
  ]
}

// The settings fields of every module (`modules`: [{ moduleId, title,
// settings, standalone }], from their JSON files), with their keys under
// the module's id, on the module's own page unless they name another (then
// under its title); a standalone module's switch and position first.
function moduleFields(modules, edgePreview) {
  var out = []
  Array.prototype.forEach.call(modules || [], function(m) {
    if (!m || !m.moduleId) return
    if (m.standalone) out = out.concat(standaloneFields(m.moduleId, edgePreview))
    Array.prototype.forEach.call(m.settings || [], function(f) {
      var field = Object.assign({}, f)
      if (f.key) field.key = m.moduleId + "." + f.key
      if (!field.page) field.page = modulePageId(m.moduleId)
      else if (!field.section) field.section = m.title || m.moduleId
      out.push(field)
    })
  })
  return out
}

// A page per module, titled after it; one without fields stays hidden,
// like any page.
function modulePages(modules) {
  var out = []
  Array.prototype.forEach.call(modules || [], function(m) {
    if (m && m.moduleId) out.push({ id: modulePageId(m.moduleId), label: m.title || m.moduleId })
  })
  return out
}

// A module's title: its own (the loaded module's, or its JSON file's),
// else its id capitalized.
function moduleTitle(id, module) {
  if (module && module.title) return module.title
  var s = String(id)
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// Where a module shows, for the Modules page: "Standalone" (or
// "Standalone · off") for a standalone one, whose `enabled` says whether it
// is on; "On" or "Off" with one notch, else the notches that list it.
function moduleStatus(id, specs, standalone, enabled) {
  if (standalone) return enabled === false ? "Standalone · off" : "Standalone"
  specs = specs || []
  var where = []
  for (var i = 0; i < specs.length; i++)
    if (indexIn(specs[i].moduleIds, id) !== -1) where.push(specs[i].id)
  if (where.length === 0) return "Off"
  return specs.length > 1 ? "In " + where.join(", ") : "On"
}

function indexIn(list, id) {
  return Array.prototype.indexOf.call(list || [], id)
}

// A notch's own page, under Notches, by its index.
function notchPageId(index) { return "notch/" + index }

// The notch index a page is for: "notch/2" is 2; -1 for any other page.
function notchIndexOfPage(id) {
  var m = /^notch\/([0-9]+)$/.exec(String(id || ""))
  return m ? Number(m[1]) : -1
}

// One line about a notch, for the Notches page: where it is and what it
// shows. `notch`: { edge, compactStyle, moduleIds }; `titles`: id -> title.
function notchSummary(notch, titles) {
  if (!notch) return ""
  titles = titles || {}
  var edge = String(notch.edge || "top")
  var where = notch.compactStyle === "bar" ? "In the bar" : edge.charAt(0).toUpperCase() + edge.slice(1) + " edge"
  var ids = toList(notch.moduleIds)
  var shows = ids.length === 0 ? "no modules" : ids.map(function(id) { return titles[id] || moduleTitle(id, null) }).join(", ")
  return where + " · " + shows
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

// A slider value: `v` snapped to `step` from `min` and kept within
// [min, max], without float noise (0.35, not 0.35000000000000003).
function snapToStep(v, min, max, step) {
  step = Number(step) > 0 ? Number(step) : 1
  var snapped = min + Math.round((v - min) / step) * step
  var decimals = (String(step).split(".")[1] || "").length
  return Math.max(min, Math.min(max, Number(snapped.toFixed(decimals))))
}

// What a control's edit writes: undefined (remove the key) when it equals
// the field's default, so the config never stores defaults.
function storedValue(field, value) {
  return field && field["default"] !== undefined && value === field["default"] ? undefined : value
}
