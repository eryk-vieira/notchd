import QtQuick
import "State.js" as State

// A notch on screen: one copy of a Notch, with the state the pointer and
// peeks change (hover, pin, peek, drag) and so its own mode. A notch that
// moves has one copy, and this picks its screen; a notch on every screen
// has one copy per screen (`fixedScreen`). NotchCard draws a copy and
// NotchWindow puts it on its screen.
Item {
  id: copy
  visible: false

  property var owner: null
  // The screen this copy stays on; "" for the copy that moves.
  property string fixedScreen: ""

  readonly property var svc: copy.owner ? copy.owner.svc : null

  // ------------------------------------------------- what the card reads
  readonly property string edge: copy.owner ? copy.owner.edge : "top"
  readonly property bool vertical: !!copy.owner && copy.owner.vertical
  readonly property var placement: copy.owner ? copy.owner.placement : ({ edge: "top", offset: 0.5, screen: "" })
  readonly property string compactStyle: copy.owner ? copy.owner.compactStyle : "notch"
  readonly property bool reserveSpace: !!copy.owner && copy.owner.reserveSpace
  readonly property bool canDrag: !!copy.owner && copy.owner.canDrag
  readonly property var compactModule: copy.owner ? copy.owner.compactModule : null
  readonly property var expandedModules: copy.owner ? copy.owner.expandedModules : []

  // ------------------------------------------------------------------ peek
  property var peekModule: null

  function requestPeek(module, ms) {
    if (!State.canPeek(module, { pinned: copy.pinned, hovered: copy.hovered,
                                 current: copy.peekModule, currentShowing: peekTimer.running })) return
    copy.peekModule = module
    peekTimer.interval = Math.max(400, Number(ms) || 2500)
    peekTimer.restart()
  }

  function dismissPeek(module) {
    if (!module || copy.peekModule === module) {
      peekTimer.stop()
      copy.peekModule = null
    }
  }

  Timer { id: peekTimer; onTriggered: copy.peekModule = null }

  // ----------------------------------------------------------------- hover
  // Several surfaces report the pointer (the notch card, the bar indicator
  // on this copy's screen); the copy counts as hovered while any has it.
  property var pointerSources: ({})
  readonly property bool pointerInside: Object.keys(copy.pointerSources).length > 0
  property bool hovered: false
  property bool pinned: false

  // The screen the pointer opened the copy that moves on; it stays there
  // while open instead of following focus (the closed notch can hang on a
  // screen without focus).
  property string openScreen: ""

  function setPointer(source, inside, screenName) {
    var next = Object.assign({}, copy.pointerSources)
    if (inside) next[source] = true
    else delete next[source]
    copy.pointerSources = next
    if (inside && screenName) copy.openScreen = screenName
  }

  onPointerInsideChanged: {
    if (pointerInside) { closeTimer.stop(); openTimer.restart() }
    else {
      openTimer.stop()
      closeTimer.restart()
      // Left before it opened: forget the screen it was about to open on.
      if (!copy.isOpen) copy.openScreen = ""
    }
  }
  onHoveredChanged: if (hovered && copy.peekModule && !copy.peekModule.urgentPeek) copy.dismissPeek()
  onPinnedChanged: if (pinned) copy.dismissPeek()
  onModeChanged: if (!copy.isOpen) copy.openScreen = ""

  Timer { id: openTimer; interval: copy.svc ? copy.svc.hoverOpenDelay : 0; onTriggered: if (!copy.dragging) copy.hovered = true }
  Timer { id: closeTimer; interval: copy.svc ? copy.svc.hoverCloseDelay : 0; onTriggered: copy.hovered = false }

  // While dragged the copy stays closed (State.mode) and nothing opens it;
  // dropping it leaves it closed until the pointer comes back.
  property bool dragging: false
  function setDragging(on) {
    copy.dragging = on
    openTimer.stop()
    copy.pinned = false
    copy.hovered = false
  }

  function open() { copy.pinned = true }
  function close() { copy.pinned = false; copy.hovered = false }
  function togglePinned(screenName) {
    if (screenName) copy.openScreen = screenName
    copy.pinned = !copy.pinned
  }
  // The settings window, on this notch's page.
  function openSettings() { if (copy.svc) copy.svc.openSettings(copy.owner ? copy.owner.index : 0) }

  // ------------------------------------------------------------------ mode
  readonly property string mode: State.mode({ peekModule: copy.peekModule, pinned: copy.pinned, dragging: copy.dragging,
                                             hovered: copy.hovered, compactModule: copy.compactModule })
  readonly property bool isOpen: copy.mode === "peek" || copy.mode === "expanded"

  // ---------------------------------------------------------------- screen
  readonly property var compositor: copy.svc ? copy.svc.compositor : null
  readonly property string focusedScreenName: copy.compositor ? copy.compositor.focusedScreenName : ""
  // Every screen, and whether its workspace takes the closed notch.
  readonly property var screenStates: {
    var screens = copy.svc ? copy.svc.screens : []
    var list = []
    for (var i = 0; i < screens.length; i++)
      list.push({ name: screens[i].name, allowed: !copy.owner || copy.owner.showsOn(screens[i]) })
    return list
  }
  function stateOf(name) {
    for (var i = 0; i < copy.screenStates.length; i++)
      if (copy.screenStates[i].name === name) return copy.screenStates[i]
    return null
  }
  // The screen the config's position names, where the closed notch stays.
  readonly property string homeScreen: copy.fixedScreen !== "" ? copy.fixedScreen : copy.placement.screen
  // The screen the copy wants, "" when none takes the closed notch. A copy
  // on its own screen stays there; the one that moves goes where
  // State.notchScreen says.
  readonly property string wantedScreen: {
    if (copy.fixedScreen !== "") {
      var own = copy.stateOf(copy.fixedScreen)
      return copy.isOpen || (own && own.allowed) ? copy.fixedScreen : ""
    }
    return State.notchScreen({
      screens: copy.screenStates, focused: copy.focusedScreenName, open: copy.isOpen,
      override: copy.openScreen, home: copy.homeScreen
    })
  }
  readonly property bool offWorkspace: copy.wantedScreen === ""
  // Where its window goes: the wanted screen; with none, its own screen or
  // the focused one, concealed.
  readonly property string screenName: copy.wantedScreen !== "" ? copy.wantedScreen
    : copy.fixedScreen !== "" ? copy.fixedScreen : copy.focusedScreenName

  // The screens that keep windows clear of the closed notch (reserveSpace):
  // a copy on its own screen reserves there while it may hang there; the
  // one that moves as State.reserveScreens says.
  readonly property var reservedScreens: {
    if (copy.fixedScreen !== "") {
      var own = copy.stateOf(copy.fixedScreen)
      return own && own.allowed ? [copy.fixedScreen] : []
    }
    return State.reserveScreens(copy.screenStates, copy.homeScreen)
  }
}
