import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const Position = load('core/Position.js');

test('resolve: a missing or broken value is top-center', () => {
  assert.deepEqual(plain(Position.resolve(undefined)), { edge: 'top', offset: 0.5 });
  assert.deepEqual(plain(Position.resolve('left')), { edge: 'top', offset: 0.5 });
  assert.deepEqual(plain(Position.resolve({ edge: 'middle', offset: 'x' })), { edge: 'top', offset: 0.5 });
  assert.deepEqual(plain(Position.resolve({ offset: null })), { edge: 'top', offset: 0.5 });
});

test('resolve keeps a known edge and clamps the offset to 0..1', () => {
  assert.deepEqual(plain(Position.resolve({ edge: 'left' })), { edge: 'left', offset: 0.5 });
  assert.deepEqual(plain(Position.resolve({ edge: 'bottom', offset: 0.2 })), { edge: 'bottom', offset: 0.2 });
  assert.deepEqual(plain(Position.resolve({ edge: 'right', offset: 3 })), { edge: 'right', offset: 1 });
  assert.deepEqual(plain(Position.resolve({ edge: 'top', offset: -1 })), { edge: 'top', offset: 0 });
  assert.deepEqual(plain(Position.resolve({ offset: '0.25' })), { edge: 'top', offset: 0.25 });
});

test('isVertical: only the side edges', () => {
  assert.equal(Position.isVertical('left'), true);
  assert.equal(Position.isVertical('right'), true);
  assert.equal(Position.isVertical('top'), false);
  assert.equal(Position.isVertical('bottom'), false);
});

test('effective: bar style locks the notch to the middle of the bar', () => {
  const pos = { edge: 'left', offset: 0.1 };
  assert.deepEqual(plain(Position.effective(pos, 'bar', 'bottom')), { edge: 'bottom', offset: 0.5 });
  assert.deepEqual(plain(Position.effective(pos, 'bar', undefined)), { edge: 'top', offset: 0.5 });
  assert.deepEqual(plain(Position.effective(pos, 'notch', 'bottom')), { edge: 'left', offset: 0.1 });
});

test('insets: only the bar edge, only while the bar shows', () => {
  assert.deepEqual(plain(Position.insets('top', 30, true)), { top: 30, bottom: 0, left: 0, right: 0 });
  assert.deepEqual(plain(Position.insets('left', 28, true)), { top: 0, bottom: 0, left: 28, right: 0 });
  assert.deepEqual(plain(Position.insets('top', 30, false)), { top: 0, bottom: 0, left: 0, right: 0 });
  assert.deepEqual(plain(Position.insets('nowhere', 30, true)), { top: 0, bottom: 0, left: 0, right: 0 });
});

const screen = { width: 1000, height: 600, cardWidth: 200, cardHeight: 40, margin: 10 };
const bar = (edge, size = 30) => Position.insets(edge, size, true);

test('place: top-center hangs under the bar, centered', () => {
  assert.deepEqual(plain(Position.place({ ...screen, edge: 'top', offset: 0.5, insets: bar('top') })), { x: 400, y: 30 });
});

test('place: bottom and the side edges sit against their edge', () => {
  const none = bar('top', 0);
  assert.deepEqual(plain(Position.place({ ...screen, edge: 'bottom', offset: 0.5, insets: none })), { x: 400, y: 560 });
  const side = { ...screen, cardWidth: 40, cardHeight: 200, insets: none };
  assert.deepEqual(plain(Position.place({ ...side, edge: 'left', offset: 0.5 })), { x: 0, y: 200 });
  assert.deepEqual(plain(Position.place({ ...side, edge: 'right', offset: 0.5 })), { x: 960, y: 200 });
});

test('place: a bar on the same edge pushes the notch off it', () => {
  assert.deepEqual(plain(Position.place({ ...screen, edge: 'bottom', offset: 0.5, insets: bar('bottom') })), { x: 400, y: 530 });
  const side = { ...screen, cardWidth: 40, cardHeight: 200 };
  assert.deepEqual(plain(Position.place({ ...side, edge: 'left', offset: 0.5, insets: bar('left', 28) })), { x: 28, y: 200 });
  assert.deepEqual(plain(Position.place({ ...side, edge: 'right', offset: 0.5, insets: bar('right', 28) })), { x: 932, y: 200 });
});

