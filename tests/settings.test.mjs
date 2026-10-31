import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { load, plain } from './load.mjs';

const Settings = load('core/settings/Settings.js');

const core = [
  { id: 'general', label: 'General', icon: 1 },
  { id: 'modules', label: 'Modules', icon: 2 },
];

test('mergePages lets a host relabel a core page and append its own', () => {
  const pages = plain(Settings.mergePages(core, [{ id: 'modules', label: 'Plugins' }, { id: 'extra', label: 'Extra' }]));
  assert.deepEqual(pages.map((p) => [p.id, p.label, p.icon]),
    [['general', 'General', 1], ['modules', 'Plugins', 2], ['extra', 'Extra', undefined]]);
  assert.equal(core[1].label, 'Modules', 'core pages are not mutated');
});

test('visiblePages hides pages without fields; fields default to general', () => {
  const schema = [{ key: 'a' }, { key: 'b', page: 'extra' }];
  const pages = Settings.mergePages(core, [{ id: 'extra' }]);
  assert.deepEqual(Settings.visiblePages(pages, schema).map((p) => p.id), ['general', 'extra']);
});

test('resolvePage falls back to the first visible page', () => {
  assert.equal(Settings.resolvePage(core, 'modules'), 'modules');
  assert.equal(Settings.resolvePage(core, 'gone'), 'general');
  assert.equal(Settings.resolvePage([], 'gone'), '');
});

test('cyclePage wraps both ways', () => {
  assert.equal(Settings.cyclePage(core, 'general', 1), 'modules');
  assert.equal(Settings.cyclePage(core, 'modules', 1), 'general');
  assert.equal(Settings.cyclePage(core, 'general', -1), 'modules');
  assert.equal(Settings.cyclePage([], 'general', 1), '');
});

test('sections groups a page by section in first-seen order', () => {
  const schema = [
    { key: 'a', section: 'Hover' },
    { key: 'b', section: 'Layout' },
    { key: 'c', section: 'Hover' },
    { key: 'd', page: 'modules' },
    { key: 'e' },
  ];
  const out = plain(Settings.sections(schema, 'general'));
  assert.deepEqual(out.map((s) => [s.name, s.fields.map((f) => f.key)]),
    [['Hover', ['a', 'c']], ['Layout', ['b']], ['', ['e']]]);
});

test('toList accepts arrays and array-likes, rejects the rest', () => {
  assert.deepEqual(plain(Settings.toList(['a', 1])), ['a', '1']);
  assert.deepEqual(plain(Settings.toList({ length: 1, 0: 'x' })), ['x']);
  assert.deepEqual(plain(Settings.toList('abc')), []);
  assert.deepEqual(plain(Settings.toList(undefined)), []);
});

test('toggleId and moveId return new lists', () => {
  const ids = ['a', 'b', 'c'];
  assert.deepEqual(plain(Settings.toggleId(ids, 'b')), ['a', 'c']);
  assert.deepEqual(plain(Settings.toggleId(ids, 'd')), ['a', 'b', 'c', 'd']);
  assert.deepEqual(plain(Settings.moveId(ids, 'c', -1)), ['a', 'c', 'b']);
  assert.deepEqual(plain(Settings.moveId(ids, 'a', -1)), ['a', 'b', 'c']);
  assert.deepEqual(plain(Settings.moveId(ids, 'x', 1)), ['a', 'b', 'c']);
  assert.deepEqual(ids, ['a', 'b', 'c']);
});

test('allIds lists enabled ids first, then the other available ones', () => {
  assert.deepEqual(plain(Settings.allIds(['media', 'ghost'], ['activities', 'media', 'osd'])),
    ['media', 'ghost', 'activities', 'osd']);
});

test('workspaceChoices offers 1-10, known and picked ones, numbers first', () => {
  assert.deepEqual(plain(Settings.workspaceChoices(['2', 'code', '12'], ['notes', 3])),
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 'code', 'notes']);
  assert.deepEqual(plain(Settings.workspaceChoices(null, null)), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
});

