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

test('reservedSpace: only when enabled in notch style, never below the baseline', () => {
  const on = { enabled: true, compactStyle: 'notch', baseline: 36, tallest: 0 };
  assert.equal(State.reservedSpace(on), 36);
  assert.equal(State.reservedSpace({ ...on, tallest: 41.2 }), 42);
  assert.equal(State.reservedSpace({ ...on, tallest: 20 }), 36);
  assert.equal(State.reservedSpace({ ...on, enabled: false }), 0);
  assert.equal(State.reservedSpace({ ...on, compactStyle: 'bar' }), 0);
});
