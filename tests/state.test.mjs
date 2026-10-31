import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const State = load('core/State.js');

const mod = (id, priority, extra = {}) => ({ id, priority, active: true, peek: {}, ...extra });

test('activeModules keeps active ones, highest priority first', () => {
  const list = [mod('media', 50), mod('osd', 100), mod('off', 90, { active: false }), null];
  assert.deepEqual(plain(State.activeModules(list).map((m) => m.id)), ['osd', 'media']);
});

test('compactModule is the first active module with a compact or bar view', () => {
  const active = [mod('osd', 100), mod('media', 50, { barView: {} }), mod('act', 40, { compact: {} })];
  assert.equal(State.compactModule(active).id, 'media');
  assert.equal(State.compactModule([mod('osd', 100)]), null);
});

test('canPeek: pinned blocks, hover only lets urgent peeks through', () => {
  const m = mod('media', 50);
  assert.equal(State.canPeek(m, { pinned: true }), false);
  assert.equal(State.canPeek(m, { hovered: true }), false);
  assert.equal(State.canPeek(mod('osd', 100, { urgentPeek: true }), { hovered: true }), true);
  assert.equal(State.canPeek(mod('x', 1, { peek: null }), {}), false);
  assert.equal(State.canPeek(null, {}), false);
});

test('canPeek: a lower-priority peek waits for a higher one on screen', () => {
  const osd = mod('osd', 100);
  const media = mod('media', 50);
  assert.equal(State.canPeek(media, { current: osd, currentShowing: true }), false);
  assert.equal(State.canPeek(media, { current: osd, currentShowing: false }), true);
  assert.equal(State.canPeek(osd, { current: media, currentShowing: true }), true);
  assert.equal(State.canPeek(osd, { current: osd, currentShowing: true }), true);
});

test('mode: peek beats expanded unless pinned, then compact, then rest', () => {
  const m = mod('media', 50);
  assert.equal(State.mode({ peekModule: m }), 'peek');
  assert.equal(State.mode({ peekModule: m, pinned: true }), 'expanded');
  assert.equal(State.mode({ hovered: true }), 'expanded');
  assert.equal(State.mode({ compactModule: m }), 'compact');
  assert.equal(State.mode({}), 'rest');
});

test('mode: a dragged notch stays closed whatever else is going on', () => {
  const m = mod('media', 50);
  assert.equal(State.mode({ dragging: true, hovered: true, pinned: true, peekModule: m, compactModule: m }), 'compact');
  assert.equal(State.mode({ dragging: true, hovered: true, peekModule: m }), 'rest');
});

// Bug: the visitor's copies, one fullscreen window per screen, showed the
// compact view while hidden; the media equalizer kept them drawing frames
// nobody saw, two thirds of what music playing cost.
test('mode: a guest copy rests while closed, and only peeks or opens', () => {
  const m = mod('media', 50);
  assert.equal(State.mode({ guest: true, compactModule: m }), 'rest');
  assert.equal(State.mode({ guest: true, dragging: true, compactModule: m }), 'rest');
  assert.equal(State.mode({ guest: true, compactModule: m, peekModule: m }), 'peek');
  assert.equal(State.mode({ guest: true, compactModule: m, hovered: true }), 'expanded');
});

test('reservedSpace: only when enabled in notch style; compact never below the baseline', () => {
  const on = { enabled: true, compactStyle: 'notch', compact: true, baseline: 36, tallest: 0, rest: 5 };
  assert.equal(State.reservedSpace(on), 36);
  assert.equal(State.reservedSpace({ ...on, tallest: 41.2 }), 42);
  assert.equal(State.reservedSpace({ ...on, tallest: 20 }), 36);
  assert.equal(State.reservedSpace({ ...on, enabled: false }), 0);
  assert.equal(State.reservedSpace({ ...on, compactStyle: 'bar' }), 0);
});

test('reservedSpace: at rest, only the lip', () => {
  const rest = { enabled: true, compactStyle: 'notch', compact: false, baseline: 36, tallest: 50, rest: 5.4 };
  assert.equal(State.reservedSpace(rest), 6);
  assert.equal(State.reservedSpace({ ...rest, compactStyle: 'bar' }), 0);
});

test('reserveStep: grow or drop now, shrink later, nothing when equal', () => {
  assert.equal(State.reserveStep(6, 33), 'now');
  assert.equal(State.reserveStep(33, 0), 'now');
  assert.equal(State.reserveStep(33, 6), 'later');
  assert.equal(State.reserveStep(33, 33), 'none');
});

