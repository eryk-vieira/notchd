// Markdown to the rich text a TextEdit shows, styled from the theme. Qt's
// own Markdown import paints links its fixed blue, sets blocks flush and
// makes headings huge, and none of it can be restyled afterwards; this
// writes the HTML with the spacing, sizes and colors set inline. Pure
// functions, so Node tests them too (tests/markdown.test.mjs).
//
// What it reads: paragraphs, # headings, - * + and 1. lists (nested by
// indent), > quotes, ``` code blocks, --- rules, | tables |, and inline
// `code`, **bold**, *italic*, ~~struck~~, [links](url), <url> and bare
// URLs. An unclosed ``` (an answer still streaming) runs to the end.
//
// `s` styles it:
//   accent      link color
//   muted       quotes, rules
//   line        table borders
//   code        background of code
//   quote       background of a quote
//   body        text size, px
//   heading     largest heading size, px
//   gap         space between blocks, px
//   lineHeight  line height, % (default 135)

function escapeHtml(t) {
  return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Inline Markdown in one block's text, as HTML.
function inline(text, s) {
  var held = []
  function hold(html) { held.push(html); return "\u0000" + (held.length - 1) + "\u0000" }
  function link(label, url) {
    return hold("<a href=\"" + escapeHtml(url) + "\" style=\"color:" + s.accent + "; text-decoration:underline\">"
      + emphasis(escapeHtml(label)) + "</a>")
  }
  var t = String(text)
  // Code spans first: nothing inside them is Markdown.
  t = t.replace(/`([^`]+)`/g, function(all, code) {
    return hold("<span style=\"font-family:monospace; background-color:" + s.code + "\">&nbsp;"
      + escapeHtml(code) + "&nbsp;</span>")
  })
  t = t.replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, function(all, label, url) { return link(label, url) })
  t = t.replace(/<(https?:\/\/[^>\s]+)>/g, function(all, url) { return link(url, url) })
  t = t.replace(/https?:\/\/[^\s<>"\u0000]+[^\s<>"\u0000.,;:!?)\]]/g, function(url) { return link(url, url) })
  t = emphasis(escapeHtml(t))
  return t.replace(/\u0000(\d+)\u0000/g, function(all, i) { return held[Number(i)] })
}

function emphasis(t) {
  return t.replace(/\*\*([^*]+?)\*\*/g, "<b>$1</b>")
    .replace(/__([^_]+?)__/g, "<b>$1</b>")
    .replace(/~~([^~]+?)~~/g, "<s>$1</s>")
    .replace(/(^|[^*\w])\*(?!\s)([^*]+?)\*(?!\w)/g, "$1<i>$2</i>")
    .replace(/(^|[^_\w])_(?!\s)([^_]+?)_(?!\w)/g, "$1<i>$2</i>")
}

var LIST_ITEM = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/
var FENCE = /^\s*(```|~~~)/
var HEADING = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/
var RULE = /^\s{0,3}([-*_])(\s*\1){2,}\s*$/
var TABLE_SEPARATOR = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/

function cells(line) {
  var t = line.trim().replace(/^\|/, "").replace(/\|$/, "")
  return t.split("|").map(function(c) { return c.trim() })
}

