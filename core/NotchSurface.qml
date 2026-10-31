import QtQuick
import Quickshell
import Quickshell.Wayland
import "State.js" as State

// Puts the notch on screen: a layer-shell overlay at the top edge of the
// focused screen (under the host's bar, if it has one). All state lives in
// NotchService and NotchCard draws it; this picks the screen, places the
// card and routes the pointer. With compactStyle "bar" the card hides at
// rest/compact (the host's bar indicator shows that) and drops out from
// under the bar to peek or expand.
//
// The window covers the whole screen on the overlay layer but its input mask
// is just the notch, so everything else stays click-through.
//
// With reserveSpace on, a second, empty window per screen holds a layer-shell
// exclusive zone as deep as a compact notch, so windows tile below it. The
// compositor stacks it under the host bar's own zone, where the notch hangs.
Item {
  id: root

  // ------------------------------------------------------------------ host
  property var svc: null
  // A compositor adapter (HyprlandCompositor, GenericCompositor, ...).
  property var compositor: null
  // The host's bar, so the notch hangs right under it. barHeight 0 = no bar.
  property int barHeight: 0
  property bool barOnTop: true
  property bool barHidden: false
  property string layerNamespace: "notchd"

  // What the notch shows (NotchCard.mode): the service's mode, or "hidden".
  readonly property string mode: card.mode

  // -------------------------------------------------------------- geometry
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var wanted = root.svc && root.svc.screenOverride !== "" ? root.svc.screenOverride
      : (root.compositor ? root.compositor.focusedScreenName : "")
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === wanted) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }
  readonly property bool fullscreenOnScreen: !!(root.compositor && root.targetScreen
    && root.compositor.hasFullscreen(root.targetScreen))

  // The bar hides over fullscreen apps, so the notch moves up with it.
  readonly property bool barVisible: !root.fullscreenOnScreen && !root.barHidden
  readonly property int topOffset: (root.barOnTop && root.barVisible) ? Math.max(0, root.barHeight) : 0

  // Hidden in bar style at rest/compact; over a fullscreen app only peeks show.
  readonly property bool concealed: root.mode === "hidden"
    || (root.fullscreenOnScreen && (root.mode === "rest" || root.mode === "compact"))
  readonly property bool pinned: !!root.svc && root.svc.pinned

  // ------------------------------------------------------- reserved space
  // A media compact view's height (22) plus the card's compact padding.
  readonly property real compactBaseline: Theme.space(22) + card.compactPadTop + card.compactPadBottom
  // The tallest compact view shown so far; reset when the theme rescales.
  property real tallestCompact: 0
  onCompactBaselineChanged: root.tallestCompact = 0
  readonly property int reservedSpace: State.reservedSpace({
    enabled: !!root.svc && root.svc.reserveSpace,
    compactStyle: root.svc ? root.svc.compactStyle : "",
    baseline: root.compactBaseline,
    tallest: root.tallestCompact
  })

  readonly property real compactHeight: card.compactHeight
  onCompactHeightChanged: if (root.compactHeight > root.tallestCompact) root.tallestCompact = root.compactHeight

  // Every screen, not just the notch's: it follows focus, and reserving only
  // there would reflow both screens on each focus change. Anchored to the
  // top like the notch: with the host's bar at the bottom, both sit at the
  // screen edge.
  Variants {
    model: root.reservedSpace > 0 ? Quickshell.screens : []
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; left: true; right: true }
      implicitHeight: root.reservedSpace
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: root.reservedSpace
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

    Item {
      id: hoverZone
      x: card.x - window.slack
      y: card.y
      width: root.concealed ? 0 : card.width + window.slack * 2
      height: root.concealed ? 0 : card.height + window.slack * 2
      HoverHandler {
        onHoveredChanged: if (root.svc) root.svc.setPointer("notch", hovered, "")
      }
    }

    NotchCard {
      id: card
      svc: root.svc
      maxWidth: window.width - Theme.space(64)
      x: Math.round((window.width - width) / 2)
      y: root.topOffset
      opacity: root.concealed ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 160 } }
    }
  }
}
