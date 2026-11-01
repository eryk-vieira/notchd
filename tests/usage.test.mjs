import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { load, plain } from './load.mjs';

const Usage = load('core/Usage.js');
// Real answers (2026-11-01), the account's fields taken out.
const fixture = (name) => JSON.parse(fs.readFileSync(new URL(`./fixtures/usage/${name}.json`, import.meta.url), 'utf8'));

test('claudeLimits: the session, the week and a model\'s week, from the limits list', () => {
  const limits = plain(Usage.claudeLimits(fixture('claude')));
  assert.deepEqual(limits.map((l) => [l.label, l.percent, l.windowSecs]),
    [['5h', 8, 18000], ['Week', 2, 604800], ['Fable week', 0, 604800]]);
  assert.equal(limits[0].resetsAt, Date.parse('2026-11-01T16:10:00.707886+00:00'));
  // Ids stay put between answers: the reset time is not in them.
  assert.deepEqual(limits.map((l) => l.id), ['claude:session', 'claude:weekly_all', 'claude:weekly_scoped:Fable']);
});

test('claudeLimits: without the list, five_hour and seven_day', () => {
  const data = fixture('claude');
  delete data.limits;
  assert.deepEqual(plain(Usage.claudeLimits(data)).map((l) => [l.id, l.label, l.percent]),
    [['claude:five_hour', '5h', 8], ['claude:seven_day', 'Week', 2]]);
  assert.equal(Usage.claudeLimits(null), null);
  assert.equal(Usage.claudeLimits([]), null);
  assert.equal(Usage.claudeLimits({ nope: 1 }), null, 'an answer without limits was taken');
  assert.deepEqual(plain(Usage.claudeLimits({ five_hour: null, seven_day: null })), [], 'a plan without windows');
  assert.deepEqual(plain(Usage.claudeLimits({ limits: [{ group: 'session', percent: 'x' }, null] })), []);
  assert.equal(Usage.claudeLimits({ limits: [{ group: 'session', percent: 140 }] })[0].percent, 100);
});

// The week came alone as the primary window: told apart by its length.
test('codexLimits: windows by their length, not their place', () => {
  const limits = plain(Usage.codexLimits(fixture('codex'), 0));
  assert.deepEqual(limits, [{ id: 'codex:604800', label: 'Week', percent: 1, resetsAt: 1793794381000, windowSecs: 604800 }]);
  const both = { rate_limit: {
    primary_window: { used_percent: 30, limit_window_seconds: 604800, reset_at: 2000 },
    secondary_window: { used_percent: 50, limit_window_seconds: 18000, reset_after_seconds: 60 } } };
  assert.deepEqual(plain(Usage.codexLimits(both, 1000)).map((l) => [l.label, l.percent, l.resetsAt]),
    [['5h', 50, 61000], ['Week', 30, 2000000]]);
  assert.equal(Usage.codexLimits({}, 0), null);
  assert.deepEqual(plain(Usage.codexLimits({ rate_limit: { primary_window: null } }, 0)), []);
});

test('request: the token in a header; an expired Claude login is not sent', () => {
  const claude = JSON.stringify({ claudeAiOauth: { accessToken: 'AT', expiresAt: 5000 } });
  const r = plain(Usage.request('claude', claude, 1000));
  assert.equal(r.url, 'https://api.anthropic.com/api/oauth/usage');
  assert.equal(r.headers.Authorization, 'Bearer AT');
  assert.equal(r.headers['anthropic-beta'], 'oauth-2025-04-20');
  assert.deepEqual(plain(Usage.request('claude', claude, 6000)), { error: 'login expired', expired: true });
  const codex = JSON.stringify({ tokens: { access_token: 'CT', account_id: 'acc' } });
  assert.deepEqual(plain(Usage.request('codex', codex, 0).headers), { Authorization: 'Bearer CT', 'ChatGPT-Account-Id': 'acc' });
  for (const text of ['', '{', '{}', '{"tokens":{}}'])
    assert.equal(Usage.request('codex', text, 0).error, 'not signed in', text);
  assert.equal(Usage.request('claude', '{"claudeAiOauth":{}}', 0).error, 'not signed in');
  assert.match(Usage.request('gemini', '{}', 0).error, /no usage/);
});

test('afterStatus: 429 waits at least 5 minutes; failures keep the limits, stale', () => {
  assert.deepEqual(plain(Usage.afterStatus(200, '', 300000)), { problem: '', stale: false, retryMs: 300000 });
  assert.deepEqual(plain(Usage.afterStatus(429, '', 300000)), { problem: 'rate limited', stale: true, retryMs: 300000 });
  assert.equal(Usage.afterStatus(429, '900', 60000).retryMs, 900000);
  assert.equal(Usage.afterStatus(401, '', 300000).problem, 'login expired');
  assert.equal(Usage.afterStatus(0, '', 300000).problem, 'offline');
  assert.equal(Usage.afterStatus(500, '', 300000).problem, 'HTTP 500');
  assert.equal(Usage.afterStatus(200, '', 1000).retryMs, 60000, 'never more than once a minute');
});

test('alerts: once per window at the threshold, again at the limit; a new window starts over', () => {
  const at = (percent, resetsAt = 1) => [{ id: 'claude:session', label: '5h', percent, resetsAt, windowSecs: 18000 }];
  // The first answer is taken as seen: a restart doesn't warn again.
  let r = Usage.alerts(at(85), null, 80);
  assert.equal(r.alerts.length, 0);
  r = Usage.alerts(at(70), {}, 80);
  assert.equal(r.alerts.length, 0);
  r = Usage.alerts(at(82), r.warned, 80);
  assert.deepEqual(plain(r.alerts).map((a) => a.level), [80]);
  r = Usage.alerts(at(90), r.warned, 80);
  assert.equal(r.alerts.length, 0, 'warned twice in one window');
  r = Usage.alerts(at(100), r.warned, 80);
  assert.deepEqual(plain(r.alerts).map((a) => a.level), [100]);
  r = Usage.alerts(at(81, 2), r.warned, 80);
  assert.deepEqual(plain(r.alerts).map((a) => a.level), [80], 'the next window did not warn');
  assert.deepEqual(Object.keys(plain(r.warned)), ['claude:session@2'], 'old windows kept');
  // 100: only at the limit.
  assert.equal(Usage.alerts(at(95), {}, 100).alerts.length, 0);
  assert.equal(Usage.alerts(at(100), {}, 100).alerts.length, 1);
});

test('resetIn and tightest', () => {
  assert.equal(Usage.resetIn(0, 0), '');
  assert.equal(Usage.resetIn(45 * 60000, 0), '45m');
  assert.equal(Usage.resetIn(200 * 60000, 0), '3h 20m');
  assert.equal(Usage.resetIn(180 * 60000, 0), '3h');
  assert.equal(Usage.resetIn((2 * 24 + 4) * 3600000, 0), '2d 4h');
  assert.equal(Usage.resetIn(-5, 0), '0m');
  const limits = [{ percent: 8, windowSecs: 604800 }, { percent: 8, windowSecs: 18000 }, { percent: 2, windowSecs: 604800 }];
  assert.equal(Usage.tightest(limits).windowSecs, 18000);
  assert.equal(Usage.tightest([]), null);
});
