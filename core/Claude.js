// The claude module's rules: the `claude` command line, the chat built from
// its stream-json events, and the chat read back from a session's
// transcript. Pure functions over plain state objects, so Node tests them
// too (tests/claude.test.mjs, against recorded events in tests/fixtures/).
// The module runs the process and binds these.
//
// A state is:
//   sessionId  the Claude Code session it continues ("" before the first)
//   messages   [{ role: "user" | "assistant", text, tools: [tool names] }]
//   busy       an answer is on its way
//   activity   while busy: "thinking" | "searching" | "writing"
//   error      why the last answer failed, else ""

var EMPTY = { sessionId: "", messages: [], busy: false, activity: "", error: "" }

// Tools a web-enabled chat gets. They run without asking: nobody is at a
// terminal to answer a permission prompt.
var WEB_TOOLS = "WebSearch,WebFetch"

// The command that keeps one session open, reading user messages on stdin
// and streaming events on stdout. No hooks, MCP servers or CLAUDE.md
// (`--setting-sources ""`, `--strict-mcp-config`): a quick chat, not a
// coding agent. o: { model, web, systemPrompt, sessionId }.
function command(o) {
  o = o || {}
  var argv = ["claude", "-p",
    "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    "--include-partial-messages",
    "--setting-sources", "", "--strict-mcp-config"]
  if (o.model) argv.push("--model", String(o.model))
  if (o.systemPrompt) argv.push("--system-prompt", String(o.systemPrompt))
  // `--tools` takes a list: given as `--tools X` it would swallow the next
  // argument, so always in the `=` form.
  if (o.web) argv.push("--tools=" + WEB_TOOLS, "--allowedTools=" + WEB_TOOLS)
  else argv.push("--tools=")
  if (o.sessionId) argv.push("--resume", String(o.sessionId))
  return argv
}

// One user message, as a line for the process's stdin.
function inputLine(text) {
  return JSON.stringify({ type: "user", message: { role: "user", content: String(text) } }) + "\n"
}

// The state with the last message replaced by fn(last).
function withLast(state, fn) {
  var list = state.messages.slice()
  list[list.length - 1] = fn(list[list.length - 1])
  return Object.assign({}, state, { messages: list })
}
function lastAssistant(state) {
  var last = state.messages.length > 0 ? state.messages[state.messages.length - 1] : null
  return last && last.role === "assistant" ? last : null
}
// The answer on its way, made if missing.
function withAnswer(state, fn) {
  if (!lastAssistant(state))
    state = Object.assign({}, state, { messages: state.messages.concat([{ role: "assistant", text: "", tools: [] }]) })
  return withLast(state, function(m) { return Object.assign({}, m, fn(m)) })
}

// The state after sending `text`: the question, an empty answer to fill,
// busy. Blank text changes nothing.
function send(state, text) {
  var t = String(text || "").trim()
  if (t === "") return state
  return Object.assign({}, state, {
    messages: state.messages.concat([{ role: "user", text: t, tools: [] }, { role: "assistant", text: "", tools: [] }]),
    busy: true, activity: "thinking", error: ""
  })
}

// A line of the process's stdout, as an event; null for anything else.
function parseLine(line) {
  var s = String(line || "").trim()
  if (s === "" || s.charAt(0) !== "{") return null
  try { return JSON.parse(s) } catch (e) { return null }
}

// The state after one stream-json event.
function apply(state, ev) {
  if (!ev || typeof ev !== "object") return state
  if (ev.type === "system" && ev.subtype === "init")
    return ev.session_id ? Object.assign({}, state, { sessionId: String(ev.session_id) }) : state
  if (ev.type === "stream_event" && ev.event) return applyStream(state, ev.event)
  if (ev.type === "result") return applyResult(state, ev)
  return state
}

