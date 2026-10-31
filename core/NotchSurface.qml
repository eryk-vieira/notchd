import QtQuick
import Quickshell
import Quickshell.Wayland
import "State.js" as State
import "Position.js" as Position

// Puts the notch on screen: a layer-shell overlay on the focused screen,
// hanging from the edge the config's `position` names, at its offset along
// it (off the host's bar where they share an edge). With the config's
// `workspaces`, the closed notch only hangs on screens showing one of them:
// on another screen when the focused one doesn't, nowhere when none does.
// Peeks and the open notch show on the focused screen regardless. All state lives in
// NotchService and NotchCard draws it; this picks the screen, places the
// card and routes the pointer. With compactStyle "bar" the card hides at
// rest/compact (the host's bar indicator shows that) and drops out from
// under the bar to peek or expand.
//
// The window covers the whole screen on the overlay layer but its input mask
// is just the notch, so everything else stays click-through.
//
// With reserveSpace on, a second, empty window per screen holds a layer-shell
// exclusive zone on the notch's edge, as deep as the closed notch
// (ReservedSpace), so windows tile clear of it. The compositor stacks it
// inside the host bar's own zone, where the notch hangs.
Item {
  id: root

  // ------------------------------------------------------------------ host
  property var svc: null
  // A compositor adapter (HyprlandCompositor, GenericCompositor, ...);
  // defaults to the service's.
  property var compositor: root.svc ? root.svc.compositor : null
  // The host's bar, so the notch hangs off it when they share an edge and
  // keeps clear of it otherwise: its thickness (barHeight; 0 = no bar) and
  // whether it is hidden. Its edge is the service's `barEdge`.
  property int barHeight: 0
  property bool barHidden: false
  property string layerNamespace: "notchd"

  // What the notch shows (NotchCard.mode): the service's mode, or "hidden".
  readonly property string mode: card.mode

  // -------------------------------------------------------------- geometry
  readonly property string focusedScreenName: root.compositor ? root.compositor.focusedScreenName : ""
  readonly property bool open: !!root.svc && (root.svc.mode === "peek" || root.svc.mode === "expanded")
  // State.notchScreen has the rules; "" when no screen takes the closed notch.
  readonly property string wantedScreen: {
    var screens = Quickshell.screens || []
    var list = []
    for (var i = 0; i < screens.length; i++)
      list.push({ name: screens[i].name, allowed: !root.svc || root.svc.showsOn(screens[i]) })
    return State.notchScreen({ screens: list, focused: root.focusedScreenName, open: root.open,
                               override: root.svc ? root.svc.screenOverride : "" })
  }
  readonly property bool offWorkspace: root.wantedScreen === ""
  // With no screen wanted, the window stays on the focused one, concealed.
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var name = root.offWorkspace ? root.focusedScreenName : root.wantedScreen
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }
  readonly property bool fullscreenOnScreen: !!(root.compositor && root.targetScreen
    && root.compositor.hasFullscreen(root.targetScreen))

  // The bar hides over fullscreen apps, so the notch moves up with it.
  readonly property bool barVisible: !root.fullscreenOnScreen && !root.barHidden
  // Where the notch is shown: while dragged, where it would land.
  property var dragPlacement: null
  readonly property var shownPlacement: root.dragPlacement
    || (root.svc ? root.svc.placement : { edge: "top", offset: 0.5 })
  readonly property string edge: card.edge
  // The reserve keeps to where the notch is, not where a drag would put it.
  readonly property string reserveEdge: root.svc ? root.svc.edge : "top"
  // What the bar takes on each edge.
  readonly property var insets: Position.insets(root.svc ? root.svc.barEdge : "top", root.barHeight, root.barVisible)

  // Hidden in bar style at rest/compact; over a fullscreen app, or with no
  // screen on an allowed workspace, only peeks and the open notch show.
  readonly property bool concealed: root.mode === "hidden"
    || ((root.fullscreenOnScreen || root.offWorkspace) && (root.mode === "rest" || root.mode === "compact"))
  readonly property bool pinned: !!root.svc && root.svc.pinned

  // ------------------------------------------------------- reserved space
  ReservedSpace {
    id: reserve
    svc: root.svc
    notchCard: card
  }

  // Every screen the closed notch may hang on, not just the one it is on: it
  // follows focus, and reserving only there would reflow both screens on
  // each focus change. Screens showing a workspace without the notch reserve
  // nothing; switching one there and back moves its windows. A strip along
  // the whole of the notch's edge; where the host's bar is on another edge,
  // both sit at the screen edge.
  //
  // A mapped layer surface does not take new anchors (the strip stayed on
  // the old edge), so each entry names its edge and moving the notch makes
  // new windows. `reserving` keeps a change of depth from doing the same.
  readonly property bool reserving: reserve.space > 0
  Variants {
    model: {
      if (!root.reserving) return []
      var edge = root.reserveEdge
      return (Quickshell.screens || []).map(function(s) { return { screen: s, edge: edge } })
    }
    PanelWindow {
      required property var modelData
      screen: modelData.screen
      visible: !root.svc || root.svc.showsOn(modelData.screen)
      anchors {
        top: modelData.edge !== "bottom"
        bottom: modelData.edge !== "top"
        left: modelData.edge !== "right"
        right: modelData.edge !== "left"
      }
      readonly property bool vertical: modelData.edge === "left" || modelData.edge === "right"
      implicitWidth: vertical ? reserve.space : 0
      implicitHeight: vertical ? 0 : reserve.space
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: reserve.space
      // Overlay, so it is arranged after the bar (top layer) and stacks
      // inside it rather than pushing the bar away.
      WlrLayershell.namespace: root.layerNamespace + "-reserve"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Draws nothing and takes no input.
      mask: Region {}
    }
  }

  // ---------------------------------------------------------------- window
  PanelWindow {
    id: window
    screen: root.targetScreen

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region { item: hitArea }

    // The notch plus some slack, so the small rest lip is easy to hover:
    // at both ends along the edge and twice that on the open side.
    readonly property real slack: Theme.space(root.mode === "rest" ? 10 : 4)
    readonly property var zone: {
      var s = window.slack
      var x = card.x - (root.edge === "left" ? 0 : root.edge === "right" ? 2 * s : s)
      var y = card.y - (root.edge === "top" ? 0 : root.edge === "bottom" ? 2 * s : s)
      if (root.concealed) return { x: x, y: y, width: 0, height: 0 }
      return { x: x, y: y, width: card.width + 2 * s, height: card.height + 2 * s }
    }

    // Input region: the zone; while pinned, everything off the bar, to
    // click away.
    Item {
      id: hitArea
      x: root.pinned ? root.insets.left : window.zone.x
      y: root.pinned ? root.insets.top : window.zone.y
      width: root.pinned ? Math.max(0, window.width - root.insets.left - root.insets.right) : window.zone.width
      height: root.pinned ? Math.max(0, window.height - root.insets.top - root.insets.bottom) : window.zone.height
    }

    MouseArea {
      anchors.fill: parent
      visible: root.pinned
      onClicked: if (root.svc) root.svc.close()
    }

    // The pointer is on the notch while it is on the card or the slack
    // around it. The card reports its own hover: an item beside it loses
    // the pointer to any control inside the card that takes hover, which
    // closed the notch as the pointer crossed its buttons. Naming the
    // screen keeps the notch on it while open, even when another screen has
    // focus (the closed notch can hang off-focus).
    readonly property string screenName: window.screen ? window.screen.name : ""
    Item {
      id: hoverZone
      x: window.zone.x
      y: window.zone.y
      width: window.zone.width
      height: window.zone.height
      HoverHandler {
        onHoveredChanged: if (root.svc) root.svc.setPointer("notch-slack", hovered, window.screenName)
      }
    }

    NotchCard {
      id: card
      svc: root.svc
      edge: root.shownPlacement.edge
      maxWidth: window.width - Theme.space(64)
      maxHeight: window.height - Theme.space(64)
      // Position.js has the rules; the shoulders stay on screen.
      readonly property real margin: card.shoulder + Theme.space(4)
      readonly property var spot: Position.place({
        edge: card.edge, offset: root.shownPlacement.offset,
        width: window.width, height: window.height, cardWidth: card.width, cardHeight: card.height,
        insets: root.insets, margin: card.margin
      })
      x: card.spot.x
      y: card.spot.y

      // Held and dragged, it jumps to the edge nearest the pointer, its
      // middle under the pointer, and lands there on release
      // (Position.dragTarget).
      onHoveredChanged: if (root.svc) root.svc.setPointer("notch", card.hovered, window.screenName)

      draggable: !!root.svc && root.svc.canDrag
      onDragStarted: if (root.svc) root.svc.setDragging(true)
      onDragMoved: function(scenePosition) {
        root.dragPlacement = Position.dragTarget({
          x: scenePosition.x, y: scenePosition.y, width: window.width, height: window.height,
          insets: root.insets, margin: card.margin, magnet: Theme.space(24)
        })
      }
      onDragEnded: {
        if (root.svc && root.dragPlacement)
          root.svc.setConfigValue("position", Position.configValue(root.dragPlacement))
        root.dragPlacement = null
        if (root.svc) root.svc.setDragging(false)
      }
      opacity: root.concealed ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 160 } }
    }
  }
}
