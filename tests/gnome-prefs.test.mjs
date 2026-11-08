// The GNOME settings window's model (hosts/gnome/prefsModel.js): the
// daemon's schema as pages, groups and controls, and edits as messages.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { load, plain } from './load.mjs';
import * as M from '../hosts/gnome/prefsModel.js';

const Settings = load('core/settings/Settings.js');
const Config = load('core/Config.js');
const fixture = (dir, name, i = 0) =>
  JSON.parse(fs.readFileSync(new URL(`./protocol/${dir}/${name}.json`, import.meta.url), 'utf8')).valid[i];

const field = (extra) => ({ page: 'general', section: '', visible: true, ...extra });

test('every field type of the schema has a control, the unknown none', () => {
  const types = ['choice', 'integer', 'number', 'boolean', 'string', 'color', 'modules', 'workspaces',
    'notches', 'moduleCatalog', 'note'];
  for (const type of types) assert.notEqual(M.controlOf({ type }), 'unsupported', type);
  assert.equal(M.controlOf({ type: 'slider' }), 'unsupported');
  assert.deepEqual(['modules', 'workspaces', 'notches', 'moduleCatalog'].map((type) => M.isWide({ type })), [true, true, true, true]);
  assert.equal(M.isWide({ type: 'boolean' }), false);
});

test('the sidebar is the pages that are not sub-pages, with Adwaita icons', () => {
  const schema = fixture('to-ui', 'schema');
  assert.deepEqual(M.navPages(schema), [{ id: 'general', label: 'General', icon: 'preferences-system-symbolic' }]);
  assert.equal(M.pageIcon('someone-else'), 'preferences-other-symbolic');
});

test('a page groups its fields by section; a wide field takes a group of its own', () => {
  const schema = { pages: [], fields: [
    field({ section: 'Hover', key: 'a', type: 'integer', label: 'A' }),
    field({ section: 'Hover', key: 'b', type: 'boolean', label: 'B' }),
    field({ section: 'Modules', key: 'm', type: 'modules', label: 'Loaded', help: 'What it shows' }),
    field({ section: 'Modules', key: 'c', type: 'boolean', label: 'C' }),
    field({ page: 'other', key: 'z', type: 'boolean' }),
  ] };
  const groups = M.pageGroups(schema, 'general');
  assert.deepEqual(groups.map((g) => [g.title, g.description, g.wide, g.fields.map((f) => f.key)]),
    [['Hover', '', false, ['a', 'b']], ['Loaded', 'What it shows', true, ['m']], ['', '', false, ['c']]]);
});

test('a page keeps its shape while only values, and visibility change', () => {
  const f = field({ key: 'a', type: 'integer', min: 0, max: 10, value: 1 });
  const before = M.pageShape({ fields: [f] }, 'general');
  assert.equal(M.pageShape({ fields: [{ ...f, value: 5, visible: false }] }, 'general'), before);
  assert.notEqual(M.pageShape({ fields: [{ ...f, max: 20 }] }, 'general'), before);
  assert.notEqual(M.pageShape({ fields: [f, field({ key: 'b', type: 'boolean' })] }, 'general'), before);
});

test('a missing value shows the default; the default goes back as a removal', () => {
  const f = field({ key: 'k', type: 'integer', default: 120 });
  assert.equal(M.valueOf(f), 120);
  assert.equal(M.valueOf({ ...f, value: 200 }), 200);
  assert.equal(M.wireValue(f, 120), null);
  assert.equal(M.wireValue(f, 200), 200);
  assert.equal(M.wireValue(field({ default: ['a', 'b'] }), ['a', 'b']), null, 'lists compare by value');
  assert.equal(M.wireValue(field({}), false), false, 'no default: the value as is');
  assert.equal(M.wireValue(f, undefined), null);
});

test('spin rows: a percent is shown 0 to 100 and comes back snapped to the step and in range', () => {
  const pct = field({ type: 'number', display: 'percent', min: 0, max: 1, step: 0.05 });
  assert.deepEqual(plain(M.spinSpec(pct)), { min: 0, max: 100, step: 5, digits: 0, unit: '%' });
  assert.equal(M.toSpin(pct, 0.85), 85);
  assert.equal(M.fromSpin(pct, 85), 0.85);
  assert.equal(M.fromSpin(pct, 87), 0.85);
  assert.equal(M.fromSpin(pct, 140), 1);
  const ms = field({ type: 'integer', min: 0, max: 2000, step: 20, unit: 'ms' });
  assert.deepEqual(plain(M.spinSpec(ms)), { min: 0, max: 2000, step: 20, digits: 0, unit: 'ms' });
  assert.equal(M.fromSpin(ms, 131), 140);
  assert.equal(M.fromSpin(ms, -5), 0);
  const fine = field({ type: 'number', min: 0, max: 1, step: 0.01 });
  assert.equal(M.spinSpec(fine).digits, 2);
  assert.equal(M.fromSpin(fine, 0.35000000000000003), 0.35);
  for (let v = 0; v <= 2000; v += 7) {
    const out = M.fromSpin(ms, v);
    assert.ok(out % 20 === 0 && out >= 0 && out <= 2000, `${v} -> ${out}`);
  }
});

