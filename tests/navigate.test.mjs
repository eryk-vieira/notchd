import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const Navigate = load('core/Navigate.js');

const Key = {
  Escape: 0x01000000, Tab: 0x01000001, Backtab: 0x01000002, Return: 0x01000004, Enter: 0x01000005,
  Left: 0x01000012, Up: 0x01000013, Right: 0x01000014, Down: 0x01000015,
  1: 0x31, 9: 0x39, 0: 0x30, H: 0x48, J: 0x4a, K: 0x4b, L: 0x4c, M: 0x4d, N: 0x4e, S: 0x53, X: 0x58, Q: 0x51,
};
const Shift = 0x02000000;
const Ctrl = 0x04000000;
const Alt = 0x08000000;
const Meta = 0x10000000;

test('keyName: digits, arrows and hjkl, tabs, Enter and Escape', () => {
  assert.equal(Navigate.keyName(Key[1], 0), '1');
  assert.equal(Navigate.keyName(Key[9], 0), '9');
  assert.equal(Navigate.keyName(Key[0], 0), '');
  assert.equal(Navigate.keyName(Key.Left, 0), 'previous');
  assert.equal(Navigate.keyName(Key.H, 0), 'previous');
  assert.equal(Navigate.keyName(Key.Right, 0), 'next');
  assert.equal(Navigate.keyName(Key.L, 0), 'next');
  assert.equal(Navigate.keyName(Key.Up, 0), 'up');
  assert.equal(Navigate.keyName(Key.K, 0), 'up');
  assert.equal(Navigate.keyName(Key.Down, 0), 'down');
  assert.equal(Navigate.keyName(Key.J, 0), 'down');
  assert.equal(Navigate.keyName(Key.Tab, 0), 'nextTab');
  assert.equal(Navigate.keyName(Key.Backtab, Shift), 'previousTab');
  assert.equal(Navigate.keyName(Key.Tab, Shift), 'previousTab');
  assert.equal(Navigate.keyName(Key.Return, 0), 'open');
  assert.equal(Navigate.keyName(Key.Enter, 0), 'open');
  assert.equal(Navigate.keyName(Key.Escape, 0), 'leave');
  assert.equal(Navigate.keyName(Key.Q, 0), '');
});

test('keyName: m, s and x act on the selected notch; n does nothing', () => {
  assert.equal(Navigate.keyName(Key.N, 0), '');
  assert.equal(Navigate.keyName(Key.M, 0), 'move');
  assert.equal(Navigate.keyName(Key.S, 0), 'settings');
  assert.equal(Navigate.keyName(Key.X, 0), 'remove');
});

test('keyName: Shift with an arrow slides; Shift with anything else is nothing', () => {
  assert.equal(Navigate.keyName(Key.Left, Shift), 'slideBack');
  assert.equal(Navigate.keyName(Key.Up, Shift), 'slideBack');
  assert.equal(Navigate.keyName(Key.Right, Shift), 'slideOn');
  assert.equal(Navigate.keyName(Key.Down, Shift), 'slideOn');
  assert.equal(Navigate.keyName(Key.X, Shift), '');
  assert.equal(Navigate.keyName(Key.H, Shift), '');
});

test('keyName: a key held with Ctrl, Alt or Super is a shortcut, not navigation', () => {
  assert.equal(Navigate.keyName(Key[1], Ctrl), '');
  assert.equal(Navigate.keyName(Key.Right, Alt), '');
  assert.equal(Navigate.keyName(Key.X, Meta), '');
});

test('keyName: Escape leaves with any modifier, Ctrl+Escape included', () => {
  assert.equal(Navigate.keyName(Key.Escape, Ctrl), 'leave');
  assert.equal(Navigate.keyName(Key.Escape, Meta), 'leave');
});

test('start: the open notch, else the first on the focused screen, else the first', () => {
  const notches = [{ open: false, screens: ['A'] }, { open: false, screens: ['B'] }, { open: true, screens: ['B'] }];
  assert.equal(Navigate.start(notches, 'B'), 2);
  notches[2].open = false;
  assert.equal(Navigate.start(notches, 'B'), 1);
  assert.equal(Navigate.start(notches, 'C'), 0);
  assert.equal(Navigate.start(notches, ''), 0);
  assert.equal(Navigate.start([], 'A'), -1);
});

const at = (selected, extra = {}) => ({ selected, count: 3, tabs: [], tab: '', ...extra });
const pick = (r) => ({ mode: r.mode, selected: r.selected, tab: r.tab, action: r.action });

