import QtQuick
import Quickshell.Hyprland

// Compositor adapter for Hyprland. A compositor adapter tells the notch
// which screen has focus, whether a fullscreen window covers a screen and
// which workspace a screen shows; see GenericCompositor.qml for the contract.
QtObject {
  readonly property string name: "hyprland"
  readonly property string focusedScreenName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

  function hasFullscreen(screen) {
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    return !!(monitor && monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen)
  }

  readonly property bool supportsWorkspaces: true
  // Special workspaces (scratchpads, negative ids) are left out.
  readonly property var knownWorkspaces: {
    var all = Hyprland.workspaces ? Hyprland.workspaces.values : []
    var out = []
    for (var i = 0; i < all.length; i++)
      if (all[i].id > 0) out.push(String(all[i].name))
    return out
  }

  function activeWorkspace(screen) {
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    var ws = monitor ? monitor.activeWorkspace : null
    return ws ? { id: ws.id, name: String(ws.name) } : null
  }
}
