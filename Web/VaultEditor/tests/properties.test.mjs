import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!doctype html><body/>', { url: 'https://vault.invalid' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement });
const { propertiesElement, propertyType, wikiLink, writeProperties, setProperty, deleteProperty, renameProperty, splitFrontmatter } = await import('../test-bundle.mjs');

const SOURCE = [
  '---',
  '# 남겨야 하는 주석',
  'started: 2026-09-07',
  'progress: 50% - 핵심개념 파악',
  'count: 3',
  'done: false',
  'source:',
  '  - "[[2. Study/Theory/AST (추상 구문 트리)|AST (추상 구문 트리)]]"',
  'tags:',
  '  - Study',
  '  - Concept',
  '---',
  '# 본문 제목',
  '',
  '- 목록 항목',
].join('\n');

const element = (source, options = {}) => propertiesElement(source, options);
const rowKeys = root => [...root.querySelectorAll('.prop-row')].map(row => row.dataset.key);

test('타입은 YAML 값의 모양에서 정해진다', () => {
  assert.equal(propertyType('보통'), 'text');
  assert.equal(propertyType('2026-09-07'), 'date');
  assert.equal(propertyType('50% - 핵심개념 파악'), 'text');
  assert.equal(propertyType(3), 'number');
  assert.equal(propertyType(false), 'checkbox');
  assert.equal(propertyType(['Study']), 'list');
});

test('위키링크 항목은 별칭만 표시하고 대상을 함께 돌려준다', () => {
  assert.deepEqual(wikiLink('[[a/b/c|별칭]]'), { target: 'a/b/c', label: '별칭' });
  assert.deepEqual(wikiLink('[[a/b/c]]'), { target: 'a/b/c', label: 'c' });
  assert.equal(wikiLink('Study'), null);
});

/// 사용자의 실제 vault 파일을 고쳐 쓰므로 본문 훼손은 가장 큰 사고다.
test('되쓰기는 본문을 한 글자도 바꾸지 않는다', () => {
  const next = writeProperties(SOURCE, setProperty('count', 7));
  assert.equal(splitFrontmatter(next).body, splitFrontmatter(SOURCE).body);
  assert.equal(splitFrontmatter(next).properties.count, 7);
});

