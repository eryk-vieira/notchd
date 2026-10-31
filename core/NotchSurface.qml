import QtQuick
import Quickshell
import Quickshell.Wayland
import "State.js" as State

// Puts the notch on screen: a layer-shell overlay at the top edge of the
// focused screen (under the host's bar, if it has one). With the config's
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
// exclusive zone as deep as the closed notch (ReservedSpace), so windows tile
// below it. The compositor stacks it under the host bar's own zone, where the
// notch hangs.
Item {
  id: root

  // ------------------------------------------------------------------ host
  property var svc: null
  // A compositor adapter (HyprlandCompositor, GenericCompositor, ...);
  // defaults to the service's.
  property var compositor: root.svc ? root.svc.compositor : null
  // The host's bar, so the notch hangs right under it. barHeight 0 = no bar.
  property int barHeight: 0
  property bool barOnTop: true
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
  readonly property int topOffset: (root.barOnTop && root.barVisible) ? Math.max(0, root.barHeight) : 0

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
  // nothing; switching one there and back moves its windows. Anchored to the
  // top like the notch: with the host's bar at the bottom, both sit at the
  // screen edge.
  Variants {
    model: reserve.space > 0 ? Quickshell.screens : []
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: !root.svc || root.svc.showsOn(modelData)
      anchors { top: true; left: true; right: true }
      implicitHeight: reserve.space
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: reserve.space
      // Overlay, so it is arranged after the bar (top layer) and stacks
      // under it rather than pushing the bar down.
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

    // Input region: the notch plus some slack so the small rest lip is easy
    // to hover; while pinned, everything below the bar, to click away.
    readonly property real slack: Theme.space(root.mode === "rest" ? 10 : 4)
    Item {
      id: hitArea
      x: root.pinned ? 0 : card.x - window.slack
      y: root.pinned ? root.topOffset : card.y
      width: root.pinned ? window.width : (root.concealed ? 0 : card.width + window.slack * 2)
      height: root.pinned ? Math.max(0, window.height - root.topOffset) : (root.concealed ? 0 : card.height + window.slack * 2)
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
      x: card.x - window.slack
      y: card.y
      width: root.concealed ? 0 : card.width + window.slack * 2
      height: root.concealed ? 0 : card.height + window.slack * 2
      HoverHandler {
        onHoveredChanged: if (root.svc) root.svc.setPointer("notch-slack", hovered, window.screenName)
      }
    }

    NotchCard {
      id: card
      svc: root.svc
      maxWidth: window.width - Theme.space(64)
      x: Math.round((window.width - width) / 2)
      y: root.topOffset
      opacity: root.concealed ? 0 : 1
      onHoveredChanged: if (root.svc) root.svc.setPointer("notch", card.hovered, window.screenName)
      Behavior on opacity { NumberAnimation { duration: 160 } }
    }
  }
}
