// Where the notch sits: a screen edge and how far along it. Pure functions
// with no QML globals, so Node tests them too (tests/position.test.mjs).
//
// The config's `position` is { edge, offset, screen }: edge "top" |
// "bottom" | "left" | "right", offset 0..1 along the edge (left to right,
// top to bottom), 0.5 the middle, and screen the monitor the closed notch
// stays on ("" or missing: the focused one; State.notchScreen). A missing
// key is top-center, following focus.

var EDGES = ["top", "bottom", "left", "right"]
var DEFAULT_EDGE = "top"
var DEFAULT_OFFSET = 0.5

function isEdge(edge) { return EDGES.indexOf(edge) !== -1 }

// Left and right: the notch runs down the edge instead of across it.
function isVertical(edge) { return edge === "left" || edge === "right" }

// The config value as { edge, offset, screen }; anything unknown falls back
// to top-center on the focused screen.
function resolve(value) {
  var v = value && typeof value === "object" ? value : {}
  var offset = Number(v.offset)
  return {
    edge: isEdge(v.edge) ? v.edge : DEFAULT_EDGE,
    offset: v.offset === undefined || v.offset === null || !isFinite(offset)
      ? DEFAULT_OFFSET : Math.max(0, Math.min(1, offset)),
    screen: typeof v.screen === "string" ? v.screen : ""
  }
}

// Where the notch actually goes. compactStyle "bar" locks it to the middle
// of the host's bar (its compact state lives in the bar, on every screen);
// otherwise the configured position.
function effective(position, compactStyle, barEdge) {
  if (compactStyle === "bar")
    return { edge: isEdge(barEdge) ? barEdge : DEFAULT_EDGE, offset: DEFAULT_OFFSET, screen: "" }
  return resolve(position)
}

// The card's top-left corner on screen, in px. `s`:
//   edge, offset        the position
//   width, height       the screen
//   cardWidth, cardHeight
//   insets              { top, bottom, left, right }: what the host's bar
//                       takes on each edge; the card hangs from its edge's
//                       inset and its offset runs between the other two
//   margin              kept free at both ends of the edge (the shoulders)
// The card's middle goes at `offset` along the free stretch, clamped so the
// card stays inside it; a card longer than the stretch is centered on it.
// Not rounded: the card's size animates in fractions of a pixel, and a
// rounded corner would step a pixel at a time while the opposite one glides
// (NotchCard snaps its content to whole pixels instead).
function place(s) {
  var edge = isEdge(s.edge) ? s.edge : DEFAULT_EDGE
  var offset = resolve({ offset: s.offset }).offset
  var insets = s.insets || {}
  function inset(e) { return Math.max(0, Number(insets[e]) || 0) }
  var margin = Math.max(0, Number(s.margin) || 0)
  var vertical = isVertical(edge)
  var length = vertical ? s.height : s.width
  var along = vertical ? s.cardHeight : s.cardWidth
  var start = (vertical ? inset("top") : inset("left")) + margin
  var end = length - (vertical ? inset("bottom") : inset("right")) - margin
  var lo = start
  var hi = end - along
  var pos = hi < lo ? (lo + hi) / 2
    : Math.max(lo, Math.min(hi, start + offset * (end - start) - along / 2))
  var depth
  if (edge === "top") depth = inset("top")
  else if (edge === "bottom") depth = s.height - inset("bottom") - s.cardHeight
  else if (edge === "left") depth = inset("left")
  else depth = s.width - inset("right") - s.cardWidth
  return vertical ? { x: depth, y: pos } : { x: pos, y: depth }
}

// What the host's bar takes on each edge: `size` on `barEdge` while it is
// shown, nothing elsewhere.
function insets(barEdge, size, shown) {
  var out = { top: 0, bottom: 0, left: 0, right: 0 }
  if (shown && isEdge(barEdge)) out[barEdge] = Math.max(0, Number(size) || 0)
  return out
}

// The screen edge nearest to a point.
function nearestEdge(x, y, width, height) {
  var d = { top: y, bottom: height - y, left: x, right: width - x }
  var best = "top"
  for (var i = 1; i < EDGES.length; i++)
    if (d[EDGES[i]] < d[best]) best = EDGES[i]
  return best
}

// Where a notch dragged to the pointer goes: the nearest edge, its middle
// under the pointer along that edge (the inverse of place). Within
// `magnet` px of the middle of the free stretch it snaps to 0.5. `s`:
// x, y (the pointer), width, height, insets, margin and magnet, as place.
function dragTarget(s) {
  var edge = nearestEdge(s.x, s.y, s.width, s.height)
  var insets = s.insets || {}
  function inset(e) { return Math.max(0, Number(insets[e]) || 0) }
  var margin = Math.max(0, Number(s.margin) || 0)
  var vertical = isVertical(edge)
  var p = vertical ? s.y : s.x
  var start = (vertical ? inset("top") : inset("left")) + margin
  var end = (vertical ? s.height - inset("bottom") : s.width - inset("right")) - margin
  if (end <= start) return { edge: edge, offset: DEFAULT_OFFSET }
  if (Math.abs(p - (start + end) / 2) <= Math.max(0, Number(s.magnet) || 0))
    return { edge: edge, offset: DEFAULT_OFFSET }
  var offset = Math.max(0, Math.min(1, (p - start) / (end - start)))
  return { edge: edge, offset: Math.round(offset * 1000) / 1000 }
}

// A position as the config stores it: defaults left out, and undefined
// (no key) for top-center on the focused screen.
function configValue(position) {
  var p = resolve(position)
  var out = {}
  if (p.edge !== DEFAULT_EDGE) out.edge = p.edge
  if (p.offset !== DEFAULT_OFFSET) out.offset = p.offset
  if (p.screen !== "") out.screen = p.screen
  return Object.keys(out).length > 0 ? out : undefined
}

// The screen a point of the desktop (global layout coordinates) is on, by
// name: the one containing it, else the nearest (a point in a gap between
// screens). `screens` are { name, x, y, width, height }; "" for none.
function screenAt(screens, x, y) {
  var best = ""
  var bestDistance = Infinity
  for (var i = 0; i < (screens || []).length; i++) {
    var s = screens[i]
    var dx = Math.max(s.x - x, 0, x - (s.x + s.width))
    var dy = Math.max(s.y - y, 0, y - (s.y + s.height))
    var d = dx * dx + dy * dy
    if (d < bestDistance) { best = s.name; bestDistance = d }
  }
  return best
}
