import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!doctype html><body/>', { url: 'https://vault.invalid' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement });
const { renderMarkdown, splitFrontmatter } = await import('../test-bundle.mjs');

test('nested emphasis and wiki aliases render inside table cells', () => {
  const html = renderMarkdown('| Name | Value |\n| :--- | ---: |\n| **[[Note\\|별칭]]** | *value*<br>next |');
  assert.match(html, /<table/);
  assert.match(html, /<strong><a[^>]+>별칭<\/a><\/strong>/);
  assert.match(html, /<em>value<\/em><br>/);
});
test('frontmatter is displayed separately without changing the source', () => {
  const source = '---\r\n# keep comment\r\ntags: [Study]\r\n---\r\n# **Title**';
  const result = splitFrontmatter(source);
  assert.deepEqual(result.properties.tags, ['Study']);
  assert.equal(result.body, '# **Title**');
  assert.equal(result.raw + result.body, source);
});
/// vault 의 checkboxes 스니펫이 `[data-task="!"]` 로 표식을 겨냥한다.
test('작업 항목은 임의 표식을 data-task 로 보존한다', () => {
  const html = renderMarkdown('- [ ] 할 일\n- [x] 완료\n- [/] 진행중\n- [!] 중요');
  assert.match(html, /<ul class="contains-task-list">/);
  assert.match(html, /<li class="task-list-item" data-task="\/"><input[^>]*data-task="\/"[^>]*checked/);
  assert.match(html, /<li class="task-list-item" data-task="!"><input[^>]*data-task="!"[^>]*checked/);
  assert.doesNotMatch(html.split('\n')[1], /checked/, '공백 표식은 완료가 아니다');
  assert.doesNotMatch(html, /\[[ x/!]\]/, '표식 원문이 본문에 남으면 안 된다');
});

/// callout 스니펫이 `> .callout-title`, `> .callout-content`, `.callout-title-inner` 를 겨냥한다.
test('콜아웃은 Obsidian 과 같은 뼈대를 낸다', () => {
  const aside = renderMarkdown('> [!folder] 구조\n> - src');
  assert.match(aside, /<aside class="callout" data-callout="folder"><div class="callout-title">/);
  assert.match(aside, /<div class="callout-title-inner">구조<\/div>/);
  assert.match(aside, /<div class="callout-content">/);
  assert.match(aside, /<\/div><\/aside>/);
  const details = renderMarkdown('> [!note]- 접힘\n> 내용');
  assert.match(details, /<summary class="callout-title">/);
  assert.match(details, /<\/div><\/details>/);
});

test('special fences preserve their language and ordinary code stays code', () => {
  assert.match(renderMarkdown('```mermaid\ngraph TD\n A-->B\n```'), /data-language="mermaid"/);
  assert.match(renderMarkdown('```dataviewjs\ndv.table([],[])\n```'), /data-language="dataviewjs"/);
  assert.match(renderMarkdown('```python\nprint("**literal**")\n```'), /\*\*literal\*\*/);
});
test('callouts, highlights, comments and unsafe HTML', () => {
  const html = renderMarkdown('> [!warning]- 주의\n> ==important==\n\n%%hidden%%\n<script>alert(1)</script>');
  assert.match(html, /<details/);
  assert.match(html, /<mark>important<\/mark>/);
  assert.doesNotMatch(html, /hidden|<script/);
});
