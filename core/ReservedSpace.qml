import QtQuick
import "State.js" as State

// How much of its edge windows leave to the closed notch (reserveSpace):
// the rest lip, or a compact notch while a module shows one. It follows the
// closed notch only, so peeks (the volume OSD) and the expanded notch never
// move windows. It grows at once and shrinks after `shrinkDelay`: as the
// notch finishes collapsing, so windows never cover it on the way and one
// module ending as another starts (`clear` then `push`) moves them once.
// NotchSurface turns `space` into an exclusive zone per screen, on the
// notch's edge.
Item {
  id: reserve
  visible: false

  // The notch copy (NotchCopy) whose closed notch it keeps clear.
  property var notch: null
  property NotchCard notchCard: null
  // NotchCard's depth animation (380 ms), plus a little.
  property int shrinkDelay: 400

  // In px; 0 reserves nothing.
  property int space: 0

  readonly property bool vertical: !!reserve.notchCard && reserve.notchCard.vertical
  // A media compact view's height (18) plus the card's compact padding. On a
  // side edge compact views differ too much to guess; the deepest seen counts.
  readonly property real compactBaseline: reserve.notchCard && !reserve.vertical
    ? Theme.space(18) + reserve.notchCard.compactPadNear + reserve.notchCard.compactPadFar : 0
  // The deepest compact view shown so far; reset when the theme rescales or
  // the notch moves to another edge.
  property real deepestCompact: 0
  onCompactBaselineChanged: reserve.deepestCompact = 0
  onVerticalChanged: reserve.deepestCompact = 0
  readonly property real compactDepth: reserve.notchCard ? reserve.notchCard.compactDepth : 0
  onCompactDepthChanged: if (reserve.compactDepth > reserve.deepestCompact) reserve.deepestCompact = reserve.compactDepth

  // State.js has the rules.
  readonly property int target: State.reservedSpace({
    enabled: !!reserve.notch && reserve.notch.reserveSpace,
    compactStyle: reserve.notch ? reserve.notch.compactStyle : "",
    compact: !!reserve.notch && !!reserve.notch.compactModule && !!reserve.notch.compactModule.compact,
    baseline: reserve.compactBaseline,
    tallest: reserve.deepestCompact,
    rest: reserve.notchCard ? reserve.notchCard.restDepth : 0
  })

  // Held while the notch is dragged, so windows move once, when it lands.
  readonly property bool held: !!reserve.notch && !!reserve.notch.dragging
  onHeldChanged: if (!reserve.held) reserve.follow()

  function follow() {
    if (reserve.held) return
    var step = State.reserveStep(reserve.space, reserve.target)
    if (step === "later") { shrinkTimer.restart(); return }
    shrinkTimer.stop()
    if (step === "now") reserve.space = reserve.target
  }
  onTargetChanged: reserve.follow()
  Component.onCompleted: reserve.space = reserve.target

  Timer {
    id: shrinkTimer
    interval: reserve.shrinkDelay
    onTriggered: reserve.space = reserve.target
  }
}