function applyStream(state, e) {
  if (!state.busy) return state
  if (e.type === "content_block_start" && e.content_block) {
    var kind = e.content_block.type
    if (kind === "tool_use") {
      var name = String(e.content_block.name || "tool")
      state = withAnswer(state, function(m) {
        return { tools: m.tools.indexOf(name) === -1 ? m.tools.concat([name]) : m.tools }
      })
      return Object.assign({}, state, { activity: "searching" })
    }
    if (kind === "thinking") return Object.assign({}, state, { activity: "thinking" })
    if (kind === "text") {
      // A second text block (after a search) starts a new paragraph.
      state = withAnswer(state, function(m) {
        return { text: m.text !== "" && !/\n\n$/.test(m.text) ? m.text + "\n\n" : m.text }
      })
      return Object.assign({}, state, { activity: "writing" })
    }
    return state
  }
  if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") {
    var piece = String(e.delta.text || "")
    state = withAnswer(state, function(m) { return { text: m.text + piece } })
    return state.activity === "writing" ? state : Object.assign({}, state, { activity: "writing" })
  }
  return state
}

function applyResult(state, ev) {
  var failed = ev.is_error === true || (ev.subtype && ev.subtype !== "success")
  var next = Object.assign({}, state, { busy: false, activity: "" })
  if (ev.session_id) next.sessionId = String(ev.session_id)
  var answer = lastAssistant(next)
  // No partial messages came (or none with text): the result has the answer.
  if (!failed && answer && answer.text.trim() === "" && ev.result)
    next = withLast(next, function(m) { return Object.assign({}, m, { text: String(ev.result) }) })
  if (failed) return fail(next, String(ev.result || ev.subtype || "the answer failed"))
  return next
}

// The state after the answer failed (the process died, an error result):
// not busy, `why` shown, an answer that never started taken out.
function fail(state, why) {
  var next = Object.assign({}, state, { busy: false, activity: "", error: String(why || "failed") })
  var answer = lastAssistant(next)
  if (answer && answer.text.trim() === "" && answer.tools.length === 0)
    next.messages = next.messages.slice(0, -1)
  return next
}

// What the closed notch calls the session: its first question, on one line,
// cut at `max` characters; "" before the first.
function title(state, max) {
  var n = max || 40
  for (var i = 0; i < state.messages.length; i++) {
    if (state.messages[i].role !== "user") continue
    var t = state.messages[i].text.replace(/\s+/g, " ").trim()
    return t.length > n ? t.slice(0, n - 1).replace(/\s+$/, "") + "…" : t
  }
  return ""
}

// The last answer's text, for copying.
function lastAnswer(state) {
  for (var i = state.messages.length - 1; i >= 0; i--)
    if (state.messages[i].role === "assistant" && state.messages[i].text !== "") return state.messages[i].text
  return ""
}

// Where Claude Code keeps a session's transcript: a folder per working
// directory, named after it with every other character a dash.
function transcriptPath(configDir, cwd, sessionId) {
  return String(configDir).replace(/\/$/, "") + "/projects/" + String(cwd).replace(/[^A-Za-z0-9]/g, "-")
    + "/" + sessionId + ".jsonl"
}

// The chat read back from a transcript (one JSON entry per line): the
// questions and the answers' text and tools, without tool results, side
// chains or meta entries.
function fromTranscript(text, sessionId) {
  var state = Object.assign({}, EMPTY, { sessionId: String(sessionId || "") })
  var seen = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var e = parseLine(lines[i])
    if (!e || !e.message || e.isSidechain || e.isMeta) continue
    if (e.uuid) { if (seen[e.uuid]) continue; seen[e.uuid] = true }
    var content = e.message.content
    if (e.type === "user") {
      var q = typeof content === "string" ? content : blocksText(content, "text")
      if (q.trim() !== "") state.messages = state.messages.concat([{ role: "user", text: q.trim(), tools: [] }])
    } else if (e.type === "assistant" && content && content.length !== undefined) {
      for (var j = 0; j < content.length; j++) {
        var b = content[j]
        if (!b) continue
        if (b.type === "text" && b.text) {
          state = withAnswer(state, function(m) { return { text: m.text !== "" ? m.text + "\n\n" + b.text : b.text } })
        } else if (b.type === "tool_use") {
          state = withAnswer(state, function(m) {
            return { tools: m.tools.indexOf(b.name) === -1 ? m.tools.concat([String(b.name)]) : m.tools }
          })
        }
      }
    }
  }
  return state
}

function blocksText(blocks, type) {
  if (!blocks || blocks.length === undefined) return ""
  var out = []
  for (var i = 0; i < blocks.length; i++)
    if (blocks[i] && blocks[i].type === type && blocks[i].text) out.push(blocks[i].text)
  return out.join("\n")
}
