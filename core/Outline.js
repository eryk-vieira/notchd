// The notch's outline as SVG path data, drawn for the top edge (x along the
// edge, y the depth away from it); NotchCard turns it onto its edge. Pure
// functions with no QML globals, so Node tests them too
// (tests/outline.test.mjs).
//
// Each end of the card along the edge meets something:
//   "shoulder"  nothing: a concave flare into the edge (the default)
//   "corner"    the screen's side (or the bar there): the card sits flush
//               with it, square. `depth`: how far along the far side a
//               notch on that side meets it (Position.corners), where
//               no hairline shows
//   "joined"    a neighbor notch, flush: the two read as one. Where the
//               neighbor is shallower, a concave fillet steps down to it;
//               where it is as deep or deeper, the end is square and the
//               neighbor draws the step.
// The start end is at x = 0 (left on a top or bottom edge, top on a side
// edge), the far end at x = w.

// SVG numbers: three decimals at most, no trailing zeros.
function num(v) {
  var s = (Math.round(v * 1000) / 1000).toFixed(3)
  return s.replace(/\.?0+$/, "") || "0"
}

// One end, as drawn at the start (x = 0, the card to its right), from the
// edge (y = 0) down to where the far side's straight line begins (y = h).
// Returns { start: [x, y], segs: [...], strokeFrom }: segs are
// { l: [x, y] } or { q: [cx, cy], to: [x, y] }, and strokeFrom the index of
// the first segment the hairline draws (the open sides only: never along
// the edge, the screen's side or a neighbor).
function end(side, s) {
  var h = s.h, sh = s.shoulder, r = s.radius, ov = s.overlap
  var kind = side && side.kind
  if (kind === "corner") {
    // Flush with the screen's side, square; no hairline along it, nor along
    // the far side where a notch on that side meets it (`depth`).
    var span = Math.max(0, Math.min(s.w, Number(side.depth) || 0))
    var flush = [{ l: [0, h] }]
    if (span > 0) flush.push({ l: [span, h] })
    return { start: [0, 0], strokeFrom: flush.length, segs: flush }
  }
  if (kind === "joined") {
    var nd = Math.max(0, Number(side.depth) || 0)
    if (nd >= h - 0.5)
      // As deep as the neighbor or shallower: square, reaching `overlap`
      // into it so no seam shows between the two windows.
      return { start: [-ov, 0], strokeFrom: 1, segs: [{ l: [-ov, h] }] }
    // Deeper: down the side, a fillet out to the neighbor's far side, then
    // this card's own far corner.
    var d = h - nd
    var rho = Math.min(sh, d / 2)
    var rr = Math.min(r, d / 2)
    return { start: [-ov, 0], strokeFrom: 3,
             segs: [{ l: [-ov, nd - ov] }, { l: [-rho, nd - ov] }, { l: [-rho, nd] },
                    { q: [0, nd], to: [0, nd + rho] }, { l: [0, h - rr] }, { q: [0, h], to: [rr, h] }] }
  }
  var sd = Math.min(sh, h / 2)
  return { start: [-sh, 0], strokeFrom: 0,
           segs: [{ q: [0, 0], to: [0, sd] }, { l: [0, h - r] }, { q: [0, h], to: [r, h] }] }
}

// `s`: w, h (the card along and deep), shoulder, radius (the far corners),
// start and end ({ kind, depth }), overlap (px a joined end reaches into
// its neighbor; 1 by default). Returns { fill, stroke }: the closed shape,
// and the open sides for the hairline.
function path(s) {
  var w = Math.max(0, Number(s.w) || 0)
  var h = Math.max(0, Number(s.h) || 0)
  var o = {
    w: w, h: h,
    shoulder: Math.max(0, Number(s.shoulder) || 0),
    radius: Math.max(0, Math.min(Number(s.radius) || 0, h / 2, w / 2)),
    overlap: s.overlap === undefined ? 1 : Math.max(0, Number(s.overlap) || 0)
  }
  var a = end(s.start, o)
  var b = end(s.end, o)
  function pt(p) { return num(p[0]) + " " + num(p[1]) }
  function mirror(p) { return [w - p[0], p[1]] }
  function seg(sg, map) {
    return sg.l ? "L " + pt(map(sg.l)) : "Q " + pt(map(sg.q)) + " " + pt(map(sg.to))
  }
  function same(p) { return p }
  // The far end, from its bottom back up to the edge: each segment
  // reversed, ending where the one before it started.
  function reversed(e, from) {
    var out = []
    for (var i = e.segs.length - 1; i >= from; i--) {
      var prev = i === 0 ? e.start : e.segs[i - 1].to || e.segs[i - 1].l
      var sg = e.segs[i]
      out.push(sg.l ? "L " + pt(mirror(prev)) : "Q " + pt(mirror(sg.q)) + " " + pt(mirror(prev)))
    }
    return out
  }
  function last(e) { var sg = e.segs[e.segs.length - 1]; return sg.to || sg.l }
  function at(e, i) { return i === 0 ? e.start : e.segs[i - 1].to || e.segs[i - 1].l }

  var fill = ["M " + pt(a.start)]
  a.segs.forEach(function(sg) { fill.push(seg(sg, same)) })
  fill.push("L " + pt(mirror(last(b))))
  fill = fill.concat(reversed(b, 0))
  fill.push("Z")

  var stroke = ["M " + pt(at(a, a.strokeFrom))]
  for (var i = a.strokeFrom; i < a.segs.length; i++) stroke.push(seg(a.segs[i], same))
  stroke.push("L " + pt(mirror(last(b))))
  stroke = stroke.concat(reversed(b, b.strokeFrom))

  return { fill: fill.join(" "), stroke: stroke.join(" ") }
}
