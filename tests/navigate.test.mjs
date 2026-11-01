import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const Navigate = load('core/Navigate.js');

const Key = {
  Escape: 0x01000000, Tab: 0x01000001, Backtab: 0x01000002, Return: 0x01000004, Enter: 0x01000005,
  Left: 0x01000012, Up: 0x01000013, Right: 0x01000014,
  1: 0x31, 9: 0x39, 0: 0x30, H: 0x48, L: 0x4c, N: 0x4e,
};
const Shift = 0x02000000;
const Ctrl = 0x04000000;
const Alt = 0x08000000;
const Meta = 0x10000000;

test('keyName: digits, arrows and hl, tabs, Enter and Escape', () => {
  assert.equal(Navigate.keyName(Key[1], 0), '1');
  assert.equal(Navigate.keyName(Key[9], 0), '9');
  assert.equal(Navigate.keyName(Key[0], 0), '');
  assert.equal(Navigate.keyName(Key.Left, 0), 'previous');
  assert.equal(Navigate.keyName(Key.H, 0), 'previous');
  assert.equal(Navigate.keyName(Key.Right, 0), 'next');
  assert.equal(Navigate.keyName(Key.L, 0), 'next');
  assert.equal(Navigate.keyName(Key.Tab, 0), 'nextTab');
  assert.equal(Navigate.keyName(Key.Backtab, Shift), 'previousTab');
  assert.equal(Navigate.keyName(Key.Tab, Shift), 'previousTab');
  assert.equal(Navigate.keyName(Key.Return, 0), 'open');
  assert.equal(Navigate.keyName(Key.Enter, 0), 'open');
  assert.equal(Navigate.keyName(Key.Escape, 0), 'leave');
  assert.equal(Navigate.keyName(Key.Up, 0), '');
  assert.equal(Navigate.keyName(Key.N, 0), '');
});

test('keyName: a key held with Ctrl, Alt or Super is a shortcut, not navigation', () => {
  assert.equal(Navigate.keyName(Key[1], Ctrl), '');
  assert.equal(Navigate.keyName(Key.Right, Alt), '');
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

test('step: a digit selects that notch; one past the last does nothing', () => {
  assert.deepEqual(plain(Navigate.step(at(0), '3')), { selected: 2, tab: '', action: '' });
  assert.deepEqual(plain(Navigate.step(at(0), '4')), { selected: 0, tab: '', action: '' });
});

test('step: a digit for the selected notch keeps its tab', () => {
  assert.deepEqual(plain(Navigate.step(at(1, { tabs: ['a', 'b'], tab: 'b' }), '2')), { selected: 1, tab: 'b', action: '' });
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
  assert.deepEqual(plain(Navigate.step(at(1), '')), { selected: 1, tab: '', action: '' });
  assert.equal(Navigate.step({ selected: 0, count: 0 }, 'next').action, 'leave');
});

test('number: 1 to 9 in config order, none past that', () => {
  assert.equal(Navigate.number(0), 1);
  assert.equal(Navigate.number(8), 9);
  assert.equal(Navigate.number(9), 0);
  assert.equal(Navigate.number(-1), 0);
});
