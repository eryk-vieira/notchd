import QtQuick
import QtQuick.Shapes

// The notch itself: its outline, its padding per mode and the view of the
// current mode, springing to fit. It draws; NotchSurface puts it on screen
// (layer-shell window, input mask, screen choice). Being a plain Item, it
// also renders offscreen, which is how tests/visual and the README image
// show the real thing.
//
// It hangs from one screen edge (`edge`) and thinks in two axes: *along*
// the edge and *depth* away from it. The outline is drawn for the top edge
// and turned onto the others; the content never turns.
Item {
  id: card

  // The notch copy it draws (NotchCopy): its mode, modules and edge.
  property var notch: null
  // The screen edge it hangs from: "top", "bottom", "left" or "right".
  property string edge: card.notch && card.notch.edge ? card.notch.edge : "top"
  readonly property bool vertical: card.edge === "left" || card.edge === "right"
  // Whether it can be dragged: held for `holdToDrag` ms, a press picks it up
  // and moving then drags it; a quick click never moves it. The card only
  // reports the drag (in its window's coordinates); whoever places it
  // decides where it goes.
  property bool draggable: false
  property int holdToDrag: 250
  readonly property bool dragging: pressArea.dragging
  signal dragStarted()
  signal dragMoved(point scenePosition)
  signal dragEnded()

  // The pointer is on the card. Here, not on an item beside it, so the
  // controls inside the views (which take hover themselves) never hide it.
  readonly property bool hovered: hover.hovered
  HoverHandler { id: hover }
  // Size the notch may grow to (the screen, less some margin).
  property real maxWidth: Theme.space(1200)
  property real maxHeight: Theme.space(1200)

  // ------------------------------------------------------------------ mode
  readonly property string notchMode: card.notch ? card.notch.mode : "rest"
  readonly property bool barStyle: !!card.notch && card.notch.compactStyle === "bar"
  // What the notch shows: in bar style, rest and compact belong to the bar.
  readonly property string mode: (card.barStyle && (card.notchMode === "rest" || card.notchMode === "compact"))
    ? "hidden" : card.notchMode

  // On a side edge, compact shows the module's `verticalCompact` (a module
  // without one gets a dot) and peek its `verticalPeek`, if it has one.
  readonly property var peekModule: card.notch ? card.notch.peekModule : null
  readonly property bool verticalPeek: card.vertical && !!card.peekModule && !!card.peekModule.verticalPeek
  readonly property Component modeComponent: {
    if (!card.notch) return restView
    if (card.mode === "peek" && card.peekModule)
      return card.verticalPeek ? card.peekModule.verticalPeek : card.peekModule.peek
    if (card.mode === "expanded") return expandedView
    var m = card.notch.compactModule
    if (card.mode === "compact" && m && m.compact)
      return !card.vertical ? m.compact : (m.verticalCompact || dotView)
    return restView
  }

  // Fade the old content out, swap, then fade the new one in while the
  // outline springs to its size.
  property Component shownComponent: null
  // The mode the shown content belongs to; it trails `mode` by the fade, so
  // it matches targetDepth while `mode` may already have moved on. Both
  // change in one step; `swapping` is true in between, when they don't match.
  property string shownMode: ""
  // Whether the shown content was laid out for a side edge; it trails
  // `vertical` the same way.
  property bool shownVertical: false
  property bool swapping: false
  onModeComponentChanged: swapAnim.restart()
  onVerticalChanged: swapAnim.restart()
  Component.onCompleted: {
    card.shownComponent = card.modeComponent
    card.shownMode = card.mode
    card.shownVertical = card.vertical
  }

  SequentialAnimation {
    id: swapAnim
    NumberAnimation { target: content; property: "opacity"; to: 0; duration: 70 }
    ScriptAction {
      script: {
        card.swapping = true
        card.shownComponent = card.modeComponent
        card.shownMode = card.mode
        card.shownVertical = card.vertical
        card.swapping = false
      }
    }
    NumberAnimation { target: content; property: "opacity"; to: 1; duration: 180 }
  }

  // -------------------------------------------------------------- geometry
  // Padding by axis: `padSide` at both ends along the edge, `padNear` on the
  // edge's side, `padFar` on the open side (which has the round corners).
  readonly property bool roomy: card.mode === "peek" || card.mode === "compact" || card.mode === "expanded"
  readonly property real padSide: !card.roomy ? 0 : Theme.space(card.mode === "expanded" ? 20 : 14)
  // Compact stays close to a bar's height: it hangs there all the time.
  readonly property real compactPadNear: Theme.space(4)
  readonly property real compactPadFar: Theme.space(6)
  readonly property real padNear: !card.roomy ? 0
    : card.mode === "expanded" ? Theme.space(14) : card.mode === "peek" ? Theme.space(6) : card.compactPadNear
  readonly property real padFar: !card.roomy ? 0
    : card.mode === "expanded" ? Theme.space(18) : card.mode === "peek" ? Theme.space(8) : card.compactPadFar
  readonly property real cornerRadius: !card.roomy ? 0
    : Theme.space(card.mode === "expanded" ? 26 : card.mode === "peek" ? 16 : 12)
  // The lip shown at rest, nothing active: its depth and length.
  readonly property real restDepth: Theme.space(5)
  readonly property real restLength: Theme.space(120)
  // The concave flare into the edge, drawn outside the card at both ends.
  readonly property real shoulder: Theme.space(10)

  // The padding the card uses. Rest, compact and vertical peek views run
  // along the edge, so on a side edge the padding turns with it. Other peek
  // and expanded views stay wide on every edge, so on a side edge they keep
  // their padding by screen axis: `padSide` left and right, `padFar` above
  // and below.
  readonly property bool turnedPadding: !card.vertical || card.mode === "rest" || card.mode === "compact"
    || (card.mode === "peek" && card.verticalPeek)
  readonly property real alongPad: card.turnedPadding ? card.padSide : card.padFar
  readonly property real nearPad: card.turnedPadding ? card.padNear : card.padSide
  readonly property real farPad: card.turnedPadding ? card.padFar : card.padSide

  readonly property real contentWidth: content.item ? (content.item as Item).implicitWidth : 0
  readonly property real contentHeight: content.item ? (content.item as Item).implicitHeight : 0
  // Whole pixels, and an even length, so the card centred on a whole pixel
  // settles on whole pixels too: crisp edges at rest. In between, the
  // springs run in fractions of a pixel.
  readonly property real targetAlong: 2 * Math.ceil(Math.min(card.vertical ? card.maxHeight : card.maxWidth,
    (card.vertical ? card.contentHeight : card.contentWidth) + card.alongPad * 2) / 2)
  readonly property real targetDepth: Math.ceil(Math.min(card.vertical ? card.maxWidth : card.maxHeight,
    (card.vertical ? card.contentWidth : card.contentHeight) + card.nearPad + card.farPad))
  // Depth of the closed notch while it shows a compact view, else 0. The
  // padding follows `mode` at once (the outline springs while the content
  // fades), so this adds the compact padding itself.
  readonly property real compactDepth: !card.swapping && card.shownMode === "compact"
    && card.shownVertical === card.vertical && content.item
    ? (card.vertical ? card.contentWidth : card.contentHeight) + card.compactPadNear + card.compactPadFar : 0

  // The length springs past its target; the depth settles without
  // overshoot so a shrinking notch never dips below zero.
  property real along: card.targetAlong
  property real depth: card.targetDepth
  Behavior on along { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
  Behavior on depth { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }

  width: card.vertical ? card.depth : card.along
  height: card.vertical ? card.along : card.depth

  // ----------------------------------------------------------------- views
  Component {
    id: restView
    Item {
      implicitWidth: card.vertical ? card.restDepth : card.restLength
      implicitHeight: card.vertical ? card.restLength : card.restDepth
    }
  }

  // Compact on a side edge for a module without a `verticalCompact`.
  Component {
    id: dotView
    Item {
      implicitWidth: Theme.space(6)
      implicitHeight: Theme.space(24)
      Rectangle {
        anchors.centerIn: parent
        width: Theme.space(6)
        height: width
        radius: width / 2
        color: Theme.accent
      }
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
          model: card.notch ? card.notch.expandedModules : []
          delegate: Loader {
            required property var modelData
            width: Theme.space(400)
            sourceComponent: modelData.expanded
          }
        }

        // Nothing active: say so instead of opening an empty card.
        Column {
          visible: !card.notch || card.notch.expandedModules.length === 0
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
            onClicked: if (card.notch) { card.notch.close(); card.notch.openSettings() }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- drawing
  // One outline, drawn for the top edge (x along, y depth): concave
  // shoulders flaring into the edge, rounded far side. `transform` turns it
  // onto the card's edge.
  Shape {
    id: outline
    width: outline.w
    height: outline.h
    preferredRendererType: Shape.CurveRenderer
    readonly property real w: Math.max(0, card.along)
    readonly property real h: Math.max(0, card.depth)
    readonly property real s: Math.min(card.shoulder, h / 2)
    readonly property real r: Math.min(Math.max(card.cornerRadius, card.roomy ? 0 : h / 2), h / 2, w / 2)
    // (x, y) -> top: (x, y), bottom: (x, h - y), left: (y, x), right: (h - y, x).
    transform: Matrix4x4 {
      matrix: card.edge === "bottom" ? Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, outline.h,  0, 0, 1, 0,  0, 0, 0, 1)
        : card.edge === "left" ? Qt.matrix4x4(0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
        : card.edge === "right" ? Qt.matrix4x4(0, -1, 0, outline.h,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
        : Qt.matrix4x4()
    }

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

    // Hairline on the open sides only, so the notch reads against dark
    // windows without drawing a seam where it meets the edge.
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
  // Held long enough (pressAndHold, cancelled by moving first), the press
  // picks the notch up instead, and the release drops it rather than
  // counting as a click.
  MouseArea {
    id: pressArea
    property bool dragging: false
    anchors.fill: parent
    cursorShape: pressArea.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    pressAndHoldInterval: card.holdToDrag
    // Accepting it (the default) also stops the release from clicking; not
    // draggable, a long press still pins.
    onPressAndHold: function(mouse) {
      if (!card.draggable) { mouse.accepted = false; return }
      pressArea.dragging = true
      card.dragStarted()
    }
    onPositionChanged: function(mouse) {
      if (pressArea.dragging) card.dragMoved(pressArea.mapToItem(null, mouse.x, mouse.y))
    }
    onReleased: if (pressArea.dragging) { pressArea.dragging = false; card.dragEnded() }
    onCanceled: if (pressArea.dragging) { pressArea.dragging = false; card.dragEnded() }
    onClicked: if (card.notch && !pressArea.dragging) card.notch.togglePinned("")
  }

  Item {
    anchors.fill: parent
    clip: true

    // Against the edge past `nearPad`, centered along it, on whole pixels of
    // the card's parent so text stays sharp while the card itself sits on
    // fractions of a pixel (Position.place).
    Loader {
      id: content
      x: Math.round(card.x + (card.edge === "left" ? card.nearPad
        : card.edge === "right" ? card.width - card.nearPad - width : (card.width - width) / 2)) - card.x
      y: Math.round(card.y + (card.edge === "top" ? card.nearPad
        : card.edge === "bottom" ? card.height - card.nearPad - height : (card.height - height) / 2)) - card.y
      sourceComponent: card.shownComponent
    }
  }
}
