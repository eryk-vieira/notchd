import test from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const C = load('core/Countdown.js');
const MIN = 60000;

test('parseDuration reads minutes, units and clock forms', () => {
  assert.equal(C.parseDuration('25'), 25 * MIN);
  assert.equal(C.parseDuration('25m'), 25 * MIN);
  assert.equal(C.parseDuration('90s'), 90000);
  assert.equal(C.parseDuration('1h30m'), 90 * MIN);
  assert.equal(C.parseDuration('1h 30m'), 90 * MIN);
  assert.equal(C.parseDuration('1.5h'), 90 * MIN);
  assert.equal(C.parseDuration('1:30'), 90000);
  assert.equal(C.parseDuration('1:00:00'), 60 * MIN);
  for (const bad of ['', 'tea', '1:75', '0', '10x', 'm', '0s'])
    assert.equal(C.parseDuration(bad), null, bad);
});

test('parseCommand: actions, added time and a duration with a label', () => {
  assert.deepEqual(plain(C.parseCommand('')), { action: 'toggle' });
  assert.deepEqual(plain(C.parseCommand('PAUSE')), { action: 'pause' });
  assert.deepEqual(plain(C.parseCommand('pomodoro')), { action: 'pomodoro' });
  assert.deepEqual(plain(C.parseCommand('+5m')), { action: 'add', ms: 5 * MIN });
  assert.deepEqual(plain(C.parseCommand('25m')), { action: 'start', ms: 25 * MIN, label: '' });
  assert.deepEqual(plain(C.parseCommand('3m Green tea')), { action: 'start', ms: 3 * MIN, label: 'Green tea' });
  assert.deepEqual(plain(C.parseCommand('1h 30m Deep work')), { action: 'start', ms: 90 * MIN, label: 'Deep work' });
  assert.ok(C.parseCommand('soon').error);
  assert.ok(C.parseCommand('+later').error);
});

test('format rounds seconds up and shows hours only when needed', () => {
  assert.equal(C.format(25 * MIN), '25:00');
  assert.equal(C.format(4001), '0:05');
  assert.equal(C.format(0), '0:00');
  assert.equal(C.format(3723000), '1:02:03');
});

test('a timer runs, pauses, resumes, takes more time and ends', () => {
  let s = C.start(1000, 10000, 'Tea');
  assert.equal(C.remaining(s, 4000), 7000);
  assert.equal(C.progress(s, 6000), 0.5);
  s = C.pause(s, 4000);
  assert.equal(s.status, 'paused');
  assert.equal(C.remaining(s, 99999), 7000, 'paused time stands still');
  s = C.toggle(s, 10000);
  assert.equal(s.status, 'running');
  assert.equal(s.endsAt, 17000);
  s = C.add(s, 10000, 5000);
  assert.equal(s.endsAt, 22000);
  assert.equal(s.duration, 15000);
  assert.equal(C.tick(s, 21999).finished, false);
  const t = C.tick(s, 22000);
  assert.equal(t.finished, true);
  assert.equal(t.state.status, 'done');
  assert.equal(t.state.label, 'Tea');
  assert.equal(C.tick(t.state, 30000).finished, false, 'finishes once');
  assert.equal(C.toggle(t.state, 30000).status, 'done', 'a done timer does not restart');
});

test('pomodoro: focus and short breaks, a long break after the last round, then done', () => {
  const cfg = { focus: 25, shortBreak: 5, longBreak: 15, rounds: 2 };
  let s = C.apply(C.IDLE, { action: 'pomodoro' }, 0, cfg);
  assert.deepEqual([s.phase, s.round, s.duration], ['focus', 1, 25 * MIN]);
  assert.equal(C.title(s), 'Focus · 1 of 2');
  const phases = [];
  let now = 0;
  for (let i = 0; i < 4; i++) {
    now = s.endsAt;
    const t = C.tick(s, now, cfg);
    assert.equal(t.finished, true);
    s = t.state;
    phases.push([s.status, s.phase, s.round]);
  }
  assert.deepEqual(phases, [
    ['running', 'short', 1],
    ['running', 'focus', 2],
    ['running', 'long', 2],
    ['done', 'long', 2]
  ]);
  assert.equal(s.next, null, 'the cycle is over');
});

test('pomodoro without autoAdvance waits for a toggle to start the next phase', () => {
  const cfg = { autoAdvance: false };
  let s = C.startPhase(0, cfg, 'focus', 1);
  s = C.tick(s, s.endsAt, cfg).state;
  assert.equal(s.status, 'done');
  assert.deepEqual(plain(s.next), { phase: 'short', round: 1 });
  s = C.toggle(s, 100, cfg);
  assert.deepEqual([s.status, s.phase, s.duration], ['running', 'short', 5 * MIN]);
});

test('skip moves a pomodoro on and stops a timer; stop always stops', () => {
  const p = C.startPhase(0, {}, 'focus', 1);
  assert.equal(C.skip(p, 10, {}).phase, 'short');
  assert.equal(C.skip(C.start(0, 5000, ''), 10, {}).status, 'idle');
  assert.equal(C.apply(p, { action: 'stop' }, 10, {}).status, 'idle');
  assert.equal(C.pause(C.IDLE, 0).status, 'idle', 'idle ignores pause');
});

test('pomodoroConfig fills in the defaults', () => {
  assert.deepEqual(plain(C.pomodoroConfig({})), { focus: 25 * MIN, short: 5 * MIN, long: 15 * MIN, rounds: 4, autoAdvance: true });
  assert.equal(C.pomodoroConfig({ focus: 50, rounds: 0 }).focus, 50 * MIN);
  assert.equal(C.pomodoroConfig({ rounds: 0 }).rounds, 4);
});

// The module wakes when the clock it shows changes, not four times a
// second: each wake-up redraws the notch's window.
test('untilChange: the time until the shown second changes, and the end itself', () => {
  const now = 1000000;
  const s = C.start(now, 2500, '');
  assert.equal(C.format(C.remaining(s, now)), '0:03');
  assert.equal(C.untilChange(s, now), 505);
  assert.equal(C.format(C.remaining(s, now + 505)), '0:02');
  assert.equal(C.untilChange(s, now + 505), 1000);
  assert.equal(C.untilChange(s, now + 1505), 1000);
  assert.ok(now + 1505 + 1000 >= s.endsAt, 'the last wake-up is at or past the end');
  assert.equal(C.untilChange(C.start(now, 2 * MIN, ''), now), 1005);
  assert.equal(C.untilChange(s, s.endsAt + 50), 1, 'past the end it wakes at once');
  assert.equal(C.untilChange(C.pause(s, now), now), 1000);
  assert.equal(C.untilChange(C.IDLE, now), 1000);
});