test('combo rows: items by label, the index back to the value, out of range to none', () => {
  const schema = fixture('to-ui', 'schema', 2);
  const f = schema.fields.find((x) => x.key === 'compact');
  assert.deepEqual(M.comboItems(f).map((i) => i.label), ['Always', 'While playing']);
  assert.equal(M.comboIndex(f, 'playing'), 1);
  assert.equal(M.comboIndex(f, 'gone'), 0);
  assert.equal(M.comboValue(f, 0), 'always');
  assert.equal(M.comboValue(f, 1), 'playing');
  assert.equal(M.comboValue(f, 9), undefined);
});

test('text and color entries commit as TextControl does', () => {
  const s = field({ type: 'string', key: 'k', default: '' });
  assert.deepEqual(M.textEdit(s, '  hi  '), { ok: true, value: 'hi' });
  assert.deepEqual(M.textEdit(s, '   '), { ok: true, value: null });
  assert.deepEqual(M.textEdit({ ...s, required: true }, ''), { ok: false });
  const c = field({ type: 'color', key: 'theme.accent' });
  assert.deepEqual(M.textEdit(c, '#88c0d0'), { ok: true, value: '#88c0d0' });
  assert.deepEqual(M.textEdit(c, 'blue'), { ok: false });
  assert.deepEqual(M.textEdit(c, '#12345'), { ok: false });
});

test('colors are Qt hex, alpha first, both ways', () => {
  assert.deepEqual(M.colorToRgba('#fff'), { red: 1, green: 1, blue: 1, alpha: 1 });
  const c = M.colorToRgba('#80ff0000');
  assert.equal(c.red, 1);
  assert.equal(c.blue, 0);
  assert.ok(Math.abs(c.alpha - 128 / 255) < 1e-9);
  assert.equal(M.colorToRgba('red'), null);
  assert.equal(M.rgbaToColor({ red: 1, green: 0.5, blue: 0, alpha: 1 }), '#ff8000');
  assert.equal(M.rgbaToColor(M.colorToRgba('#80ff0000')), '#80ff0000');
});

const catalog = [
  { moduleId: 'media', title: 'Now playing' },
  { moduleId: 'timer', title: 'Timer' },
  { moduleId: 'osd', title: 'OSD' },
  { moduleId: 'claude', title: 'Claude', agent: true },
];

test('a notch module list: switched-on first in order, then the rest', () => {
  const f = field({ type: 'modules', key: 'modules', default: ['media'], value: ['timer', 'gone'] });
  const rows = M.moduleRows(f, catalog);
  assert.deepEqual(rows.map((r) => [r.id, r.on, r.known, r.canUp, r.canDown]), [
    ['timer', true, true, false, true],
    ['gone', true, false, true, false],
    ['media', false, true, false, false],
    ['osd', false, true, false, false],
    ['claude', false, true, false, false],
  ]);
  assert.equal(rows[0].title, 'Timer');
  assert.equal(rows[1].title, 'Gone');
  assert.deepEqual(M.moduleRows({ ...f, value: undefined }, catalog).filter((r) => r.on).map((r) => r.id), ['media'], 'the default');
});

test('workspace chips: 1 to 10 and the picked ones, numbers first', () => {
  const chips = M.workspaceChips(field({ type: 'workspaces', value: [3, 'web'] }), [], Settings);
  assert.equal(chips.length, 11);
  assert.deepEqual(chips.filter((c) => c.on).map((c) => c.value), [3, 'web']);
  assert.equal(chips[10].label, 'web');
  assert.equal(M.workspaceChips(field({ type: 'workspaces' }), [], Settings).filter((c) => c.on).length, 0);
  assert.equal(M.workspaceChips(field({ type: 'workspaces' }), ['11'], Settings).at(-1).value, 11);
});

const state = { settingsOpen: false, settingsPage: 'general', order: ['main', 'side'], notches: [
  { id: 'main', edge: 'top', number: 1, modules: ['media', 'timer'] },
  { id: 'side', edge: 'left', number: 2, modules: [] },
] };

test('the notch list: where each is and what it shows, removable with more than one', () => {
  const rows = M.notchRows(state, catalog, Settings);
  assert.deepEqual(rows.map((r) => [r.index, r.id, r.number, r.summary, r.removable]), [
    [0, 'main', 1, 'Top edge · Now playing, Timer', true],
    [1, 'side', 2, 'Left edge · no modules', true],
  ]);
  assert.equal(M.notchRows({ notches: [state.notches[0]] }, catalog, Settings)[0].removable, false);
});

test('an undecorated notch can go while another stays, and is no reason to keep the last decorated one', () => {
  const hidden = { id: 'osd', edge: 'top', number: 2, decoration: false, modules: ['osd'] };
  const rows = M.notchRows({ order: ['main', 'osd'], notches: [state.notches[0], hidden] }, catalog, Settings);
  assert.deepEqual(rows.map((r) => [r.id, r.removable]), [['main', false], ['osd', true]]);
});

