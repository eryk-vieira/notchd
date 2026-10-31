import { test } from 'node:test';
import assert from 'node:assert/strict';
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
