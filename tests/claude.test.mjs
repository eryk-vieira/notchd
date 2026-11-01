import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { load, plain } from './load.mjs';

const Claude = load('core/Claude.js');

// Events recorded from `claude -p --output-format stream-json
// --include-partial-messages` (session ids and the init event's details
// scrubbed): a plain answer, and one that searches the web first.
const events = (name) => fs.readFileSync(new URL(`fixtures/claude-${name}.jsonl`, import.meta.url), 'utf8')
  .split('\n').map((l) => Claude.parseLine(l)).filter(Boolean);
const run = (state, list) => list.reduce((s, ev) => Claude.apply(s, ev), state);

test('command: one session over stream-json, without hooks, MCP or CLAUDE.md', () => {
  const argv = plain(Claude.command({ model: 'sonnet', systemPrompt: 'Be brief.', web: false }));
  assert.equal(argv[0], 'claude');
  for (const flag of ['-p', '--verbose', '--include-partial-messages', '--strict-mcp-config'])
    assert.ok(argv.includes(flag), flag);
  assert.deepEqual(argv.slice(argv.indexOf('--input-format'), argv.indexOf('--input-format') + 2), ['--input-format', 'stream-json']);
  assert.deepEqual(argv.slice(argv.indexOf('--setting-sources'), argv.indexOf('--setting-sources') + 2), ['--setting-sources', '']);
  assert.deepEqual(argv.slice(argv.indexOf('--model'), argv.indexOf('--model') + 2), ['--model', 'sonnet']);
  assert.ok(argv.includes('--tools='), 'no tools without web');
  assert.ok(!argv.includes('--resume'));
});

// `--tools X` swallows the argument after it: always `--tools=X`.
test('command: web tools allowed in the = form, and --resume for a session', () => {
  const argv = plain(Claude.command({ model: 'opus', web: true, sessionId: 'abc' }));
  assert.ok(argv.includes('--tools=WebSearch,WebFetch'));
  assert.ok(argv.includes('--allowedTools=WebSearch,WebFetch'));
  assert.ok(!argv.includes('--tools'));
  assert.deepEqual(argv.slice(-2), ['--resume', 'abc']);
});

test('inputLine: one stream-json user message per line', () => {
  const line = Claude.inputLine('oi\nmundo');
  assert.ok(line.endsWith('\n') && line.indexOf('\n') === line.length - 1);
  assert.deepEqual(JSON.parse(line), { type: 'user', message: { role: 'user', content: 'oi\nmundo' } });
});

test('send: the question and an empty answer, busy; blank changes nothing', () => {
  const s = Claude.send(Claude.EMPTY, '  Qual a capital?  ');
  assert.deepEqual(plain(s.messages.map((m) => [m.role, m.text])), [['user', 'Qual a capital?'], ['assistant', '']]);
  assert.equal(s.busy, true);
  assert.equal(s.activity, 'thinking');
  assert.equal(Claude.send(Claude.EMPTY, '   '), Claude.EMPTY);
});

test('a plain answer streams in and ends idle with the session id', () => {
  const s = run(Claude.send(Claude.EMPTY, 'Reply with exactly: two words'), events('notools'));
  assert.equal(s.busy, false);
  assert.equal(s.error, '');
  assert.equal(s.sessionId, '00000000-0000-4000-8000-000000000001');
  assert.equal(s.messages.length, 2);
  assert.equal(s.messages[1].text, 'two words');
});

test('an answer that searches first records the tool and says so while busy', () => {
  const list = events('web');
  let s = Claude.send(Claude.EMPTY, 'who won?');
  const seen = new Set();
  for (const ev of list) { s = Claude.apply(s, ev); if (s.busy) seen.add(s.activity); }
  assert.ok(seen.has('searching') && seen.has('writing'), [...seen].join());
  assert.deepEqual(plain(s.messages[1].tools), ['WebSearch']);
  const result = list.find((e) => e.type === 'result').result;
  assert.equal(s.messages[1].text, result);
});

test('an error result fails the answer and drops one that never started', () => {
  let s = Claude.send(Claude.EMPTY, 'q');
  s = Claude.apply(s, { type: 'result', subtype: 'error_during_execution', is_error: true, result: 'boom' });
  assert.equal(s.busy, false);
  assert.equal(s.error, 'boom');
  assert.deepEqual(plain(s.messages.map((m) => m.role)), ['user']);
});