test('toggleWorkspace keeps numbers as numbers and clears to undefined', () => {
  assert.deepEqual(plain(Settings.toggleWorkspace([3, 1], '2')), [1, 2, 3]);
  assert.deepEqual(plain(Settings.toggleWorkspace([1, 2], 2)), [1]);
  assert.deepEqual(plain(Settings.toggleWorkspace(undefined, 'code')), ['code']);
  assert.equal(Settings.toggleWorkspace([1], 1), undefined);
});

test('snapToStep snaps to the step from min, clamps, and drops float noise', () => {
  assert.equal(Settings.snapToStep(0.351, 0, 1, 0.01), 0.35);
  assert.equal(Settings.snapToStep(0.1 + 0.2, 0, 1, 0.01), 0.3);
  assert.equal(Settings.snapToStep(1.4, 0, 1, 0.01), 1);
  assert.equal(Settings.snapToStep(-3, 0, 1, 0.01), 0);
  assert.equal(Settings.snapToStep(124, 0, 1000, 10), 120);
  assert.equal(Settings.snapToStep(7, 5, 100, 10), 5);
  assert.equal(Settings.snapToStep(7, 0, 100, 0), 7);
});

test('storedValue removes the key when an edit picks the default', () => {
  const field = { key: 'position.edge', default: 'top' };
  assert.equal(Settings.storedValue(field, 'top'), undefined);
  assert.equal(Settings.storedValue(field, 'left'), 'left');
  assert.equal(Settings.storedValue({ default: 0.5 }, 0.5), undefined);
  assert.equal(Settings.storedValue({ default: false }, false), undefined);
  assert.equal(Settings.storedValue({}, 'x'), 'x');
  assert.equal(Settings.storedValue({ default: 'top' }, undefined), undefined);
});

test('moduleFields puts a module\'s fields under its id, on its own page', () => {
  const fields = plain(Settings.moduleFields([
    { moduleId: 'resources', title: 'Resources', settings: [
      { key: 'compact', type: 'choice', default: 'always' },
      { key: 'disk', type: 'string', page: 'extra', section: 'Disk' },
      { key: 'color', type: 'color', page: 'appearance' },
      { type: 'note', label: 'Linux only' }
    ] },
    { moduleId: 'media', title: 'Now playing', settings: [] },
    { moduleId: 'bare', settings: [{ key: 'x', type: 'boolean' }] }
  ]));
  assert.deepEqual(fields.map((f) => [f.key, f.page, f.section]), [
    ['resources.compact', 'modules/resources', undefined],
    ['resources.disk', 'extra', 'Disk'],
    ['resources.color', 'appearance', 'Resources'],
    [undefined, 'modules/resources', undefined],
    ['bare.x', 'modules/bare', undefined]
  ]);
  assert.equal(fields[0].default, 'always');
  assert.deepEqual(plain(Settings.moduleFields(undefined)), []);
});

test('modulePages gives each loaded module a page under Modules', () => {
  assert.deepEqual(plain(Settings.modulePages([{ moduleId: 'media', title: 'Now playing' }, { moduleId: 'bare' }, null])),
    [{ id: 'modules/media', label: 'Now playing' }, { id: 'modules/bare', label: 'bare' }]);
});

const withSub = [
  { id: 'general' }, { id: 'modules' }, { id: 'modules/media' }, { id: 'appearance' }
];

test('a module page is a sub-page: off the sidebar, under its parent', () => {
  assert.deepEqual(Settings.navPages(withSub).map((p) => p.id), ['general', 'modules', 'appearance']);
  assert.equal(Settings.parentPage('modules/media'), 'modules');
  assert.equal(Settings.parentPage('general'), 'general');
  assert.equal(Settings.parentPage(undefined), '');
});

test('resolvePage falls back from a gone sub-page to its parent', () => {
  assert.equal(Settings.resolvePage(withSub, 'modules/media'), 'modules/media');
  assert.equal(Settings.resolvePage(withSub, 'modules/timer'), 'modules');
  assert.equal(Settings.resolvePage(withSub, 'gone/x'), 'general');
  assert.equal(Settings.resolvePage([{ id: 'a/b' }], 'x'), 'a/b');
});

