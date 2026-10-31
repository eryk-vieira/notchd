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

test('resolve falls back to defaults for missing or bad keys', () => {
  const r = plain(Config.resolve({}, ['media']));
  assert.deepEqual(r, { moduleIds: ['media'], hoverOpenDelay: 120, hoverCloseDelay: 300, compactStyle: 'bar', reserveSpace: false, draggable: true, workspaces: null });
});

test('resolve reads and clamps the core keys', () => {
  const r = plain(Config.resolve(
    { modules: ['osd', 3], hoverOpenDelay: -50, hoverCloseDelay: 'x', compactStyle: 'notch', reserveSpace: true, draggable: false, workspaces: [1, 'code'] }, []));
  assert.deepEqual(r, { moduleIds: ['osd', '3'], hoverOpenDelay: 0, hoverCloseDelay: 0, compactStyle: 'notch', reserveSpace: true, draggable: false, workspaces: [1, 'code'] });
  assert.equal(Config.resolve({ compactStyle: 'weird' }, []).compactStyle, 'bar');
  assert.equal(Config.resolve({ reserveSpace: 'yes' }, []).reserveSpace, false);
  assert.equal(Config.resolve({ draggable: 'no' }, []).draggable, true);
  assert.equal(Config.resolve({ workspaces: [] }, []).workspaces, null);
  assert.equal(Config.resolve({ workspaces: 3 }, []).workspaces, null);
  assert.deepEqual(plain(Config.resolve({ workspaces: [2, '', null, 'x'] }, []).workspaces), [2, 'x']);
});
