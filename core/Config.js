// Config rules: reading and editing the JSON config, and resolving it into
// the values the service runs on. Pure functions with no QML globals, so
// Node tests them too (tests/config.test.mjs). Keep it plain ES5 functions:
// QML imports this file as is and Node evaluates it in a vm context.

var DEFAULTS = {
  hoverOpenDelay: 120,
  hoverCloseDelay: 300,
  compactStyle: "bar",
  reserveSpace: false
}

// A config file's text as an object. Anything but a JSON object is an error;
// the caller keeps the last good config.
function parse(text) {
  var cfg
  try {
    cfg = JSON.parse(String(text || "{}"))
  } catch (e) {
    return { ok: false, error: String(e && e.message || e) }
  }
  if (!cfg || typeof cfg !== "object" || Array.isArray(cfg))
    return { ok: false, error: "the config must be a JSON object" }
  return { ok: true, config: cfg }
}

// A key's value; dotted keys reach into objects ("theme.accent").
function valueAt(cfg, key) {
  var parts = String(key).split(".")
  var node = cfg
  for (var i = 0; i < parts.length; i++) {
    if (!node || typeof node !== "object") return undefined
    node = node[parts[i]]
  }
  return node
}

// A copy of cfg with one key set. `undefined` removes the key, and objects
// it leaves empty go too, so the file never keeps `"theme": {}` around.
function withValue(cfg, key, value) {
  var out = JSON.parse(JSON.stringify(cfg || {}))
  var parts = String(key).split(".")
  var chain = [out]
  var node = out
  for (var i = 0; i < parts.length - 1; i++) {
    if (!node[parts[i]] || typeof node[parts[i]] !== "object") {
      if (value === undefined) return out
      node[parts[i]] = {}
    }
    node = node[parts[i]]
    chain.push(node)
  }
  var leaf = parts[parts.length - 1]
  if (value === undefined) delete node[leaf]
  else node[leaf] = value
  for (var j = chain.length - 1; j > 0; j--)
    if (Object.keys(chain[j]).length === 0) delete chain[j - 1][parts[j - 1]]
  return out
}

function delay(value, fallback) {
  if (value === undefined) return fallback
  return Math.max(0, Number(value) || 0)
}

// The core keys as the service uses them. A missing key falls back to its
// default, so deleting it (by hand or in the settings window) resets it.
function resolve(cfg, defaultModules) {
  cfg = cfg || {}
  return {
    moduleIds: Array.isArray(cfg.modules) ? cfg.modules.map(String) : defaultModules,
    hoverOpenDelay: delay(cfg.hoverOpenDelay, DEFAULTS.hoverOpenDelay),
    hoverCloseDelay: delay(cfg.hoverCloseDelay, DEFAULTS.hoverCloseDelay),
    compactStyle: cfg.compactStyle === "notch" ? "notch" : DEFAULTS.compactStyle,
    reserveSpace: cfg.reserveSpace === true
  }
}
