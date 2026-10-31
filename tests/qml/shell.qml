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
      { name: "on a side edge the card grows sideways", run: root.sideEdgeAxes },
      { name: "a peek shows on the focused screen and leaves the other copies alone", run: root.peekOnFocusedCopy },
      { name: "a peek goes only to the notches that show the module", run: root.peekOnlyWhereShown },
      { name: "notches, copies and modules survive a config edit", run: root.survivesConfigEdits },
      { name: "adding a notch and removing it gives the config back", run: root.addAndRemoveNotch },
      { name: "only the first notch asking for the bar gets it", run: root.oneBarNotch },
      { name: "a notch kept on a screen stays there and a peek also shows where you work", run: root.peekBesideHomedNotch },
      { name: "an OSD peek shows once, on the focused screen only", run: root.osdPeekOnFocusedScreen },
      { name: "a system module no notch lists loads and always peeks, never over a notch", run: root.systemModuleAlwaysShows },
      { name: "a notch's settings all sit on one page, under its picker", run: root.notchSettingsOnOnePage },
      { name: "resources read the system", run: root.resourcesRead },
      { name: "resources show closed by default, or only once one runs short", run: root.resourcesCompactWhenShort },
      { name: "a timer counts down closed, peeks when it ends and goes back to rest", run: root.timerRunsAndEnds },
      { name: "timer commands: pomodoro phases, pause, errors and its settings", run: root.timerCommands }
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

  // Two screens, A and B; B has focus.
  QtObject {
    id: twoScreens
    property string focusedScreenName: "B"
    function hasFullscreen(screen) { return false }
    readonly property bool supportsWorkspaces: false
    readonly property var knownWorkspaces: []
    function activeWorkspace(screen) { return null }
  }

  NotchService {
    id: multi
    ipcTarget: "notchd-qmltest-multi"
    configPath: root.dir + "/multi.json"
    compositor: twoScreens
    screens: [{ name: "A" }, { name: "B" }]
    defaultModules: ["activities"]
  }

  NotchService {
    id: barred
    ipcTarget: "notchd-qmltest-bar"
    configPath: root.dir + "/bar.json"
    compositor: twoScreens
    screens: [{ name: "A" }, { name: "B" }]
    barStyleAvailable: true
    defaultModules: []
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
    var notch = service.notches[0]
    root.check(Array.isArray(notch.workspaces), "workspaces is not an array: " + JSON.stringify(notch.workspaces))
    root.check(JSON.stringify(notch.workspaces) === "[1,2,3]", "workspaces is " + JSON.stringify(notch.workspaces))
    root.check(!notch.showsOn(screen), "shows on workspace 4 with [1,2,3]")
    chips.toggle(4)
    root.check(notch.showsOn(screen), "does not show on workspace 4 after adding it")
    chips.toggle(4)
    root.check(!notch.showsOn(screen), "still shows on workspace 4 after removing it")
    chips.toggle(1); chips.toggle(2); chips.toggle(3)
    root.check(service.configValue("workspaces") === undefined, "an empty pick left the key in the config")
    root.check(notch.showsOn(screen), "no pick should mean every workspace")
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
    notch: cardSvc
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
    var copy = service.firstCopy
    copy.setPointer("notch", true, "DP-1")
    copy.setPointer("notch", false, "")
    root.check(copy.mode !== "expanded", "opened without waiting for the hover delay")
    root.check(copy.openScreen === "", "kept screen " + copy.openScreen)
    root.done()
  }

  // ------------------------------------------------------ reserved space
  // The space follows the closed notch, so the volume OSD (a peek) and the
  // expanded notch open over windows without moving them; it grows at once
  // and shrinks after a delay.
  ReservedSpace {
    id: reserve
    notch: cardSvc
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
    notch: cardSvc
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
      notch: pointerSvc
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

  // ------------------------------------------------------------- notches
  readonly property var twoNotches: ({
    notches: [{ id: "main", modules: ["activities"], position: { screen: "all" } },
              { id: "side", modules: [], position: { edge: "left" } }]
  })
  function push(id, peek) {
    return multi.moduleById("activities").push(JSON.stringify({ id: id, title: id, sticky: true, peek: peek }))
  }

  // Bug: one notch window moved between screens. With media showing on one
  // monitor, changing the volume on another took the notch away from it.
  // A notch on every screen now peeks on the focused one only.
  function peekOnFocusedCopy() {
    var main = null
    root.steps([
      [0, function() { multi.replaceConfig(root.twoNotches) }],
      [300, function() {
        main = multi.notchById("main")
        root.check(!!main && main.copies.length === 2, "main has " + (main ? main.copies.length : 0) + " copies, not one per screen")
        root.check(root.push("build", false) === "ok", "activities not loaded")
      }],
      [100, function() {
        root.check(main.copyOn("A").mode === "compact" && main.copyOn("B").mode === "compact",
                   "a quiet push left " + main.copyOn("A").mode + " / " + main.copyOn("B").mode)
        twoScreens.focusedScreenName = "B"
        root.push("deploy", true)
      }],
      [100, function() {
        root.check(main.copyOn("B").mode === "peek", "the focused copy shows " + main.copyOn("B").mode)
        root.check(main.copyOn("A").mode === "compact", "the copy on the other screen shows " + main.copyOn("A").mode)
        root.check(multi.peeking(multi.moduleById("activities")), "the service does not report the peek")
        multi.dismissPeek(null)
        twoScreens.focusedScreenName = "A"
        root.push("lint", true)
      }],
      [100, function() {
        root.check(main.copyOn("A").mode === "peek" && main.copyOn("B").mode === "compact",
                   "focus on A: " + main.copyOn("A").mode + " / " + main.copyOn("B").mode)
        multi.dismissPeek(null)
      }]
    ], function() { root.done() })
  }

  function peekOnlyWhereShown() {
    var side = multi.notchById("side")
    root.check(!!side && side.copies.length === 1 && !side.everyScreen, "side should be one copy that moves")
    root.push("test", true)
    root.steps([[100, function() {}]], function() {
      root.check(side.copies[0].mode === "rest", "a notch without the module shows " + side.copies[0].mode)
      root.check(side.edge === "left", "side hangs from " + side.edge)
      multi.dismissPeek(null)
      root.done()
    })
  }

  // The notches, their copies and the modules are made once: a config edit
  // (a slider moving) must not make them again, losing what they show.
  function survivesConfigEdits() {
    var main = multi.notchById("main")
    var copy = main.copyOn("A")
    var module = multi.moduleById("activities")
    copy.open()
    multi.setConfigValue("hoverOpenDelay", 50)
    multi.setConfigValue("notches.0.position.edge", "bottom")
    root.steps([[50, function() {}]], function() {
      root.check(multi.notchById("main") === main, "the notch was made again")
      root.check(main.copyOn("A") === copy, "the copy was made again")
      root.check(copy.pinned, "the copy forgot it was pinned")
      root.check(multi.moduleById("activities") === module, "the module was loaded again")
      root.check(module.items.length > 0, "the module lost its activities")
      root.check(main.edge === "bottom", "the edit did not apply: " + main.edge)
      copy.close()
      module.clear("")
      root.done()
    })
  }

  function addAndRemoveNotch() {
    var start = { modules: ["activities"], hoverOpenDelay: 40 }
    multi.replaceConfig(start)
    root.check(multi.notches.length === 1, "one notch to start, not " + multi.notches.length)
    var at = multi.addNotch()
    root.check(at === 1 && multi.notches.length === 2, "added at " + at + ", " + multi.notches.length + " notches")
    root.check(JSON.stringify(multi.config.notches[0]) === "{}", "the first notch should inherit it all: " + JSON.stringify(multi.config.notches))
    root.check(multi.notches[1].edge !== multi.notches[0].edge, "the new notch hangs on the same edge")
    root.check(multi.notches[1].modules.length === 0, "the new notch starts with modules")
    multi.removeNotch(1)
    root.check(JSON.stringify(multi.config) === JSON.stringify(start), "the config came back as " + JSON.stringify(multi.config))
    root.done()
  }

  function oneBarNotch() {
    barred.replaceConfig({ notches: [{}, { id: "second" }] })
    root.steps([[50, function() {}]], function() {
      var first = barred.notches[0], second = barred.notches[1]
      root.check(barred.barNotch === first, "the bar went to " + (barred.barNotch ? barred.barNotch.notchId : "none"))
      root.check(first.compactStyle === "bar" && second.compactStyle === "notch",
                 "styles " + first.compactStyle + " / " + second.compactStyle)
      root.check(first.everyScreen && first.copies.length === 2, "the bar notch needs a copy per bar")
      root.check(!!first.copyOn("B") && first.copyOn("B") !== first.copyOn("A"), "no copy for bar B")
      root.done()
    })
  }

  // Bug: the notch kept on the ultrawide (position.screen) showing music
  // left it when the volume changed on the laptop screen. Now it stays and
  // shows the volume there; on the laptop screen, where no notch with the
  // OSD hangs, the visitor shows it once at the top, however many notches
  // kept elsewhere have the module.
  function peekBesideHomedNotch() {
    var music = null, side = null
    var visitor = multi.visitor
    root.steps([
      [0, function() {
        multi.replaceConfig({ modules: ["activities"], position: { screen: "A" },
                              notches: [{}, { id: "side", position: { edge: "left", screen: "A" } }] })
        twoScreens.focusedScreenName = "B"
      }],
      [100, function() {
        music = multi.notchById("main"); side = multi.notchById("side")
        root.check(music.copies.length === 1 && music.copies[0].screenName === "A", "the notch kept on A is not one copy on A")
        root.check(visitor.copies.length === 2 && visitor.copyOn("B").offWorkspace, "the visitor shows while nothing peeks")
        root.push("music", false)
        root.push("volume", true)
      }],
      [100, function() {
        root.check(music.copies[0].mode === "peek" && music.copies[0].screenName === "A",
                   "the notch on A shows " + music.copies[0].mode + " on " + music.copies[0].screenName)
        root.check(side.copies[0].mode === "peek" && side.copies[0].screenName === "A", "the side notch left A")
        var guest = visitor.copyOn("B")
        root.check(guest.mode === "peek" && !guest.offWorkspace && guest.edge === "top",
                   "no peek at the top of B: " + guest.mode + " on " + guest.edge)
        root.check(visitor.copyOn("A").mode !== "peek", "the visitor also peeked on A, where the notches are")
        root.check(JSON.stringify(guest.reservedScreens) === "[]", "the visitor reserves " + JSON.stringify(guest.reservedScreens))
        multi.dismissPeek(null)
      }],
      [100, function() {
        root.check(music.copies[0].mode === "compact", "after the peek the notch on A shows " + music.copies[0].mode)
        root.check(visitor.copyOn("B").offWorkspace, "the visitor stays after the peek")
        twoScreens.focusedScreenName = "A"
        root.push("again", true)
      }],
      [100, function() {
        root.check(visitor.copyOn("A").mode !== "peek" && visitor.copyOn("B").mode !== "peek",
                   "the visitor peeked with focus where the notches are")
        multi.dismissPeek(null)
        // A notch that follows focus peeks on B itself: no visitor.
        multi.setConfigValue("notches.1.position.screen", "")
        twoScreens.focusedScreenName = "B"
        root.push("follow", true)
      }],
      [100, function() {
        root.check(visitor.copyOn("B").mode !== "peek", "the visitor peeked beside a notch that follows focus")
        multi.dismissPeek(null)
        multi.moduleById("activities").clear("")
      }]
    ], function() { root.done() })
  }

  // Bug: brightness changes on the focused monitor only, yet its OSD opened
  // in the notches of the other monitors too. A module with
  // peekOnFocusedScreen (the OSD) peeks once: in the first notch on the
  // focused screen that shows it, else at the top, in the visitor.
  function osdPeekOnFocusedScreen() {
    var module = multi.moduleById("activities")
    var visitor = multi.visitor
    function modes() {
      return multi.notches.map(function(n) { return n.notchId + ":" + n.copies[0].mode }).join(" ")
        + " visitor:" + visitor.copies.map(function(c) { return c.mode }).join("/")
    }
    function peeking() {
      return multi.notches.filter(function(n) { return n.copies[0].mode === "peek" }).map(function(n) { return n.notchId })
        .concat(visitor.copies.filter(function(c) { return c.mode === "peek" }).map(function(c) { return "visitor@" + c.fixedScreen }))
        .join(" ")
    }
    root.steps([
      [0, function() {
        module.peekOnFocusedScreen = true
        multi.replaceConfig({ modules: ["activities"],
                              notches: [{ position: { screen: "A" } }, { id: "a2", position: { edge: "left", screen: "A" } },
                                        { id: "b", position: { screen: "B" } }] })
        twoScreens.focusedScreenName = "B"
      }],
      [100, function() { root.push("brightness", true) }],
      [100, function() {
        root.check(peeking() === "b", "focus on B: " + modes())
        multi.dismissPeek(null)
        twoScreens.focusedScreenName = "A"
        root.push("volume", true)
      }],
      [100, function() {
        root.check(peeking() === "main", "focus on A: " + modes())
        multi.dismissPeek(null)
        multi.setConfigValue("notches.2.position.screen", "A")
        twoScreens.focusedScreenName = "B"
        root.push("volume", true)
      }],
      [100, function() {
        root.check(peeking() === "visitor@B", "nothing on B: " + modes())
        multi.dismissPeek(null)
        module.peekOnFocusedScreen = false
        module.clear("")
      }]
    ], function() { root.done() })
  }

  // Bug: with the OSD taken out of every notch, the module did not load and
  // the volume and brightness showed nowhere. A host's system module loads
  // anyway and peeks in the default notch, at the top of the focused screen.
  function systemModuleAlwaysShows() {
    var visitor = multi.visitor
    root.steps([
      [0, function() {
        multi.replaceConfig({ modules: [], position: { screen: "A" } })
        twoScreens.focusedScreenName = "B"
      }],
      [100, function() {
        root.check(multi.moduleById("activities") === null, "loaded a module no notch lists (test setup)")
        multi.systemModules = ["activities"]
      }],
      [100, function() {
        root.check(multi.moduleById("activities") !== null, "the system module did not load")
        root.check(multi.notches[0].modules.length === 0, "the notch took the system module")
        root.push("volume", true)
      }],
      [100, function() {
        root.check(visitor.copyOn("B").mode === "peek", "no peek at the top of B: " + visitor.copyOn("B").mode)
        root.check(multi.notches[0].copies[0].mode === "rest", "the notch on A shows " + multi.notches[0].copies[0].mode)
        multi.dismissPeek(null)
        twoScreens.focusedScreenName = "A"
        root.push("brightness", true)
      }],
      // Bug: on a screen with a notch that doesn't list the OSD, the default
      // notch drew the volume right over it. The notch there shows it.
      [100, function() {
        root.check(multi.notches[0].copies[0].mode === "peek", "the notch on A did not show the peek: " + multi.notches[0].copies[0].mode)
        root.check(visitor.copyOn("A").mode !== "peek", "the default notch drew over the notch on A")
        multi.dismissPeek(null)
        multi.systemModules = []
      }]
    ], function() { root.done() })
  }

  // A notch's keys were split between General and Modules, each with its own
  // picker. Every field for the picked notch's keys sits on the "notch" page,
  // under a single picker; the other pages only have keys for every notch.
  function notchSettingsOnOnePage() {
    multi.replaceConfig({ notches: [{ modules: ["activities"] }, { id: "side", position: { edge: "bottom" } }] })
    multi.settingsNotch = 1
    var schema = multi.settingsSchema
    var pickers = schema.filter(function(f) { return f.type === "notches" })
    root.check(pickers.length === 1 && pickers[0].page === "notch", "pickers: " + JSON.stringify(pickers.map(function(f) { return f.page })))
    var notchPage = schema.filter(function(f) { return f.page === "notch" })
    root.check(notchPage.length > 0 && notchPage[0].type === "notches", "the picker is not first on the notch page")
    schema.forEach(function(f) {
      var own = !!f.key && f.key.indexOf("notches.") === 0
      if (own) root.check(f.page === "notch", f.key + " is on " + f.page)
      else if (f.key && f.key !== "notches") root.check(f.page !== "notch", f.key + " applies to every notch but is on the notch page")
    })
    root.check(schema.some(function(f) { return f.key === "notches.1.modules" }), "the notch's modules are missing")
    multi.settingsPage = "general"
    multi.openSettings(0)
    root.check(multi.settingsPage === "notch", "the gear opened " + multi.settingsPage)
    multi.closeSettings()
    multi.settingsNotch = 0
    multi.replaceConfig({})
    root.done()
  }

  NotchService {
    id: resourced
    ipcTarget: "notchd-qmltest-resources"
    configPath: root.dir + "/resources.json"
    compositor: twoScreens
    defaultModules: ["resources"]
  }

  // FileView on /proc (whose files report no size) and df's output both
  // reach the module: a CPU figure needs two samples, 2 s apart.
  function resourcesRead() {
    var m = resourced.moduleById("resources")
    root.check(!!m, "the module did not load")
    root.steps([[2600, function() {
      root.check(m.cpu !== null && m.cpu >= 0 && m.cpu <= 1, "cpu: " + m.cpu)
      root.check(m.cores > 0, "cores: " + m.cores)
      root.check(!!m.memory && m.memory.total > 0, "memory: " + JSON.stringify(m.memory))
      root.check(!!m.disk && m.disk.total > 0, "disk: " + JSON.stringify(m.disk))
      root.check(m.active && !!m.expanded, "no expanded view")
    }]], function() { root.done() })
  }

  // By default the closed notch always shows the three. With `compact` at
  // "short" it rests while every resource is fine; one running short peeks
  // once and takes the compact slot until it drops back. The setting is on
  // the General page, under the module's id.
  function resourcesCompactWhenShort() {
    var m = resourced.moduleById("resources")
    var notch = resourced.notches[0]
    m.sampling = false
    m.pressure = ({})
    resourced.replaceConfig({})
    m.record("memory", 0.5)
    root.check(notch.compactModule === m && m.compactRows.length === 3, "not shown by default")
    var field = resourced.settingsSchema.filter(function(f) { return f.key === "resources.compact" })[0]
    root.check(!!field && field.page === "general" && field.section === "Resources", "field: " + JSON.stringify(field))

    resourced.setConfigValue("resources.compact", "short")
    root.check(notch.compactModule === null, "the notch shows resources with nothing short")
    m.record("memory", 0.95)
    root.check(notch.compactModule === m && m.compactRows.length === 1, "memory short, no compact view")
    root.check(m.peekId === "memory" && resourced.peeking(m), "memory short, no peek")
    resourced.dismissPeek(null)
    m.record("memory", 0.96)
    root.check(!resourced.peeking(m), "peeked again while still short")
    m.record("memory", 0.8)
    root.check(notch.compactModule === null, "still compact after memory dropped")
    m.record("cpu", 0.99)
    root.check(notch.compactModule === null, "one CPU burst counted as short")
    resourced.replaceConfig({})
    m.sampling = true
    root.done()
  }

  NotchService {
    id: timed
    ipcTarget: "notchd-qmltest-timer"
    configPath: root.dir + "/timer.json"
    compositor: twoScreens
    defaultModules: ["timer"]
  }

  // Idle, the notch rests and the timer only offers its quick starts when
  // open. Started, it takes the compact slot with the time left; at the end
  // it peeks (urgent, so even over the open notch) and says so until stopped.
  function timerRunsAndEnds() {
    var m = timed.moduleById("timer")
    var notch = timed.notches[0]
    timed.replaceConfig({ timer: { notify: false } })
    root.check(!!m && m.active && notch.compactModule === null, "idle timer is in the closed notch")
    root.check(m.command("2s Tea") === "ok", "start refused")
    root.check(notch.compactModule === m && m.status === "running", "running timer not in the closed notch")
    root.check(m.clock === "0:02", "clock: " + m.clock)
    timed.dismissPeek(null)
    root.steps([[2600, function() {
      root.check(m.status === "done", "not done after its time: " + m.status)
      root.check(timed.peeking(m), "no peek at the end")
      root.check(notch.compactModule === m && m.doneText === "Time's up", "done text: " + m.doneText)
      timed.dismissPeek(null)
      root.check(m.command("stop") === "ok", "stop refused")
      root.check(notch.compactModule === null, "stopped timer still in the closed notch")
    }]], function() { timed.replaceConfig({}); root.done() })
  }

  function timerCommands() {
    var m = timed.moduleById("timer")
    timed.replaceConfig({ timer: { notify: false, focus: 50 } })
    root.check(m.command("pause") === "no timer running", "pause while idle: " + m.command("pause"))
    root.check(m.command("soon").indexOf("usage") === 0, "a bad command was accepted")
    m.command("pomodoro")
    root.check(m.countdown.phase === "focus" && m.countdown.duration === 50 * 60000, "focus setting ignored: " + JSON.stringify(m.countdown))
    m.command("toggle")
    root.check(m.status === "paused", "toggle did not pause")
    var left = m.remaining
    m.command("+5m")
    root.check(m.remaining === left + 5 * 60000, "added time lost while paused")
    m.command("skip")
    root.check(m.countdown.phase === "short" && m.status === "running", "skip: " + JSON.stringify(m.countdown))
    var keys = timed.settingsSchema.filter(function(f) { return f.section === "Timer" }).map(function(f) { return f.key })
    root.check(keys.indexOf("timer.focus") !== -1 && keys.indexOf("timer.notify") !== -1, "settings: " + keys)
    m.command("stop")
    timed.dismissPeek(null)
    timed.replaceConfig({})
    root.done()
  }
}
