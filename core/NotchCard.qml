import QtQuick
import QtQuick.Shapes

// The notch itself: its outline, its padding per mode and the view of the
// current mode, springing to fit. It draws; NotchSurface puts it on screen
// (layer-shell window, input mask, screen choice). Being a plain Item, it
// also renders offscreen, which is how tests/visual and the README image
// show the real thing.
Item {
  id: card

  property var svc: null
  // Width the notch may grow to (the screen, less some margin).
  property real maxWidth: Theme.space(1200)

  // ------------------------------------------------------------------ mode
  readonly property string svcMode: card.svc ? card.svc.mode : "rest"
  readonly property bool barStyle: !!card.svc && card.svc.compactStyle === "bar"
  // What the notch shows: in bar style, rest and compact belong to the bar.
  readonly property string mode: (card.barStyle && (card.svcMode === "rest" || card.svcMode === "compact"))
    ? "hidden" : card.svcMode

  readonly property Component modeComponent: {
    if (!card.svc) return restView
    if (card.mode === "peek" && card.svc.peekModule) return card.svc.peekModule.peek
    if (card.mode === "expanded") return expandedView
    if (card.mode === "compact" && card.svc.compactModule && card.svc.compactModule.compact)
      return card.svc.compactModule.compact
    return restView
  }

  // Fade the old content out, swap, then fade the new one in while the
  // outline springs to its size.
  property Component shownComponent: null
  // The mode the shown content belongs to; it trails `mode` by the fade, so
  // it matches targetHeight while `mode` may already have moved on. Both
  // change in one step; `swapping` is true in between, when they don't match.
  property string shownMode: ""
  property bool swapping: false
  onModeComponentChanged: swapAnim.restart()
  Component.onCompleted: { card.shownComponent = card.modeComponent; card.shownMode = card.mode }

  SequentialAnimation {
    id: swapAnim
    NumberAnimation { target: content; property: "opacity"; to: 0; duration: 70 }
    ScriptAction {
      script: {
        card.swapping = true
        card.shownComponent = card.modeComponent
        card.shownMode = card.mode
        card.swapping = false
      }
    }
    NumberAnimation { target: content; property: "opacity"; to: 1; duration: 180 }
  }

  // -------------------------------------------------------------- geometry
  readonly property bool roomy: card.mode === "peek" || card.mode === "compact" || card.mode === "expanded"
  readonly property real padX: !card.roomy ? 0 : Theme.space(card.mode === "expanded" ? 20 : 14)
  // Compact stays close to a bar's height: it hangs there all the time.
  readonly property real compactPadTop: Theme.space(4)
  readonly property real compactPadBottom: Theme.space(6)
  readonly property real padTop: !card.roomy ? 0
    : card.mode === "expanded" ? Theme.space(14) : card.mode === "peek" ? Theme.space(6) : card.compactPadTop
  readonly property real padBottom: !card.roomy ? 0
    : card.mode === "expanded" ? Theme.space(18) : card.mode === "peek" ? Theme.space(8) : card.compactPadBottom
  readonly property real cornerRadius: !card.roomy ? 0
    : Theme.space(card.mode === "expanded" ? 26 : card.mode === "peek" ? 16 : 12)
  // The concave flare into the bar, drawn outside the card's own width.
  readonly property real shoulder: Theme.space(10)

  readonly property real targetWidth: Math.min(card.maxWidth, (content.item ? (content.item as Item).implicitWidth : 0) + card.padX * 2)
  readonly property real targetHeight: (content.item ? (content.item as Item).implicitHeight : 0) + card.padTop + card.padBottom
  // Height of the closed notch while it shows a compact view, else 0. The
  // padding follows `mode` at once (the outline springs while the content
  // fades), so this adds the compact padding itself.
  readonly property real compactHeight: !card.swapping && card.shownMode === "compact" && content.item
    ? (content.item as Item).implicitHeight + card.compactPadTop + card.compactPadBottom : 0

  width: card.targetWidth
  height: card.targetHeight
  // The width springs past its target; the height settles without
  // overshoot so a shrinking notch never dips below zero.
  Behavior on width { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
  Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }

  // ----------------------------------------------------------------- views
  Component {
    id: restView
    Item {
      implicitWidth: Theme.space(120)
      implicitHeight: Theme.space(5)
    }
  }

  Component {
    id: expandedView
    Column {
      spacing: Theme.space(6)

      Column {
        id: expandedStack
        spacing: Theme.space(16)

        Repeater {
          model: card.svc ? card.svc.expandedModules : []
          delegate: Loader {
            required property var modelData
            width: Theme.space(400)
            sourceComponent: modelData.expanded
          }
        }

        // Nothing active: say so instead of opening an empty card.
        Column {
          visible: !card.svc || card.svc.expandedModules.length === 0
          width: Theme.space(260)
          spacing: Theme.space(2)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: "All quiet"
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
      }

      // Footer: the gear opens the settings window (and closes the notch,
      // which would otherwise sit over it).
      Item {
        width: expandedStack.width
        implicitHeight: gear.implicitHeight
        Text {
          id: gear
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: String.fromCodePoint(0xF0493)  // nf-md-cog
          color: gearArea.containsMouse ? Theme.foreground : Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.heading
          MouseArea {
            id: gearArea
            anchors.fill: parent
            anchors.margins: -Theme.space(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (card.svc) { card.svc.close(); card.svc.openSettings() }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- drawing
  // One outline: concave shoulders flaring into the bar, rounded bottom.
  Shape {
    id: outline
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    readonly property real w: Math.max(0, card.width)
    readonly property real h: Math.max(0, card.height)
    readonly property real s: Math.min(card.shoulder, h / 2)
    readonly property real r: Math.min(Math.max(card.cornerRadius, card.roomy ? 0 : h / 2), h / 2, w / 2)

    ShapePath {
      fillColor: Theme.background
      strokeColor: "transparent"
      startX: -card.shoulder; startY: 0
      PathQuad { x: 0; y: outline.s; controlX: 0; controlY: 0 }
      PathLine { x: 0; y: outline.h - outline.r }
      PathQuad { x: outline.r; y: outline.h; controlX: 0; controlY: outline.h }
      PathLine { x: outline.w - outline.r; y: outline.h }
      PathQuad { x: outline.w; y: outline.h - outline.r; controlX: outline.w; controlY: outline.h }
      PathLine { x: outline.w; y: outline.s }
      PathQuad { x: outline.w + card.shoulder; y: 0; controlX: outline.w; controlY: 0 }
      PathLine { x: -card.shoulder; y: 0 }
    }

    // Hairline on the sides and bottom only, so the notch reads against
    // dark windows without drawing a seam where it meets the bar.
    ShapePath {
      fillColor: "transparent"
      strokeColor: card.roomy ? Theme.line : "transparent"
      strokeWidth: 1
      startX: -card.shoulder; startY: 0
      PathQuad { x: 0; y: outline.s; controlX: 0; controlY: 0 }
      PathLine { x: 0; y: outline.h - outline.r }
      PathQuad { x: outline.r; y: outline.h; controlX: 0; controlY: outline.h }
      PathLine { x: outline.w - outline.r; y: outline.h }
      PathQuad { x: outline.w; y: outline.h - outline.r; controlX: outline.w; controlY: outline.h }
      PathLine { x: outline.w; y: outline.s }
      PathQuad { x: outline.w + card.shoulder; y: 0; controlX: outline.w; controlY: 0 }
    }
  }

  // Click toggles pinned; controls inside the views take their own clicks.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (card.svc) card.svc.togglePinned("")
  }

  Item {
    anchors.fill: parent
    clip: true

    Loader {
      id: content
      anchors.horizontalCenter: parent.horizontalCenter
      y: card.padTop
      sourceComponent: card.shownComponent
    }
  }
}
