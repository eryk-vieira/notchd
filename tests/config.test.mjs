import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const Config = load('core/Config.js');

test('parse accepts a JSON object and rejects everything else', () => {
  assert.deepEqual(plain(Config.parse('{"a":1}')), { ok: true, config: { a: 1 } });
  assert.deepEqual(plain(Config.parse('')), { ok: true, config: {} });
  assert.equal(Config.parse('[1]').ok, false);
  assert.equal(Config.parse('"x"').ok, false);
  assert.equal(Config.parse('null').ok, false);
  assert.equal(Config.parse('{oops').ok, false);
});

test('valueAt follows dotted keys and tolerates missing parents', () => {
  const cfg = { theme: { accent: '#fff' }, modules: ['media'] };
  assert.equal(Config.valueAt(cfg, 'theme.accent'), '#fff');
  assert.equal(Config.valueAt(cfg, 'theme.missing'), undefined);
  assert.equal(Config.valueAt(cfg, 'nope.deeper.still'), undefined);
  assert.equal(Config.valueAt(cfg, 'modules.0'), 'media');
});

test('withValue sets nested keys without touching the input', () => {
  const cfg = { hoverOpenDelay: 100 };
  const next = Config.withValue(cfg, 'theme.accent', '#abc');
  assert.deepEqual(plain(next), { hoverOpenDelay: 100, theme: { accent: '#abc' } });
  assert.deepEqual(cfg, { hoverOpenDelay: 100 });
});

test('withValue stores a plain copy of the value', () => {
  const list = [1, 2];
  const next = Config.withValue({}, 'workspaces', list);
  list.push(3);
  assert.deepEqual(plain(next), { workspaces: [1, 2] });
  assert.equal(Array.isArray(next.workspaces), true);
});

test('withValue with undefined removes the key and emptied parents', () => {
  const cfg = { theme: { accent: '#abc' }, topOffset: 4 };
  assert.deepEqual(plain(Config.withValue(cfg, 'theme.accent', undefined)), { topOffset: 4 });
  assert.deepEqual(plain(Config.withValue(cfg, 'topOffset', undefined)), { theme: { accent: '#abc' } });
});

test('withValue removing a key under a missing parent changes nothing', () => {
  assert.deepEqual(plain(Config.withValue({ a: 1 }, 'theme.accent', undefined)), { a: 1 });
});

test('resolve: the service-wide keys, defaults for missing or bad ones', () => {
  assert.deepEqual(plain(Config.resolve({})), { hoverOpenDelay: 120, hoverCloseDelay: 300 });
  assert.deepEqual(plain(Config.resolve({ hoverOpenDelay: -50, hoverCloseDelay: 'x' })), { hoverOpenDelay: 0, hoverCloseDelay: 0 });
});

const one = (cfg, defaults = ['media']) => plain(Config.notches(cfg, defaults))[0];

test('notches: without a list, the top level is the one notch, at its defaults', () => {
  assert.deepEqual(plain(Config.notches({}, ['media'])), [{
    id: 'main', index: 0, prefix: '', moduleIds: ['media'],
    reserveSpace: false, draggable: true, tabs: true, idleIcons: true, workspaces: null, position: undefined
  }].map(plain));
  assert.equal(plain(Config.notches({ notches: [] }, [])).length, 1);
});

test('notches: reads and clamps the notch keys', () => {
  const n = one({ modules: ['osd', 3], reserveSpace: true, draggable: false, tabs: false, workspaces: [1, 'code'] }, []);
  assert.deepEqual(n.moduleIds, ['osd', '3']);
  assert.equal(n.reserveSpace, true);
  assert.equal(n.draggable, false);
  assert.equal(n.tabs, false);
  assert.equal(one({ tabs: 'no' }).tabs, true);
  assert.equal(one({ idleIcons: false }).idleIcons, false);
  assert.equal(one({ idleIcons: 'no' }).idleIcons, true);
  assert.deepEqual(n.workspaces, [1, 'code']);
  // The compact style left with the notch in the bar: a config that still
  // has one changes nothing.
  assert.equal(one({ compactStyle: 'bar' }).compactStyle, undefined);
  assert.equal(one({ reserveSpace: 'yes' }).reserveSpace, false);
  assert.equal(one({ draggable: 'no' }).draggable, true);
  assert.equal(one({ workspaces: [] }).workspaces, null);
  assert.equal(one({ workspaces: 3 }).workspaces, null);
  assert.deepEqual(one({ workspaces: [2, '', null, 'x'] }).workspaces, [2, 'x']);
});

