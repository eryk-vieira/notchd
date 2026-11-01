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

// What `claude -p --resume <id>` prints when Claude Code no longer has the
// session (recorded, id changed), before it exits with 1.
const gone = { type: 'result', subtype: 'error_during_execution', is_error: true, num_turns: 0,
  session_id: '11111111-2222-4333-8444-555555555555',
  errors: ['No conversation found with session ID: 11111111-2222-4333-8444-555555555555'] };

test('a session gone starts over from the last question, to send again', () => {
  let s = run(Claude.send(Claude.EMPTY, 'first'), events('notools'));
  s = Claude.send(s, 'second');
  s = Claude.apply(s, gone);
  assert.equal(s.retry, true);
  assert.equal(s.busy, true);
  assert.equal(s.sessionId, '');
  assert.equal(s.error, '');
  assert.match(s.notice, /new one/);
  assert.deepEqual(plain(s.messages.map((m) => [m.role, m.text])), [['user', 'second'], ['assistant', '']]);
  const { state, line } = Claude.resend(s);
  assert.equal(state.retry, false);
  assert.equal(JSON.parse(line).message.content, 'second');
  // The answer in the new session clears nothing but the flag already gone.
  const after = run(state, events('notools'));
  assert.equal(after.messages[1].text, 'two words');
  assert.match(after.notice, /new one/);
  assert.equal(Claude.send(after, 'third').notice, '');
});

test('an error result without text says what its errors say', () => {
  let s = Claude.send(Claude.EMPTY, 'q');
  s = Claude.apply(s, { type: 'result', subtype: 'error_during_execution', is_error: true, errors: ['rate limited'] });
  assert.equal(s.error, 'rate limited');
  assert.equal(s.retry, false);
});

test('title: a made title wins over the first question', () => {
  const s = Object.assign({}, Claude.send(Claude.EMPTY, 'Como converter HEIC'), { title: 'Converter HEIC para JPG' });
  assert.equal(Claude.title(s, 40), 'Converter HEIC para JPG');
  assert.equal(Claude.title(Object.assign({}, Claude.EMPTY, { title: 'Só o título' })), 'Só o título');
});

test('wantsTitle: once, after the first answer, unless it has one or failed', () => {
  const one = run(Claude.send(Claude.EMPTY, 'q'), events('notools'));
  assert.equal(Claude.wantsTitle(one), true);
  assert.equal(Claude.wantsTitle(Claude.send(Claude.EMPTY, 'q')), false);            // busy
  assert.equal(Claude.wantsTitle(Object.assign({}, one, { title: 't' })), false);
  assert.equal(Claude.wantsTitle(run(Claude.send(one, 'again'), events('notools'))), false);
  assert.equal(Claude.wantsTitle(Object.assign({}, one, { error: 'x' })), false);
});

test('titleCommand: Haiku, no session kept, no tools, the chat in the prompt', () => {
  const one = run(Claude.send(Claude.EMPTY, 'Reply with exactly: two words'), events('notools'));
  const argv = plain(Claude.titleCommand(one));
  assert.deepEqual(argv.slice(argv.indexOf('--model'), argv.indexOf('--model') + 2), ['--model', 'haiku']);
  for (const flag of ['-p', '--no-session-persistence', '--strict-mcp-config', '--tools=']) assert.ok(argv.includes(flag), flag);
  assert.ok(!argv.includes('--resume'));
  const prompt = argv[argv.length - 1];
  assert.ok(prompt.includes('Reply with exactly: two words') && prompt.includes('two words'));
});

test('cleanTitle: first line, no quotes, Markdown, label or final period', () => {
  assert.equal(Claude.cleanTitle('"Converter HEIC para JPG."\n'), 'Converter HEIC para JPG');
  assert.equal(Claude.cleanTitle('\n**Title: Kernel Linux estável**\nmore'), 'Kernel Linux estável');
  assert.equal(Claude.cleanTitle('“Copa de 2022”'), 'Copa de 2022');
  assert.equal(Claude.cleanTitle('   '), '');
  assert.equal(Claude.cleanTitle('x'.repeat(80)).length, 60);
});

test('terminalCommand: the terminal, then claude --resume in the session dir', () => {
  assert.deepEqual(plain(Claude.terminalCommand('', '/s/claude', 'id1')),
    ['xdg-terminal-exec', 'sh', '-c', 'cd "$0" && exec claude --resume "$1"', '/s/claude', 'id1']);
  assert.deepEqual(plain(Claude.terminalCommand(' alacritty  -e ', '/d', 'x')).slice(0, 3), ['alacritty', '-e', 'sh']);
});

test('fromTranscript: Claude Code\'s own title, from a terminal session', () => {
  const lines = [
    { type: 'user', uuid: 'u1', message: { role: 'user', content: 'oi' } },
    { type: 'ai-title', aiTitle: 'Saudação simples', sessionId: 'sid' },
  ].map((e) => JSON.stringify(e)).join('\n');
  assert.equal(Claude.fromTranscript(lines, 'sid').title, 'Saudação simples');
});