test('되쓰기는 주석과 키 순서를 보존한다', () => {
  const next = writeProperties(SOURCE, setProperty('done', true));
  assert.match(next, /# 남겨야 하는 주석/);
  assert.deepEqual(Object.keys(splitFrontmatter(next).properties), ['started', 'progress', 'count', 'done', 'source', 'tags']);
});

test('이름을 바꿔도 속성 자리는 그대로다', () => {
  const next = writeProperties(SOURCE, renameProperty('count', 'total'));
  assert.deepEqual(Object.keys(splitFrontmatter(next).properties), ['started', 'progress', 'total', 'done', 'source', 'tags']);
  assert.equal(splitFrontmatter(next).properties.total, 3);
});

test('위키링크 항목은 YAML 원문 형태를 유지한다', () => {
  const next = writeProperties(SOURCE, setProperty('tags', ['Study', 'Bundler']));
  assert.match(next, /- "\[\[2\. Study\/Theory\/AST \(추상 구문 트리\)\|AST \(추상 구문 트리\)\]\]"/);
  assert.deepEqual(splitFrontmatter(next).properties.tags, ['Study', 'Bundler']);
});

test('속성을 전부 지우면 frontmatter 블록째 사라진다', () => {
  let next = SOURCE;
  for (const key of Object.keys(splitFrontmatter(SOURCE).properties)) next = writeProperties(next, deleteProperty(key));
  assert.equal(next, splitFrontmatter(SOURCE).body);
  assert.equal(splitFrontmatter(next).raw, '');
});

test('속성이 없던 문서에도 첫 속성을 붙일 수 있다', () => {
  const next = writeProperties('# 제목\n\n본문', setProperty('tags', ['Study']));
  assert.deepEqual(splitFrontmatter(next).properties.tags, ['Study']);
  assert.equal(splitFrontmatter(next).body, '# 제목\n\n본문');
});

test('CRLF 문서는 CRLF 를 유지한다', () => {
  const source = '---\r\ntags:\r\n  - Study\r\n---\r\n# 제목';
  const next = writeProperties(source, setProperty('count', 1));
  assert.ok(!/[^\r]\n/.test(next), '섞인 줄바꿈이 생기면 안 된다');
  assert.equal(splitFrontmatter(next).body, '# 제목');
});

test('행은 속성마다 하나씩, 타입에 맞는 컨트롤로 그려진다', () => {
  const root = element(SOURCE);
  assert.deepEqual(rowKeys(root), ['started', 'progress', 'count', 'done', 'source', 'tags']);
  assert.equal(root.querySelector('[data-key="started"] input[type=date]').value, '2026-09-07');
  assert.equal(root.querySelector('[data-key="count"] input[type=number]').value, '3');
  assert.equal(root.querySelector('[data-key="done"] input[type=checkbox]').checked, false);
  assert.equal(root.querySelectorAll('[data-key="tags"] .prop-chip').length, 2);
  assert.equal(root.querySelector('[data-key="source"] .prop-chip a').textContent, 'AST (추상 구문 트리)');
});

test('칩의 ✕ 는 그 항목만 지운다', () => {
  let written = null;
  const root = element(SOURCE, { onChange: next => { written = next; } });
  root.querySelectorAll('[data-key="tags"] .prop-chip .prop-x')[0].click();
  assert.deepEqual(splitFrontmatter(written).properties.tags, ['Concept']);
  assert.deepEqual(splitFrontmatter(written).properties.source, splitFrontmatter(SOURCE).properties.source);
});

test('값을 고치면 새 전문이 전달된다', () => {
  let written = null;
  const root = element(SOURCE, { onChange: next => { written = next; } });
  const input = root.querySelector('[data-key="progress"] .prop-value input[type=text]');
  input.value = '80% - 정리';
  input.dispatchEvent(new dom.window.Event('change'));
  assert.equal(splitFrontmatter(written).properties.progress, '80% - 정리');
});

test('키 칸을 고치면 값을 지키며 이름만 바뀐다', () => {
  let written = null;
  const root = element(SOURCE, { onChange: next => { written = next; } });
  const key = root.querySelector('[data-key="progress"] .prop-key');
  key.value = '진행도';
  key.dispatchEvent(new dom.window.Event('change'));
  const properties = splitFrontmatter(written).properties;
  assert.equal(properties['진행도'], '50% - 핵심개념 파악');
  assert.ok(!('progress' in properties));
});

test('속성 추가 버튼은 빈 속성 한 줄을 만든다', () => {
  let written = null;
  const root = element(SOURCE, { onChange: next => { written = next; } });
  root.querySelector('.prop-new').click();
  assert.ok('새 속성' in splitFrontmatter(written).properties);
  assert.deepEqual(rowKeys(root).at(-1), '새 속성');
});

test('참조 문서는 편집할 수 없다', () => {
  let written = null;
  const root = element(SOURCE, { readOnly: true, onChange: next => { written = next; } });
  assert.equal(root.dataset.readonly, 'true');
  assert.equal(root.querySelector('.prop-new'), null);
  root.querySelector('[data-key="tags"] .prop-x').click();
  assert.equal(written, null);
});

/// 깨진 YAML 을 편집 UI 로 덮으면 고칠 방법이 사라진다.
test('YAML 이 깨지면 편집 UI 대신 오류를 보여준다', () => {
  const root = element('---\ntags: [unclosed\n---\n# 제목');
  assert.equal(root.querySelectorAll('.prop-row').length, 0);
  assert.match(root.querySelector('.error').textContent, /속성 YAML 오류/);
});
