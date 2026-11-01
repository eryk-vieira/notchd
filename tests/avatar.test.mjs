import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const Avatar = load('core/Avatar.js');
const Agent = load('core/Agent.js');

// A face as make-avatar.py writes it, 600x640, upright: lips level at
// y=400, eyes level at y=280.
const face = () => ({
  size: [600, 640],
  points: {
    mouthL: [250, 400], mouthR: [350, 400], chin: [300, 480], top: [300, 180],
    left: [180, 300], right: [420, 300],
    eyeAOuter: [200, 280], eyeAInner: [260, 280], eyeAUpper: [230, 270], eyeALower: [230, 288],
    eyeBOuter: [400, 280], eyeBInner: [340, 280], eyeBUpper: [370, 270], eyeBLower: [370, 288],
  },
});

test('paths: the data and cache homes, XDG first', () => {
  assert.equal(Avatar.dataHome('', '/home/u'), '/home/u/.local/share');
  assert.equal(Avatar.dataHome('/x/data/', '/home/u'), '/x/data');
  assert.equal(Avatar.avatarDir('/x/data', 'claude'), '/x/data/notchd/avatars/claude');
  assert.equal(Avatar.modelsDir('', '/home/u'), '/home/u/.cache/notchd/models');
  assert.equal(Avatar.modelsDir('/c', '/home/u'), '/c/notchd/models');
});

test('removable: only a folder right under the avatars root', () => {
  assert.equal(Avatar.removable('/d/notchd/avatars/claude', '/d'), true);
  assert.equal(Avatar.removable('/d/notchd/avatars', '/d'), false);
  assert.equal(Avatar.removable('/d/notchd/avatars/', '/d'), false);
  assert.equal(Avatar.removable('/d/notchd/avatars/a/b', '/d'), false);
  assert.equal(Avatar.removable('/d/notchd/avatars/..', '/d'), false);
  assert.equal(Avatar.removable('/home/u', '/d'), false);
  assert.equal(Avatar.removable('', '/d'), false);
});

test('localPath: file and qs urls to a path; anything else is no path', () => {
  assert.equal(Avatar.localPath('file:///p/core/avatar/make-avatar.py', '/c'), '/p/core/avatar/make-avatar.py');
  assert.equal(Avatar.localPath('qs:@/qs/core/avatar/a%20b.py', '/cfg/'), '/cfg/core/avatar/a b.py');
  assert.equal(Avatar.localPath('qs:///plug/core/avatar/x.py', ''), '/plug/core/avatar/x.py');
  assert.equal(Avatar.localPath('qrc:/x.py', '/c'), '');
  assert.equal(Avatar.localPath('qs:@/qs/x.py', ''), '');
});

test('ownerOf: the agent a field\'s key belongs to', () => {
  assert.equal(Avatar.ownerOf('claude.avatar'), 'claude');
  assert.equal(Avatar.ownerOf('my-shell.avatar'), 'my-shell');
  assert.equal(Avatar.ownerOf('claude.avatarColors'), '');
  assert.equal(Avatar.ownerOf(undefined), '');
});

test('pipelineArgs: a .py runs with python3, a fake runs as is', () => {
  assert.deepEqual(plain(Avatar.pipelineArgs('/n/core/avatar/make-avatar.py', '/p.jpg', '/o', '/m')),
    ['python3', '/n/core/avatar/make-avatar.py', '--photo', '/p.jpg', '--out', '/o', '--models', '/m']);
  assert.deepEqual(plain(Avatar.pipelineArgs('/t/bin/make-avatar', '/p.jpg', '/o', '/m')).slice(0, 2), ['/t/bin/make-avatar', '--photo']);
});

test('faceFromLandmarks: lips, chin below them, eyes and their lids', () => {
  const f = plain(Avatar.faceFromLandmarks(face()));
  assert.deepEqual(f.size, [600, 640]);
  assert.deepEqual(f.mouthL, [250, 400]);
  assert.equal(f.chin, 80);
  assert.deepEqual(f.eyeA, [200, 280, 260, 280]);
  assert.deepEqual(f.lidsA, [12.5, 8 * 1.1]);
  assert.equal(f.openMax, 50 * 0.22);
  assert.deepEqual(f.box, { x: 180, y: 180, w: 240, h: 300 });
});