test('cyclePage steps through the sidebar, from a sub-page\'s parent', () => {
  assert.equal(Settings.cyclePage(withSub, 'modules', 1), 'appearance');
  assert.equal(Settings.cyclePage(withSub, 'modules/media', 1), 'appearance');
  assert.equal(Settings.cyclePage(withSub, 'modules/media', -1), 'general');
});

test('moduleTitle uses the loaded module\'s title, else its id', () => {
  assert.equal(Settings.moduleTitle('media', { title: 'Now playing' }), 'Now playing');
  assert.equal(Settings.moduleTitle('timer', null), 'Timer');
});

test('moduleStatus says where a module shows, or that it is standalone', () => {
  const one = [{ id: 'main', moduleIds: ['media'] }];
  const two = [{ id: 'main', moduleIds: ['media', 'osd'] }, { id: 'jobs', moduleIds: ['activities', 'media'] }];
  assert.equal(Settings.moduleStatus('media', one), 'On');
  assert.equal(Settings.moduleStatus('timer', one), 'Off');
  assert.equal(Settings.moduleStatus('media', two), 'In main, jobs');
  assert.equal(Settings.moduleStatus('activities', two), 'In jobs');
  assert.equal(Settings.moduleStatus('osd', two, true, true), 'Standalone', 'a notch listing it does not count');
  assert.equal(Settings.moduleStatus('osd', one, true, false), 'Standalone · off');
  assert.equal(Settings.moduleStatus('timer', undefined), 'Off');
});

test('parseModuleInfo keeps a title and well-formed fields, drops the rest', () => {
  assert.deepEqual(plain(Settings.parseModuleInfo('{ "title": "Timer", "settings": [{ "key": "a", "type": "boolean" }, 3, { "key": "b" }] }')),
    { title: 'Timer', settings: [{ key: 'a', type: 'boolean' }] });
  assert.deepEqual(plain(Settings.parseModuleInfo('{ "settings": {} }')), { title: '', settings: [] });
  assert.equal(Settings.parseModuleInfo('{ "standalone": true }').standalone, true);
  assert.equal(Settings.parseModuleInfo('{ "standalone": "yes" }').standalone, undefined);
  const bad = plain(Settings.parseModuleInfo('{ nope'));
  assert.deepEqual([bad.title, bad.settings], ['', []]);
  assert.ok(bad.error);
  assert.equal(plain(Settings.parseModuleInfo('[]')).error, 'not an object');
});

test('settingDefault finds a field\'s default by key', () => {
  const fields = [{ key: 'focus', default: 25 }, { key: 'notify', default: false }];
  assert.equal(Settings.settingDefault(fields, 'focus'), 25);
  assert.equal(Settings.settingDefault(fields, 'notify'), false);
  assert.equal(Settings.settingDefault(fields, 'gone'), undefined);
  assert.equal(Settings.settingDefault(undefined, 'focus'), undefined);
});

test('notch pages are sub-pages of Notches, by index', () => {
  assert.equal(Settings.notchPageId(2), 'notch/2');
  assert.equal(Settings.notchIndexOfPage('notch/2'), 2);
  assert.equal(Settings.notchIndexOfPage('notch'), -1);
  assert.equal(Settings.notchIndexOfPage('modules/media'), -1);
  assert.equal(Settings.notchIndexOfPage('notch/x'), -1);
  assert.equal(Settings.parentPage(Settings.notchPageId(0)), 'notch');
});

test('notchSummary says where a notch is and what it shows', () => {
  const titles = { media: 'Now playing' };
  assert.equal(Settings.notchSummary({ edge: 'bottom', moduleIds: ['media', 'timer'] }, titles),
    'Bottom edge · Now playing, Timer');
  assert.equal(Settings.notchSummary({ edge: 'top', moduleIds: [] }, titles), 'Top edge · no modules');
  assert.equal(Settings.notchSummary(null, titles), '');
});

