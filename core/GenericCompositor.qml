import QtQuick

// Fallback compositor adapter, and the contract every adapter follows:
//
//   name                 string, for logs
//   focusedScreenName    name of the focused output ("" when unknown; the
//                        surface then uses the first screen)
//   hasFullscreen(screen) whether a fullscreen window covers that screen
//
// Without compositor IPC it knows neither, so the notch stays on the first
// screen and never hides for fullscreen apps.
QtObject {
  readonly property string name: "generic"
  readonly property string focusedScreenName: ""
  function hasFullscreen(screen) { return false }
}
