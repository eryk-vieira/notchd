// An agent's avatar: a photo made into an ASCII face (core/avatar/
// make-avatar.py makes the files, AvatarView.qml draws them). The rules
// live here: where the mouth and eyes are, how the face is framed, its
// colors from the theme, the job's progress, when it blinks and how it
// talks. Plain functions: QML imports this file as is and the Node tests
// load it in a vm.

// ------------------------------------------------------------------ files
// $XDG_DATA_HOME/notchd/avatars/<id>: color.png (the photo, the person's
// mask in its alpha), depth.png (0 far .. 1 near), face.json (the face's
// points), source.jpg (the photo, to make it again).
function dataHome(xdgDataHome, home) {
  var x = String(xdgDataHome || "").replace(/\/+$/, "")
  return x !== "" ? x : String(home || "").replace(/\/+$/, "") + "/.local/share"
}
function avatarsRoot(dataHomeDir) { return String(dataHomeDir || "").replace(/\/+$/, "") + "/notchd/avatars" }
function avatarDir(dataHomeDir, id) { return avatarsRoot(dataHomeDir) + "/" + id }
// Models are downloaded once, here.
function modelsDir(xdgCacheHome, home) {
  var x = String(xdgCacheHome || "").replace(/\/+$/, "")
  return (x !== "" ? x : String(home || "").replace(/\/+$/, "") + "/.cache") + "/notchd/models"
}
// Only a folder of our own is ever deleted: one right under the avatars
// root, never the root itself or anything outside it.
function removable(dir, dataHomeDir) {
  var root = avatarsRoot(dataHomeDir) + "/"
  var d = String(dir || "")
  if (d.indexOf(root) !== 0) return false
  var rest = d.slice(root.length)
  return rest !== "" && rest.indexOf("/") === -1 && rest !== "." && rest !== ".."
}
// A file of the core as a path: Qt.resolvedUrl gives file:// urls, or under
// Quickshell `qs:@/qs/<path>` (resolved against `shellDir`) and
// `qs:///<absolute path>` (the Omarchy shell, for a plugin's core). "" for
// anything else.
function localPath(url, shellDir) {
  var s = String(url || "")
  var path = ""
  if (s.indexOf("file://") === 0) path = s.slice(7)
  else if (s.indexOf("qs:@/qs/") === 0 && shellDir) path = String(shellDir).replace(/\/$/, "") + "/" + s.slice(8)
  else if (s.indexOf("qs:///") === 0) path = s.slice(5)
  else return ""
  return decodeURIComponent(path)
}
// Whose avatar a settings field is: its key is "<id>.avatar".
function ownerOf(key) {
  var k = String(key || "")
  return /\.avatar$/.test(k) ? k.slice(0, -7) : ""
}
// The pipeline's command line: `pipeline` is the script (or a test's fake).
function pipelineArgs(pipeline, photo, out, models) {
  var p = String(pipeline || "")
  var run = /\.py$/.test(p) ? ["python3", p] : [p]
  return run.concat(["--photo", String(photo), "--out", String(out), "--models", String(models)])
}

// --------------------------------------------------------------- the face
// face.json, as make-avatar.py writes it: { size: [w, h], points: { name:
// [x, y] } } in the photo's pixels. The shader wants the lips' corners,
// how far the chin is below them, each eye's corners and how far its lids
// reach, and how far the jaw drops. null when something is missing.
var POINT_NAMES = ["mouthL", "mouthR", "chin", "top", "left", "right",
  "eyeAOuter", "eyeAInner", "eyeAUpper", "eyeALower",
  "eyeBOuter", "eyeBInner", "eyeBUpper", "eyeBLower"]

function isPoint(p) {
  return !!p && p.length === 2 && isFinite(p[0]) && isFinite(p[1])
}

// Distance of `p` from the line a→b, positive on the side "down" points to
// (the photo's +y, the way a face faces).
function sideDistance(a, b, p) {
  var dx = b[0] - a[0], dy = b[1] - a[1]
  var len = Math.sqrt(dx * dx + dy * dy) || 1
  var nx = -dy / len, ny = dx / len
  if (ny < 0) { nx = -nx; ny = -ny }
  return (p[0] - a[0]) * nx + (p[1] - a[1]) * ny
}

