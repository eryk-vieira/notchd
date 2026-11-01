import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { load, plain } from './load.mjs';

const Agent = load('core/Agent.js');
const Terminal = load('core/Terminal.js');

// Titles as Codex 0.166 sets them by default: spinning while it starts and
// works, the project alone until the thread is named, then "thread | project".
test('codexTitle: the spinner means working', () => {
  assert.deepEqual(plain(Agent.codexTitle('⠋ job-stuff')), { working: true, title: '' });
  assert.deepEqual(plain(Agent.codexTitle('⠼ Fix the login bug | job-stuff')), { working: true, title: 'Fix the login bug' });
  assert.deepEqual(plain(Agent.codexTitle('Fix the login bug | job-stuff')), { working: false, title: 'Fix the login bug' });
});

test('codexTitle: the project alone is no title', () => {
  assert.deepEqual(plain(Agent.codexTitle('job-stuff')), { working: false, title: '' });
  assert.deepEqual(plain(Agent.codexTitle('')), { working: false, title: '' });
  assert.deepEqual(plain(Agent.codexTitle(undefined)), { working: false, title: '' });
});

test('codexTitle: a thread named with the separator keeps it; an id is no title', () => {
  assert.deepEqual(plain(Agent.codexTitle('A | B | proj')), { working: false, title: 'A | B' });
  assert.deepEqual(plain(Agent.codexTitle('⠙ 01a194a2-ebb9-7443-ad26-3577def90666 | proj')), { working: true, title: '' });
});

// Titles as Claude Code sets them: ✳ idle, a turning half circle while it
// works, "Claude Code" until the conversation is named.
test('claudeTitle: ✳ is idle, a half circle is working', () => {
  assert.deepEqual(plain(Agent.claudeTitle('✳ Claude Code')), { working: false, title: '' });
  assert.deepEqual(plain(Agent.claudeTitle('◐ Claude Code')), { working: true, title: '' });
  assert.deepEqual(plain(Agent.claudeTitle('◑ Simple acknowledgment reply')), { working: true, title: 'Simple acknowledgment reply' });
  assert.deepEqual(plain(Agent.claudeTitle('✳ Simple acknowledgment reply')), { working: false, title: 'Simple acknowledgment reply' });
});

test('claudeTitle: no title before it starts', () => {
  assert.deepEqual(plain(Agent.claudeTitle('')), { working: false, title: '' });
  assert.deepEqual(plain(Agent.claudeTitle(null)), { working: false, title: '' });
});

test('donePeek: only when work ends with no view open, after typing', () => {
  const base = { wasWorking: true, working: false, open: false, typed: true };
  assert.equal(Agent.donePeek(base), true);
  assert.equal(Agent.donePeek({ ...base, open: true }), false, 'you are looking at it');
  assert.equal(Agent.donePeek({ ...base, typed: false }), false, 'the spinner while it starts');
  assert.equal(Agent.donePeek({ ...base, working: true }), false);
  assert.equal(Agent.donePeek({ ...base, wasWorking: false }), false);
});

test('parseCommand: new, ask with or without text, else usage', () => {
  assert.deepEqual(plain(Agent.parseCommand(' new ')), { action: 'new', text: '' });
  assert.deepEqual(plain(Agent.parseCommand('ask')), { action: 'ask', text: '' });
  assert.deepEqual(plain(Agent.parseCommand('ask  why is the sky blue? ')), { action: 'ask', text: 'why is the sky blue?' });
  assert.deepEqual(plain(Agent.parseCommand('asking')), { action: 'usage', text: '' });
  assert.deepEqual(plain(Agent.parseCommand('')), { action: 'usage', text: '' });
});

test('parseCommand: a line break in the question would send it early', () => {
  assert.deepEqual(plain(Agent.parseCommand('ask first\nsecond\r\n third')), { action: 'ask', text: 'first second third' });
});

test('expandHome: ~ and ~/x under home, the rest as given', () => {
  assert.equal(Terminal.expandHome('~', '/home/u'), '/home/u');
  assert.equal(Terminal.expandHome('', '/home/u/'), '/home/u');
  assert.equal(Terminal.expandHome('  ~/Projects/x ', '/home/u'), '/home/u/Projects/x');
  assert.equal(Terminal.expandHome('/srv/work', '/home/u'), '/srv/work');
  assert.equal(Terminal.expandHome('~other', '/home/u'), '~other');
  assert.equal(Terminal.expandHome(undefined, ''), '/');
});

// Run through a real sh: the extra arguments must arrive as given, quotes
// and brackets included, after the command's own.
test('shellArgs: the command is parsed by sh, the extra arguments are not', () => {
  const argv = plain(Terminal.shellArgs("printf '%s|' first", ['-c', 'a=["x","y"]', 'it\'s "x" $HOME']));
  const out = execFileSync('/bin/sh', argv, { encoding: 'utf8' });
  assert.equal(out, 'first|-c|a=["x","y"]|it\'s "x" $HOME|');
});

test('shellArgs: TERM says 256 colors', () => {
  const out = execFileSync('/bin/sh', plain(Terminal.shellArgs('printenv TERM')), { encoding: 'utf8', env: { TERM: 'xterm', PATH: process.env.PATH } });
  assert.equal(out.trim(), 'xterm-256color');
});

// Bug: with Breeze's palette, the messages you sent to Codex sat on an
// orange band (ANSI 8, which Codex uses when it can't ask the background).
// tests/qml/shell.qml checks the color itself where the widget is installed.
test('SCHEME: Tango, whose bright black is gray', () => {
  assert.equal(Terminal.SCHEME, 'Tango');
});

test('PROBE imports only the widget', () => {
  assert.match(Terminal.PROBE, /import QMLTermWidget/);
});

test('isLeaveKey: Ctrl+Escape alone; plain Escape is the agent\'s', () => {
  const ESC = 0x01000000, CTRL = 0x04000000, SHIFT = 0x02000000, KEYPAD = 0x20000000;
  assert.equal(Terminal.isLeaveKey(ESC, CTRL), true);
  assert.equal(Terminal.isLeaveKey(ESC, CTRL | KEYPAD), true);
  assert.equal(Terminal.isLeaveKey(ESC, 0), false);
  assert.equal(Terminal.isLeaveKey(ESC, CTRL | SHIFT), false);
  assert.equal(Terminal.isLeaveKey(0x43, CTRL), false);   // Ctrl+C goes to the agent
});
