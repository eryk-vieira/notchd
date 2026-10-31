import QtQuick

// Fallback compositor adapter, and the contract every adapter follows:
//
//   name                 string, for logs
//   focusedScreenName    name of the focused output ("" when unknown; the
//                        surface then uses the first screen)
//   hasFullscreen(screen) whether a fullscreen window covers that screen
//   supportsWorkspaces   whether activeWorkspace() can answer; without it
//                        the `workspaces` setting is hidden
//   knownWorkspaces      names of the workspaces that exist now, offered
//                        in the settings
//   activeWorkspace(screen) { id, name } of the workspace shown on that
//                        screen, or null when unknown
//
// Without compositor IPC it knows none of it, so the notch stays on the
// first screen, never hides for fullscreen apps and shows on every workspace.
QtObject {
  readonly property string name: "generic"
  readonly property string focusedScreenName: ""
  function hasFullscreen(screen) { return false }
  readonly property bool supportsWorkspaces: false
  readonly property var knownWorkspaces: []
  function activeWorkspace(screen) { return null }
}
