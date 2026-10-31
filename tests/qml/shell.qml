import QtQuick
import QtTest
import Quickshell
import "core"
import "core/settings"

// Behaviour tests that need the QML runtime: bindings, signals, animations.
// Rules that are plain JS belong in the Node tests instead. Most cases here
// are regression tests for bugs found by hand; each says what it guards.
//
// scripts/qml-test.sh links the core next to this file, points
// NOTCHD_QMLTEST_DIR at an empty scratch dir (the service's config lives
// there) and runs it offscreen. Each case logs "PASS <name>" or
// "FAIL <name>: <why>"; "DONE" ends the run.
ShellRoot {
  id: root

  readonly property string dir: Quickshell.env("NOTCHD_QMLTEST_DIR")

  // ------------------------------------------------------------- harness
  // Cases run one after another; a case calls done() (or fail()) when it is
  // finished, so async ones can wait on timers.
  property var cases: []
  property int index: -1
  property string current: ""
  property bool failed: false

  function check(cond, why) {
    if (!cond && !root.failed) {
      root.failed = true
      console.log("FAIL " + root.current + ": " + why)
    }
    return cond
  }
  function done() {
    if (!root.failed) console.log("PASS " + root.current)
    Qt.callLater(root.next)
  }
  function next() {
    root.index++
    if (root.index >= root.cases.length) { console.log("DONE"); Qt.quit(); return }
    root.current = root.cases[root.index].name
    root.failed = false
    try { root.cases[root.index].run() }
    catch (e) { root.check(false, "threw " + e); root.done() }
  }

  // Runs fn after ms, then the next step; steps([[ms, fn], ...], last).
  function steps(list, last) {
    if (list.length === 0) { last(); return }
    var step = list[0]
    stepTimer.interval = step[0]
    stepTimer.action = function() { step[1](); root.steps(list.slice(1), last) }
    stepTimer.restart()
  }
  Timer {
    id: stepTimer
    property var action: null
    onTriggered: if (action) action()
  }

  Component.onCompleted: {
    root.cases = [
      { name: "workspace chips store a real list", run: root.workspaceChipsList },
      { name: "compact depth ignores peek and expanded transitions", run: root.compactDepthTransitions },
      { name: "leaving the notch before it opens forgets the screen", run: root.hoverLeaveForgetsScreen },
      { name: "peeks and the open notch never move windows", run: root.reserveIgnoresOpenNotch },
      { name: "reserved space grows at once and shrinks after the delay", run: root.reserveGrowsAndShrinks },
      { name: "one module ending as another starts keeps the space", run: root.reserveBridgesModules },
      { name: "the space shrinks as the notch closes, not seconds later", run: root.reserveShrinksPromptly },
      { name: "a dragged notch moves windows once, when it lands", run: root.reserveHeldWhileDragging },
      { name: "the notch stays hovered over the controls inside it", run: root.hoverOverControls },
      { name: "a quick click pins the notch and never drags it", run: root.quickClickPins },
      { name: "a quick press-and-pull never drags the notch", run: root.quickPullNoDrag },
      { name: "held, then moved, the notch is dragged and not pinned", run: root.holdThenDrag },
      { name: "a side edge reserves the side compact view, never the old one turned", run: root.reserveFollowsEdge },
      { name: "on a side edge the card grows sideways", run: root.sideEdgeAxes }
    ]
    Qt.callLater(root.next)
  }

  // --------------------------------------------------------------- fakes
  // A compositor whose every screen shows workspace 4.
  QtObject {
    id: workspace4
    readonly property string focusedScreenName: ""
    function hasFullscreen(screen) { return false }
    readonly property bool supportsWorkspaces: true
    readonly property var knownWorkspaces: ["1", "2", "3", "4"]
    function activeWorkspace(screen) { return { id: 4, name: "4" } }
  }

  NotchService {
    id: service
    ipcTarget: "notchd-qmltest"
    configPath: root.dir + "/config.json"
    compositor: workspace4
  }

  // ---------------------------------------------------------------- cases
  // Bug: a list edited in the settings went through the control's `var`
  // signal, came out as a sequence (Array.isArray false), and Config.resolve
  // read it as "no list": every workspace. Adding a workspace seemed to work;
  // removing it again did nothing.
  WorkspaceChips {
    id: chips
    svc: service
    value: service.configValue("workspaces")
    onEdited: function(v) { service.setConfigValue("workspaces", v) }
  }

  function workspaceChipsList() {
    var screen = { name: "test" }
    chips.toggle(1); chips.toggle(2); chips.toggle(3)
    root.check(Array.isArray(service.workspaces), "workspaces is not an array: " + JSON.stringify(service.workspaces))
    root.check(JSON.stringify(service.workspaces) === "[1,2,3]", "workspaces is " + JSON.stringify(service.workspaces))
    root.check(!service.showsOn(screen), "shows on workspace 4 with [1,2,3]")
    chips.toggle(4)
    root.check(service.showsOn(screen), "does not show on workspace 4 after adding it")
    chips.toggle(4)
    root.check(!service.showsOn(screen), "still shows on workspace 4 after removing it")
    chips.toggle(1); chips.toggle(2); chips.toggle(3)
    root.check(service.configValue("workspaces") === undefined, "an empty pick left the key in the config")
    root.check(service.showsOn(screen), "no pick should mean every workspace")
    root.done()
  }

  // Bugs: the reserved space grew past the compact notch. First the peek's
  // height was read as compact (the shown mode and content swap in two
  // steps), then compact content plus the expanded padding (the padding
  // follows the new mode at once while the old content fades out).
  QtObject {
    id: cardSvc
    property string mode: "compact"
    property string edge: "top"
    property bool dragging: false
    readonly property string compactStyle: "notch"
    readonly property bool reserveSpace: true
    property var compactModule: fakeModule
    readonly property var peekModule: fakeModule
    readonly property var expandedModules: []
    function togglePinned(screenName) {}
    function close() {}
    function openSettings() {}
  }
  QtObject {
    id: fakeModule
    readonly property Component compact: Component { Item { implicitWidth: 120; implicitHeight: 18 } }
    readonly property Component peek: Component { Item { implicitWidth: 300; implicitHeight: 70 } }
  }
  NotchCard {
    id: card
    svc: cardSvc
    property real tallestCompact: 0
    onCompactDepthChanged: if (compactDepth > tallestCompact) tallestCompact = compactDepth
  }

  function compactDepthTransitions() {
    var settle = 450
    var base = 0
    root.steps([
      [settle, function() { base = card.compactDepth; card.tallestCompact = base }],
      [0, function() { cardSvc.mode = "peek" }],
      [settle, function() { cardSvc.mode = "compact" }],
      [settle, function() { cardSvc.mode = "expanded" }],
      [settle, function() { cardSvc.mode = "compact" }],
      [settle, function() {}]
    ], function() {
      root.check(base > 0, "no compact height measured")
      root.check(card.tallestCompact === base, "compact height reached " + card.tallestCompact + ", compact is " + base)
      root.done()
    })
  }

  // Bug: hovering the notch named its screen as the one to open on; leaving
  // before it opened kept that, so the next peek showed on that screen
  // instead of the focused one.
  function hoverLeaveForgetsScreen() {
    service.setPointer("notch", true, "DP-1")
    service.setPointer("notch", false, "")
    root.check(service.mode !== "expanded", "opened without waiting for the hover delay")
    root.check(service.screenOverride === "", "kept screen " + service.screenOverride)
    root.done()
  }

  // ------------------------------------------------------ reserved space
  // The space follows the closed notch, so the volume OSD (a peek) and the
  // expanded notch open over windows without moving them; it grows at once
  // and shrinks after a delay.
  ReservedSpace {
    id: reserve
    svc: cardSvc
    notchCard: card
    shrinkDelay: 300
    property int lowest: 0
    property int highest: 0
    function watch() { lowest = space; highest = space }
    onSpaceChanged: { lowest = Math.min(lowest, space); highest = Math.max(highest, space) }
  }

  // Closed notch: compact (a module active) or rest.
  function closeAs(compact) {
    cardSvc.compactModule = compact ? fakeModule : null
    cardSvc.mode = compact ? "compact" : "rest"
  }

  function reserveIgnoresOpenNotch() {
    var settle = 450
    var compact = 0
    root.steps([
      [0, function() { root.closeAs(true) }],
      [settle, function() { compact = reserve.space; reserve.watch(); cardSvc.mode = "peek" }],
      [settle, function() { cardSvc.mode = "expanded" }],
      [settle, function() { cardSvc.mode = "compact" }],
      [settle, function() {
        root.check(reserve.lowest === compact && reserve.highest === compact,
                   "compact: moved between " + reserve.lowest + " and " + reserve.highest + ", closed is " + compact)
        root.closeAs(false)
      }],
      [settle * 2, function() { reserve.watch(); cardSvc.mode = "peek" }],  // the OSD, from rest
      [settle, function() { cardSvc.mode = "rest" }],
      [settle, function() {}]
    ], function() {
      root.check(reserve.space === Math.ceil(card.restDepth), "rest reserves " + reserve.space + ", the lip is " + card.restDepth)
      root.check(reserve.lowest === reserve.highest, "a peek from rest moved it between " + reserve.lowest + " and " + reserve.highest)
      root.done()
    })
  }

  function reserveGrowsAndShrinks() {
    var rest = Math.ceil(card.restDepth)
    var compact = 0
    root.steps([
      [0, function() { root.closeAs(false) }],
      [450, function() {
        root.check(reserve.space === rest, "rest reserves " + reserve.space)
        root.closeAs(true)
        compact = reserve.space
        root.check(compact > rest, "did not grow at once: " + compact)
        root.closeAs(false)
      }],
      [150, function() { root.check(reserve.space === compact, "shrank before the delay: " + reserve.space) }],
      [350, function() { root.check(reserve.space === rest, "did not shrink after the delay: " + reserve.space) }]
    ], function() { root.done() })
  }

  function reserveBridgesModules() {
    var compact = 0
    root.steps([
      [0, function() { root.closeAs(true) }],
      [450, function() { compact = reserve.space; reserve.watch(); root.closeAs(false) }],
      [100, function() { root.closeAs(true) }],
      [500, function() {}]
    ], function() {
      root.check(reserve.lowest === compact, "dipped to " + reserve.lowest + " between modules, compact is " + compact)
      root.done()
    })
  }

  // ------------------------------------------------------------ edges
  // Moving a compact notch to a side edge swaps its view for the dot (the
  // fake module has no verticalCompact). For the length of the fade the old,
  // wide view is still loaded; measured on the new axis it would read as a
  // notch 130 px deep and push windows that far.
  function reserveFollowsEdge() {
    var settle = 450
    var top = 0
    root.steps([
      [0, function() { root.closeAs(true) }],
      [settle, function() { top = reserve.space; reserve.watch(); cardSvc.edge = "left" }],
      [settle, function() {}]
    ], function() {
      root.check(card.vertical, "the card did not take the left edge")
      root.check(reserve.highest <= top, "grew to " + reserve.highest + " moving to the side; compact on top is " + top)
      root.check(reserve.space === Math.ceil(card.compactDepth) && reserve.space > 0,
                 "reserves " + reserve.space + ", the side compact view is " + card.compactDepth + " deep")
      cardSvc.edge = "top"
      root.done()
    })
  }

  // Content never turns: on a side edge its width is the notch's depth
  // (width) and its height runs along the edge (height).
  function sideEdgeAxes() {
    // The fade (70 ms) swaps the content, then the spring (460 ms) runs.
    var settle = 800
    root.steps([
      [0, function() { cardSvc.edge = "right"; cardSvc.mode = "peek" }],
      [settle, function() {}]
    ], function() {
      root.check(card.width === 300 + card.nearPad + card.farPad, "width " + card.width + " for a 300 px wide peek")
      root.check(card.height === 70 + card.alongPad * 2, "height " + card.height + " for a 70 px tall peek")
      root.check(card.nearPad === card.farPad, "a wide peek sits off-center: " + card.nearPad + " / " + card.farPad)
      cardSvc.edge = "top"
      root.closeAs(false)
      root.done()
    })
  }

  // Bug: when the last module ended, windows stayed clear of a notch that
  // was already back to its lip for 4 s (the default shrink delay). The
  // space now goes once the notch has collapsed.
  ReservedSpace {
    id: defaultReserve
    svc: cardSvc
    notchCard: card
  }

  function reserveShrinksPromptly() {
    var rest = Math.ceil(card.restDepth)
    root.steps([
      [0, function() { root.closeAs(true) }],
      [450, function() {
        root.check(defaultReserve.space > rest, "compact did not grow the space: " + defaultReserve.space)
        root.closeAs(false)
      }],
      [600, function() {}]
    ], function() {
      root.check(defaultReserve.space === rest,
                 "still " + defaultReserve.space + " px 600 ms after the notch closed; the lip is " + rest)
      root.done()
    })
  }

  // Dragging turns the card to each edge it passes; the space waits for the
  // drop instead of following it there and back.
  function reserveHeldWhileDragging() {
    var compact = 0
    root.steps([
      [0, function() { root.closeAs(true) }],
      [450, function() {
        compact = reserve.space
        reserve.watch()
        cardSvc.dragging = true
        cardSvc.edge = "left"
        root.closeAs(false)
      }],
      [600, function() {
        root.check(reserve.lowest === compact && reserve.highest === compact,
                   "moved between " + reserve.lowest + " and " + reserve.highest + " mid-drag; it was " + compact)
        cardSvc.edge = "top"
        cardSvc.dragging = false
      }],
      [600, function() {}]
    ], function() {
      root.check(reserve.space === Math.ceil(card.restDepth), "after the drop it reserves " + reserve.space)
      root.done()
    })
  }

  // ------------------------------------------------------------- pointer
  // Real pointer events (QtTest) on a card in a window. The TestCase runs
  // no tests of its own; it only sends the events.
  TestCase { id: pointer; when: false }

  QtObject {
    id: controlModule
    property bool controlHovered: false
    readonly property Component expanded: Component {
      Item {
        implicitWidth: 300
        implicitHeight: 100
        // A control that takes hover, like the gear or the media buttons.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onContainsMouseChanged: controlModule.controlHovered = containsMouse
        }
      }
    }
  }
  QtObject {
    id: pointerSvc
    readonly property string mode: "expanded"
    readonly property string edge: "top"
    readonly property string compactStyle: "notch"
    readonly property var compactModule: null
    readonly property var peekModule: null
    readonly property var expandedModules: [controlModule]
    property int pins: 0
    function togglePinned(screenName) { pins++ }
    function close() {}
    function openSettings() {}
  }
  FloatingWindow {
    id: pointerWin
    implicitWidth: 500
    implicitHeight: 400
    NotchCard {
      id: pointerCard
      svc: pointerSvc
      draggable: true
      x: 50
      property int started: 0
      property int moved: 0
      property int ended: 0
      onDragStarted: started++
      onDragMoved: function(p) { moved++ }
      onDragEnded: ended++
      function reset() { started = 0; moved = 0; ended = 0; pointerSvc.pins = 0 }
    }
  }
  // A spot on the card outside its content: the open side's padding.
  function padX() { return pointerCard.width / 2 }
  function padY() { return pointerCard.height - 4 }

  // Bug: the hover was tracked on an item beside the card, and any control
  // inside the card that takes hover took the pointer from it. Crossing the
  // media buttons or the gear closed the notch (after the close delay) and
  // opened it again: it flickered.
  function hoverOverControls() {
    root.steps([
      [600, function() { pointer.mouseMove(pointerCard, root.padX(), root.padY()) }],
      [50, function() {
        root.check(pointerCard.hovered === true, "not hovered on the card's padding")
        pointer.mouseMove(pointerCard, pointerCard.width / 2, pointerCard.height / 2)
      }],
      [50, function() {
        root.check(controlModule.controlHovered, "the pointer is not on the control (test setup)")
        root.check(pointerCard.hovered === true, "lost the hover over a control inside the card")
        pointer.mouseMove(pointerCard, root.padX(), root.padY())
      }],
      [50, function() { root.check(pointerCard.hovered === true, "not hovered back on the padding") }]
    ], function() { root.done() })
  }

  function quickClickPins() {
    pointerCard.reset()
    pointer.mouseClick(pointerCard, root.padX(), root.padY())
    root.steps([[50, function() {}]], function() {
      root.check(pointerSvc.pins === 1, "a click pinned " + pointerSvc.pins + " times")
      root.check(pointerCard.started === 0, "a click started a drag")
      root.done()
    })
  }

  function quickPullNoDrag() {
    pointerCard.reset()
    pointer.mousePress(pointerCard, root.padX(), root.padY())
    root.steps([
      [40, function() { pointer.mouseMove(pointerCard, root.padX() + 40, root.padY() + 60, -1, Qt.LeftButton) }],
      [40, function() { pointer.mouseMove(pointerCard, root.padX() + 80, root.padY() + 120, -1, Qt.LeftButton) }],
      [400, function() { pointer.mouseRelease(pointerCard, root.padX() + 80, root.padY() + 120) }],
      [50, function() {}]
    ], function() {
      root.check(pointerCard.started === 0, "moving straight away dragged the notch")
      root.done()
    })
  }

  function holdThenDrag() {
    pointerCard.reset()
    pointer.mousePress(pointerCard, root.padX(), root.padY())
    root.steps([
      [pointerCard.holdToDrag + 150, function() {
        root.check(pointerCard.started === 1, "holding did not pick the notch up")
        pointer.mouseMove(pointerCard, root.padX() + 40, root.padY() + 60, -1, Qt.LeftButton)
      }],
      [40, function() { pointer.mouseMove(pointerCard, root.padX() + 80, root.padY() + 120, -1, Qt.LeftButton) }],
      [40, function() { pointer.mouseRelease(pointerCard, root.padX() + 80, root.padY() + 120) }],
      [50, function() {}]
    ], function() {
      root.check(pointerCard.moved >= 1, "the drag reported no move")
      root.check(pointerCard.ended === 1, "the drop ended " + pointerCard.ended + " drags")
      root.check(!pointerCard.dragging, "still dragging after the drop")
      root.check(pointerSvc.pins === 0, "the drop also pinned the notch")
      root.done()
    })
  }
}