test('place: the offset runs along the stretch the bar leaves free', () => {
  const side = { ...screen, cardWidth: 40, cardHeight: 100, margin: 0 };
  // Bar on top: the left edge runs from 30 to 600; the middle is 315.
  assert.deepEqual(plain(Position.place({ ...side, edge: 'left', offset: 0.5, insets: bar('top') })), { x: 0, y: 265 });
});

test('place: the ends clamp so the card and its shoulders stay on screen', () => {
  assert.deepEqual(plain(Position.place({ ...screen, edge: 'top', offset: 0, insets: bar('top') })), { x: 10, y: 30 });
  assert.deepEqual(plain(Position.place({ ...screen, edge: 'top', offset: 1, insets: bar('top') })), { x: 790, y: 30 });
  // A side edge with the bar on top: the card never slides under the bar.
  const side = { ...screen, cardWidth: 40, cardHeight: 200 };
  assert.deepEqual(plain(Position.place({ ...side, edge: 'left', offset: 0, insets: bar('top') })), { x: 0, y: 40 });
  assert.deepEqual(plain(Position.place({ ...side, edge: 'right', offset: 1, insets: bar('bottom') })), { x: 960, y: 360 });
});

test('place: a card longer than the edge is centered on it', () => {
  const big = { ...screen, cardWidth: 40, cardHeight: 700, margin: 0 };
  assert.deepEqual(plain(Position.place({ ...big, edge: 'left', offset: 0, insets: bar('top', 0) })), { x: 0, y: -50 });
});

test('nearestEdge: the closest side of the screen', () => {
  assert.equal(Position.nearestEdge(500, 10, 1000, 600), 'top');
  assert.equal(Position.nearestEdge(500, 590, 1000, 600), 'bottom');
  assert.equal(Position.nearestEdge(20, 300, 1000, 600), 'left');
  assert.equal(Position.nearestEdge(990, 300, 1000, 600), 'right');
  assert.equal(Position.nearestEdge(500, 300, 1000, 600), 'top');
});

const drag = { width: 1000, height: 600, insets: { top: 30, bottom: 0, left: 0, right: 0 }, margin: 0, magnet: 0 };

test('dragTarget: the nearest edge, the notch middle under the pointer', () => {
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: 250, y: 40 })), { edge: 'top', offset: 0.25 });
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: 900, y: 590 })), { edge: 'bottom', offset: 0.9 });
  // The left edge runs from the bar (30) to the bottom (600).
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: 10, y: 315 })), { edge: 'left', offset: 0.5 });
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: 10, y: 30 + 57 })), { edge: 'left', offset: 0.1 });
});

test('dragTarget: offsets clamp to the ends and round to a thousandth', () => {
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: -40, y: 5 })), { edge: 'left', offset: 0 });
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: 333.333, y: 20 })), { edge: 'top', offset: 0.333 });
  assert.deepEqual(plain(Position.dragTarget({ ...drag, x: 5, y: 10, width: 1000, height: 30 })), { edge: 'left', offset: 0.5 });
});

test('dragTarget: the magnet snaps near the middle', () => {
  assert.deepEqual(plain(Position.dragTarget({ ...drag, magnet: 24, x: 520, y: 40 })), { edge: 'top', offset: 0.5 });
  assert.deepEqual(plain(Position.dragTarget({ ...drag, magnet: 24, x: 530, y: 40 })), { edge: 'top', offset: 0.53 });
});

test('configValue leaves defaults out; top-center is no key at all', () => {
  assert.equal(Position.configValue({ edge: 'top', offset: 0.5 }), undefined);
  assert.equal(Position.configValue(undefined), undefined);
  assert.deepEqual(plain(Position.configValue({ edge: 'left', offset: 0.5 })), { edge: 'left' });
  assert.deepEqual(plain(Position.configValue({ edge: 'top', offset: 0.2 })), { offset: 0.2 });
  assert.deepEqual(plain(Position.configValue({ edge: 'right', offset: 0.75 })), { edge: 'right', offset: 0.75 });
});
