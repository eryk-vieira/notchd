import QtQuick
import Quickshell.Hyprland

// Compositor adapter for Hyprland. A compositor adapter tells the surface
// which screen has focus and whether a fullscreen window covers a screen;
// see GenericCompositor.qml for the contract.
QtObject {
  readonly property string name: "hyprland"
  readonly property string focusedScreenName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

  function hasFullscreen(screen) {
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    return !!(monitor && monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen)
  }
}
