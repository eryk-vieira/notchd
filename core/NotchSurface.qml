import QtQuick
import Quickshell
import Quickshell.Wayland
import "State.js" as State

// Puts the notches on screen: a NotchWindow for every copy of every notch
// (NotchService.copies), which places it and routes its pointer, plus the
// space the closed notches keep clear of windows.
//
// With reserveSpace on, an empty window per screen edge holds a layer-shell
// exclusive zone as deep as the deepest closed notch there (ReservedSpace,
// State.reserveZones), so windows tile clear of them and two notches on one
// edge don't add up. The compositor stacks it inside the host bar's own
// zone, where the notch hangs.
Item {
  id: root

  // ------------------------------------------------------------------ host
  property var svc: null
  // The host's bar, so a notch hangs off it when they share an edge and
  // keeps clear of it otherwise: its thickness (barHeight; 0 = no bar) and
  // whether it is hidden. Its edge is the service's `barEdge`.
  property int barHeight: 0
  property bool barHidden: false
  property string layerNamespace: "notchd"

  // The window of each copy, in the service's order.
  readonly property var windows: windowVariants.instances

  Variants {
    id: windowVariants
    model: root.svc ? root.svc.copies : []
    NotchWindow {
      required property var modelData
      copy: modelData
      barHeight: root.barHeight
      barHidden: root.barHidden
      layerNamespace: root.layerNamespace
    }
  }

  // ------------------------------------------------------- reserved space
  // { "<screen>|<edge>": px } over every copy's reserve.
  readonly property var zones: State.reserveZones(root.windows.map(function(w) { return w.reserve }))

  // A mapped layer surface does not take new anchors (the strip stayed on
  // the old edge), so each window is one screen edge, and a notch moving to
  // another edge makes a new one. Its depth follows the zone.
  Variants {
    model: Object.keys(root.zones)
    PanelWindow {
      id: strip
      required property var modelData
      readonly property string screenName: modelData.split("|")[0]
      readonly property string edge: modelData.split("|")[1]
      readonly property int space: root.zones[modelData] || 0
      screen: {
        var screens = Quickshell.screens || []
        for (var i = 0; i < screens.length; i++) if (screens[i].name === strip.screenName) return screens[i]
        return null
      }
      anchors {
        top: strip.edge !== "bottom"
        bottom: strip.edge !== "top"
        left: strip.edge !== "right"
        right: strip.edge !== "left"
      }
      readonly property bool vertical: strip.edge === "left" || strip.edge === "right"
      implicitWidth: strip.vertical ? strip.space : 0
      implicitHeight: strip.vertical ? 0 : strip.space
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: strip.space
      // Overlay, so it is arranged after the bar (top layer) and stacks
      // inside it rather than pushing the bar away.
      WlrLayershell.namespace: root.layerNamespace + "-reserve"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Draws nothing and takes no input.
      mask: Region {}
    }
  }
}
