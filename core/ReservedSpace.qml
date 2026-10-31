import QtQuick
import "State.js" as State

// How much of the top edge windows leave to the closed notch (reserveSpace):
// the rest lip, or a compact notch while a module shows one. It follows the
// closed notch only, so peeks (the volume OSD) and the expanded notch never
// move windows. It grows at once and shrinks after `shrinkDelay`: as the
// notch finishes collapsing, so windows never cover it on the way and one
// module ending as another starts (`clear` then `push`) moves them once.
// NotchSurface turns `space` into an exclusive zone per screen.
Item {
  id: reserve
  visible: false

  property var svc: null
  property NotchCard notchCard: null
  // NotchCard's height animation (380 ms), plus a little.
  property int shrinkDelay: 400

  // In px; 0 reserves nothing.
  property int space: 0

  // A media compact view's height (18) plus the card's compact padding.
  readonly property real compactBaseline: reserve.notchCard
    ? Theme.space(18) + reserve.notchCard.compactPadTop + reserve.notchCard.compactPadBottom : 0
  // The tallest compact view shown so far; reset when the theme rescales.
  property real tallestCompact: 0
  onCompactBaselineChanged: reserve.tallestCompact = 0
  readonly property real compactHeight: reserve.notchCard ? reserve.notchCard.compactHeight : 0
  onCompactHeightChanged: if (reserve.compactHeight > reserve.tallestCompact) reserve.tallestCompact = reserve.compactHeight

  // State.js has the rules.
  readonly property int target: State.reservedSpace({
    enabled: !!reserve.svc && reserve.svc.reserveSpace,
    compactStyle: reserve.svc ? reserve.svc.compactStyle : "",
    compact: !!reserve.svc && !!reserve.svc.compactModule && !!reserve.svc.compactModule.compact,
    baseline: reserve.compactBaseline,
    tallest: reserve.tallestCompact,
    rest: reserve.notchCard ? reserve.notchCard.restHeight : 0
  })

  function follow() {
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
