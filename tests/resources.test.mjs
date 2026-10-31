import test from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const R = load('core/Resources.js');

const STAT = `cpu  100 0 50 800 50 0 0 0 0 0
cpu0 50 0 25 400 25 0 0 0 0 0
intr 12345`;

test('cpuTimes reads the aggregate line, iowait counted as idle', () => {
  assert.deepEqual(plain(R.cpuTimes(STAT)), { idle: 850, total: 1000 });
  assert.equal(R.cpuTimes('intr 1\n'), null);
  assert.equal(R.cpuTimes(''), null);
});

test('cpuCount counts the per-CPU lines', () => {
  assert.equal(R.cpuCount(STAT), 1);
  assert.equal(R.cpuCount('cpu  1 2 3 4\ncpu0 1 2 3 4\ncpu1 1 2 3 4\ncpu10 1 2 3 4\n'), 3);
  assert.equal(R.cpuCount(''), 0);
});

test('cpuUsage is the busy share of the time between samples', () => {
  assert.equal(R.cpuUsage({ idle: 850, total: 1000 }, { idle: 900, total: 1200 }), 0.75);
  assert.equal(R.cpuUsage(null, { idle: 1, total: 2 }), null, 'no previous sample');
  assert.equal(R.cpuUsage({ idle: 1, total: 2 }, { idle: 1, total: 2 }), null, 'no time passed');
});

test('memory counts what cannot be reclaimed, not the page cache', () => {
  const m = R.memory('MemTotal:       16000000 kB\nMemFree:  1000000 kB\nMemAvailable:   12000000 kB\nCached: 9000000 kB\n');
  assert.equal(m.total, 16000000 * 1024);
  assert.equal(m.used, 4000000 * 1024);
  assert.equal(m.fraction, 0.25);
  assert.equal(R.memory('MemFree: 1 kB\n'), null);
});

test('disk uses df capacity: the space reserved for root is not free', () => {
  const d = R.disk(`Filesystem        1-blocks         Used    Available Capacity Mounted on
/dev/nvme0n1p2 1000000000000 600000000000 300000000000      67% /`);
  assert.equal(d.total, 1000000000000);
  assert.equal(d.used, 600000000000);
  assert.ok(Math.abs(d.fraction - 2 / 3) < 1e-9);
  assert.equal(R.disk('Filesystem 1-blocks Used Available Capacity Mounted on'), null);
  assert.equal(R.disk(''), null);
});

test('sizes read short, used in the total unit', () => {
  assert.equal(R.formatBytes(512 * 1024 * 1024), '512 MiB');
  assert.equal(R.formatBytes(7.8 * 1024 ** 3), '7.8 GiB');
  assert.equal(R.formatBytes(512 * 1024 ** 3), '512 GiB');
  assert.equal(R.formatUsage(7.8 * 1024 ** 3, 31.2 * 1024 ** 3), '7.8 of 31.2 GiB');
  assert.equal(R.formatUsage(900 * 1024 ** 2, 1.5 * 1024 ** 4), '0.0 of 1.5 TiB');
});

test('nextPressure: hot after holding at the line, cools below it with a margin', () => {
  const rule = { warn: 0.9, hold: 3, clear: 0.05 };
  let s = { hot: false, streak: 0 };
  s = R.nextPressure(s, 0.95, rule); assert.equal(s.hot, false);
  s = R.nextPressure(s, 0.95, rule); assert.equal(s.hot, false);
  s = R.nextPressure(s, 0.2, rule);  assert.deepEqual(plain(s), { hot: false, streak: 0 }, 'a spike resets the streak');
  for (let i = 0; i < 3; i++) s = R.nextPressure(s, 0.92, rule);
  assert.equal(s.hot, true, 'hot after three samples in a row');
  s = R.nextPressure(s, 0.87, rule); assert.equal(s.hot, true, 'still hot just under the line');
  s = R.nextPressure(s, 0.84, rule); assert.equal(s.hot, false, 'cool past the margin');
  assert.equal(R.nextPressure({ hot: true, streak: 1 }, null, rule).hot, true, 'no sample keeps the state');
  assert.equal(R.nextPressure(undefined, 0.95, { warn: 0.9 }).hot, true, 'hold defaults to one sample');
});