test('step: a digit selects that notch; one past the last does nothing', () => {
  assert.deepEqual(plain(pick(Navigate.step(at(0), '3'))), { mode: 'select', selected: 2, tab: '', action: '' });
  assert.deepEqual(plain(pick(Navigate.step(at(0), '4'))), { mode: 'select', selected: 0, tab: '', action: '' });
});

test('step: a digit for the selected notch keeps its tab', () => {
  assert.equal(Navigate.step(at(1, { tabs: ['a', 'b'], tab: 'b' }), '2').tab, 'b');
});

test('step: previous and next wrap around', () => {
  assert.equal(Navigate.step(at(2), 'next').selected, 0);
  assert.equal(Navigate.step(at(0), 'previous').selected, 2);
  assert.equal(Navigate.step(at(1), 'next').selected, 2);
  assert.equal(Navigate.step({ selected: 0, count: 1 }, 'next').selected, 0);
});

test('step: moving to another notch leaves its tab to it', () => {
  assert.equal(Navigate.step(at(0, { tabs: ['a', 'b'], tab: 'b' }), 'next').tab, '');
});

test('step: up and down do nothing outside the move mode', () => {
  assert.deepEqual(plain(pick(Navigate.step(at(1), 'up'))), { mode: 'select', selected: 1, tab: '', action: '' });
});

test('step: Tab walks the selected notch\'s tabs, both ways, wrapping', () => {
  const s = at(0, { tabs: ['codex', 'claude', 'timer'], tab: 'codex' });
  assert.equal(Navigate.step(s, 'nextTab').tab, 'claude');
  assert.equal(Navigate.step(s, 'previousTab').tab, 'timer');
  assert.equal(Navigate.step({ ...s, tab: 'timer' }, 'nextTab').tab, 'codex');
  // A tab it doesn't know counts as the first.
  assert.equal(Navigate.step({ ...s, tab: 'gone' }, 'nextTab').tab, 'claude');
  // One module or none: nothing to walk.
  assert.equal(Navigate.step(at(0, { tabs: ['codex'], tab: 'codex' }), 'nextTab').tab, 'codex');
  assert.equal(Navigate.step(at(0), 'nextTab').tab, '');
});

test('step: Enter opens, Escape leaves, an unknown key does nothing', () => {
  assert.equal(Navigate.step(at(1), 'open').action, 'open');
  assert.equal(Navigate.step(at(1), 'leave').action, 'leave');
  assert.deepEqual(plain(pick(Navigate.step(at(1), ''))), { mode: 'select', selected: 1, tab: '', action: '' });
  assert.equal(Navigate.step({ selected: 0, count: 0 }, 'next').action, 'leave');
});

test('step: s opens the selected notch\'s settings', () => {
  assert.equal(Navigate.step(at(2), 'settings').action, 'settings');
});

test('step: x asks first; x again removes it, anything else keeps it', () => {
  const asked = Navigate.step(at(1), 'remove');
  assert.deepEqual(plain(pick(asked)), { mode: 'remove', selected: 1, tab: '', action: '' });
  assert.deepEqual(plain(pick(Navigate.step({ ...at(1), mode: 'remove' }, 'remove'))),
    { mode: 'select', selected: 1, tab: '', action: 'remove' });
  // Removing the last one selects the one before.
  assert.equal(Navigate.step({ ...at(2), mode: 'remove' }, 'remove').selected, 1);
  // Escape (or any other key) keeps it, and stays in navigation.
  assert.deepEqual(plain(pick(Navigate.step({ ...at(1), mode: 'remove' }, 'leave'))), { mode: 'select', selected: 1, tab: '', action: '' });
  assert.equal(Navigate.step({ ...at(1), mode: 'remove' }, 'next').action, '');
});

test('step: the last notch is never removed', () => {
  assert.equal(Navigate.step({ selected: 0, count: 1 }, 'remove').mode, 'select');
});

