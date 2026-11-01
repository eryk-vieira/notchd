import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "core"
import "core/settings"
import "core/Position.js" as Position

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
      { name: "a joined row's depth ignores a peek opening and closing", run: root.closedDepthTransitions },
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
      { name: "the visitor's hidden copies hold no compact view", run: root.visitorRestsWhileClosed },
      { name: "a visitor copy has a window only while it shows, and shortly after", run: root.visitorWindowOnlyWhileShown },
      { name: "notches, copies and modules survive a config edit", run: root.survivesConfigEdits },
      { name: "adding a notch and removing it gives the config back", run: root.addAndRemoveNotch },
      { name: "a notch kept on a screen stays there and a peek also shows where you work", run: root.peekBesideHomedNotch },
      { name: "an OSD peek shows once, on the focused screen only", run: root.osdPeekOnFocusedScreen },
      { name: "a standalone module shows in its own place, never in a notch", run: root.standaloneOwnPlace },
      { name: "a notch's settings all sit on its own page, under the Notches list", run: root.notchSettingsOnOnePage },
      { name: "a module no notch loads still has its settings page and title", run: root.unloadedModuleSettings },
      { name: "resources read the system", run: root.resourcesRead },
      { name: "resources show closed by default, or only once one runs short", run: root.resourcesCompactWhenShort },
      { name: "a timer counts down closed, peeks when it ends and goes back to rest", run: root.timerRunsAndEnds },
      { name: "timer commands: pomodoro phases, pause, errors and its settings", run: root.timerCommands },
      { name: "a module you type into takes the keyboard only while pinned open", run: root.keyboardOnlyWhilePinned },
      { name: "Escape in a field inside the notch closes it", run: root.escapeCloses },
      { name: "a module sets the width of its expanded view", run: root.expandedWidthFromModule },
      { name: "a notch in the list dropped on the top edge stays there", run: root.dropOnTopStays },
      { name: "corners: a side notch's place never feeds back into the insets it takes", run: root.cornersNoLoop },
      { name: "codex: without qmltermwidget, the notch says what to install", run: root.codexMissing },
      { name: "codex: runs in the notch, keeps running closed, and its title says when it works", run: root.codexRuns },
      { name: "claude: runs in the notch, keeps running closed, and its title says when it works", run: root.claudeRuns },
      { name: "claude: ask over IPC opens the notch and types the question in; new starts another", run: root.claudeAsk },
      { name: "claude: the closed notch keeps its size while it works", run: root.agentBusySteady },
      { name: "codex: closed and idle for idleMinutes, it stops; opened again, it starts", run: root.codexIdle },
      { name: "terminal: the band behind your messages (ANSI 8) is gray, not orange", run: root.messageBandGray },
      { name: "a window its monitor took away comes back with the monitor", run: root.keepShownReopens }
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
    readonly property bool reserveSpace: true
    property var compactModule: fakeModule
    readonly property var peekModule: fakeModule
    readonly property var expandedModules: []
    function togglePinned(screenName) {}
    function close() {}
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
    property var closedDepths: []
    onClosedDepthChanged: closedDepths = closedDepths.concat([closedDepth])
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

  // Bug: closing a peek, the notches joined to it grew for a moment and
  // shrank back, as if about to open. The row's depth went by the closing
  // card's own depth, still the peek's while its content faded out.
  function closedDepthTransitions() {
    var settle = 450
    var base = 0
    root.steps([
      [settle, function() { base = card.closedDepth; card.closedDepths = [] }],
      [0, function() { cardSvc.mode = "peek" }],
      [settle, function() { cardSvc.mode = "compact" }],
      [settle, function() { cardSvc.mode = "expanded" }],
      [settle, function() { cardSvc.mode = "compact" }],
      [settle, function() {}]
    ], function() {
      root.check(base > 0, "no closed depth measured")
      root.check(card.closedDepths.length === 0, "the closed depth moved: " + base + " then " + card.closedDepths)
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
        // A control that takes hover, like the media buttons.
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
    readonly property var compactModule: null
    readonly property var peekModule: null
    readonly property var expandedModules: [controlModule]
    property int pins: 0
    property int closes: 0
    function togglePinned(screenName) { pins++ }
    function close() { closes++ }
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

  // Bug: the visitor's copies (a fullscreen window per screen, hidden while
  // closed) showed the compact view of whatever was active. Music playing
  // kept the equalizer drawing frames in windows nobody could see.
  function visitorRestsWhileClosed() {
    var visitor = multi.visitor
    root.push("quiet", false)
    root.steps([
      [100, function() {
        root.check(visitor.copies.length === 2, "the visitor has " + visitor.copies.length + " copies, not one per screen")
        visitor.copies.forEach(function(c) {
          root.check(c.mode === "rest", "a closed visitor copy on " + c.fixedScreen + " shows " + c.mode)
        })
        twoScreens.focusedScreenName = "B"
        multi.requestPeek(multi.moduleById("activities"), 2000)
      }],
      [100, function() {
        root.check(visitor.copies.some(function(c) { return c.mode === "peek" }) || multi.peeking(multi.moduleById("activities")),
                   "nothing peeks")
        multi.dismissPeek(null)
      }]
    ], function() { root.done() })
  }

  // The visitor's copies held a fullscreen window each (its buffers, ~25 MB
  // per screen) while hidden. A guest's window now goes when it closes,
  // after `windowLinger`, so the close animation ends and a peek soon after
  // reuses it.
  function visitorWindowOnlyWhileShown() {
    var visitor = multi.visitor
    var copy = null
    var saved = multi.config
    visitor.copies.forEach(function(c) { c.windowLinger = 300 })
    // A notch kept on A, focus on B: a peek there goes to the visitor.
    multi.replaceConfig({ modules: ["activities"], position: { screen: "A" } })
    twoScreens.focusedScreenName = "B"
    root.steps([
      [100, function() {
        root.check(visitor.copies.every(function(c) { return !c.needsWindow }),
                   "a closed visitor copy wants a window: " + visitor.copies.map(function(c) { return c.mode }))
        root.check(multi.notches[0].copies.every(function(c) { return c.needsWindow }), "a notch of the config lost its window")
        multi.requestPeek(multi.moduleById("activities"), 400)
      }],
      [100, function() {
        copy = visitor.copyOn("B")
        root.check(!!copy && copy.mode === "peek", "the visitor does not peek on B: " + (copy ? copy.mode : "no copy"))
        root.check(!!copy && copy.needsWindow, "a peeking visitor copy has no window")
      }],
      [500, function() {
        root.check(copy.mode !== "peek", "the peek did not end")
        root.check(copy.needsWindow, "the window went before the notch finished closing")
      }],
      [400, function() {
        root.check(!copy.needsWindow, "the window stayed after windowLinger")
      }]
    ], function() {
      visitor.copies.forEach(function(c) { c.windowLinger = 5000 })
      multi.replaceConfig(saved)
      root.done()
    })
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

  // Standalone modules (the OSD) are never in a notch, even one whose
  // `modules` list them: they load on their own (unless switched off) and
  // peek in a notch of their own, on the focused screen, where
  // "<id>.position" says.
  NotchService {
    id: standaloneSvc
    ipcTarget: "notchd-qmltest-standalone"
    configPath: root.dir + "/standalone.json"
    compositor: twoScreens
    screens: [{ name: "A" }, { name: "B" }]
    defaultModules: ["activities"]
    hostModules: ({ osd: Qt.resolvedUrl("hosts/omarchy/modules/osd.qml") })
  }

  function standaloneOwnPlace() {
    var svc = standaloneSvc
    function own() { return svc.standaloneNotch("osd") }
    function osd() { return svc.moduleById("osd") }
    // Bug: in the Omarchy shell the OSD did not load at startup; the module
    // list was rebuilt before the standalone ids followed the module files.
    root.check(!!osd() && !!own(), "the OSD did not load at startup")
    root.steps([
      [0, function() {
        svc.replaceConfig({ modules: ["osd", "activities"], position: { screen: "all" } })
        twoScreens.focusedScreenName = "B"
      }],
      [100, function() {
        root.check(!!osd(), "the OSD did not load")
        root.check(svc.isStandalone("osd"), "the OSD is not standalone")
        root.check(svc.notches[0].modules.indexOf(osd()) === -1, "the notch took the OSD")
        root.check(!!own() && own().edge === "top" && own().placement.offset === 0.5, "no OSD place at the top center")
        osd().show(JSON.stringify({ icon: "volume", value: "40" }))
      }],
      [100, function() {
        root.check(own().copyOn("B").mode === "peek", "no peek on B: " + own().copyOn("B").mode)
        root.check(own().copyOn("A").mode !== "peek", "the OSD peeked on A too")
        root.check(svc.notches[0].copies.every(function(c) { return c.mode !== "peek" }), "a notch peeked")
        svc.dismissPeek(null)
        svc.setConfigValue("osd.position", { edge: "bottom", offset: 0.2 })
        twoScreens.focusedScreenName = "A"
      }],
      [100, function() {
        root.check(own().edge === "bottom" && own().placement.offset === 0.2, "position: " + JSON.stringify(own().placement))
        osd().show(JSON.stringify({ icon: "brightness", value: "70" }))
      }],
      [100, function() {
        root.check(own().copyOn("A").mode === "peek", "no peek on A: " + own().copyOn("A").mode)
        svc.dismissPeek(null)
        svc.setConfigValue("osd.enabled", false)
      }],
      [100, function() {
        root.check(osd() === null && own() === null, "switched off, the OSD still loads")
        root.check(svc.moduleCatalog.some(function(m) { return m.moduleId === "osd" && m.standalone }), "the OSD left the catalog")
        root.check(svc.settingsSchema.some(function(f) { return f.key === "osd.enabled" && f.page === "modules/osd" }), "no switch on its page")
        var lists = svc.settingsSchema.filter(function(f) { return f.type === "moduleCatalog" })
        root.check(lists.length === 2 && !lists[0].standalone && lists[1].standalone === true,
                   "the Modules page does not list standalone modules apart: " + JSON.stringify(lists))
        svc.setConfigValue("osd.enabled", undefined)
      }],
      [100, function() {
        root.check(!!osd() && !!own(), "switched back on, the OSD did not load")
        svc.replaceConfig({})
      }]
    ], function() { root.done() })
  }

  // A notch's keys were split between General and Modules, each with its own
  // picker. The Notches page lists the notches; every field for the picked
  // notch's keys sits on its own page, "notch/<index>"; the other pages only
  // have keys for every notch.
  function notchSettingsOnOnePage() {
    multi.replaceConfig({ notches: [{ modules: ["activities"] }, { id: "side", position: { edge: "bottom" } }] })
    multi.settingsPage = "notch/1"
    root.check(multi.settingsNotch === 1, "showing notch/1 edits notch " + multi.settingsNotch)
    var schema = multi.settingsSchema
    var lists = schema.filter(function(f) { return f.type === "notches" })
    root.check(lists.length === 1 && lists[0].page === "notch", "lists: " + JSON.stringify(lists.map(function(f) { return f.page })))
    schema.forEach(function(f) {
      var own = !!f.key && f.key.indexOf("notches.") === 0
      if (own) root.check(f.page === "notch/1", f.key + " is on " + f.page)
      else if (f.key && f.key !== "notches") root.check(f.page.indexOf("notch") !== 0, f.key + " applies to every notch but is on " + f.page)
    })
    root.check(schema.some(function(f) { return f.key === "notches.1.modules" }), "the notch's modules are missing")
    root.check(multi.settingsPages.some(function(p) { return p.id === "notch/1" && p.label === "side" }), "no page for side")
    multi.settingsPage = "general"
    multi.openSettings(0)
    root.check(multi.settingsPage === "notch/0" && multi.settingsNotch === 0, "openSettings(0) opened " + multi.settingsPage)
    multi.closeSettings()
    multi.replaceConfig({})
    root.done()
  }

  // A module's settings were read from the loaded module, so one no notch
  // showed had no page and no gear. They come from its JSON file now.
  function unloadedModuleSettings() {
    root.check(multi.moduleById("timer") === null, "timer is loaded (test setup)")
    var fields = multi.settingsSchema.filter(function(f) { return f.page === "modules/timer" })
    root.check(fields.some(function(f) { return f.key === "timer.focus" }), "timer fields: " + JSON.stringify(fields.map(function(f) { return f.key })))
    root.check(multi.settingsPages.some(function(p) { return p.id === "modules/timer" && p.label === "Timer" }), "no page for timer")
    root.check(multi.moduleSetting("timer", "focus") === 25, "default: " + multi.moduleSetting("timer", "focus"))
    multi.setConfigValue("timer.focus", 50)
    root.check(multi.moduleSetting("timer", "focus") === 50, "set: " + multi.moduleSetting("timer", "focus"))
    var media = multi.moduleCatalog.filter(function(m) { return m.moduleId === "media" })[0]
    root.check(!!media && media.title === "Now playing", "media: " + JSON.stringify(media))
    var activities = multi.moduleById("activities")
    root.check(!!activities && activities.title === "Activities", "loaded title: " + (activities ? activities.title : ""))
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
  // the module's own page, under the module's id.
  function resourcesCompactWhenShort() {
    var m = resourced.moduleById("resources")
    var notch = resourced.notches[0]
    m.sampling = false
    m.pressure = ({})
    resourced.replaceConfig({})
    m.record("memory", 0.5)
    root.check(notch.compactModule === m && m.compactRows.length === 3, "not shown by default")
    var field = resourced.settingsSchema.filter(function(f) { return f.key === "resources.compact" })[0]
    root.check(!!field && field.page === "modules/resources", "field: " + JSON.stringify(field))

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
    var keys = timed.settingsSchema.filter(function(f) { return f.page === "modules/timer" }).map(function(f) { return f.key })
    root.check(keys.indexOf("timer.focus") !== -1 && keys.indexOf("timer.notify") !== -1, "settings: " + keys)
    m.command("stop")
    timed.dismissPeek(null)
    timed.replaceConfig({})
    root.done()
  }

  // ------------------------------------------------------------ keyboard
  // A notch window takes the keyboard (layer-shell Exclusive) only while
  // pinned open on a module you type into: hover alone must never take it
  // from the window you are typing in.
  NotchService {
    id: typer
    ipcTarget: "notchd-qmltest-typing"
    configPath: root.dir + "/typing.json"
    compositor: workspace4
    hostModules: ({ typing: Qt.resolvedUrl("fixtures/typing.qml") })
    defaultModules: ["typing"]
  }

  function keyboardOnlyWhilePinned() {
    root.steps([[100, function() {}]], function() {
      var module = typer.moduleById("typing")
      var copy = typer.notches.length > 0 ? typer.notches[0].copies[0] : null
      if (!root.check(!!module && !!copy, "the typing module or its notch did not load")) { root.done(); return }
      root.check(copy.keyboardFocus === "none", "closed, it takes the keyboard: " + copy.keyboardFocus)
      copy.hovered = true
      root.check(copy.mode === "expanded", "hovered, it is " + copy.mode)
      root.check(copy.keyboardFocus === "none", "hover alone took the keyboard")
      module.requestKeyboard()
      root.check(copy.pinned, "a press on the field did not pin the notch")
      root.check(copy.keyboardFocus === "exclusive", "pinned on the field, it takes " + copy.keyboardFocus)
      copy.close()
      root.check(copy.keyboardFocus === "none", "closed again, it keeps the keyboard")
      root.done()
    })
  }

  function expandedWidthFromModule() {
    var copy = typer.notches.length > 0 ? typer.notches[0].copies[0] : null
    copy.open()
    root.steps([[500, function() {}]], function() {
      root.check(typingCard.mode === "expanded", "the card is " + typingCard.mode)
      root.check(typingCard.width >= Theme.space(520) && typingCard.width < Theme.space(640),
                 "a 520 px expanded view made a card " + typingCard.width + " wide")
      copy.close()
      root.done()
    })
  }
  NotchCard {
    id: typingCard
    notch: typer.notches.length > 0 ? typer.notches[0].copies[0] : null
  }

  // Escape from a field in a view goes up to the card, which closes the
  // notch.
  QtObject {
    id: escapeModule
    property var field: null
    readonly property Component expanded: Component {
      TextInput {
        text: "type here"
        Component.onCompleted: escapeModule.field = this
      }
    }
  }
  QtObject {
    id: escapeSvc
    readonly property string mode: "expanded"
    readonly property string edge: "top"
    readonly property var compactModule: null
    readonly property var peekModule: null
    readonly property var expandedModules: [escapeModule]
    property int closes: 0
    function togglePinned(screenName) {}
    function close() { closes++ }
  }
  FloatingWindow {
    id: escapeWin
    implicitWidth: 500
    implicitHeight: 300
    NotchCard { id: escapeCard; notch: escapeSvc; x: 50 }
    // Keys go to a TestCase's own window: this one sits in it.
    TestCase { id: keys; when: false }
  }

  function escapeCloses() {
    root.steps([[500, function() {
      if (!root.check(!!escapeModule.field, "the field did not load")) return
      escapeModule.field.forceActiveFocus()
      root.check(escapeModule.field.activeFocus, "the field did not take focus (test setup)")
      keys.keyClick(Qt.Key_Escape)
    }], [50, function() {}]], function() {
      root.check(escapeSvc.closes === 1, "Escape closed it " + escapeSvc.closes + " times")
      root.done()
    })
  }

  // ------------------------------------------------------------------ drop
  // Bug: with the top-level position on the left, a notch in `notches`
  // dropped on the top edge was saved without `edge` (top is the default),
  // took "left" from the top level and jumped back. The drop saves what
  // NotchWindow saves: Position.configValue(drop, notch.inheritedPosition).
  NotchService {
    id: dropSvc
    ipcTarget: "notchd-qmltest-drop"
    configPath: root.dir + "/drop.json"
    compositor: workspace4
    defaultModules: ["activities"]
  }

  function dropOnTopStays() {
    dropSvc.replaceConfig({ position: { edge: "left", offset: 0.9, screen: "DP-1" },
                            notches: [{}, { id: "side", modules: ["activities"] }] })
    var side = dropSvc.notchById("side")
    if (!root.check(!!side && side.edge === "left", "the second notch should start on the left")) { root.done(); return }
    var drop = { edge: "top", offset: 0.5, screen: "DP-1" }
    side.setValue("position", Position.configValue(drop, side.inheritedPosition))
    root.check(side.edge === "top", "dropped on the top edge, it went to " + side.edge)
    root.check(side.placement.offset === 0.5, "dropped in the middle, it is at " + side.placement.offset)
    var main = dropSvc.notchById("main")
    main.setValue("position", Position.configValue({ edge: "top", offset: 0.5, screen: "" }, main.inheritedPosition))
    root.check(main.edge === "top" && main.placement.screen === "", "the first notch went to " + JSON.stringify(main.placement))
    root.done()
  }

  // ---------------------------------------------------------------- agents
  // The claude and codex modules (TerminalModule) against fake terminal UIs
  // (tests/qml/fixtures/bin) that set the terminal's title as Claude Code and
  // Codex do. The terminal needs the qmltermwidget package; where it isn't
  // installed, the cases that need it note so in the log and pass.
  NotchService {
    id: codexSvc
    ipcTarget: "notchd-qmltest-codex"
    configPath: root.dir + "/codex.json"
    compositor: workspace4
    defaultModules: ["codex"]
  }
  FloatingWindow {
    id: codexWin
    implicitWidth: 900
    implicitHeight: 600
    NotchCard { notch: codexSvc.notches.length > 0 ? codexSvc.notches[0].copies[0] : null }
    TestCase { id: codexKeys; when: false }
  }
  NotchService {
    id: claudeSvc
    ipcTarget: "notchd-qmltest-claude"
    configPath: root.dir + "/claude.json"
    compositor: workspace4
    defaultModules: ["claude"]
  }
  FloatingWindow {
    id: claudeWin
    implicitWidth: 900
    implicitHeight: 600
    NotchCard { id: claudeCard; notch: claudeSvc.notches.length > 0 ? claudeSvc.notches[0].copies[0] : null }
    TestCase { id: claudeKeys; when: false }
  }

  // Runs a command; `out` and `code` once it exits.
  Process {
    id: shellCmd
    property int code: -1
    property string out: ""
    stdout: StdioCollector { onStreamFinished: shellCmd.out = text }
    onExited: function(code) { shellCmd.code = code }
  }
  function run(argv) {
    shellCmd.out = ""
    shellCmd.code = -1
    shellCmd.command = argv
    shellCmd.running = true
  }

  // The terminal is not there: the case only notes it.
  function noTerminal(m) {
    if (m.available) return false
    console.log("NOTE " + root.current + ": qmltermwidget is not installed; the terminal was not tested")
    root.done()
    return true
  }

  function codexMissing() {
    var m = codexMissingSvc.moduleById("codex")
    if (!root.check(!!m, "the codex module did not load")) { root.done(); return }
    m.available = false
    codexMissingSvc.open()
    root.steps([[500, function() {}]], function() {
      root.check(m.viewsOpen === 1, "the notch did not open on it: " + m.viewsOpen)
      root.check(m.term === null && m.loadError === "", "it tried to start a terminal")
      codexMissingSvc.close()
      root.done()
    })
  }
  NotchService {
    id: codexMissingSvc
    ipcTarget: "notchd-qmltest-codex-missing"
    configPath: root.dir + "/codex-missing.json"
    compositor: workspace4
    defaultModules: ["codex"]
  }
  NotchCard { notch: codexMissingSvc.notches.length > 0 ? codexMissingSvc.notches[0].copies[0] : null }

  // One agent from start to restart: its command line and folder, Escape
  // going to it, the dot and the title from its terminal's title, parked
  // while closed and still running, a peek when it finishes while closed,
  // the same terminal back on reopening, a new one (and the old one
  // stopped) on restart, and noticing when it quits.
  function agentRuns(svc, keys, id, expected) {
    var m = svc.moduleById(id)
    if (!root.check(!!m, "the " + id + " module did not load")) { root.done(); return }
    if (root.noTerminal(m)) return
    var cfg = {}
    cfg[id] = { directory: root.dir }
    svc.replaceConfig(cfg)
    var copy = svc.notches[0].copies[0]
    var argsFile = root.dir + "/" + id + "-args"
    var first = null, pid = ""
    svc.open()
    root.steps([
      [900, function() {
        first = m.term
        if (!root.check(!!first, "opening the notch started no terminal")) return
        root.check(!m.working && m.sessionTitle === "", "after starting: working " + m.working + ", title " + m.sessionTitle)
        root.check(first.activeFocus, "the terminal does not have the focus")
        // Escape goes to the agent: the notch stays open.
        keys.keyClick(Qt.Key_Escape)
        // The Escape is on the fake's line: end that line first.
        first.write("\rwork\r")
        root.run(["cat", argsFile])
      }],
      [200, function() {
        var args = shellCmd.out.split("\n")
        root.check(args[0] === "", id + " got options: " + args[0])
        root.check(args[1] === root.dir, id + " started in " + args[1])
        pid = args[2]
        root.check(copy.pinned, "Escape closed the notch")
        root.check(m.working, "the spinner did not make it working")
      }],
      [900, function() {
        root.check(!m.working && m.sessionTitle === expected, "after work: working " + m.working + ", title " + m.sessionTitle)
        m.closeNotch()
      }],
      [600, function() {
        root.check(m.viewsOpen === 0 && m.term === first && first.parent === m, "closing did not park the terminal")
        root.check(!m.exited, "closing stopped it")
        m.typed = true
        first.write("work\r")
      }],
      [1100, function() {
        root.check(copy.peekModule === m, "the end of work while closed did not peek")
        svc.open()
      }],
      [500, function() {
        root.check(m.term === first && first.parent !== m && first.visible, "reopened, it did not show the same terminal")
        m.restart()
      }],
      [900, function() {
        root.check(m.term !== first && !!m.term && !m.exited, "restart did not start a new terminal")
        root.run(["cat", argsFile])
      }],
      [300, function() {
        root.check(shellCmd.out.split("\n")[2] !== pid, "the new terminal runs the old " + id)
        root.run(["kill", "-0", pid])
      }],
      [300, function() {
        root.check(shellCmd.code !== 0, "the old " + id + " (" + pid + ") still runs after restart")
        m.term.write("quit\r")
      }],
      [500, function() {
        root.check(m.exited && !m.working, id + " quit and the module did not notice")
        svc.close()
      }]
    ], function() {
      m.stop()
      root.done()
    })
  }
  function codexRuns() { root.agentRuns(codexSvc, codexKeys, "codex", "Fake thread") }
  function claudeRuns() { root.agentRuns(claudeSvc, claudeKeys, "claude", "Fake conversation") }

  // Over IPC: ask opens the notch with the keyboard and types the question
  // in once the agent is up; new starts another; anything else, the usage.
  function claudeAsk() {
    var m = claudeSvc.moduleById("claude")
    if (root.noTerminal(m)) return
    var copy = claudeSvc.notches[0].copies[0]
    var pid = ""
    root.steps([
      // The last case's view is still closing.
      [600, function() {
        root.check(m.command("nonsense").indexOf("usage") === 0, "an unknown command did not answer the usage")
        root.check(m.command("ask why is the sky blue?") === "ok", "ask failed")
        root.check(copy.pinned && copy.keyboardFocus === "exclusive", "ask did not open the notch with the keyboard")
      }],
      [1500, function() { root.run(["cat", root.dir + "/claude-args"]) }],
      [300, function() {
        var lines = shellCmd.out.split("\n")
        root.check(lines.indexOf("got why is the sky blue?") !== -1, "the question did not reach claude: " + JSON.stringify(lines))
        pid = lines[2]
        root.check(m.command("new") === "ok", "new failed")
      }],
      [900, function() { root.run(["cat", root.dir + "/claude-args"]) }],
      [300, function() {
        root.check(shellCmd.out.split("\n")[2] !== pid, "new did not start another claude")
        m.closeNotch()
      }]
    ], function() {
      m.stop()
      root.done()
    })
  }

  // Bug (claude chat, kept for the terminal): while busy the mark cycled
  // through glyphs of different widths, so the closed notch kept resizing
  // (it springs to fit). Now the mark stays, and the working dot's place is
  // kept while it is off.
  function agentBusySteady() {
    var m = claudeSvc.moduleById("claude")
    claudeSvc.close()
    var widths = []
    root.steps([
      [600, function() { m.status = { working: false, title: "A title" } }],
      [500, function() { widths.push(claudeCard.width) }],
      [0, function() { m.status = { working: true, title: "A title" } }],
      [500, function() { widths.push(claudeCard.width) }],
      [130, function() { widths.push(claudeCard.width) }],
      [130, function() { widths.push(claudeCard.width) }]
    ], function() {
      root.check(claudeCard.mode === "compact", "the notch is " + claudeCard.mode)
      var min = Math.min.apply(null, widths), max = Math.max.apply(null, widths)
      root.check(max - min < 0.5, "the closed notch changed width going busy and while busy: " + JSON.stringify(widths))
      m.status = { working: false, title: "" }
      root.done()
    })
  }

  function codexIdle() {
    var m = codexSvc.moduleById("codex")
    if (root.noTerminal(m)) return
    // 0.02 min: 1.2 s.
    codexSvc.replaceConfig({ codex: { directory: root.dir, idleMinutes: 0.02 } })
    root.steps([
      // The last case's view is still closing.
      [600, function() { codexSvc.open() }],
      [800, function() {
        root.check(!!m.term, "opening started no terminal")
        codexSvc.close()
      }],
      [700, function() { root.check(!!m.term, "it stopped before idleMinutes") }],
      [1200, function() {
        root.check(m.term === null, "closed and idle, it kept running")
        codexSvc.open()
      }],
      [600, function() {
        root.check(!!m.term && !m.exited, "opened again, no new terminal")
        codexSvc.close()
      }]
    ], function() {
      m.stop()
      codexSvc.replaceConfig({})
      root.done()
    })
  }

  // Bug: the messages you sent to Codex sat on an orange band. Codex can't
  // ask this terminal for its background (no OSC 11 answer), so it paints
  // them with ANSI 8, Breeze's orange. A terminal paints a band in ANSI 8;
  // the grab's pixel must be a gray.
  Item { id: bandHolder; parent: codexWin.contentItem; y: 500; width: 300; height: 60 }
  Canvas {
    id: bandCanvas
    parent: codexWin.contentItem
    width: 1; height: 1
    property var done: null
    onImageLoaded: requestPaint()
    onPaint: {
      if (!bandCanvas.done) return
      var ctx = getContext("2d")
      ctx.drawImage(bandCanvas.done.url, -40, -8)
      var px = ctx.getImageData(0, 0, 1, 1).data
      var cb = bandCanvas.done.cb
      bandCanvas.done = null
      cb([px[0], px[1], px[2]])
    }
  }
  function messageBandGray() {
    var m = codexSvc.moduleById("codex")
    if (root.noTerminal(m)) return
    var c = Qt.createComponent(Qt.resolvedUrl("core/terminal/TerminalView.qml"))
    var t = c.createObject(bandHolder, { program: "/bin/sh", width: 300, height: 60,
      programArguments: ["-c", "printf '\\033[48;5;8m%30s\\033[0m\\n' ''; sleep 5"] })
    var file = root.dir + "/band.png"
    var rgb = null
    root.steps([
      [700, function() {
        bandHolder.grabToImage(function(result) {
          result.saveToFile(file)
          bandCanvas.done = { url: "file://" + file, cb: function(px) { rgb = px } }
          bandCanvas.loadImage("file://" + file)
        })
      }],
      [500, function() {}]
    ], function() {
      if (root.check(rgb !== null, "could not read the band's color")) {
        var spread = Math.max(rgb[0], rgb[1], rgb[2]) - Math.min(rgb[0], rgb[1], rgb[2])
        root.check(spread < 16, "the band is not gray: rgb " + rgb.join(","))
      }
      t.destroy()
      root.done()
    })
  }

  // ---------------------------------------------------------------- corners
  // Bug: NotchSurface read every window's cornerItem for the insets side
  // notches take, then threw the side ones away; the binding still depended
  // on them, and a side notch's cornerItem comes from its place, which comes
  // from those insets: ~1300 binding-loop warnings at start, with notches on
  // the top and left edges of one screen. The same bindings as NotchSurface
  // and NotchWindow, on plain objects (PanelWindow can't load offscreen);
  // qml-test.sh fails on the warning a loop logs.
  QtObject {
    id: cornerSurface
    property var windows: []
    readonly property var cornerInsets: Position.corners(cornerSurface.windows.map(function(w) { return Position.cornerInput(w, false) }))
    function insetOf(w) { var i = cornerSurface.windows.indexOf(w); return i >= 0 ? cornerSurface.cornerInsets[i] : null }
  }
  QtObject {
    id: cornerTop
    readonly property string edge: "top"
    readonly property string windowScreenName: "A"
    readonly property var cornerItem: ({ screen: "A", edge: "top", atStart: true, atEnd: false, depth: 30, shown: true })
  }
  QtObject {
    id: cornerSide
    readonly property string edge: "left"
    readonly property string windowScreenName: "A"
    // Its place starts below the inset the top notch gives it.
    readonly property var inset: cornerSurface.insetOf(cornerSide)
    readonly property var cornerItem: ({ screen: "A", edge: "left", atStart: !cornerSide.inset || cornerSide.inset.start === 0,
                                         atEnd: false, depth: 20, shown: true })
  }
  function cornersNoLoop() {
    cornerSurface.windows = [cornerTop, cornerSide]
    var inset = cornerSide.inset
    root.check(!!inset && inset.start > 0, "the side notch takes no inset from the top one: " + JSON.stringify(inset))
    root.check(cornerSide.cornerItem.atStart === false, "the side notch's place ignored its inset")
    cornerSurface.windows = []
    root.done()
  }

  // ------------------------------------------------------- monitor off/on
  // Bug: switching a monitor off and on left the notches gone. The
  // compositor closes the layer surfaces on an output that goes away and
  // Quickshell marks those windows hidden itself; their `visible` binding
  // never changed, so nothing showed them again. A stand-in for the window
  // (PanelWindow can't load offscreen): `closed` is the compositor closing
  // it, and setting `visible` true again (KeepShown.shown) reopens it.
  QtObject {
    id: keptWindow
    property bool closed: false
    readonly property bool visible: windowKept.shown && !keptWindow.closed
    readonly property Connections reopened: Connections {
      target: windowKept
      function onShownChanged() { if (windowKept.shown) keptWindow.closed = false }
    }
  }
  KeepShown {
    id: windowKept
    target: keptWindow
    wanted: false
  }
  function keepShownReopens() {
    windowKept.wanted = true
    windowKept.screen = { name: "A" }
    root.check(keptWindow.visible, "not shown at first")
    root.steps([
      // Its monitor goes off: closed, and its copy moves to another screen.
      [0, function() { keptWindow.closed = true; windowKept.screen = { name: "B" } }],
      [50, function() {
        root.check(keptWindow.visible, "not back on the screen it moved to")
        // Every monitor off: closed, and nowhere to go.
        keptWindow.closed = true
        windowKept.screen = null
      }],
      [50, function() {
        root.check(!keptWindow.visible, "shown with no screen")
        windowKept.screen = { name: "A" }
      }],
      [50, function() {
        root.check(keptWindow.visible, "not back when a monitor came back")
        // Closed on the same screen: back too.
        keptWindow.closed = true
      }],
      [50, function() { root.check(keptWindow.visible, "not back after a close on the same screen") }]
    ], function() {
      windowKept.wanted = false
      windowKept.screen = null
      root.done()
    })
  }
}