function faceFromLandmarks(face) {
  if (!face || typeof face !== "object") return null
  var size = face.size
  if (!size || !(size[0] > 0) || !(size[1] > 0)) return null
  var p = face.points || {}
  for (var i = 0; i < POINT_NAMES.length; i++)
    if (!isPoint(p[POINT_NAMES[i]])) return null

  function eye(prefix) {
    var outer = p[prefix + "Outer"], inner = p[prefix + "Inner"]
    // Lids a little past the lash line, so a closed eye covers it.
    var up = Math.max(4, -sideDistance(outer, inner, p[prefix + "Upper"]) * 1.25)
    var low = Math.max(3, sideDistance(outer, inner, p[prefix + "Lower"]) * 1.1)
    return { corners: [outer[0], outer[1], inner[0], inner[1]], lids: [up, low] }
  }
  var a = eye("eyeA"), b = eye("eyeB")
  var halfMouth = Math.sqrt(Math.pow(p.mouthR[0] - p.mouthL[0], 2) + Math.pow(p.mouthR[1] - p.mouthL[1], 2)) / 2
  return {
    size: [size[0], size[1]],
    mouthL: p.mouthL.slice(), mouthR: p.mouthR.slice(),
    chin: Math.max(halfMouth * .5, sideDistance(p.mouthL, p.mouthR, p.chin)),
    eyeA: a.corners, lidsA: a.lids, eyeB: b.corners, lidsB: b.lids,
    // The jaw's drop at full opening: about a fifth of half the mouth, so
    // a big photo or a close-up doesn't gape.
    openMax: halfMouth * .22,
    box: { x: p.left[0], y: p.top[1], w: p.right[0] - p.left[0], h: p.chin[1] - p.top[1] }
  }
}

// Where the photo sits in a view: `zoom` is the photo's height over the
// view's, `focus` the photo point (0..1) at the view's centre. The face
// (forehead to chin) fills `fill` of the view's height, a little above the
// middle so the hair shows.
function framing(face, fill) {
  if (!face) return { zoom: 1, focus: [.5, .5] }
  var w = face.size[0], h = face.size[1]
  var fh = Math.max(1, face.box.h) / h
  var zoom = Math.min(4, Math.max(.6, (fill || .6) / fh))
  var cx = (face.box.x + face.box.w / 2) / w
  var cy = (face.box.y + face.box.h / 2) / h - .06 / zoom
  return { zoom: zoom, focus: [cx, cy] }
}