test('fail keeps an answer that already has text', () => {
  let s = Claude.send(Claude.EMPTY, 'q');
  s = Claude.apply(s, { type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: 'meio' } } });
  s = Claude.fail(s, 'claude exited');
  assert.equal(s.error, 'claude exited');
  assert.equal(s.messages[1].text, 'meio');
});

test('without partial messages the result has the answer', () => {
  let s = Claude.send(Claude.EMPTY, 'q');
  s = Claude.apply(s, { type: 'result', subtype: 'success', result: 'resposta', session_id: 'x' });
  assert.equal(s.messages[1].text, 'resposta');
  assert.equal(s.sessionId, 'x');
});

test('deltas after the answer ended change nothing', () => {
  const done = run(Claude.send(Claude.EMPTY, 'q'), events('notools'));
  const after = Claude.apply(done, { type: 'stream_event', event: { type: 'content_block_delta', delta: { type: 'text_delta', text: 'x' } } });
  assert.equal(after, done);
});

test('title: the first question on one line, cut; empty before it', () => {
  assert.equal(Claude.title(Claude.EMPTY), '');
  const s = Claude.send(Claude.EMPTY, 'Como converter\nHEIC para JPG no Linux sem perder metadados?');
  assert.equal(Claude.title(s, 24), 'Como converter HEIC par…');
  assert.equal(Claude.title(Claude.send(Claude.EMPTY, 'curto'), 24), 'curto');
});

test('lastAnswer: the latest answer with text', () => {
  const s = run(Claude.send(Claude.EMPTY, 'q'), events('notools'));
  assert.equal(Claude.lastAnswer(s), 'two words');
  assert.equal(Claude.lastAnswer(Claude.send(s, 'again')), 'two words');
});

test('transcriptPath: a folder per working directory, other characters as dashes', () => {
  assert.equal(Claude.transcriptPath('/home/u/.claude/', '/home/u/.local/state/notchd/claude', 'id1'),
    '/home/u/.claude/projects/-home-u--local-state-notchd-claude/id1.jsonl');
});

// The shape Claude Code writes: one line per content block, tool results as
// user entries, thinking blocks, repeated entries.
test('fromTranscript: questions and answers, without tool results or side chains', () => {
  const lines = [
    { type: 'queue-operation' },
    { type: 'user', uuid: 'u1', message: { role: 'user', content: 'Quem ganhou?' } },
    { type: 'assistant', uuid: 'a1', message: { content: [{ type: 'tool_use', name: 'WebSearch', input: {} }] } },
    { type: 'user', uuid: 'r1', message: { content: [{ type: 'tool_result', content: 'results' }] } },
    { type: 'assistant', uuid: 'a2', message: { content: [{ type: 'thinking', thinking: '' }] } },
    { type: 'assistant', uuid: 'a3', message: { content: [{ type: 'text', text: 'A Argentina.' }] } },
    { type: 'assistant', uuid: 'a3', message: { content: [{ type: 'text', text: 'A Argentina.' }] } },
    { type: 'user', uuid: 's1', isSidechain: true, message: { content: 'side' } },
    { type: 'user', uuid: 'm1', isMeta: true, message: { content: 'meta' } },
    { type: 'user', uuid: 'u2', message: { role: 'user', content: [{ type: 'text', text: 'E em 2018?' }] } },
    { type: 'assistant', uuid: 'a4', message: { content: [{ type: 'text', text: 'A França.' }] } },
  ].map((e) => JSON.stringify(e)).join('\n') + '\nnot json\n';
  const s = Claude.fromTranscript(lines, 'sid');
  assert.equal(s.sessionId, 'sid');
  assert.equal(s.busy, false);
  assert.deepEqual(plain(s.messages), [
    { role: 'user', text: 'Quem ganhou?', tools: [] },
    { role: 'assistant', text: 'A Argentina.', tools: ['WebSearch'] },
    { role: 'user', text: 'E em 2018?', tools: [] },
    { role: 'assistant', text: 'A França.', tools: [] },
  ]);
});