test('notches: each listed notch inherits the top-level keys it leaves out', () => {
  const cfg = {
    modules: ['media'], reserveSpace: true, position: { edge: 'left', offset: 0.2 },
    notches: [{}, { id: 'jobs', modules: ['activities'], reserveSpace: false, tabs: false, position: { offset: 0.8, screen: 'all' } }]
  };
  const [main, jobs] = plain(Config.notches(cfg, ['osd']));
  assert.deepEqual([main.tabs, jobs.tabs], [true, false]);
  assert.deepEqual([main.id, main.prefix, main.moduleIds, main.reserveSpace], ['main', 'notches.0.', ['media'], true]);
  assert.deepEqual(main.position, { edge: 'left', offset: 0.2 });
  assert.deepEqual([jobs.id, jobs.index, jobs.prefix, jobs.moduleIds, jobs.reserveSpace],
                   ['jobs', 1, 'notches.1.', ['activities'], false]);
  assert.deepEqual(jobs.position, { edge: 'left', offset: 0.8, screen: 'all' });
});

test('notches: ids default by place and never repeat', () => {
  const ids = plain(Config.notches({ notches: [{}, {}, { id: 'main' }, { id: ' x ' }, { id: 'x' }, 'junk'] }, []))
    .map((n) => n.id);
  assert.deepEqual(ids, ['main', 'notch-2', 'main-2', 'x', 'x-2', 'notch-6']);
});

test('moduleUnion: every module a notch shows, once, in first-seen order', () => {
  const specs = plain(Config.notches({ notches: [{ modules: ['osd', 'media'] }, { modules: ['activities', 'osd'] }] }, []));
  assert.deepEqual(plain(Config.moduleUnion(specs)), ['osd', 'media', 'activities']);
  // The host's system modules load whether a notch lists them or not.
  assert.deepEqual(plain(Config.moduleUnion(specs, ['osd', 'clock'])), ['osd', 'media', 'activities', 'clock']);
});

test('freeNotchId: the lowest notch-<n> not taken', () => {
  assert.equal(Config.freeNotchId(['main']), 'notch-2');
  assert.equal(Config.freeNotchId(['main', 'notch-2', 'notch-4']), 'notch-3');
});

test('withNotchAdded turns the top-level notch into the first entry', () => {
  const cfg = { modules: ['media'], hoverOpenDelay: 50 };
  const next = plain(Config.withNotchAdded(cfg, { id: 'jobs', modules: [] }));
  assert.deepEqual(next, { modules: ['media'], hoverOpenDelay: 50, notches: [{}, { id: 'jobs', modules: [] }] });
  assert.deepEqual(plain(Config.withNotchAdded(next, { id: 'c' })).notches.length, 3);
  assert.deepEqual(cfg, { modules: ['media'], hoverOpenDelay: 50 });
});

test('withoutNotch: the last one left goes back to the top level', () => {
  const cfg = { modules: ['media'], position: { edge: 'left', offset: 0.2 },
                notches: [{}, { id: 'jobs', modules: ['activities'], position: { offset: 0.9 } }] };
  assert.deepEqual(plain(Config.withoutNotch(cfg, 0)),
                   { modules: ['activities'], position: { edge: 'left', offset: 0.9 } });
  assert.deepEqual(plain(Config.withoutNotch(cfg, 1)), { modules: ['media'], position: { edge: 'left', offset: 0.2 } });
  const three = { notches: [{ id: 'a' }, { id: 'b' }, { id: 'c' }] };
  assert.deepEqual(plain(Config.withoutNotch(three, 1)), { notches: [{ id: 'a' }, { id: 'c' }] });
  // The last notch stays.
  assert.deepEqual(plain(Config.withoutNotch({ modules: [] }, 0)), { modules: [] });
  assert.deepEqual(plain(Config.withoutNotch(three, 7)), three);
});

test('withValue reaches into the notch list and never prunes an entry', () => {
  const cfg = { notches: [{}, { id: 'jobs', position: { edge: 'left' } }] };
  assert.deepEqual(plain(Config.withValue(cfg, 'notches.1.position.edge', 'right')).notches[1],
                   { id: 'jobs', position: { edge: 'right' } });
  assert.deepEqual(plain(Config.withValue(cfg, 'notches.0.reserveSpace', true)).notches[0], { reserveSpace: true });
  // Emptying an entry keeps it: an empty notch inherits everything.
  const emptied = plain(Config.withValue({ notches: [{ draggable: false }, {}] }, 'notches.0.draggable', undefined));
  assert.deepEqual(emptied, { notches: [{}, {}] });
  const moved = plain(Config.withValue(cfg, 'notches.1.position.edge', undefined));
  assert.deepEqual(moved, { notches: [{}, { id: 'jobs' }] });
  // Removing an entry by index takes it out of the list, no hole.
  assert.deepEqual(plain(Config.withValue(cfg, 'notches.0', undefined)), { notches: [{ id: 'jobs', position: { edge: 'left' } }] });
});