test('workspaceAllowed matches ids or names; no list or no workspace allows', () => {
  assert.equal(State.workspaceAllowed(null, { id: 5, name: '5' }), true);
  assert.equal(State.workspaceAllowed([], { id: 5, name: '5' }), true);
  assert.equal(State.workspaceAllowed([1, 2], null), true);
  assert.equal(State.workspaceAllowed([1, 2], { id: 2, name: '2' }), true);
  assert.equal(State.workspaceAllowed(['2'], { id: 2, name: '2' }), true);
  assert.equal(State.workspaceAllowed(['code'], { id: 7, name: 'code' }), true);
  assert.equal(State.workspaceAllowed([1, 2, 3], { id: 4, name: '4' }), false);
});

test('notchScreen: closed, the focused screen if allowed, else the first allowed one', () => {
  const screens = [{ name: 'DP-1', allowed: true }, { name: 'eDP-1', allowed: false }];
  assert.equal(State.notchScreen({ screens, focused: 'DP-1' }), 'DP-1');
  assert.equal(State.notchScreen({ screens, focused: 'eDP-1' }), 'DP-1');
  assert.equal(State.notchScreen({ screens: [{ name: 'a', allowed: false }], focused: 'a' }), '');
  assert.equal(State.notchScreen({ screens: [], focused: 'a' }), '');
});

test('notchScreen: open, the screen it was opened from, else the focused one', () => {
  const screens = [{ name: 'DP-1', allowed: true }, { name: 'eDP-1', allowed: false }];
  assert.equal(State.notchScreen({ screens, focused: 'eDP-1', open: true }), 'eDP-1');
  assert.equal(State.notchScreen({ screens, focused: 'eDP-1', open: true, override: 'DP-1' }), 'DP-1');
  assert.equal(State.notchScreen({ screens, focused: 'gone', open: true }), 'DP-1');
  assert.equal(State.notchScreen({ screens, focused: 'eDP-1', override: 'gone' }), 'DP-1');
  assert.equal(State.notchScreen({ screens, focused: 'DP-1', override: 'eDP-1' }), 'DP-1');
});

test('notchScreen: closed, the notch stays on its home screen whatever has focus', () => {
  const screens = [{ name: 'DP-1', allowed: true }, { name: 'eDP-1', allowed: true }];
  assert.equal(State.notchScreen({ screens, focused: 'DP-1', home: 'eDP-1' }), 'eDP-1');
  // A home whose workspace does not take the notch, or that is gone, falls back.
  const busy = [{ name: 'DP-1', allowed: true }, { name: 'eDP-1', allowed: false }];
  assert.equal(State.notchScreen({ screens: busy, focused: 'eDP-1', home: 'eDP-1' }), 'DP-1');
  assert.equal(State.notchScreen({ screens, focused: 'DP-1', home: 'HDMI-A-1' }), 'DP-1');
});

test('reserveScreens: only the home screen while the notch can hang there', () => {
  const screens = [{ name: 'DP-1', allowed: true }, { name: 'eDP-1', allowed: true }, { name: 'HDMI-A-1', allowed: false }];
  assert.deepEqual(plain(State.reserveScreens(screens, 'eDP-1')), ['eDP-1']);
  assert.deepEqual(plain(State.reserveScreens(screens, '')), ['DP-1', 'eDP-1']);
  assert.deepEqual(plain(State.reserveScreens(screens, 'HDMI-A-1')), ['DP-1', 'eDP-1']);
});

test('compactStyles: only the first notch asking for the bar gets it', () => {
  assert.deepEqual(plain(State.compactStyles(['notch', 'bar', 'bar'], true)), ['notch', 'bar', 'notch']);
  assert.deepEqual(plain(State.compactStyles(['bar', 'bar'], false)), ['notch', 'notch']);
  assert.deepEqual(plain(State.compactStyles([], true)), []);
});

// Bug: with the notch showing media on one monitor, changing the volume on
// another moved the one notch there. A notch on every screen peeks only on
// the focused one; the others keep what they show.
test('peekCopy: the copy on the focused screen, else the first', () => {
  assert.equal(State.peekCopy(['DP-1', 'HDMI-A-1'], 'HDMI-A-1'), 'HDMI-A-1');
  assert.equal(State.peekCopy(['DP-1', 'HDMI-A-1'], ''), 'DP-1');
  assert.equal(State.peekCopy([''], 'HDMI-A-1'), '');
  assert.equal(State.peekCopy([], 'DP-1'), null);
});