// Every module's JSON file parses, and each field the window can save has
// a key, a type and a default within its range.
test('every module JSON file is well-formed', () => {
  const files = ['core/modules', 'hosts/omarchy/modules'].flatMap((dir) =>
    fs.readdirSync(new URL(`../${dir}`, import.meta.url)).filter((f) => f.endsWith('.json')).map((f) => `${dir}/${f}`));
  assert.ok(files.length >= 5, 'files: ' + files);
  for (const file of files) {
    const text = fs.readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
    const info = plain(Settings.parseModuleInfo(text));
    assert.equal(info.error, undefined, file);
    assert.ok(info.title, `${file}: no title`);
    const keys = Object.keys(JSON.parse(text));
    assert.deepEqual(keys.filter((k) => !['title', 'settings', 'standalone'].includes(k)), [], `${file}: unknown keys`);
    if (info.standalone)
      for (const f of info.settings) assert.ok(!['enabled', 'position'].includes(String(f.key).split('.')[0]), `${file}: ${f.key} is the standalone switch's or position's`);
    assert.equal(info.settings.length, JSON.parse(text).settings?.length ?? 0, `${file}: a field was dropped`);
    for (const f of info.settings) {
      if (f.type === 'note') continue;
      assert.ok(f.key && f.default !== undefined, `${file}: ${JSON.stringify(f)}`);
      if (f.min !== undefined) assert.ok(f.default >= f.min && f.default <= f.max, `${file}: ${f.key} out of range`);
      if (f.options) assert.ok(f.options.some((o) => o.value === f.default), `${file}: ${f.key} default not an option`);
    }
  }
  const qml = ['core/modules', 'hosts/omarchy/modules'].flatMap((dir) =>
    fs.readdirSync(new URL(`../${dir}`, import.meta.url)).filter((f) => f.endsWith('.qml')).map((f) => `${dir}/${f.replace(/\.qml$/, '.json')}`));
  for (const json of qml) assert.ok(files.includes(json), `${json} is missing`);
});

test('moduleInfoPath finds the JSON file next to a module, file or qs: url', () => {
  assert.equal(Settings.moduleInfoPath('file:///p/core/modules/media.qml', '/c'), '/p/core/modules/media.json');
  assert.equal(Settings.moduleInfoPath('file:///p/my%20mods/a.qml', ''), '/p/my mods/a.json');
  assert.equal(Settings.moduleInfoPath('qs:@/qs/core/modules/timer.qml', '/home/u/.config/qs/'), '/home/u/.config/qs/core/modules/timer.json');
  assert.equal(Settings.moduleInfoPath('qs:@/qs/core/modules/timer.qml', ''), '');
  // The Omarchy shell names a plugin's core modules this way; their files
  // were not found, so their titles and settings were missing there.
  assert.equal(Settings.moduleInfoPath('qs:///home/u/plugins/notchd/core/modules/media.qml', '/usr/share/omarchy/shell'),
    '/home/u/plugins/notchd/core/modules/media.json');
  assert.equal(Settings.moduleInfoPath('https://x/y.qml', '/c'), '');
  assert.equal(Settings.moduleInfoPath('', '/c'), '');
});

test('a standalone module\'s page starts with its switch and position', () => {
  const fields = plain(Settings.moduleFields([
    { moduleId: 'osd', title: 'OSD', standalone: true, settings: [{ key: 'size', type: 'integer', default: 1 }] }
  ], 'edge.qml'));
  assert.deepEqual(fields.map((f) => [f.key, f.page, f.section, f.default]), [
    ['osd.enabled', 'modules/osd', undefined, true],
    ['osd.position.edge', 'modules/osd', 'Position', 'top'],
    ['osd.position.offset', 'modules/osd', 'Position', 0.5],
    ['osd.size', 'modules/osd', undefined, 1]
  ]);
  assert.equal(fields[1].options[0].preview, 'edge.qml');
});