// Bug: a notch dragged onto a screen showing a workspace left out of
// `workspaces` landed there and went straight back to the other screen.
// The drop lets that workspace in.
test('withWorkspace adds the workspace a notch was dropped on', () => {
  assert.deepEqual(plain(Config.withWorkspace([1, 2, 3], { id: 4, name: '4' })), [1, 2, 3, 4]);
  assert.deepEqual(plain(Config.withWorkspace([3, 'code'], { id: 1, name: '1' })), [1, 3, 'code']);
  assert.deepEqual(plain(Config.withWorkspace([1], { id: 7, name: 'mail' })), [1, 'mail']);
  assert.deepEqual(plain(Config.withWorkspace([1, 2], { id: 2, name: '2' })), [1, 2]);
  assert.deepEqual(plain(Config.withWorkspace(['web'], { id: 9, name: 'web' })), ['web']);
  assert.equal(Config.withWorkspace(null, { id: 4, name: '4' }), null);
  assert.deepEqual(plain(Config.withWorkspace([1], null)), [1]);
  // A list that went through a QML var property is array-like, not an Array.
  assert.deepEqual(plain(Config.withWorkspace({ length: 2, 0: 1, 1: 3 }, { id: 2, name: '2' })), [1, 2, 3]);
});

test('moduleLoadList: what notches show, never a standalone module, then the standalone ones switched on', () => {
  const specs = [{ moduleIds: ['osd', 'media'] }, { moduleIds: ['activities', 'media'] }];
  assert.deepEqual(plain(Config.moduleLoadList(specs, ['osd', 'clock'], ['osd', 'clock'])), ['media', 'activities', 'osd', 'clock']);
  assert.deepEqual(plain(Config.moduleLoadList(specs, ['osd', 'clock'], ['clock'])), ['media', 'activities', 'clock'], 'osd is off, even listed');
  assert.deepEqual(plain(Config.moduleLoadList(specs, [], ['media'])), ['osd', 'media', 'activities'], 'enabled only counts for standalone ones');
  assert.deepEqual(plain(Config.moduleLoadList([], undefined, undefined)), []);
});

test('terminals: each entry with a command, in order, its title or ""', () => {
  const r = plain(Config.terminals({ terminals: {
    btop: { title: 'System', command: ' btop ' },
    logs: { command: 'journalctl -f' }
  } }));
  assert.deepEqual(r, { list: [
    { id: 'btop', title: 'System', command: 'btop' },
    { id: 'logs', title: '', command: 'journalctl -f' }
  ], errors: [] });
  assert.deepEqual(plain(Config.terminals({})), { list: [], errors: [] });
});

// An id is a config key too ("btop": { "width" }): one the config already
// has, a module's, or one with a dot would read or write something else.
test('terminals: an id that is taken or no key, or an entry without a command, is left out with why', () => {
  const r = plain(Config.terminals({ terminals: {
    theme: { command: 'x' }, tabs: { command: 'x' }, media: { command: 'x' },
    'a.b': { command: 'x' }, '1x': { command: 'x' },
    empty: { command: '  ' }, none: {}, bad: 'btop', ok: { command: 'x' }
  } }, ['media']));
  assert.deepEqual(r.list.map((t) => t.id), ['ok']);
  assert.equal(r.errors.length, 8, r.errors.join('\n'));
  assert.ok(r.errors[0].startsWith('theme: taken'));
  assert.ok(r.errors[2].startsWith('media: taken'));
  assert.equal(Config.terminals({ terminals: ['btop'] }).errors.length, 1);
});

test('withTerminalAdded: a free id, running your shell', () => {
  const first = plain(Config.withTerminalAdded({ modules: ['media'] }, []));
  assert.equal(first.id, 'terminal');
  assert.deepEqual(first.config, { modules: ['media'], terminals: { terminal: { title: 'Terminal', command: '$SHELL' } } });
  // Taken by a terminal, a config key or a module: the next number.
  const next = plain(Config.withTerminalAdded({ terminals: { terminal: { command: 'x' } }, 'terminal-2': { width: 1 } }, ['terminal-3']));
  assert.equal(next.id, 'terminal-4');
  assert.deepEqual(next.config.terminals['terminal-4'], { title: 'Terminal 4', command: '$SHELL' });
  assert.deepEqual(plain(Config.terminals(next.config)).errors, []);
});

test('withoutTerminal: its entry, its settings and its place in every notch go', () => {
  const cfg = {
    modules: ['media', 'btop'],
    notches: [{}, { id: 'tools', modules: ['btop', 'dev'] }],
    terminals: { btop: { command: 'btop' }, dev: { command: 'npm run dev' } },
    btop: { width: 900 }
  };
  assert.deepEqual(plain(Config.withoutTerminal(cfg, 'btop')), {
    modules: ['media'],
    notches: [{}, { id: 'tools', modules: ['dev'] }],
    terminals: { dev: { command: 'npm run dev' } }
  });
  const none = plain(Config.withoutTerminal(Config.withoutTerminal(cfg, 'btop'), 'dev'));
  assert.equal(none.terminals, undefined);
  // Not a terminal: nothing changes, a module's settings least of all.
  assert.deepEqual(plain(Config.withoutTerminal({ media: { equalizer: 'light' } }, 'media')), { media: { equalizer: 'light' } });
});
