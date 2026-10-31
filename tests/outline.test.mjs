import test from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const Outline = load('core/Outline.js');

const card = { w: 200, h: 30, shoulder: 10, radius: 12 };
const shoulder = { kind: 'shoulder' };

test('outline: shoulders at both ends, the shape the notch always had', () => {
  const p = Outline.path({ ...card, start: shoulder, end: shoulder });
  assert.equal(p.fill,
    'M -10 0 Q 0 0 0 10 L 0 18 Q 0 30 12 30 L 188 30 Q 200 30 200 18 L 200 10 Q 200 0 210 0 Z');
  // The hairline: the open sides, never along the edge.
  assert.equal(p.stroke,
    'M -10 0 Q 0 0 0 10 L 0 18 Q 0 30 12 30 L 188 30 Q 200 30 200 18 L 200 10 Q 200 0 210 0');
});

test('outline: unknown or missing ends are shoulders', () => {
  assert.deepEqual(Outline.path({ ...card }), Outline.path({ ...card, start: shoulder, end: shoulder }));
});

// Asked for: in the corner of the screen, the end that would touch the
// screen's side sits flush with it, square (a flare down that side was
// tried and dropped).
test('outline: a corner end sits flush and square against the screen side', () => {
  const p = Outline.path({ ...card, start: { kind: 'corner' }, end: shoulder });
  assert.ok(p.fill.startsWith('M 0 0 L 0 30 L 188 30'), p.fill);
  // No hairline along the screen's side: it starts at the square corner.
  assert.ok(p.stroke.startsWith('M 0 30 L 188 30'), p.stroke);
  const q = Outline.path({ ...card, start: shoulder, end: { kind: 'corner' } });
  assert.ok(q.fill.endsWith('L 200 30 L 200 0 Z'), q.fill);
  assert.ok(q.stroke.endsWith('L 200 30'), q.stroke);
});

// Asked for: a notch on the side edge meets one in the corner from below;
// the hairline stops where they meet.
test('outline: a corner end leaves out the hairline where a side notch meets it', () => {
  const p = Outline.path({ ...card, start: { kind: 'corner', depth: 26 }, end: shoulder });
  assert.ok(p.fill.startsWith('M 0 0 L 0 30 L 26 30 L 188 30'), p.fill);
  assert.ok(p.stroke.startsWith('M 26 30 L 188 30'), p.stroke);
});

// Asked for: notches next to each other read as one.
test('outline: joined to a neighbor as deep, the end is square and reaches into it', () => {
  const p = Outline.path({ ...card, start: { kind: 'joined', depth: 30 }, end: shoulder });
  assert.ok(p.fill.startsWith('M -1 0 L -1 30 L 188 30'), p.fill);
  assert.ok(p.stroke.startsWith('M -1 30 L 188 30'), p.stroke);
  // Shallower than the neighbor: the same; the neighbor draws the step.
  assert.ok(Outline.path({ ...card, start: { kind: 'joined', depth: 40 } }).fill.startsWith('M -1 0 L -1 30 L'));
});

test('outline: joined to a shallower neighbor, a fillet steps down to it', () => {
  const p = Outline.path({ ...card, start: { kind: 'joined', depth: 10 }, end: shoulder });
  // Down the shared side to the neighbor's far side, a fillet out to it,
  // then this card's own far corner.
  assert.ok(p.fill.startsWith('M -1 0 L -1 9 L -10 9 L -10 10 Q 0 10 0 20 L 0 20 Q 0 30 10 30 L 188 30'), p.fill);
  assert.ok(p.stroke.startsWith('M -10 10 Q 0 10 0 20'), p.stroke);
  // A small step keeps the fillet and the corner inside it.
  const small = Outline.path({ ...card, start: { kind: 'joined', depth: 26 } }).fill;
  assert.ok(small.startsWith('M -1 0 L -1 25 L -2 25 L -2 26 Q 0 26 0 28 L 0 28 Q 0 30 2 30'), small);
});

test('outline: the far end mirrors the start', () => {
  const p = Outline.path({ ...card, start: shoulder, end: { kind: 'joined', depth: 10 } });
  assert.ok(p.fill.includes('L 190 30 Q 200 30 200 20 L 200 20 Q 200 10 210 10 L 210 9 L 201 9 L 201 0 Z'), p.fill);
  assert.ok(p.stroke.endsWith('Q 200 10 210 10'), p.stroke);
});
