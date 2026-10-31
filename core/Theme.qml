pragma Singleton
import QtQuick

// Visual tokens for the notch and its modules. The core never reads a desktop's
// theme itself: the host sets `provider` to an object with any of the keys
// below (a host's own theme mapped onto these names) and everything else falls
// back to the defaults here. Bindings on Theme follow the provider live.
//
//   foreground, background, accent        colors
//   fontFamily                             font family name
//   fontCaption, fontBodySmall, fontBody,
//   fontHeading, fontDisplay               pixel sizes
//   spacingScale                           multiplier behind space()
QtObject {
  id: theme

  property var provider: null

  function pick(key, fallback) {
    var p = theme.provider
    var v = p ? p[key] : undefined
    return v === undefined || v === null || v === "" ? fallback : v
  }

  readonly property color foreground: pick("foreground", "#cacccc")
  readonly property color background: pick("background", "#101315")
  readonly property color accent: pick("accent", theme.foreground)

  readonly property real spacingScale: Math.max(0.1, Number(pick("spacingScale", 1)) || 1)

  // Design pixels to real pixels, so layouts keep their proportions when the
  // host makes everything denser or roomier.
  function space(px) {
    var n = Number(px) * theme.spacingScale
    if (!isFinite(n) || n <= 0) return 0
    return Math.max(1, Math.round(n))
  }

  readonly property QtObject font: QtObject {
    readonly property string family: theme.pick("fontFamily", "monospace")
    readonly property int caption: theme.pick("fontCaption", 10)
    readonly property int bodySmall: theme.pick("fontBodySmall", 11)
    readonly property int body: theme.pick("fontBody", 12)
    readonly property int heading: theme.pick("fontHeading", 16)
    readonly property int display: theme.pick("fontDisplay", 24)
  }
}
