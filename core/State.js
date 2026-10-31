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
