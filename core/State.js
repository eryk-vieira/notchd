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

// "peek" | "expanded" | "compact" | "rest". Being dragged, the notch stays
// closed: the pointer is on it, but it is moving it, not opening it. A
// `guest` (a copy of the visitor) is hidden while closed, so it rests
// instead of holding a compact view nobody sees: a live view there kept its
// window drawing frames.
function mode(s) {
  var compact = s.compactModule && !s.guest ? "compact" : "rest"
  if (s.dragging) return compact
  if (s.peekModule && !s.pinned) return "peek"
  if (s.pinned || s.hovered) return "expanded"
  return compact
}

// Whether a copy needs its window on screen. A notch of the config always
// has one. A guest (a copy of the visitor) is hidden while closed, and its
// window, which covers its screen, holds buffers (~25 MB) for nothing: it
// has one while open, and `lingering` after, so it closes with its
// animation and a peek soon after reuses it (showing the window again takes
// ~50 ms).
function needsWindow(s) {
  return !s.guest || !!s.open || !!s.lingering
}

// How far windows are kept from the notch's edge (the layer-shell exclusive
// zone), in px; 0 reserves nothing. Only a notch that hangs there when
// closed (compactStyle "notch") needs it. It follows the closed notch, not
// what is on screen: peeks and the expanded notch open over the windows.
// `compact`: a module shows a compact view; then the tallest compact view
// seen (`tallest`), never less than `baseline`, so a module whose view
// changes size doesn't move windows each time. Otherwise the rest lip
// (`rest`).
function reservedSpace(s) {
  if (!s.enabled || s.compactStyle !== "notch") return 0
  if (!s.compact) return Math.ceil(Number(s.rest) || 0)
  return Math.ceil(Math.max(Number(s.baseline) || 0, Number(s.tallest) || 0))
}

// When the reserved space moves from `held` to `target`: "now" to grow (the
// notch must not cover windows) or to drop it altogether, "later" to shrink
// (one module ending as another starts moves windows once, not twice),
// "none" when nothing changes (a pending shrink is cancelled).
function reserveStep(held, target) {
  if (target === held) return "none"
  if (target > held || target === 0) return "now"
  return "later"
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
// peeks or is expanded, `home` the screen the config's position names.
// Closed, it shows on its home screen if allowed there, else on the focused
// screen if allowed there, else on the first screen that is. Open, it shows
// where the pointer opened it; else a notch with a home screen opens where
// it hangs closed (a peek never takes it off its screen: needsVisitor shows
// it where you work), and one without on the focused screen, whatever the
// workspace.
function notchScreen(s) {
  var screens = s.screens || []
  function find(name) {
    for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
    return null
  }
  var focused = find(s.focused) || screens[0] || null
  var home = s.home ? find(s.home) : null
  function closed() {
    if (home && home.allowed) return home.name
    if (focused && focused.allowed) return focused.name
    for (var i = 0; i < screens.length; i++) if (screens[i].allowed) return screens[i].name
    return ""
  }
  if (!s.open) return closed()
  var over = s.override ? find(s.override) : null
  if (over) return over.name
  if (home) return closed() || home.name
  return focused ? focused.name : ""
}

// The screens that keep windows clear of the closed notch (reserveSpace),
// by name: just its home screen while the notch can hang there, else every
// screen it may hang on (it follows focus, and reserving only where it is
// would reflow both screens on each focus change).
function reserveScreens(screens, home) {
  var allowed = (screens || []).filter(function(s) { return s.allowed })
  for (var i = 0; i < allowed.length; i++)
    if (home && allowed[i].name === home) return [home]
  return allowed.map(function(s) { return s.name })
}

// ---------------------------------------------------------------- notches
// The compact style each notch gets, from the ones configured: the host's
// bar holds one notch's compact state, so only the first notch that asks
// for "bar" gets it, and only when the host has a bar indicator; the rest
// hang ("notch").
function compactStyles(configured, barAvailable) {
  var taken = !barAvailable
  return (configured || []).map(function(style) {
    if (style !== "bar" || taken) return "notch"
    taken = true
    return "bar"
  })
}

// The copy of a notch that shows a peek, by its screen name: the copy on
// the focused screen, else the first. A notch with one copy (it follows
// focus or stays on its screen) has `copies` [""] and that copy peeks.
function peekCopy(copies, focused) {
  if (!copies || copies.length === 0) return null
  if (copies.length === 1) return copies[0]
  return copies.indexOf(focused) !== -1 ? focused : copies[0]
}

// Whether a peek also needs the visitor: a notch of its own at the top of
// the focused screen, shown once, just for the peek. `peeks` are the notches
// that show the module, as { kind, screen }: kind "all" (a copy on every
// screen) and "follow" (it moves to the focused screen) always peek there;
// "homed" (kept on a screen) peeks on `screen`, where it hangs. With no
// notch peeking on the focused screen, the visitor does; never with the
// focused screen unknown.
function needsVisitor(peeks, focused) {
  if (!focused) return false
  for (var i = 0; i < (peeks || []).length; i++)
    if (peeks[i].kind !== "homed" || peeks[i].screen === focused) return false
  return true
}

// Where a peek that shows only on the focused screen goes (a module's
// `peekOnFocusedScreen`): the index of the first notch in `peeks` (the
// notches that show the module, in config order, as needsVisitor takes
// them) that peeks on the focused screen, or -1 for the visitor. With the
// focused screen unknown, the first notch; -1 with none.
function focusedPeek(peeks, focused) {
  peeks = peeks || []
  if (!focused) return peeks.length > 0 ? 0 : -1
  for (var i = 0; i < peeks.length; i++)
    if (peeks[i].kind !== "homed" || peeks[i].screen === focused) return i
  return -1
}

// What windows leave free per screen edge, from every notch copy's reserve
// ({ screens, edge, space }): the deepest one on each, so notches sharing
// an edge don't add up. As { "<screen>|<edge>": space }, spaces above 0.
function reserveZones(reserves) {
  var out = {}
  for (var i = 0; i < (reserves || []).length; i++) {
    var r = reserves[i]
    if (!r || !(r.space > 0)) continue
    for (var j = 0; j < (r.screens || []).length; j++) {
      var key = r.screens[j] + "|" + r.edge
      out[key] = Math.max(out[key] || 0, r.space)
    }
  }
  return out
}