// ------------------------------------------------------------- the colors
// The face is lit by two lights: a warm one from the left (the theme's
// accent), a cool one from the right (its complement) and a highlight
// (the accent, lighter). On a grey accent the lights are two greys. "photo"
// keeps the photo's own colors. Colors as [r, g, b], 0..1.
function rgbToHsl(c) {
  var r = c[0], g = c[1], b = c[2]
  var max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2
  if (max === min) return [0, 0, l]
  var d = max - min
  var s = l > .5 ? d / (2 - max - min) : d / (max + min)
  var h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
  return [h / 6, s, l]
}
function hslToRgb(hsl) {
  var h = hsl[0], s = hsl[1], l = hsl[2]
  if (s === 0) return [l, l, l]
  function f(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  var q = l < .5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
  return [f(p, q, h + 1 / 3), f(p, q, h), f(p, q, h - 1 / 3)]
}
function palette(accent, mode) {
  var hsl = rgbToHsl(accent)
  var grey = hsl[1] < .15
  var warm = hslToRgb([hsl[0], hsl[1], Math.min(.6, Math.max(.45, hsl[2]))])
  var cool = grey ? hslToRgb([0, 0, .32]) : hslToRgb([(hsl[0] + .5) % 1, Math.max(.6, hsl[1]), .5])
  var hot = hslToRgb([hsl[0], hsl[1], Math.min(.85, hsl[2] + .3)])
  return { warm: warm, cool: cool, hot: hot, photo: mode === "photo" ? 1 : 0 }
}

// ---------------------------------------------------------------- the job
// One line of the pipeline's output: { step, progress } while it works,
// { done: true } or { error, packages } at the end. null for anything else.
function parseProgress(line) {
  var data
  try { data = JSON.parse(String(line)) } catch (e) { return null }
  if (!data || typeof data !== "object" || Array.isArray(data)) return null
  if (data.done === true) return { done: true }
  if (typeof data.error === "string")
    return { error: data.error, packages: Array.isArray(data.packages) ? data.packages.map(String) : [] }
  if (typeof data.step === "string")
    return { step: data.step, progress: typeof data.progress === "number" ? Math.max(0, Math.min(1, data.progress)) : -1 }
  return null
}

var STEPS = {
  download: "Downloading the models (once, about 120 MB)",
  load: "Reading the photo",
  mask: "Cutting out the person",
  face: "Finding the face",
  depth: "Estimating depth",
  write: "Saving"
}
// What the settings say about a job: { running, step, progress, error,
// packages }, or null when there is none.
function statusText(job) {
  if (!job) return ""
  if (job.error === "missing")
    return "Needs " + job.packages.join(", ") + ": run make avatar-deps in notchd's folder, or install them with your package manager."
  if (job.error) return job.error
  if (!job.running) return ""
  var text = STEPS[job.step] || "Starting"
  return job.progress >= 0 ? text + " " + Math.round(job.progress * 100) + " %" : text + "…"
}

// "avatar <photo>" makes one, "avatar remove" removes it; the rest of an
// agent's IPC command after "avatar" (Agent.parseCommand). `home` for ~.
function request(text, home) {
  var t = String(text || "").trim()
  if (t === "") return { action: "usage" }
  if (t === "remove") return { action: "remove" }
  var path = t.replace(/^"(.*)"$/, "$1").replace(/^'(.*)'$/, "$1")
  if (path === "~" || path.indexOf("~/") === 0) path = String(home || "").replace(/\/+$/, "") + path.slice(1)
  if (path.charAt(0) !== "/") return { action: "relative", path: path }
  return { action: "create", photo: path }
}

// ------------------------------------------------------------ the blinks
// Every 2.5 to 6.5 s, one in five doubled; 70 ms down, 40 ms shut, 150 ms
// up. `rand` returns 0..1.
function nextBlink(rand) {
  return rand() < .2 ? .32 : 2.5 + rand() * 4
}
// How shut the eyes are `d` seconds into a blink: 0 open .. 1 shut.
function blinkLevel(d) {
  if (!(d >= 0) || d > .26) return 0
  if (d < .07) return Math.sin(d / .07 * Math.PI / 2)
  if (d < .11) return 1
  return 1 - Math.pow((d - .11) / .15, 1.6)
}

// ------------------------------------------------------------ the speech
// A phrase without audio: 3 to 9 words of 1 to 3 syllables (90 to 210 ms),
// a short gap between words, a breath after. Most syllables open the mouth
// a little; one in seven is a wide vowel. Times from `t`.
function speechPlan(t, rand) {
  var at = t, syllables = []
  var words = 3 + Math.floor(rand() * 7)
  for (var w = 0; w < words; w++) {
    var count = 1 + Math.floor(rand() * 3)
    for (var k = 0; k < count; k++) {
      var d = .09 + rand() * .12
      var amp = rand() < .15 ? .7 + rand() * .3 : .2 + rand() * .4
      syllables.push({ start: at, end: at + d, amp: amp, wide: .92 + rand() * .16, word: w })
      at += d
    }
    at += .05 + rand() * .12
  }
  return { syllables: syllables, end: at, until: at + .35 + rand() * .7 }
}
// The mouth at `t`: { open: 0..1, wide }. Inside a word the lips only half
// close between syllables.
function speechLevel(plan, t) {
  var s = plan ? plan.syllables : []
  for (var i = 0; i < s.length; i++) {
    if (t < s[i].start) return { open: 0, wide: 1 }
    if (t < s[i].end) {
      var ph = (t - s[i].start) / (s[i].end - s[i].start)
      var inWord = i + 1 < s.length && s[i + 1].word === s[i].word
      var floor = inWord && ph > .5 ? .12 : 0
      return { open: Math.max(floor, s[i].amp * Math.sin(Math.PI * ph)), wide: s[i].wide }
    }
  }
  return { open: 0, wide: 1 }
}

// The mouth from a voice as it plays: `db` its level now (dB below full
// scale), `peak` the recent peak (the last call's, -20 to begin with). The
// level counts against that peak, which falls 7 dB a second (0.12 a frame
// at 60 fps), so a loud voice and a quiet one move it alike: open about
// .35 most of the time, wide only on stressed vowels. { open, wide, peak }.
function voiceMouth(db, peak) {
  var level = Number(db)
  if (!isFinite(level)) level = -100
  var p = Math.max(level, (isFinite(Number(peak)) ? Number(peak) : -20) - .12)
  var rel = Math.min(1, Math.max(0, (level - p + 20) / 20))
  return { open: level < -55 ? 0 : .8 * Math.pow(rel, 2.2), wide: 1, peak: p }
}
