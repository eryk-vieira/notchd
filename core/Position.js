// Where the notch sits: a screen edge and how far along it. Pure functions
// with no QML globals, so Node tests them too (tests/position.test.mjs).
//
// The config's `position` is { edge, offset, screen }: edge "top" |
// "bottom" | "left" | "right", offset 0..1 along the edge (left to right,
// top to bottom), 0.5 the middle, and screen the monitor the closed notch
// stays on ("" or missing: the focused one, State.notchScreen; ALL_SCREENS:
// a copy of the notch on every monitor). A missing key is top-center,
// following focus.

var EDGES = ["top", "bottom", "left", "right"]
var DEFAULT_EDGE = "top"
var DEFAULT_OFFSET = 0.5
var ALL_SCREENS = "all"

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
// of the host's bar, with a copy on every screen (its compact state lives in
// the bar, and there is a bar on each); otherwise the configured position.
function effective(position, compactStyle, barEdge) {
  if (compactStyle === "bar")
    return { edge: isEdge(barEdge) ? barEdge : DEFAULT_EDGE, offset: DEFAULT_OFFSET, screen: ALL_SCREENS }
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

// The stretch of an edge the notch's middle may take (place's rules): its
// two ends, { start, end }, in px along the edge. `s` as place.
function stretch(s) {
  var edge = isEdge(s.edge) ? s.edge : DEFAULT_EDGE
  var insets = s.insets || {}
  function inset(e) { return Math.max(0, Number(insets[e]) || 0) }
  var margin = Math.max(0, Number(s.margin) || 0)
  var vertical = isVertical(edge)
  var length = vertical ? s.height : s.width
  return {
    start: (vertical ? inset("top") : inset("left")) + margin,
    end: length - (vertical ? inset("bottom") : inset("right")) - margin
  }
}

// Notches sharing an edge of a screen, side by side: none sits on another.
// `items`, each { group, center, size, start, end, open, skip }: the group
// ("<screen>|<edge>"), where its middle wants to be and its length along
// the edge (closed: open ones give the size they had closed, so they open
// from where they were), the stretch it must stay in (stretch), whether it
// is open, and whether it takes no part (hidden, being dragged). In each
// group, in order of `center` (ties: list order), notches at least `gap`
// apart, each moved as little as it takes. Returns, per item, { shift } to
// add to its place along the edge and { covered }: a closed notch an open
// one (`openSize`) grows over, which should hide while it is open.
function pack(items, gap) {
  items = items || []
  gap = Math.max(0, Number(gap) || 0)
  var out = items.map(function() { return { shift: 0, covered: false } })
  var groups = {}
  for (var i = 0; i < items.length; i++) {
    if (!items[i] || items[i].skip) continue
    var g = String(items[i].group)
    if (!groups[g]) groups[g] = []
    groups[g].push(i)
  }
  Object.keys(groups).forEach(function(g) {
    var order = groups[g].slice().sort(function(a, b) {
      return items[a].center - items[b].center || a - b
    })
    // Blocks of notches touching each other: `rel` is each one's middle
    // from the block's first, `pos` the first's middle.
    var blocks = []
    function want(block) {
      var sum = 0
      for (var k = 0; k < block.idx.length; k++) sum += items[block.idx[k]].center - block.rel[k]
      var pos = sum / block.idx.length
      var lo = -Infinity, hi = Infinity
      for (var m = 0; m < block.idx.length; m++) {
        var it = items[block.idx[m]]
        lo = Math.max(lo, it.start + it.size / 2 - block.rel[m])
        hi = Math.min(hi, it.end - it.size / 2 - block.rel[m])
      }
      block.pos = lo > hi ? (lo + hi) / 2 : Math.max(lo, Math.min(hi, pos))
    }
    function lastEnd(block) {
      var k = block.idx.length - 1
      return block.pos + block.rel[k] + items[block.idx[k]].size / 2
    }
    for (var n = 0; n < order.length; n++) {
      var block = { idx: [order[n]], rel: [0], pos: 0 }
      want(block)
      blocks.push(block)
      while (blocks.length > 1) {
        var prev = blocks[blocks.length - 2]
        var last = blocks[blocks.length - 1]
        if (lastEnd(prev) + gap + items[last.idx[0]].size / 2 <= last.pos + 1e-9) break
        var base = prev.rel[prev.rel.length - 1] + items[prev.idx[prev.idx.length - 1]].size / 2
          + gap + items[last.idx[0]].size / 2
        for (var q = 0; q < last.idx.length; q++) {
          prev.idx.push(last.idx[q])
          prev.rel.push(base + last.rel[q])
        }
        blocks.pop()
        want(prev)
      }
    }
    blocks.forEach(function(b) {
      for (var k = 0; k < b.idx.length; k++)
        out[b.idx[k]].shift = b.pos + b.rel[k] - items[b.idx[k]].center
    })
    // An open notch grows from where it was; the closed ones it reaches hide.
    order.forEach(function(o) {
      if (!items[o].open) return
      var mid = items[o].center + out[o].shift
      var half = Math.max(items[o].size, Number(items[o].openSize) || 0) / 2
      order.forEach(function(c) {
        if (c === o || items[c].open) return
        var cm = items[c].center + out[c].shift
        if (Math.abs(cm - mid) < half + items[c].size / 2 + gap) out[c].covered = true
      })
    })
  })
  return out
}