test('reserveZones: the deepest reserve per screen edge, never the sum', () => {
  const zones = plain(State.reserveZones([
    { screens: ['DP-1', 'HDMI-A-1'], edge: 'top', space: 10 },
    { screens: ['DP-1'], edge: 'top', space: 24 },
    { screens: ['DP-1'], edge: 'left', space: 8 },
    { screens: ['HDMI-A-1'], edge: 'bottom', space: 0 },
    null
  ]));
  assert.deepEqual(zones, { 'DP-1|top': 24, 'HDMI-A-1|top': 10, 'DP-1|left': 8 });
});

// Bug: with the notch kept on the ultrawide (position.screen) showing
// music, changing the volume while working on the laptop screen moved the
// notch over there. A notch with a home screen now stays where it hangs,
// peeks included.
test('notchScreen: open, a notch with a home screen stays where it hangs', () => {
  const screens = [{ name: 'DP-1', allowed: true }, { name: 'eDP-1', allowed: true }];
  assert.equal(State.notchScreen({ screens, focused: 'eDP-1', home: 'DP-1', open: true }), 'DP-1');
  // Its home's workspace leaves it out: it opens where it hangs instead.
  const busy = [{ name: 'DP-1', allowed: false }, { name: 'eDP-1', allowed: true }, { name: 'HDMI-A-1', allowed: true }];
  assert.equal(State.notchScreen({ screens: busy, focused: 'HDMI-A-1', home: 'DP-1', open: true }), 'HDMI-A-1');
  // Hanging nowhere, it opens on its home.
  const none = [{ name: 'DP-1', allowed: false }, { name: 'eDP-1', allowed: false }];
  assert.equal(State.notchScreen({ screens: none, focused: 'eDP-1', home: 'DP-1', open: true }), 'DP-1');
  // Opened by the pointer on another screen, it stays there.
  assert.equal(State.notchScreen({ screens, focused: 'DP-1', home: 'DP-1', open: true, override: 'eDP-1' }), 'eDP-1');
});

// The volume must show where you work: on a screen where no notch with the
// OSD hangs, it shows once at the top, not once per notch kept elsewhere.
test('needsVisitor: only when no notch with the module peeks on the focused screen', () => {
  const homedOnDp = { kind: 'homed', screen: 'DP-1' };
  assert.equal(State.needsVisitor([homedOnDp], 'eDP-1'), true);
  assert.equal(State.needsVisitor([homedOnDp, { kind: 'homed', screen: 'HDMI-A-1' }], 'eDP-1'), true);
  assert.equal(State.needsVisitor([homedOnDp], 'DP-1'), false);
  assert.equal(State.needsVisitor([homedOnDp, { kind: 'homed', screen: 'eDP-1' }], 'eDP-1'), false);
  assert.equal(State.needsVisitor([homedOnDp, { kind: 'follow' }], 'eDP-1'), false);
  assert.equal(State.needsVisitor([{ kind: 'all' }], 'eDP-1'), false);
  assert.equal(State.needsVisitor([], 'eDP-1'), true);
  assert.equal(State.needsVisitor([homedOnDp], ''), false);
});

// Brightness changes on the focused monitor only, yet its OSD opened on the
// notches of the other monitors too. The OSD peeks once, on the focused one.
test('focusedPeek: the first notch peeking on the focused screen, else the visitor', () => {
  const dp = { kind: 'homed', screen: 'DP-1' };
  const edp = { kind: 'homed', screen: 'eDP-1' };
  assert.equal(State.focusedPeek([dp, edp, { kind: 'homed', screen: 'eDP-1' }], 'eDP-1'), 1);
  assert.equal(State.focusedPeek([dp, { kind: 'all' }], 'eDP-1'), 1);
  assert.equal(State.focusedPeek([dp, { kind: 'follow' }, edp], 'eDP-1'), 1);
  assert.equal(State.focusedPeek([dp], 'eDP-1'), -1);
  assert.equal(State.focusedPeek([dp], 'DP-1'), 0);
  assert.equal(State.focusedPeek([dp, edp], ''), 0);
  assert.equal(State.focusedPeek([], ''), -1);
});
