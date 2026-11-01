import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, plain } from './load.mjs';

const Markdown = load('core/Markdown.js');
const S = { accent: '#ffaa00', muted: '#888888', line: '#333333', code: '#222222', body: 12, heading: 16, gap: 9 };
const html = (md) => Markdown.toHtml(md, S);

// Bug: Qt's own Markdown import painted links its fixed blue, unreadable on
// a dark notch, and nothing could restyle them.
test('links take the accent color: [label](url), <url> and bare URLs', () => {
  const out = html('See [CNN](https://cnn.com/a?b=1&c=2), <https://e.com> and https://x.org/y.');
  assert.equal((out.match(/<a /g) || []).length, 3);
  assert.ok(out.includes('<a href="https://cnn.com/a?b=1&amp;c=2" style="color:#ffaa00'));
  assert.ok(out.includes('>CNN</a>'));
  assert.ok(out.includes('href="https://x.org/y"'), 'the period after a bare URL is not part of it');
  assert.ok(!/#0000ff|blue/i.test(out));
});

// Bug: blocks sat flush against each other and headings were huge.
test('blocks get space between them, the last none; headings stay moderate', () => {
  const out = html('# Title\n\nFirst paragraph\ncontinues.\n\nSecond.');
  assert.ok(out.includes('font-size:16px; font-weight:600'));
  assert.ok(out.includes('margin-bottom:9px; line-height:135%">First paragraph continues.</p>'));
  assert.ok(out.endsWith('margin-bottom:0px; line-height:135%">Second.</p>'));
  assert.ok(!/<h1/.test(out));
});

test('blocks: kinds and their text', () => {
  const b = plain(Markdown.blocks('## Sub\n\npara\n\n- a\n- b\n\n```js\nx < 1\n```\n\n> quoted\n\n---\n\n| A | B |\n|---|---|\n| 1 | 2 |'));
  assert.deepEqual(b.map((x) => x.kind), ['heading', 'paragraph', 'list', 'code', 'quote', 'rule', 'table']);
  assert.equal(b[0].level, 2);
  assert.equal(b[3].text, 'x < 1');
  assert.deepEqual(b[6].rows, [['A', 'B'], ['1', '2']]);
});

test('lists nest by indent and keep going across a blank line before an item', () => {
  const [list] = plain(Markdown.blocks('- **Binance:**\n    - saques suspensos\n    - fundo SAFU\n- Mercado: caiu\n\n- depois'));
  assert.equal(list.kind, 'list');
  assert.deepEqual(list.items.items.map((i) => i.text), ['**Binance:**', 'Mercado: caiu', 'depois']);
  assert.deepEqual(list.items.items[0].children.items.map((i) => i.text), ['saques suspensos', 'fundo SAFU']);
  const out = html('1. one\n2. two');
  assert.ok(out.startsWith('<ol ') && out.includes('<li '));
});

test('a list item\'s wrapped text joins it; a paragraph after a blank line ends the list', () => {
  const b = plain(Markdown.blocks('- first\n  still first\n\nAfter.'));
  assert.deepEqual(b.map((x) => x.kind), ['list', 'paragraph']);
  assert.equal(b[0].items.items[0].text, 'first still first');
});

test('inline: bold, italic, struck and code, with nothing inside code read', () => {
  const out = html('**bold** and *it* and _it2_ and ~~gone~~ and `a **b** <c>` and snake_case_name');
  assert.ok(out.includes('<b>bold</b>') && out.includes('<i>it</i>') && out.includes('<i>it2</i>') && out.includes('<s>gone</s>'));
  assert.ok(out.includes('&nbsp;a **b** &lt;c&gt;&nbsp;</span>'));
  assert.ok(out.includes('snake_case_name'));
});

test('HTML in the text is shown, not run', () => {
  const out = html('<script>alert(1)</script> & <b>x</b>');
  assert.ok(out.includes('&lt;script&gt;') && out.includes('&amp;') && !out.includes('<script>'));
});

test('an unclosed code block (still streaming) runs to the end', () => {
  const b = plain(Markdown.blocks('Here:\n\n```\nline 1\nline 2'));
  assert.deepEqual(b.map((x) => x.kind), ['paragraph', 'code']);
  assert.equal(b[1].text, 'line 1\nline 2');
});

test('empty text is no HTML', () => {
  assert.equal(html(''), '');
  assert.equal(html('\n\n'), '');
});

// Qt reads -qt-list-indent as a level: a nested list at 1 sat flush with
// its parent.
test('a nested list is one level further in', () => {
  const out = Markdown.toHtml('- a\n    - b\n        - c', S);
  assert.ok(out.includes('-qt-list-indent:1') && out.includes('-qt-list-indent:2') && out.includes('-qt-list-indent:3'));
});

// Qt ignores a table's margins, and a line right after a table lands in
// its background: code blocks sat flush against what follows, then grew.
test('after a block drawn as a table, the next one keeps its distance', () => {
  const out = Markdown.toHtml('```\nx\n```\n\nafter', S);
  assert.ok(out.includes('</table><p style="margin-top:9px;'), out);
  const two = Markdown.toHtml('```\nx\n```\n\n> q', S);
  assert.ok(/<\/table>(<p style="margin:0px; font-size:\d+px; line-height:100%">&nbsp;<\/p>){2}<table/.test(two), two);
  assert.ok(Markdown.toHtml('text\n\n```\nx\n```', S).endsWith('</table>'));
});
