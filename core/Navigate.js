// Navigation mode: a shortcut (IPC `navigate`) highlights every notch,
// numbered in config order, and the keyboard picks one. The selected notch
// opens as a preview (expanded, not pinned); Tab walks its tabs, Enter
// pins it open, Escape leaves everything as it was. Keys act on the
// selected notch too: its settings, removing it (asked twice) and moving it (a mode of its own: arrows for the edge, Shift to slide
// along it, Tab for the monitor). NotchService holds the state; these are
// its rules. Pure functions, so Node tests them too (tests/navigate.test.mjs).

// Qt key codes and modifiers (Qt.Key_*, Qt.*Modifier), so the rules don't
// need the QML runtime.
var KEY = {
  escape: 0x01000000, tab: 0x01000001, backtab: 0x01000002,
  ret: 0x01000004, enter: 0x01000005,
  left: 0x01000012, up: 0x01000013, right: 0x01000014, down: 0x01000015,
  digit1: 0x31, digit9: 0x39,
  h: 0x48, j: 0x4a, k: 0x4b, l: 0x4c, m: 0x4d, s: 0x53, x: 0x58
}
var SHIFT = 0x02000000
// Ctrl, Alt, Meta: a key held with one is a shortcut, not navigation;
// only Ctrl+Escape (or any Escape) leaves, as it closes a notch.
var CHORD = 0x04000000 | 0x08000000 | 0x10000000

// What a key press means in navigation: "1".."9" (a notch by its number),
// "previous" / "next" (← → or h l), "up" / "down" (↑ ↓ or k j),
// "slideBack" / "slideOn" (Shift with an arrow: back is ← or ↑),
// "previousTab" / "nextTab", "open", "leave", "move" (m), "settings" (s),
// "remove" (x); "" for a key it doesn't use.
function keyName(key, modifiers) {
  modifiers = Number(modifiers) || 0
  if (key === KEY.escape) return "leave"
  if (modifiers & CHORD) return ""
  var shift = !!(modifiers & SHIFT)
  if (shift && (key === KEY.left || key === KEY.up)) return "slideBack"
  if (shift && (key === KEY.right || key === KEY.down)) return "slideOn"
  if (key === KEY.backtab || (key === KEY.tab && shift)) return "previousTab"
  if (key === KEY.tab) return "nextTab"
  if (shift) return ""
  if (key >= KEY.digit1 && key <= KEY.digit9) return String(key - KEY.digit1 + 1)
  if (key === KEY.left || key === KEY.h) return "previous"
  if (key === KEY.right || key === KEY.l) return "next"
  if (key === KEY.up || key === KEY.k) return "up"
  if (key === KEY.down || key === KEY.j) return "down"
  if (key === KEY.ret || key === KEY.enter) return "open"
  if (key === KEY.m) return "move"
  if (key === KEY.s) return "settings"
  if (key === KEY.x) return "remove"
  return ""
}

// The notch selected as navigation starts, by index in `notches` (config
// order), each as { open, screens }: the first open one (pinned or
// hovered), else the first on the focused screen, else the first; -1 for
// no notch.
function start(notches, focused) {
  notches = notches || []
  if (notches.length === 0) return -1
  for (var i = 0; i < notches.length; i++)
    if (notches[i] && notches[i].open) return i
  for (var j = 0; focused && j < notches.length; j++)
    if (notches[j] && (notches[j].screens || []).indexOf(focused) !== -1) return j
  return 0
}

// Wraps `i` into 0..count-1.
function wrap(i, count) {
  return ((i % count) + count) % count
}

var EDGE_KEYS = { previous: "left", next: "right", up: "top", down: "bottom" }

