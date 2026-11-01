import QtQuick
import QtQuick.Shapes
import "Outline.js" as Outline

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

  // Escape and Ctrl+Escape close it. Keys reach it while its window has the
  // keyboard (pinned open): from a field inside a view, which leaves Escape
  // alone, or the card itself, which holds the focus otherwise. A terminal
  // keeps Escape and lets Ctrl+Escape out (Terminal.isLeaveKey).
  focus: true
  Keys.onEscapePressed: if (card.notch) card.notch.close()
  // How each end of the card along the edge meets what is beside it
  // (Outline.js): "shoulder" flares into the edge, "corner" sits flush and
  // square against the screen's side, "joined" sits flush with a
  // neighbor notch so the two read as one. The start is the left end on a
  // top or bottom edge, the top end on a side edge. Whoever places the card
  // decides (NotchWindow, from Position.place and Position.pack).
  property string startSide: "shoulder"
  property string endSide: "shoulder"
  // A joined neighbor's depth, for the step down to a shallower one (only
  // while depths spring: a joined row shares one depth, `minDepth`).
  property real startNeighborDepth: 0
  property real endNeighborDepth: 0
  // At least this deep: a joined row takes its deepest notch's depth
  // (Position.rowDepths), the content centered in what it adds.
  property real minDepth: 0
  // Size the notch may grow to (the screen, less some margin).
  property real maxWidth: Theme.space(1200)
  property real maxHeight: Theme.space(1200)

  // ------------------------------------------------------------------ mode
  readonly property string mode: card.notch ? card.notch.mode : "rest"

  // On a side edge, compact shows the module's `verticalCompact` (a module
  // without one gets a dot) and peek its `verticalPeek`, if it has one.
  readonly property var peekModule: card.notch ? card.notch.peekModule : null
  readonly property bool verticalPeek: card.vertical && !!card.peekModule && !!card.peekModule.verticalPeek
  readonly property Component modeComponent: {
    if (!card.notch) return restView
    if (card.mode === "peek" && card.peekModule)
      return card.verticalPeek ? card.peekModule.verticalPeek : card.peekModule.peek
    if (card.mode === "expanded") return expandedView
    // With tabs, every active module side by side; an idle one as its icon
    // (State.compactModules).
    var several = card.notch.compactModules || []
    if (card.mode === "compact" && (several.length > 1 || (several.length === 1 && !several[0].compact)))
      return compactRowView
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
    card.trackClosedDepth()
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
  // Its own depth, from its content; a joined row may make it deeper.
  readonly property real naturalDepth: Math.ceil(Math.min(card.vertical ? card.maxWidth : card.maxHeight,
    (card.vertical ? card.contentWidth : card.contentHeight) + card.nearPad + card.farPad))
  readonly property real targetDepth: Math.max(card.naturalDepth,
    Math.ceil(Math.min(card.vertical ? card.maxWidth : card.maxHeight, card.minDepth)))
  // Its own depth closed, held while it is open and while its content
  // swaps: what a joined row goes by (Position.rowDepths). Read live, a
  // closing peek's depth (its content still fading out) made the row grow
  // for a moment and shrink back, as if about to open.
  property real closedDepth: 0
  function trackClosedDepth() {
    if (!card.swapping && card.shownMode === card.mode && card.shownVertical === card.vertical
        && (card.mode === "rest" || card.mode === "compact"))
      card.closedDepth = card.naturalDepth
  }
  onNaturalDepthChanged: card.trackClosedDepth()
  onSwappingChanged: card.trackClosedDepth()
  onShownModeChanged: card.trackClosedDepth()
  // Made deeper by its row: shown like a compact notch even at rest, so the
  // row's outline and corners run through it.
  readonly property bool stretched: card.targetDepth > card.naturalDepth
  // Half of what the row adds, moving the content off the edge so it stays
  // centered; it springs with the depth.
  property real contentShift: Math.max(0, card.targetDepth - card.naturalDepth) / 2
  Behavior on contentShift { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
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

  // Several modules' compact views in one closed notch (a notch with tabs):
  // side by side, a thin line between them; down a side edge, one under
  // the other, each its vertical view (or a dot). A module with nothing to
  // show closed shows its icon (NotchModule.icon, the notch's idleIcons).
  Component {
    id: compactRowView
    Grid {
      id: compactRow
      readonly property var modules: card.notch ? (card.notch.compactModules || []) : []
      columns: card.vertical ? 1 : Math.max(1, compactRow.modules.length * 2 - 1)
      columnSpacing: Theme.space(10)
      rowSpacing: Theme.space(8)
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter
      Repeater {
        // A module, then a line before the next: [m0, line, m1, line, m2].
        model: Math.max(0, compactRow.modules.length * 2 - 1)
        delegate: Item {
          id: slot
          required property int index
          readonly property var module: slot.index % 2 === 0 ? compactRow.modules[slot.index / 2] : null
          readonly property Component view: !slot.module ? lineView
            : !slot.module.compact ? null
            : card.vertical ? (slot.module.verticalCompact || dotView) : slot.module.compact
          implicitWidth: slot.view ? slotView.implicitWidth : slotIcon.implicitWidth
          implicitHeight: slot.view ? slotView.implicitHeight : slotIcon.implicitHeight
          Loader {
            id: slotView
            anchors.centerIn: parent
            sourceComponent: slot.view
          }
          Text {
            id: slotIcon
            anchors.centerIn: parent
            visible: !slot.view
            textFormat: Text.PlainText
            text: slot.module && !slot.view ? slot.module.icon : ""
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body + 2
          }
        }
      }
      Component {
        id: lineView
        Rectangle {
          implicitWidth: card.vertical ? Theme.space(14) : 1
          implicitHeight: card.vertical ? 1 : Theme.space(14)
          color: Theme.line
        }
      }
    }
  }

  // How tall the content may be: the room the card has, less its padding.
  // The expanded view scrolls what doesn't fit.
  readonly property real contentRoom: Math.max(0, card.maxHeight
    - (card.vertical && !card.turnedPadding ? 2 * card.alongPad : card.nearPad + card.farPad))

  Component {
    id: expandedView
    Column {
      id: expanded
      spacing: Theme.space(10)
      // Every expanded module, one above the other; with the notch's `tabs`,
      // the one whose tab is picked (State.shownModules).
      readonly property var shown: card.notch ? (card.notch.shownModules || card.notch.expandedModules || []) : []
      readonly property var tabs: card.notch ? (card.notch.tabModules || []) : []

      // The tabs: a module's title each, the picked one raised.
      Row {
        id: tabRow
        visible: expanded.tabs.length > 0
        spacing: Theme.space(4)
        Repeater {
          model: expanded.tabs
          delegate: Rectangle {
            id: tab
            required property var modelData
            readonly property bool picked: expanded.shown.indexOf(tab.modelData) !== -1
            width: tabLabel.implicitWidth + Theme.space(24)
            height: tabLabel.implicitHeight + Theme.space(10)
            radius: Theme.radiusSmall
            color: tab.picked ? Theme.selected : tabMouse.containsMouse ? Theme.hover : "transparent"
            Text {
              id: tabLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: tab.modelData.title || tab.modelData.moduleId
              color: tab.picked ? Theme.foreground : Theme.muted
              font.family: Theme.font.family
              font.pixelSize: Theme.font.body
            }
            // News you haven't seen (NotchModule.attention).
            Rectangle {
              visible: !!tab.modelData.attention
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Theme.space(4)
              width: Theme.space(6)
              height: width
              radius: width / 2
              color: Theme.accent
            }
            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (card.notch) card.notch.showTab(tab.modelData.moduleId)
            }
          }
        }
      }

      // The modules, as tall as they are up to the room the card has; past
      // that, the wheel (where a module doesn't take it, as a terminal does)
      // and the scrollbar move them. Not flicked by a drag: that selects
      // text in a terminal.
      Item {
        id: scrollBox
        width: expandedStack.width
        height: Math.min(expandedStack.height,
          Math.max(Theme.space(80), card.contentRoom - (tabRow.visible ? tabRow.height + expanded.spacing : 0)))
        readonly property bool overflow: expandedStack.height > scrollBox.height + 1

        Flickable {
          id: scroll
          anchors.fill: parent
          contentWidth: expandedStack.width
          contentHeight: expandedStack.height
          interactive: false
          clip: scrollBox.overflow
          function scrollBy(dy) {
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, scroll.contentY + dy))
          }

          Column {
            id: expandedStack
            spacing: Theme.space(16)

            Repeater {
              model: expanded.shown
              delegate: Loader {
                required property var modelData
                width: Theme.space(modelData.expandedWidth || 400)
                sourceComponent: modelData.expanded
              }
            }

            // Nothing active: say so instead of opening an empty card.
            Column {
              visible: expanded.shown.length === 0
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
        }

        WheelHandler {
          enabled: scrollBox.overflow
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * Theme.space(60)
            scroll.scrollBy(-dy)
          }
        }

        // The scrollbar, in the card's padding beside the modules: where the
        // view is, and a handle to drag.
        Item {
          id: scrollTrack
          visible: scrollBox.overflow
          x: scrollBox.width + Theme.space(6)
          width: Theme.space(8)
          height: scrollBox.height
          Rectangle {
            id: scrollHandle
            readonly property real share: scroll.contentHeight > 0 ? scroll.height / scroll.contentHeight : 1
            x: Theme.space(2)
            width: Theme.space(4)
            height: Math.max(Theme.space(24), scrollTrack.height * scrollHandle.share)
            y: scroll.contentHeight > scroll.height
              ? (scrollTrack.height - scrollHandle.height) * scroll.contentY / (scroll.contentHeight - scroll.height) : 0
            radius: width / 2
            color: handleMouse.pressed || handleMouse.containsMouse ? Theme.muted : Theme.faint
          }
          MouseArea {
            id: handleMouse
            anchors.fill: parent
            anchors.margins: -Theme.space(2)
            hoverEnabled: true
            preventStealing: true
            property real grab: 0
            function follow(y) {
              var free = scrollTrack.height - scrollHandle.height
              if (free <= 0) return
              var top = Math.max(0, Math.min(free, y - handleMouse.grab))
              scroll.contentY = top / free * (scroll.contentHeight - scroll.height)
            }
            onPressed: function(mouse) {
              var inside = mouse.y >= scrollHandle.y && mouse.y <= scrollHandle.y + scrollHandle.height
              handleMouse.grab = inside ? mouse.y - scrollHandle.y : scrollHandle.height / 2
              handleMouse.follow(mouse.y)
            }
            onPositionChanged: function(mouse) { if (pressed) handleMouse.follow(mouse.y) }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- drawing
  // One outline, drawn for the top edge (x along, y depth): each end as
  // `startSide` and `endSide` say (Outline.js), rounded far side.
  // `transform` turns it onto the card's edge.
  Shape {
    id: outline
    width: outline.w
    height: outline.h
    preferredRendererType: Shape.CurveRenderer
    readonly property real w: Math.max(0, card.along)
    readonly property real h: Math.max(0, card.depth)
    readonly property real r: card.stretched && !card.roomy ? Math.min(Theme.space(12), h / 2, w / 2)
      : Math.min(Math.max(card.cornerRadius, card.roomy ? 0 : h / 2), h / 2, w / 2)
    // (x, y) -> top: (x, y), bottom: (x, h - y), left: (y, x), right: (h - y, x).
    transform: Matrix4x4 {
      matrix: card.edge === "bottom" ? Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, outline.h,  0, 0, 1, 0,  0, 0, 0, 1)
        : card.edge === "left" ? Qt.matrix4x4(0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
        : card.edge === "right" ? Qt.matrix4x4(0, -1, 0, outline.h,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1)
        : Qt.matrix4x4()
    }

    readonly property var paths: Outline.path({
      w: outline.w, h: outline.h, shoulder: card.shoulder, radius: outline.r,
      start: { kind: card.startSide, depth: card.startNeighborDepth },
      end: { kind: card.endSide, depth: card.endNeighborDepth }
    })

    ShapePath {
      fillColor: Theme.background
      strokeColor: "transparent"
      PathSvg { path: outline.paths.fill }
    }

    // Hairline on the open sides only, so the notch reads against dark
    // windows without drawing a seam where it meets the edge, the screen's
    // side or a neighbor.
    // While navigating, in the accent, the selected notch's thicker.
    ShapePath {
      fillColor: "transparent"
      strokeColor: card.navShown ? Theme.accent : card.roomy || card.stretched ? Theme.line : "transparent"
      strokeWidth: card.navSelected ? 2 : 1
      PathSvg { path: outline.paths.stroke }
    }
  }

  // ------------------------------------------------------------ navigation
  // While navigating (NotchService.navigating), a small label at the
  // notch's top right, outside it: its number and name, the selected one's
  // in the accent with the keys under it. Kept on screen.
  readonly property bool navShown: !!card.notch && !!card.notch.navShown
  readonly property bool navSelected: card.navShown && !!card.notch.navSelected
  readonly property int navNumber: card.navShown ? Number(card.notch.navNumber) || 0 : 0
  readonly property string navName: card.navShown ? String(card.notch.navName || "") : ""
  readonly property bool navTabs: card.navSelected && (card.notch.tabModules || []).length > 1
  readonly property int navCount: card.navSelected ? Number(card.notch.navCount) || 0 : 0
  readonly property string navKeysHint: [
    card.navCount > 1 ? "1-" + Math.min(9, card.navCount) + " ←→" : "",
    card.navTabs ? "Tab" : "", "Enter", "Esc"
  ].filter(function(s) { return s !== "" }).join("  ")
  Rectangle {
    id: navLabel
    visible: card.navShown
    readonly property real gap: Theme.space(6)
    width: navText.implicitWidth + Theme.space(12)
    height: navText.implicitHeight + Theme.space(6)
    radius: Theme.radiusSmall
    color: Theme.background
    border.color: card.navSelected ? Theme.accent : Theme.line
    border.width: 1
    // Right of the card past its shoulder, at its top, or left of it where
    // the right has no room; on the right edge, left of it, the open side.
    // Over the card's content if neither fits.
    z: 1
    readonly property real roomX: card.parent ? card.parent.width : 0
    readonly property real roomY: card.parent ? card.parent.height : 0
    readonly property real past: navLabel.gap + (card.vertical ? 0 : card.shoulder)
    readonly property real rightX: card.width + navLabel.past
    readonly property real leftX: -navLabel.past - navLabel.width
    readonly property real wishX: card.edge === "right" ? navLabel.leftX
      : card.edge === "left" || navLabel.roomX <= 0 || card.x + navLabel.rightX + navLabel.width <= navLabel.roomX
        ? navLabel.rightX : card.x + navLabel.leftX >= 0 ? navLabel.leftX : navLabel.rightX
    readonly property real wishY: card.edge === "top" ? navLabel.gap : 0
    x: navLabel.roomX > 0 ? Math.max(-card.x, Math.min(navLabel.wishX, navLabel.roomX - card.x - navLabel.width)) : navLabel.wishX
    y: navLabel.roomY > 0 ? Math.max(-card.y, Math.min(navLabel.wishY, navLabel.roomY - card.y - navLabel.height)) : navLabel.wishY
    Column {
      id: navText
      anchors.centerIn: parent
      spacing: Theme.space(1)
      Row {
        spacing: Theme.space(5)
        Text {
          visible: card.navNumber > 0
          textFormat: Text.PlainText
          text: String(card.navNumber)
          color: Theme.accent
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: card.navName
          color: card.navSelected ? Theme.foreground : Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
      Text {
        visible: card.navSelected
        textFormat: Text.PlainText
        text: card.navKeysHint
        color: Theme.faint
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption - 1
      }
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
      x: Math.round(card.x + (card.edge === "left" ? card.nearPad + card.contentShift
        : card.edge === "right" ? card.width - card.nearPad - card.contentShift - width : (card.width - width) / 2)) - card.x
      y: Math.round(card.y + (card.edge === "top" ? card.nearPad + card.contentShift
        : card.edge === "bottom" ? card.height - card.nearPad - card.contentShift - height : (card.height - height) / 2)) - card.y
      sourceComponent: card.shownComponent
    }
  }
}