// The blocks of a Markdown text: [{ kind, ... }].
function blocks(md) {
  var lines = String(md || "").replace(/\r\n?/g, "\n").split("\n")
  var out = []
  var i = 0
  while (i < lines.length) {
    var line = lines[i]
    if (line.trim() === "") { i++; continue }
    var m
    if (FENCE.test(line)) {
      var fence = line.trim().slice(0, 3)
      var code = []
      i++
      while (i < lines.length && lines[i].trim().indexOf(fence) !== 0) code.push(lines[i++])
      i++
      out.push({ kind: "code", text: code.join("\n") })
      continue
    }
    if ((m = HEADING.exec(line))) { out.push({ kind: "heading", level: m[1].length, text: m[2] }); i++; continue }
    if (RULE.test(line)) { out.push({ kind: "rule" }); i++; continue }
    if (line.indexOf("|") !== -1 && i + 1 < lines.length && TABLE_SEPARATOR.test(lines[i + 1])) {
      var rows = [cells(line)]
      i += 2
      while (i < lines.length && lines[i].indexOf("|") !== -1 && lines[i].trim() !== "") rows.push(cells(lines[i++]))
      out.push({ kind: "table", rows: rows })
      continue
    }
    if (/^\s{0,3}>/.test(line)) {
      var quote = []
      while (i < lines.length && /^\s{0,3}>/.test(lines[i])) quote.push(lines[i++].replace(/^\s{0,3}>\s?/, ""))
      out.push({ kind: "quote", blocks: blocks(quote.join("\n")) })
      continue
    }
    if (LIST_ITEM.test(line)) {
      var items = []
      while (i < lines.length) {
        var l = lines[i]
        if ((m = LIST_ITEM.exec(l))) {
          items.push({ indent: m[1].replace(/\t/g, "    ").length, ordered: /\d/.test(m[2]), text: m[3] })
          i++
        } else if (l.trim() !== "" && /^\s+/.test(l) && items.length > 0) {
          items[items.length - 1].text += " " + l.trim()
          i++
        } else if (l.trim() === "") {
          // A blank line ends the list unless an item or its text follows.
          var j = i + 1
          while (j < lines.length && lines[j].trim() === "") j++
          if (j < lines.length && (LIST_ITEM.test(lines[j]) || /^\s+\S/.test(lines[j]))) i = j
          else break
        } else break
      }
      out.push({ kind: "list", items: nest(items) })
      continue
    }
    var para = []
    while (i < lines.length && lines[i].trim() !== "" && !FENCE.test(lines[i]) && !HEADING.test(lines[i])
           && !LIST_ITEM.test(lines[i]) && !/^\s{0,3}>/.test(lines[i]) && !RULE.test(lines[i])) para.push(lines[i++].trim())
    out.push({ kind: "paragraph", text: para.join(" ") })
  }
  return out
}

// Flat list items, by indent, as a tree: { ordered, items: [{ text,
// children }] }, children a nested list or null. An item further in than
// the one before starts a list inside it; one further out goes back up.
function nest(flat) {
  var root = { indent: flat.length > 0 ? flat[0].indent : 0, ordered: flat.length > 0 && flat[0].ordered, items: [] }
  var stack = [root]
  for (var i = 0; i < flat.length; i++) {
    var it = flat[i]
    while (stack.length > 1 && it.indent < stack[stack.length - 1].indent) stack.pop()
    var top = stack[stack.length - 1]
    if (it.indent > top.indent && top.items.length > 0) {
      var child = { indent: it.indent, ordered: it.ordered, items: [] }
      top.items[top.items.length - 1].children = child
      stack.push(child)
      top = child
    }
    top.items.push({ text: it.text, children: null })
  }
  return root
}

// Qt's list indent is a level, not a step: a nested list says how deep.
function listHtml(list, s, outerGap, depth, top) {
  var tag = list.ordered ? "ol" : "ul"
  var level = depth || 1
  var html = "<" + tag + " style=\"margin-top:" + (top || 0) + "px; margin-bottom:" + outerGap + "px; margin-left:0px; -qt-list-indent:" + level + "\">"
  for (var i = 0; i < list.items.length; i++) {
    var it = list.items[i]
    html += "<li style=\"margin-bottom:" + Math.round(s.gap / 3) + "px; line-height:" + (s.lineHeight || 135) + "%\">"
      + inline(it.text, s)
    if (it.children) html += listHtml(it.children, s, Math.round(s.gap / 3), level + 1)
    html += "</li>"
  }
  return html + "</" + tag + ">"
}

// A box's padding (code, quotes): less at the bottom, where the last line
// already has the room under its letters.
function boxPadding(s) {
  var p = Math.round(s.gap * 0.75)
  return "padding-top:" + p + "px; padding-bottom:" + Math.max(1, p - Math.round(s.body * 0.45)) + "px; padding-left:"
    + p + "px; padding-right:" + p + "px; "
}

