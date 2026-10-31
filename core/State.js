// The notch's state rules: which modules show, which peek wins, which mode
// the notch is in. Pure functions with no QML globals, so Node tests them too
// (tests/state.test.mjs). Modules are any objects with `active`, `priority`,
// `compact`, `barView`, `peek`, `expanded` and `urgentPeek`.

// Active modules, highest priority first.
function activeModules(modules) {
  var out = []
  for (var i = 0; i < modules.length; i++)
    if (modules[i] && modules[i].active) out.push(modules[i])
  out.sort(function(a, b) { return b.priority - a.priority })
  return out
}

// The module that owns the compact slot: the first active one with a view
// for it.
function compactModule(active) {
  for (var i = 0; i < active.length; i++)
    if (active[i].compact || active[i].barView) return active[i]
  return null
}

// Whether `module` may peek now. `current` is the module peeking, if any,
// and `currentShowing` whether its peek is still on screen. A pinned notch
// never peeks; hover only lets urgent peeks through; a peek on screen is not
// cut short by a lower-priority one (the OSD by a track change).
function canPeek(module, s) {
  if (!module || !module.peek || s.pinned) return false
  if (s.hovered && !module.urgentPeek) return false
  if (s.current && s.current !== module && s.currentShowing
      && s.current.priority > module.priority) return false
  return true
}

// "peek" | "expanded" | "compact" | "rest".
function mode(s) {
  if (s.peekModule && !s.pinned) return "peek"
  if (s.pinned || s.hovered) return "expanded"
  if (s.compactModule) return "compact"
  return "rest"
}

// How far windows are kept from the notch's edge (the layer-shell exclusive
// zone), in px; 0 reserves nothing. Only a notch that hangs there when
// closed (compactStyle "notch") needs it. It is the tallest compact view
// seen (`tallest`), never less than `baseline`, so windows move once rather
// than every time a module comes and goes.
function reservedSpace(s) {
  if (!s.enabled || s.compactStyle !== "notch") return 0
  return Math.ceil(Math.max(Number(s.baseline) || 0, Number(s.tallest) || 0))
}

// Whether the notch hangs on a workspace. `list` is the config's
// `workspaces` (null: every one); entries match a workspace's id or name.
// An unknown workspace (no compositor support) is allowed.
function workspaceAllowed(list, ws) {
  if (!list || !list.length || !ws) return true
  for (var i = 0; i < list.length; i++)
    if (String(list[i]) === String(ws.id) || String(list[i]) === String(ws.name)) return true
  return false
}

// The screen the notch goes on, by name; "" for none. `screens` are
// { name, allowed } (allowed: its workspace takes the notch), `override` the
// screen it was opened from (counts only while open), `open` whether it
// peeks or is expanded. Open,
// it shows on the focused screen whatever the workspace; closed, on the
// focused screen if allowed there, else on the first screen that is.
function notchScreen(s) {
  var screens = s.screens || []
  function find(name) {
    for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
    return null
  }
  var over = s.open && s.override ? find(s.override) : null
  if (over) return over.name
  var focused = find(s.focused) || screens[0] || null
  if (s.open || (focused && focused.allowed)) return focused ? focused.name : ""
  for (var i = 0; i < screens.length; i++) if (screens[i].allowed) return screens[i].name
  return ""
}
