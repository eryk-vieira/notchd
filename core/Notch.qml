import QtQuick
import Quickshell
import "Position.js" as Position

// One notch of the config's `notches` (or the top-level one): its modules,
// where it hangs and how. NotchService makes one per notch the daemon's
// `state` lists; it shows as copies (NotchCopy), which bind the state of
// each screen's copy, while this holds what they share. A notch stays on the
// screen(s) the config names (the first of the layout without one): a copy
// on each, which the daemon lists in its state, each a notch of its own; with
// `workspaces` leaving its screen's workspace out, the copy hides there
// instead of moving.
//
// A notch without decoration (`"decoration": false`) shows nothing at rest:
// its copies have no window until one of its modules peeks (or navigation
// draws its place), and it draws over the decorated notches it overlaps then.
// With no screen it has a copy on every screen. The Omarchy host's `osd` is
// one, declared by the host.
//
// The service also makes one `visitor`: no config of its own, a copy per
// screen at the top, each hidden until it shows a peek on a screen where no
// notch with that module does. The daemon decides which peeks go where.
Item {
  id: notch
  visible: false

  property var svc: null
  property string notchId: ""
  // The visitor, rather than a notch of the config.
  property bool visitor: false
  // The visitor: hidden while closed, a copy on every screen, only there
  // for peeks (NotchCopy.guest).
  readonly property bool guest: notch.visitor
  // What the daemon calls it in the messages that name a copy: its id, the
  // visitor's "".
  readonly property string wireId: notch.notchId

  // ----------------------------------------------------------------- state
  // The daemon's notch: its place, its modules, the copies' state.
  readonly property var info: {
    if (!notch.svc || notch.visitor) return null
    return notch.svc.notchInfo[notch.notchId] || null
  }
  // The copies' state, one per screen where there is one.
  readonly property var copyInfos: notch.visitor ? (notch.svc ? notch.svc.visitorInfo : []) : notch.info ? notch.info.copies : []
  // The state of the copy on a screen.
  function copyInfo(screen) {
    var list = notch.copyInfos
    for (var i = 0; i < list.length; i++) if (list[i].screen === screen) return list[i]
    return null
  }

  // ---------------------------------------------------------------- config
  // The keys of the config's entry the state does not carry (Config.notches);
  // null for the visitor.
  readonly property var spec: notch.svc && !notch.guest ? notch.svc.notchSpec(notch.notchId) : null
  // Its place among the notches, -1 for the visitor.
  readonly property int index: notch.svc && !notch.guest ? notch.svc.notchIds.indexOf(notch.notchId) : -1
  readonly property var moduleIds: notch.info && !notch.guest ? notch.info.modules : []
  // Whether it shows at rest (the daemon's `decoration`); an undecorated one
  // only peeks, over the notches it overlaps.
  readonly property bool decoration: !notch.info || notch.info.decoration !== false
  // Keep windows out of the strip the closed notch hangs into.
  readonly property bool reserveSpace: !!notch.spec && notch.spec.reserveSpace
  // The open notch shows one module at a time, picked from tabs.
  readonly property bool tabs: !!notch.info && !notch.guest && notch.info.tabs
  // A module with nothing to show closed shows its icon there.
  readonly property bool idleIcons: !!notch.spec && notch.spec.idleIcons
  // Workspaces the closed notch hangs on (ids or names); null: every one.
  readonly property var workspaces: notch.spec ? notch.spec.workspaces : null
  // The position, { edge, offset, screen } (Position.js): the daemon's
  // (`screen` the first it hangs on), the visitor's the default.
  readonly property var wantedPlace: Position.resolve(notch.visitor ? undefined
    : notch.info ? { edge: notch.info.edge, offset: notch.info.offset, screen: notch.info.screen }
    : notch.spec ? notch.spec.position : undefined)
  // Where it is. Replaced only when it moves: a state that says the same
  // makes nothing move.
  property var placement: Position.resolve(undefined)
  onWantedPlaceChanged: if (JSON.stringify(notch.wantedPlace) !== JSON.stringify(notch.placement)) notch.placement = notch.wantedPlace
  readonly property string edge: notch.placement.edge
  readonly property bool vertical: Position.isVertical(notch.edge)
  // Whether it can be dragged to another edge.
  readonly property bool canDrag: !!notch.info && !notch.guest && notch.decoration && notch.info.draggable

  // The config key for one of this notch's keys: "position" at the top
  // level, "notches.<index>.position" in a list.
  function configKey(key) { return (notch.spec ? notch.spec.prefix : "") + key }
  function setValue(key, value) { if (notch.svc) notch.svc.setConfigValue(notch.configKey(key), value) }

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
  // The ones with something to show now.
  readonly property var activeModules: notch.modules.filter(function(m) { return m.active })
  // What the closed notch shows side by side, as the daemon says
  // (State.compactModules): its first copy's, which every copy has.
  readonly property var compactModules: notch.copies.length > 0 ? notch.copies[0].compactModules : []
  readonly property var compactModule: notch.copies.length > 0 ? notch.copies[0].compactModule : null

  // ---------------------------------------------------------------- copies
  // Screen names, one copy each, as the daemon has them. Replaced only when
  // the list changes: a new one would make every copy again.
  readonly property var wantedScreens: notch.copyInfos.map(function(c) { return c.screen })
  property var copyScreens: []
  onWantedScreensChanged: notch.syncScreens()
  function syncScreens() {
    if (JSON.stringify(notch.wantedScreens) !== JSON.stringify(notch.copyScreens)) notch.copyScreens = notch.wantedScreens
  }
  Component.onCompleted: {
    notch.placement = notch.wantedPlace
    notch.syncScreens()
  }

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

  // The copy on a screen.
  function copyOn(screenName) {
    var list = notch.copies
    for (var i = 0; i < list.length; i++) if (list[i].fixedScreen === screenName) return list[i]
    return null
  }

  // ------------------------------------------------------------ navigation
  // The number it shows while navigating (1 to 9, else 0: reached with the
  // arrows), the daemon's: where it is, not its place in the config; and
  // whether it is the one selected (NotchService.navSelected).
  readonly property int navNumber: notch.info && !notch.guest ? notch.info.number : 0
  readonly property bool navSelected: !!notch.svc && notch.svc.navigating && !notch.guest
    && notch.svc.navSelected === notch.notchId

  // ------------------------------------------------------------------ open
  // The daemon opens it, on the focused screen: its first copy, pinned.
  function open() { if (notch.svc && !notch.guest) notch.svc.notchIpc("openNotch", [notch.notchId]) }
  function close() { if (notch.svc && !notch.guest) notch.svc.notchIpc("closeNotch", [notch.notchId]) }
  function toggle() { if (notch.svc && !notch.guest) notch.svc.notchIpc("toggleNotch", [notch.notchId]) }
}
