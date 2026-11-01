import QtQuick
import Quickshell
import "State.js" as State
import "Position.js" as Position
import "Navigate.js" as Navigate

// One notch of the config's `notches` (or the top-level one): its modules,
// where it hangs and how. NotchService makes one per notch; it shows as
// copies (NotchCopy), which hold the state the pointer and peeks change,
// while this holds what they share:
//   following focus      one copy, which moves to the focused screen
//   kept on a screen     one copy, which stays where it hangs (its home, or
//                        where `workspaces` sends it), peeks included
//   on every screen      ("all") a copy per screen, each a
//                        notch of its own
//
// The service also makes one `visitor`: no config of its own, every module,
// a copy per screen at the top, each hidden until it shows a peek on a
// screen where no notch with that module does (State.needsVisitor). And one
// per standalone module switched on (`standaloneId`): only that module, on
// every screen where "<id>.position" says, hidden until it peeks.
Item {
  id: notch
  visible: false

  property var svc: null
  property string notchId: ""
  // The visitor, rather than a notch of the config.
  property bool visitor: false
  // A standalone module's own notch: it shows only that module, where the
  // module's "<id>.position" says.
  property string standaloneId: ""
  // The visitor or a standalone notch: hidden while closed, a copy on every
  // screen, only there for peeks (NotchCopy.guest).
  readonly property bool guest: notch.visitor || notch.standaloneId !== ""

  // ---------------------------------------------------------------- config
  // The resolved entry (Config.notches); keeps the last one while the id is
  // on its way out.
  readonly property var spec: notch.svc ? notch.svc.notchSpec(notch.notchId) : null
  readonly property int index: notch.spec ? notch.spec.index : 0
  // Never a standalone module, but in its own notch.
  readonly property var moduleIds: {
    if (notch.standaloneId !== "") return [notch.standaloneId]
    var list = notch.visitor ? (notch.svc ? notch.svc.moduleIds : []) : notch.spec ? notch.spec.moduleIds : []
    var service = notch.svc
    return service ? list.filter(function(id) { return !service.isStandalone(id) }) : list
  }
  // Keep windows out of the strip the closed notch hangs into; NotchSurface
  // reserves it.
  readonly property bool reserveSpace: !!notch.spec && notch.spec.reserveSpace
  // The open notch shows one module at a time, picked from tabs.
  readonly property bool tabs: !!notch.spec && notch.spec.tabs
  // A module with nothing to show closed shows its icon there.
  readonly property bool idleIcons: !!notch.spec && notch.spec.idleIcons
  // Workspaces the closed notch hangs on (ids or names); null: every one.
  readonly property var workspaces: notch.spec ? notch.spec.workspaces : null
  // The configured position, { edge, offset, screen } (Position.js).
  readonly property var position: Position.resolve(notch.standaloneId !== "" ? (notch.svc ? notch.svc.standalonePosition(notch.standaloneId) : { screen: Position.ALL_SCREENS })
    : notch.visitor ? { screen: Position.ALL_SCREENS }
    : notch.spec ? notch.spec.position : undefined)
  // Where it is.
  readonly property var placement: notch.position
  readonly property string edge: notch.placement.edge
  readonly property bool vertical: Position.isVertical(notch.edge)
  // A copy on every screen, each showing the notch.
  readonly property bool everyScreen: notch.placement.screen === Position.ALL_SCREENS
  // Kept on one screen (its home), by name.
  readonly property bool homed: !notch.everyScreen && notch.placement.screen !== ""
  // Whether it can be dragged to another edge.
  readonly property bool canDrag: !!notch.spec && notch.spec.draggable

  // The config key for one of this notch's keys: "position" at the top
  // level, "notches.<index>.position" in a list.
  // The position it takes without a key of its own: in `notches`, the
  // top-level one (Config.notches merges it key by key); else the defaults.
  readonly property var inheritedPosition: notch.spec && notch.spec.prefix !== "" && notch.svc
    ? notch.svc.configValue("position") : undefined

  function configKey(key) { return (notch.spec ? notch.spec.prefix : "") + key }
  function setValue(key, value) { if (notch.svc) notch.svc.setConfigValue(notch.configKey(key), value) }

  // Whether the closed notch hangs on `screen`, by the workspace it shows.
  // Bindings that call it follow workspace switches.
  function showsOn(screen) {
    var compositor = notch.svc ? notch.svc.compositor : null
    var ws = compositor && screen ? compositor.activeWorkspace(screen) : null
    return State.workspaceAllowed(notch.workspaces, ws)
  }

  // --------------------------------------------------------------- modules
  // Its modules, in its order, out of the ones the service loaded.
  readonly property var modules: {
    var out = []
    var loaded = notch.svc ? notch.svc.modules : []
    for (var i = 0; i < notch.moduleIds.length; i++)
      for (var j = 0; j < loaded.length; j++)
        if (loaded[j].moduleId === notch.moduleIds[i]) { out.push(loaded[j]); break }
    return out
  }
  function hasModule(module) { return !!module && notch.modules.indexOf(module) !== -1 }

  // State.js has the rules; bindings read each module's `active` and
  // `priority`, so they re-run when any module changes state.
  readonly property var activeModules: State.activeModules(notch.modules)
  readonly property var compactModule: State.compactModule(notch.activeModules)
  // What the closed notch shows side by side (State.compactModules): with
  // tabs, every active module's compact view; else the compact module's.
  // With idleIcons, a module with nothing to show closed as its icon.
  readonly property var compactModules: State.compactModules(notch.activeModules, notch.tabs, notch.idleIcons)
  readonly property var expandedModules: notch.activeModules.filter(function(m) { return !!m.expanded })

  // ---------------------------------------------------------------- screens
  readonly property string focusedScreenName: notch.svc && notch.svc.compositor ? notch.svc.compositor.focusedScreenName : ""
  // Every screen, and whether its workspace takes the closed notch.
  readonly property var screenStates: {
    var screens = notch.svc ? notch.svc.screens : []
    var list = []
    for (var i = 0; i < screens.length; i++)
      list.push({ name: screens[i].name, allowed: notch.showsOn(screens[i]) })
    return list
  }

  // ---------------------------------------------------------------- copies
  // Screen names, one copy each; [""] for the one copy that moves.
  readonly property var copyScreens: notch.everyScreen
    ? (notch.svc ? notch.svc.screens : []).map(function(s) { return s.name }) : [""]

  Variants {
    id: copyVariants
    readonly property var owner: notch
    model: notch.copyScreens
    NotchCopy {
      required property var modelData
      owner: copyVariants.owner
      fixedScreen: modelData
    }
  }
  readonly property var copies: copyVariants.instances

  // The copy on a screen; the one copy, for a notch that moves.
  function copyOn(screenName) {
    var list = notch.copies
    if (!notch.everyScreen) return list.length > 0 ? list[0] : null
    for (var i = 0; i < list.length; i++) if (list[i].fixedScreen === screenName) return list[i]
    return null
  }

  // The copy that peeks or opens: the one on the focused screen, if there is
  // one per screen (State.peekCopy).
  function focusedCopy() {
    var name = State.peekCopy(notch.copyScreens, notch.focusedScreenName)
    return name === null ? null : notch.copyOn(name)
  }

  // ----------------------------------------------------------------- peeks
  // A module's peek, if this notch shows the module: on the focused copy,
  // or the one copy wherever it is.
  function requestPeek(module, ms) {
    if (notch.hasModule(module)) notch.showPeek(module, ms)
  }
  // The peek, whether this notch lists the module or not: a system module's
  // borrows the notch on the screen you work on.
  function showPeek(module, ms) {
    var copy = notch.focusedCopy()
    if (copy) copy.requestPeek(module, ms)
  }
  // How it peeks, for State.needsVisitor: on the focused screen, or, kept
  // on a screen, where it is.
  function peekPlace() {
    if (!notch.homed) return { kind: notch.everyScreen ? "all" : "follow" }
    var copy = notch.copies.length > 0 ? notch.copies[0] : null
    return { kind: "homed", screen: copy ? copy.screenName : notch.placement.screen }
  }
  function dismissPeek(module) {
    for (var i = 0; i < notch.copies.length; i++) notch.copies[i].dismissPeek(module)
  }

  // ------------------------------------------------------------ navigation
  // Its place among the config's notches (-1 for the visitor and standalone
  // notches), the number it shows while navigating (1 to 9, else 0) and
  // whether it is the one selected (NotchService.navSelected).
  readonly property int navIndex: notch.svc && !notch.guest ? notch.svc.notches.indexOf(notch) : -1
  readonly property int navNumber: Navigate.number(notch.navIndex)
  readonly property bool navSelected: !!notch.svc && notch.svc.navigating && notch.navIndex >= 0
    && notch.svc.navSelected === notch.navIndex

  // ------------------------------------------------------------------ open
  // Opened for a module (`module`, optional), on that module's tab.
  function open(module) {
    var copy = notch.focusedCopy()
    if (!copy) return
    if (module) copy.showTab(module.moduleId)
    copy.open()
  }
  function close() { for (var i = 0; i < notch.copies.length; i++) notch.copies[i].close() }
  function toggle() {
    for (var i = 0; i < notch.copies.length; i++)
      if (notch.copies[i].pinned) { notch.close(); return }
    notch.open()
  }
}
