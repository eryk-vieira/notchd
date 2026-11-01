import QtQuick

// Brings back a layer-shell window that the compositor closed. Bind the
// window's `visible` to `shown`.
//
// When the output a window is on goes away (a monitor turned off or
// unplugged), the compositor closes the window's layer surface, and Quickshell
// then marks the window hidden on its own. The window's `visible` binding
// still says true and nothing it depends on changes, so the window never
// came back: the notches stayed gone after the monitor was switched on
// again. When the window is hidden while `wanted` and there is a `screen`
// for it, this turns `shown` off and on again. The binding then shows the
// window again on the screen it has moved to. With no screen it stays
// hidden, rather than landing on whichever screen Qt picks, and shows again
// when one comes back.
QtObject {
  id: keeper

  // The window whose `visible` follows `shown`.
  property var target: null
  // Whether it should be on screen.
  property bool wanted: true
  // The screen it goes on; null while there is none, and it hides.
  property var screen: null

  property bool reopening: false
  readonly property bool shown: keeper.wanted && !!keeper.screen && !keeper.reopening

  function reopen() {
    if (!keeper.target || keeper.target.visible || !keeper.wanted || !keeper.screen) return
    keeper.reopening = true
    keeper.reopening = false
  }

  // Later, not inside the change: the screen list may still be updating.
  onScreenChanged: Qt.callLater(keeper.reopen)
  readonly property Connections watch: Connections {
    target: keeper.target
    function onVisibleChanged() { if (!keeper.target.visible) Qt.callLater(keeper.reopen) }
  }
}
