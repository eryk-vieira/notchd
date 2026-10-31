import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons

// The notch surface under the bar. All state lives in Service.qml; this only
// draws it. With compactStyle "bar" it hides at rest/compact (the bar
// indicator shows that) and drops out from under the bar to peek or expand.
//
// The window covers the whole screen on the overlay layer but its input mask
// is just the notch, so everything else stays click-through.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Injected by the shell when the service is up; looked up otherwise.
  property var service: null
  readonly property var svc: root.service

  Timer {
    interval: 200
    repeat: true
    running: !root.service && !!root.shell
    onTriggered: root.service = root.shell.serviceFor("eryk.notch")
  }

  // The shell calls these when the overlay is summoned/hidden.
  function open() { if (root.svc) root.svc.open() }
  function close() { if (root.svc) root.svc.close() }

  // ----------------------------------------------------------------- theme
  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property string fontFamily: Style.font.family

  // ------------------------------------------------------------------ mode
  readonly property string svcMode: root.svc ? root.svc.mode : "rest"
  readonly property bool barStyle: !!root.svc && root.svc.compactStyle === "bar"
  // What this surface shows: in bar style, rest and compact belong to the bar.
  readonly property string mode: (root.barStyle && (root.svcMode === "rest" || root.svcMode === "compact"))
    ? "hidden" : root.svcMode

  readonly property Component modeComponent: {
    if (!root.svc) return restView
    if (root.mode === "peek" && root.svc.peekModule) return root.svc.peekModule.peek
    if (root.mode === "expanded") return expandedView
    if (root.mode === "compact" && root.svc.compactModule && root.svc.compactModule.compact)
      return root.svc.compactModule.compact
    return restView
  }

  // Fade the old content out, swap, then fade the new one in while the
  // outline springs to its size.
  property Component shownComponent: null
  onModeComponentChanged: swapAnim.restart()
  Component.onCompleted: root.shownComponent = root.modeComponent

  SequentialAnimation {
    id: swapAnim
    NumberAnimation { target: content; property: "opacity"; to: 0; duration: 70 }
    ScriptAction { script: root.shownComponent = root.modeComponent }
    NumberAnimation { target: content; property: "opacity"; to: 1; duration: 180 }
  }

  // -------------------------------------------------------------- geometry
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var wanted = root.svc && root.svc.screenOverride !== "" ? root.svc.screenOverride
      : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === wanted) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }
  readonly property var targetMonitor: root.targetScreen ? Hyprland.monitorFor(root.targetScreen) : null
  readonly property bool fullscreenOnScreen: !!(root.targetMonitor && root.targetMonitor.activeWorkspace
    && root.targetMonitor.activeWorkspace.hasFullscreen)

  readonly property int barSize: root.shell && root.shell.bar ? Math.max(0, Number(root.shell.bar.barSize) || 0) : 0
  readonly property string barPosition: root.shell && root.shell.bar ? String(root.shell.bar.position || "top") : "top"
  readonly property bool barVisible: !root.fullscreenOnScreen && (root.shell && root.shell.bar ? !root.shell.bar.barHidden : true)
  readonly property int topOffset: (root.barPosition === "top" && root.barVisible)
    ? (root.barSize > 0 ? root.barSize : Style.bar.sizeHorizontal) : 0

  // Hidden in bar style at rest/compact; over a fullscreen app only peeks show.
  readonly property bool concealed: root.mode === "hidden"
    || (root.fullscreenOnScreen && (root.mode === "rest" || root.mode === "compact"))
  readonly property bool pinned: !!root.svc && root.svc.pinned

  readonly property bool roomy: root.mode === "peek" || root.mode === "compact" || root.mode === "expanded"
  readonly property real padX: !root.roomy ? 0 : Style.space(root.mode === "expanded" ? 20 : 14)
  readonly property real padTop: !root.roomy ? 0 : Style.space(root.mode === "expanded" ? 14 : 6)
  readonly property real padBottom: !root.roomy ? 0 : Style.space(root.mode === "expanded" ? 18 : 8)
  readonly property real cornerRadius: !root.roomy ? 0 : Style.space(root.mode === "expanded" ? 26 : 16)
  readonly property real shoulder: Style.space(10)

  readonly property real maxWidth: window.width - Style.space(64)
  readonly property real targetWidth: Math.min(root.maxWidth, (content.item ? content.item.implicitWidth : 0) + root.padX * 2)
  readonly property real targetHeight: (content.item ? content.item.implicitHeight : 0) + root.padTop + root.padBottom

  // ----------------------------------------------------------------- views
  Component {
    id: restView
    Item {
      implicitWidth: Style.space(120)
      implicitHeight: Style.space(5)
    }
  }

  Component {
    id: expandedView
    Column {
      spacing: Style.space(16)

      Repeater {
        model: root.svc ? root.svc.expandedModules : []
        delegate: Loader {
          required property var modelData
          width: Style.space(400)
          sourceComponent: modelData.expanded
        }
      }

      // Nothing active: say so instead of opening an empty card.
      Column {
        visible: !root.svc || root.svc.expandedModules.length === 0
        width: Style.space(260)
        spacing: Style.space(2)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: Qt.formatDate(new Date(), "dddd, d MMMM")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "All quiet"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---------------------------------------------------------------- window
  PanelWindow {
    id: window
    screen: root.targetScreen

    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "eryk-notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region { item: hitArea }

    // Input region: the notch plus some slack so the small rest lip is easy
    // to hover; while pinned, everything below the bar, to click away.
    readonly property real slack: Style.space(root.mode === "rest" ? 10 : 4)
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
      onClicked: root.close()
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

    Item {
      id: card
      x: Math.round((window.width - width) / 2)
      y: root.topOffset
      width: root.targetWidth
      height: root.targetHeight
      opacity: root.concealed ? 0 : 1

      // The width springs past its target; the height settles without
      // overshoot so a shrinking notch never dips below zero.
      Behavior on width { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
      Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      // One outline: concave shoulders flaring into the bar, rounded bottom.
      Shape {
        id: outline
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real w: Math.max(0, card.width)
        readonly property real h: Math.max(0, card.height)
        readonly property real s: Math.min(root.shoulder, h / 2)
        readonly property real r: Math.min(Math.max(root.cornerRadius, root.roomy ? 0 : h / 2), h / 2, w / 2)

        ShapePath {
          fillColor: root.bg
          strokeColor: "transparent"
          startX: -root.shoulder; startY: 0
          PathQuad { x: 0; y: outline.s; controlX: 0; controlY: 0 }
          PathLine { x: 0; y: outline.h - outline.r }
          PathQuad { x: outline.r; y: outline.h; controlX: 0; controlY: outline.h }
          PathLine { x: outline.w - outline.r; y: outline.h }
          PathQuad { x: outline.w; y: outline.h - outline.r; controlX: outline.w; controlY: outline.h }
          PathLine { x: outline.w; y: outline.s }
          PathQuad { x: outline.w + root.shoulder; y: 0; controlX: outline.w; controlY: 0 }
          PathLine { x: -root.shoulder; y: 0 }
        }

        // Hairline on the sides and bottom only, so the notch reads against
        // dark windows without drawing a seam where it meets the bar.
        ShapePath {
          fillColor: "transparent"
          strokeColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.roomy ? 0.14 : 0)
          strokeWidth: 1
          startX: -root.shoulder; startY: 0
          PathQuad { x: 0; y: outline.s; controlX: 0; controlY: 0 }
          PathLine { x: 0; y: outline.h - outline.r }
          PathQuad { x: outline.r; y: outline.h; controlX: 0; controlY: outline.h }
          PathLine { x: outline.w - outline.r; y: outline.h }
          PathQuad { x: outline.w; y: outline.h - outline.r; controlX: outline.w; controlY: outline.h }
          PathLine { x: outline.w; y: outline.s }
          PathQuad { x: outline.w + root.shoulder; y: 0; controlX: outline.w; controlY: 0 }
        }
      }

      // Click toggles pinned; controls inside the views take their own clicks.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.svc) root.svc.togglePinned("")
      }

      Item {
        anchors.fill: parent
        clip: true

        Loader {
          id: content
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.padTop
          sourceComponent: root.shownComponent
        }
      }
    }
  }
}