test('faceFromLandmarks: the chin is measured across a tilted mouth', () => {
  const f = face();
  // The mouth tilted 45°: the chin's distance is along the perpendicular.
  f.points.mouthL = [0, 0]; f.points.mouthR = [100, 100]; f.points.chin = [0, 100];
  assert.ok(Math.abs(Avatar.faceFromLandmarks(f).chin - 100 / Math.SQRT2) < 1e-9);
});

test('faceFromLandmarks: lids never collapse to nothing', () => {
  const f = face();
  f.points.eyeAUpper = [230, 280]; f.points.eyeALower = [230, 280];
  const r = plain(Avatar.faceFromLandmarks(f));
  assert.deepEqual(r.lidsA, [4, 3]);
});

test('faceFromLandmarks: null when anything is missing', () => {
  assert.equal(Avatar.faceFromLandmarks(null), null);
  assert.equal(Avatar.faceFromLandmarks({ size: [0, 10], points: face().points }), null);
  const f = face(); delete f.points.chin;
  assert.equal(Avatar.faceFromLandmarks(f), null);
  const g = face(); g.points.mouthL = [1, NaN];
  assert.equal(Avatar.faceFromLandmarks(g), null);
});

test('framing: the face fills the asked share of the view, a bit above the middle', () => {
  const f = Avatar.faceFromLandmarks(face());
  const fr = plain(Avatar.framing(f, 0.7));
  // face height 300 of 640: zoom = .7 / (300 / 640)
  assert.ok(Math.abs(fr.zoom - 0.7 / (300 / 640)) < 1e-9);
  assert.equal(fr.focus[0], 0.5);
  assert.ok(fr.focus[1] < (180 + 150) / 640);
  assert.deepEqual(plain(Avatar.framing(null, 0.7)), { zoom: 1, focus: [0.5, 0.5] });
});

test('framing: zoom stays between .6 and 4', () => {
  const tiny = face(); tiny.points.top = [300, 470];
  assert.equal(Avatar.framing(Avatar.faceFromLandmarks(tiny), 0.7).zoom, 4);
  assert.equal(Avatar.framing(Avatar.faceFromLandmarks(face()), 0.1).zoom, 0.6);
});

test('palette: warm is the accent, cool its complement, photo keeps the photo', () => {
  const p = plain(Avatar.palette([1, 0.4, 0.1], ''));
  assert.ok(p.warm[0] > p.warm[2], 'warm stays orange');
  assert.ok(p.cool[2] > p.cool[0], 'its complement is blue');
  assert.ok(p.hot[1] > p.warm[1], 'the highlight is lighter');
  assert.equal(p.photo, 0);
  assert.equal(Avatar.palette([1, 0.4, 0.1], 'photo').photo, 1);
});

test('palette: a grey accent lights the face with two greys', () => {
  const p = plain(Avatar.palette([0.79, 0.8, 0.8], ''));
  for (const c of [p.warm, p.cool]) assert.ok(Math.max(...c) - Math.min(...c) < 0.05);
});

test('parseProgress: steps, the end, errors; anything else is null', () => {
  assert.deepEqual(plain(Avatar.parseProgress('{"step":"download","progress":0.42}')), { step: 'download', progress: 0.42 });
  assert.deepEqual(plain(Avatar.parseProgress('{"step":"depth"}')), { step: 'depth', progress: -1 });
  assert.deepEqual(plain(Avatar.parseProgress('{"step":"x","progress":3}')), { step: 'x', progress: 1 });
  assert.deepEqual(plain(Avatar.parseProgress('{"done":true}')), { done: true });
  assert.deepEqual(plain(Avatar.parseProgress('{"error":"missing","packages":["python-mediapipe"]}')),
    { error: 'missing', packages: ['python-mediapipe'] });
  assert.equal(Avatar.parseProgress('Downloading...'), null);
  assert.equal(Avatar.parseProgress('[1]'), null);
  assert.equal(Avatar.parseProgress('{}'), null);
});

test('statusText: the step and its percent, what is missing, nothing when idle', () => {
  assert.equal(Avatar.statusText(null), '');
  assert.equal(Avatar.statusText({ running: true, step: 'download', progress: 0.42 }), 'Downloading the models (once, about 120 MB) 42 %');
  assert.equal(Avatar.statusText({ running: true, step: 'face', progress: -1 }), 'Finding the face…');
  assert.equal(Avatar.statusText({ running: true, step: '', progress: -1 }), 'Starting…');
  assert.match(Avatar.statusText({ running: false, error: 'missing', packages: ['python-mediapipe'] }), /^Needs python-mediapipe: run make avatar-deps/);
  assert.equal(Avatar.statusText({ running: false, error: 'no face in the photo' }), 'no face in the photo');
  assert.equal(Avatar.statusText({ running: false }), '');
});

