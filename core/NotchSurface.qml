import QtQuick
import Quickshell
import Quickshell.Wayland

// Puts the notch on screen: a layer-shell overlay at the top edge of the
// focused screen (under the host's bar, if it has one). All state lives in
// NotchService and NotchCard draws it; this picks the screen, places the
// card and routes the pointer. With compactStyle "bar" the card hides at
// rest/compact (the host's bar indicator shows that) and drops out from
// under the bar to peek or expand.
//
// The window covers the whole screen on the overlay layer but its input mask
// is just the notch, so everything else stays click-through.
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