// One key (keyName) in navigation. `s`: { mode, selected, count, tabs, tab }:
// the mode ("select", the default; "move", moving the selected notch;
// "remove", asking before removing it), the selected notch's index, how
// many notches there are, the selected notch's tabs (module ids, [] for
// none) and the one it shows. Returns { mode, selected, tab, action, move }:
// the mode after the key; `tab` the tab to show, "" for the notch's own (a
// newly selected notch keeps the tab it had); `action`:
//   ""           keep navigating
//   "open"       pin the selected notch, end navigation
//   "leave"      end it, everything as it was
//   "settings"   end navigation, open the selected notch's settings
//   "remove"     remove the selected notch (`selected` is the one after)
//   "moveStart"  remember where the selected notch is
//   "move"       move it as `move` says (moveTarget)
//   "moveDone"   keep where it went
//   "moveCancel" put it back
// The last notch is never removed.
function step(s, key) {
  var count = Number(s.count) || 0
  var selected = Number(s.selected) || 0
  var tabs = s.tabs || []
  var tab = s.tab || ""
  var mode = s.mode || "select"
  function out(m, sel, t, action, move) {
    return { mode: m, selected: sel, tab: t, action: action || "", move: move || null }
  }
  if (count === 0) return out("select", -1, "", "leave")

  if (mode === "remove") {
    if (key === "remove") return out("select", Math.min(selected, count - 2), "", "remove")
    return out("select", selected, tab)
  }

  if (mode === "move") {
    if (EDGE_KEYS[key]) return out("move", selected, tab, "move", { edge: EDGE_KEYS[key] })
    if (key === "slideBack" || key === "slideOn") return out("move", selected, tab, "move", { slide: key === "slideOn" ? 1 : -1 })
    if (key === "previousTab" || key === "nextTab") return out("move", selected, tab, "move", { screen: key === "nextTab" ? 1 : -1 })
    if (key === "open") return out("select", selected, tab, "moveDone")
    if (key === "leave") return out("select", selected, tab, "moveCancel")
    return out("move", selected, tab)
  }

  if (key === "leave") return out("select", selected, tab, "leave")
  if (key === "open") return out("select", selected, tab, "open")
  if (key === "settings") return out("select", selected, tab, "settings")
  if (key === "move") return out("move", selected, tab, "moveStart")
  if (key === "remove") return out(count > 1 ? "remove" : "select", selected, tab)
  if (/^[1-9]$/.test(key)) {
    var n = Number(key) - 1
    if (n >= count || n === selected) return out("select", selected, tab)
    return out("select", n, "")
  }
  if (key === "previous" || key === "next") {
    if (count < 2) return out("select", selected, tab)
    return out("select", wrap(selected + (key === "next" ? 1 : -1), count), "")
  }
  if (key === "previousTab" || key === "nextTab") {
    if (tabs.length < 2) return out("select", selected, tab)
    var at = Math.max(0, tabs.indexOf(tab))
    return out("select", selected, tabs[wrap(at + (key === "nextTab" ? 1 : -1), tabs.length)])
  }
  return out("select", selected, tab)
}

// How far a slide moves a notch along its edge.
var SLIDE = 0.05

// Where a move (step's `move`) puts a notch at `position` ({ edge, offset,
// screen }, resolved): { edge } onto that edge, at the same offset;
// { slide: -1 | 1 } along it, by SLIDE, kept within 0 to 1; { screen: -1 |
// 1 } to the screen before or after in `screens` (names), counting from
// the one it names, else the one it is on (`on`). A notch on every screen
// ("all") or following focus goes to one screen of its own. With one
// screen, a screen move does nothing.
function moveTarget(position, move, screens, on) {
  var p = { edge: position.edge, offset: position.offset, screen: position.screen }
  if (!move) return p
  if (move.edge) p.edge = move.edge
  if (move.slide) p.offset = Math.max(0, Math.min(1, Math.round((p.offset + move.slide * SLIDE) * 100) / 100))
  if (move.screen) {
    screens = screens || []
    if (screens.length < 2) return p
    var at = screens.indexOf(p.screen)
    if (at === -1) at = screens.indexOf(on)
    p.screen = at === -1 ? screens[0] : screens[wrap(at + move.screen, screens.length)]
  }
  return p
}

// The keys the selected notch's label lists, one string per line: `mode`
// as step has it, `count` notches, whether it has `tabs` to walk and how
// many `screens` there are.
function hint(mode, count, tabs, screens) {
  if (mode === "remove") return ["x remove   Esc keep"]
  if (mode === "move") {
    return [["←↑↓→ edge", "⇧ slide", screens > 1 ? "Tab screen" : ""].filter(Boolean).join("   "),
            "↵ done   Esc undo"]
  }
  return [[count > 1 ? "1-" + Math.min(9, count) + " ←→" : "", tabs ? "Tab" : "", "↵ open", "Esc"].filter(Boolean).join("   "),
          ["m move", "s settings", count > 1 ? "x remove" : ""].filter(Boolean).join("   ")]
}

// The number a notch shows in navigation: its place in config order, 1 to
// 9; 0 (no number, reached with the arrows) past that or outside it.
function number(index) {
  return index >= 0 && index < 9 ? index + 1 : 0
}