test('the notch list follows the daemon\'s spatial order, each with its number, its page by config index', () => {
  // Config order Media (left), Herdr (top center), FLEX (top left).
  const spatial = { order: ['flex', 'herdr', 'media'], notches: [
    { id: 'media', edge: 'left', number: 3, modules: [] },
    { id: 'herdr', edge: 'top', number: 2, modules: [] },
    { id: 'flex', edge: 'top', number: 1, modules: [] },
  ] };
  assert.deepEqual(M.notchRows(spatial, catalog, Settings).map((r) => [r.id, r.number, r.index]),
    [['flex', 1, 2], ['herdr', 2, 1], ['media', 3, 0]]);
  // Without an order (an older daemon) the config's.
  const none = { notches: spatial.notches.map(({ number, ...n }) => n) };
  assert.deepEqual(M.notchRows(none, catalog, Settings).map((r) => [r.id, r.number]),
    [['media', 0], ['herdr', 0], ['flex', 0]]);
});

test('a module catalog part: status from the state, a page when the schema has one', () => {
  const schema = { modules: catalog, pages: [{ id: 'modules/media', label: 'Now playing', sub: true }] };
  const rows = M.catalogRows({ part: 'notch' }, schema, state, {}, Settings, Config);
  assert.deepEqual(rows.map((r) => [r.id, r.status, r.page]), [
    ['media', 'In main', 'modules/media'],
    ['timer', 'In main', ''],
    ['osd', 'Off', ''],
  ]);
  // Yours: every custom module of the catalog, removable, with what it has.
  const yours = [
    { moduleId: 'herdr', title: 'Herdr', origin: 'user', process: true, terminal: true, dir: '/c/modules/herdr', permissions: ['network'] },
    { moduleId: 'btop', title: 'btop', origin: 'user', terminal: true, dir: '/c/modules/btop' },
  ];
  const withYours = { modules: [...catalog, ...yours], pages: [...schema.pages, { id: 'modules/btop', label: 'btop', sub: true }] };
  const yourRows = M.catalogRows({ part: 'user' }, withYours, state, {}, Settings, Config);
  assert.deepEqual(plain(yourRows.map((r) => [r.id, r.removable, r.badges, r.detail, r.page])), [
    ['herdr', true, ['process', 'terminal'], '/c/modules/herdr · permissions: network', ''],
    ['btop', true, ['terminal'], '/c/modules/btop', 'modules/btop'],
  ]);
  assert.equal(M.catalogRows({ part: 'notch' }, withYours, state, {}, Settings, Config).some((r) => r.removable), false,
    'the built-in ones are not removable');
});

test('config edits are one set per top-level key that changed, null for a removal', () => {
  assert.deepEqual(M.configSets({ a: 1, b: { c: 2 }, gone: 1 }, { a: 1, b: { c: 3 }, d: [] }),
    [{ key: 'b', value: { c: 3 } }, { key: 'gone', value: null }, { key: 'd', value: [] }]);
});

test('pages: a notch page counts while the notch exists, another missing page falls back', () => {
  const schema = { pages: [{ id: 'general', sub: false }, { id: 'notch', sub: false }, { id: 'notch/0', label: 'main', sub: true }] };
  assert.equal(M.resolvePage(schema, state, 'notch/0'), 'notch/0');
  assert.equal(M.resolvePage(schema, state, 'notch/1'), 'notch/1', 'the daemon fills it in once told');
  assert.equal(M.resolvePage(schema, state, 'notch/5'), 'notch');
  assert.equal(M.resolvePage(schema, state, 'modules/gone'), 'general');
  assert.equal(M.notchIdOfPage(schema, state, 'notch/0'), 'main');
  assert.equal(M.notchIdOfPage(schema, state, 'notch/1'), 'side');
  assert.equal(M.notchIdOfPage(schema, state, 'general'), '');
});

test('the window follows the daemon page, but not its echo of one it reported', () => {
  const open = { settingsOpen: true, settingsPage: 'notch/1' };
  assert.equal(M.pageToFollow(open, 'general', [], 10_000), 'notch/1');
  assert.equal(M.pageToFollow(open, 'notch/1', [], 10_000), '');
  assert.equal(M.pageToFollow(open, 'general', [{ page: 'notch/1', at: 9_000 }], 10_000), '');
  assert.equal(M.pageToFollow(open, 'general', [{ page: 'notch/1', at: 7_000 }], 10_000), 'notch/1');
  assert.equal(M.pageToFollow({ ...open, settingsOpen: false }, 'general', [], 10_000), '');
});

test('every field of a real schema fixture maps to a control', () => {
  for (const i of [0, 2]) {
    for (const f of fixture('to-ui', 'schema', i).fields) assert.notEqual(M.controlOf(f), 'unsupported', f.type);
  }
});