test('step: m moves the selected notch: arrows pick the edge, Shift slides, Tab the screen', () => {
  assert.deepEqual(plain(pick(Navigate.step(at(1), 'move'))), { mode: 'move', selected: 1, tab: '', action: 'moveStart' });
  const moving = { ...at(1), mode: 'move' };
  assert.deepEqual(plain(Navigate.step(moving, 'up').move), { edge: 'top' });
  assert.deepEqual(plain(Navigate.step(moving, 'down').move), { edge: 'bottom' });
  assert.deepEqual(plain(Navigate.step(moving, 'previous').move), { edge: 'left' });
  assert.deepEqual(plain(Navigate.step(moving, 'next').move), { edge: 'right' });
  assert.deepEqual(plain(Navigate.step(moving, 'slideOn').move), { slide: 1 });
  assert.deepEqual(plain(Navigate.step(moving, 'slideBack').move), { slide: -1 });
  assert.deepEqual(plain(Navigate.step(moving, 'nextTab').move), { screen: 1 });
  assert.deepEqual(plain(Navigate.step(moving, 'previousTab').move), { screen: -1 });
  assert.equal(Navigate.step(moving, 'up').mode, 'move');
  // Digits don't select another notch while moving.
  assert.deepEqual(plain(pick(Navigate.step(moving, '3'))), { mode: 'move', selected: 1, tab: '', action: '' });
});

test('step: moving, Enter keeps where it went and Escape puts it back, both still navigating', () => {
  const moving = { ...at(1), mode: 'move' };
  assert.deepEqual(plain(pick(Navigate.step(moving, 'open'))), { mode: 'select', selected: 1, tab: '', action: 'moveDone' });
  assert.deepEqual(plain(pick(Navigate.step(moving, 'leave'))), { mode: 'select', selected: 1, tab: '', action: 'moveCancel' });
});

test('moveTarget: onto an edge at the same offset', () => {
  const p = { edge: 'top', offset: 0.3, screen: 'A' };
  assert.deepEqual(plain(Navigate.moveTarget(p, { edge: 'left' }, ['A', 'B'], 'A')), { edge: 'left', offset: 0.3, screen: 'A' });
});

test('moveTarget: a slide moves 5 % along the edge, within the edge', () => {
  const p = { edge: 'top', offset: 0.5, screen: '' };
  assert.equal(Navigate.moveTarget(p, { slide: 1 }, [], '').offset, 0.55);
  assert.equal(Navigate.moveTarget(p, { slide: -1 }, [], '').offset, 0.45);
  assert.equal(Navigate.moveTarget({ ...p, offset: 0.98 }, { slide: 1 }, [], '').offset, 1);
  assert.equal(Navigate.moveTarget({ ...p, offset: 0.02 }, { slide: -1 }, [], '').offset, 0);
});

test('moveTarget: Tab cycles the screens; from following focus or every screen, from where it is', () => {
  const p = { edge: 'top', offset: 0.5, screen: 'A' };
  const screens = ['A', 'B', 'C'];
  assert.equal(Navigate.moveTarget(p, { screen: 1 }, screens, 'A').screen, 'B');
  assert.equal(Navigate.moveTarget(p, { screen: -1 }, screens, 'A').screen, 'C');
  assert.equal(Navigate.moveTarget({ ...p, screen: '' }, { screen: 1 }, screens, 'B').screen, 'C');
  assert.equal(Navigate.moveTarget({ ...p, screen: 'all' }, { screen: 1 }, screens, '').screen, 'A');
  // One screen: nowhere to go.
  assert.equal(Navigate.moveTarget({ ...p, screen: '' }, { screen: 1 }, ['A'], 'A').screen, '');
});

test('hint: the keys the label lists, by mode', () => {
  assert.deepEqual(plain(Navigate.hint('select', 3, true, 2)),
    ['1-3 ←→   Tab   ↵ open   Esc', 'm move   s settings   x remove']);
  // One notch: no numbers, nothing to remove; no tabs.
  assert.deepEqual(plain(Navigate.hint('select', 1, false, 1)), ['↵ open   Esc', 'm move   s settings']);
  assert.deepEqual(plain(Navigate.hint('move', 3, false, 2)), ['←↑↓→ edge   ⇧ slide   Tab screen', '↵ done   Esc undo']);
  assert.deepEqual(plain(Navigate.hint('move', 3, false, 1)), ['←↑↓→ edge   ⇧ slide', '↵ done   Esc undo']);
  assert.deepEqual(plain(Navigate.hint('remove', 3, false, 1)), ['x remove   Esc keep']);
});

test('number: 1 to 9 in config order, none past that', () => {
  assert.equal(Navigate.number(0), 1);
  assert.equal(Navigate.number(8), 9);
  assert.equal(Navigate.number(9), 0);
  assert.equal(Navigate.number(-1), 0);
});