test('request: a photo by its path, ~ under home, remove; a relative path is refused', () => {
  assert.deepEqual(plain(Avatar.request('/p/me.jpg', '/home/u')), { action: 'create', photo: '/p/me.jpg' });
  assert.deepEqual(plain(Avatar.request('~/Pictures/me 2.jpg', '/home/u/')), { action: 'create', photo: '/home/u/Pictures/me 2.jpg' });
  assert.deepEqual(plain(Avatar.request('"/p/a b.jpg"', '/h')), { action: 'create', photo: '/p/a b.jpg' });
  assert.deepEqual(plain(Avatar.request('remove', '/h')), { action: 'remove' });
  assert.deepEqual(plain(Avatar.request('', '/h')), { action: 'usage' });
  assert.deepEqual(plain(Avatar.request('me.jpg', '/h')), { action: 'relative', path: 'me.jpg' });
});

test('Agent.parseCommand: avatar and its argument', () => {
  assert.deepEqual(plain(Agent.parseCommand('avatar ~/me.jpg')), { action: 'avatar', text: '~/me.jpg' });
  assert.deepEqual(plain(Agent.parseCommand('avatar')), { action: 'avatar', text: '' });
  assert.equal(Agent.parseCommand('avatars').action, 'usage');
});

test('blinks: the next one in 2.5 to 6.5 s, or a quick second one', () => {
  assert.equal(Avatar.nextBlink(() => 0.1), 0.32);
  assert.equal(Avatar.nextBlink(() => 0.5), 2.5 + 0.5 * 4);
});

test('blinkLevel: down, shut, up, then open', () => {
  assert.equal(Avatar.blinkLevel(-1), 0);
  assert.equal(Avatar.blinkLevel(0), 0);
  assert.ok(Math.abs(Avatar.blinkLevel(0.07) - 1) < 1e-9);
  assert.equal(Avatar.blinkLevel(0.09), 1);
  assert.ok(Avatar.blinkLevel(0.2) > 0 && Avatar.blinkLevel(0.2) < 1);
  assert.equal(Avatar.blinkLevel(0.3), 0);
});

// A seeded generator, so the plan is the same every run.
const seeded = (seed) => () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;

test('speechPlan: syllables in order, words apart, a breath after', () => {
  const plan = plain(Avatar.speechPlan(10, seeded(7)));
  assert.ok(plan.syllables.length >= 3);
  for (let i = 1; i < plan.syllables.length; i++) assert.ok(plan.syllables[i].start >= plan.syllables[i - 1].end);
  for (const s of plan.syllables) {
    assert.ok(s.end - s.start >= 0.09 && s.end - s.start <= 0.21);
    assert.ok(s.amp >= 0.2 && s.amp <= 1);
  }
  assert.ok(plan.until > plan.end && plan.end > 10);
});

test('speechLevel: open inside a syllable, half closed between syllables of a word, shut between words', () => {
  const plan = {
    syllables: [
      { start: 0, end: 0.1, amp: 0.5, wide: 1.05, word: 0 },
      { start: 0.1, end: 0.2, amp: 0.5, wide: 1, word: 0 },
      { start: 0.3, end: 0.4, amp: 0.8, wide: 1, word: 1 },
    ],
    end: 0.4, until: 1,
  };
  assert.ok(Math.abs(Avatar.speechLevel(plan, 0.05).open - 0.5) < 1e-9);
  assert.equal(Avatar.speechLevel(plan, 0.05).wide, 1.05);
  assert.equal(Avatar.speechLevel(plan, 0.099).open, 0.12);   // end of a syllable, same word next
  assert.ok(Avatar.speechLevel(plan, 0.199).open < 0.12);     // last syllable of its word closes
  assert.equal(Avatar.speechLevel(plan, 0.25).open, 0);       // between words
  assert.equal(Avatar.speechLevel(plan, 2).open, 0);
  assert.equal(Avatar.speechLevel(null, 0).open, 0);
});