// `gap`: the space after it; `top`: before it, after a block drawn as a
// table (whose own margins Qt ignores).
function blockHtml(b, s, gap, first, top) {
  var lh = "line-height:" + (s.lineHeight || 135) + "%"
  top = top || 0
  if (b.kind === "paragraph")
    return "<p style=\"margin-top:" + top + "px; margin-bottom:" + gap + "px; " + lh + "\">" + inline(b.text, s) + "</p>"
  if (b.kind === "heading") {
    var size = b.level === 1 ? s.heading : b.level === 2 ? Math.round((s.heading + s.body) / 2) : s.body
    return "<p style=\"margin-top:" + (first ? 0 : Math.max(top, Math.round(s.gap / 2))) + "px; margin-bottom:" + Math.round(s.gap / 2)
      + "px; font-size:" + size + "px; font-weight:600\">" + inline(b.text, s) + "</p>"
  }
  if (b.kind === "list") return listHtml(b.items, s, gap, 1, top)
  if (b.kind === "code")
    return "<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"background-color:" + s.code + "\"><tr><td style=\""
      + boxPadding(s) + "font-family:monospace; white-space:pre\">"
      + escapeHtml(b.text).replace(/\n/g, "<br/>") + "</td></tr></table>"
  if (b.kind === "rule")
    return "<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"margin-bottom:" + gap
      + "px\"><tr><td style=\"background-color:" + s.line + "; font-size:1px\">&nbsp;</td></tr></table>"
  if (b.kind === "quote") {
    var inner = ""
    for (var i = 0; i < b.blocks.length; i++) inner += blockHtml(b.blocks[i], s, i === b.blocks.length - 1 ? 0 : s.gap, i === 0)
    // A box: Qt paints a cell's background only as tall as its own text,
    // so a bar beside the quote would be a dot.
    return "<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\" style=\"background-color:"
      + (s.quote || s.code) + "\"><tr><td style=\"" + boxPadding(s) + "color:" + s.muted + "; font-style:italic\">" + inner + "</td></tr></table>"
  }
  if (b.kind === "table") {
    var rows = ""
    for (var r = 0; r < b.rows.length; r++) {
      rows += "<tr>"
      for (var c = 0; c < b.rows[r].length; c++)
        rows += (r === 0 ? "<th style=\"text-align:left\">" : "<td>") + inline(b.rows[r][c], s) + (r === 0 ? "</th>" : "</td>")
      rows += "</tr>"
    }
    return "<table cellspacing=\"0\" cellpadding=\"" + Math.round(s.gap / 2) + "\" border=\"1\" style=\"margin-bottom:" + gap
      + "px; border-color:" + s.line + "; border-style:solid; border-collapse:collapse\">" + rows + "</table>"
  }
  return ""
}

// Blocks drawn as tables (code, quotes, rules, tables). Qt ignores a
// table's margins and draws a line right after one inside its background,
// so the space after one is the next block's top margin, or, before
// another table, a spacer line.
var TABLE_KINDS = { code: true, quote: true, rule: true, table: true }
function spacer(s) {
  return "<p style=\"margin:0px; font-size:1px; line-height:100%\">&nbsp;</p>"
    + "<p style=\"margin:0px; font-size:" + Math.max(1, Math.round(s.gap * 0.8)) + "px; line-height:100%\">&nbsp;</p>"
}

// The whole text as HTML; the last block has no space after it.
function toHtml(md, s) {
  var list = blocks(md)
  var html = ""
  for (var i = 0; i < list.length; i++) {
    var last = i === list.length - 1
    var afterTable = i > 0 && TABLE_KINDS[list[i - 1].kind]
    if (afterTable && TABLE_KINDS[list[i].kind]) html += spacer(s)
    html += blockHtml(list[i], s, last ? 0 : s.gap, i === 0, afterTable ? s.gap : 0)
  }
  return html
}
