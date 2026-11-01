// Navigation mode: a shortcut (IPC `navigate`) highlights every notch,
// numbered in config order, and the keyboard picks one. The selected notch
// opens as a preview (expanded, not pinned); Tab walks its tabs, Enter
// pins it open, Escape leaves everything as it was. NotchService holds the
// state; these are its rules. Pure functions, so Node tests them too
// (tests/navigate.test.mjs).

// Qt key codes and modifiers (Qt.Key_*, Qt.*Modifier), so the rules don't
// need the QML runtime.
var KEY = {
  escape: 0x01000000, tab: 0x01000001, backtab: 0x01000002,
  ret: 0x01000004, enter: 0x01000005,
  left: 0x01000012, right: 0x01000014,
  digit1: 0x31, digit9: 0x39, h: 0x48, l: 0x4c
}
var SHIFT = 0x02000000
// Ctrl, Alt, Meta: a key held with one is a shortcut, not navigation;
// only Ctrl+Escape (or any Escape) leaves, as it closes a notch.
var CHORD = 0x04000000 | 0x08000000 | 0x10000000

// What a key press means in navigation: "1".."9" (a notch by its number),
// "previous" / "next" (the notch before or after), "previousTab" /
// "nextTab", "open", "leave"; "" for a key it doesn't use.
function keyName(key, modifiers) {
  modifiers = Number(modifiers) || 0
  if (key === KEY.escape) return "leave"
  if (modifiers & CHORD) return ""
  if (key >= KEY.digit1 && key <= KEY.digit9) return String(key - KEY.digit1 + 1)
  if (key === KEY.left || key === KEY.h) return "previous"
  if (key === KEY.right || key === KEY.l) return "next"
  if (key === KEY.backtab || (key === KEY.tab && (modifiers & SHIFT))) return "previousTab"
  if (key === KEY.tab) return "nextTab"
  if (key === KEY.ret || key === KEY.enter) return "open"
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

// One key (keyName) in navigation. `s`: { selected, count, tabs, tab }, the
// selected notch's index, how many notches there are, the selected notch's
// tabs (module ids, [] for none) and the one it shows. Returns
// { selected, tab, action }: `tab` is the tab to show, "" for the notch's
// own (a newly selected notch keeps the tab it had); `action` is "open"
// (pin the selected notch, end navigation), "leave" (end it, as it was) or
// "" (keep navigating).
function step(s, key) {
  var count = Number(s.count) || 0
  var selected = Number(s.selected) || 0
  var tabs = s.tabs || []
  var tab = s.tab || ""
  if (count === 0) return { selected: -1, tab: "", action: "leave" }
  if (key === "leave") return { selected: selected, tab: tab, action: "leave" }
  if (key === "open") return { selected: selected, tab: tab, action: "open" }
  if (/^[1-9]$/.test(key)) {
    var n = Number(key) - 1
    if (n >= count || n === selected) return { selected: selected, tab: tab, action: "" }
    return { selected: n, tab: "", action: "" }
  }
  if (key === "previous" || key === "next") {
    if (count < 2) return { selected: selected, tab: tab, action: "" }
    return { selected: wrap(selected + (key === "next" ? 1 : -1), count), tab: "", action: "" }
  }
  if (key === "previousTab" || key === "nextTab") {
    if (tabs.length < 2) return { selected: selected, tab: tab, action: "" }
    var at = Math.max(0, tabs.indexOf(tab))
    return { selected: selected, tab: tabs[wrap(at + (key === "nextTab" ? 1 : -1), tabs.length)], action: "" }
  }
  return { selected: selected, tab: tab, action: "" }
}

// The number a notch shows in navigation: its place in config order, 1 to
// 9; 0 (no number, reached with the arrows) past that or outside it.
function number(index) {
  return index >= 0 && index < 9 ? index + 1 : 0
}
