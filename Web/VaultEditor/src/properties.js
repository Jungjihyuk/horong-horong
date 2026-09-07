import { parseDocument } from 'yaml';
import { splitFrontmatter } from './markdown.js';

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const WIKI = /^!?\[\[([^\]]+)\]\]$/;

/// YAML 값의 모양에서 편집 컨트롤을 정한다. Obsidian 의 속성 타입과 맞췄다.
export function propertyType(value) {
  if (Array.isArray(value)) return 'list';
  if (typeof value === 'boolean') return 'checkbox';
  if (typeof value === 'number') return 'number';
  if (typeof value === 'string' && DATE.test(value)) return 'date';
  return 'text';
}

/// `[[대상|별칭]]` 이면 표시 이름과 대상을 돌려준다. 아니면 `null`.
export function wikiLink(value) {
  const match = typeof value === 'string' ? value.trim().match(WIKI) : null;
  if (!match) return null;
  const [target, alias] = match[1].split('|');
  return { target, label: alias ?? target.split('#')[0].split('/').at(-1) };
}

const pairOf = (doc, key) => doc.contents?.items?.find(pair => (pair.key?.value ?? pair.key) === key);

export const setProperty = (key, value) => doc => doc.set(key, value);
export const deleteProperty = key => doc => doc.delete(key);
/// `delete` 후 `set` 으로 바꾸면 속성이 맨 뒤로 밀린다. 키 노드만 갈아끼워 자리를 지킨다.
export const renameProperty = (key, next) => doc => {
  const pair = pairOf(doc, key);
  if (!pair || !next || next === key || pairOf(doc, next)) return;
  if (pair.key && typeof pair.key === 'object' && 'value' in pair.key) pair.key.value = next;
  else pair.key = next;
};

/// frontmatter 구간만 갈아끼운다. **본문은 한 글자도 건드리지 않는다** — 사용자의 실제
/// vault 파일을 고쳐 쓰기 때문이다. `parseDocument` 를 거치므로 주석·키 순서·인용이 남는다.
export function writeProperties(source, mutate) {
  const { raw, yaml, body } = splitFrontmatter(source);
  const doc = parseDocument(yaml || '');
  mutate(doc);
  const eol = (raw || source).includes('\r\n') ? '\r\n' : '\n';
  const bom = raw.startsWith('\uFEFF') ? '\uFEFF' : '';
  const contents = doc.contents;
  // 속성을 전부 지우면 블록째 걷어낸다. 빈 `---\n---` 는 빈 속성으로 읽혀 남는다.
  if (contents == null || (Array.isArray(contents.items) && !contents.items.length)) return bom + body;
  const text = String(doc).replace(/\n+$/, '').split('\n').join(eol);
  // 원문이 닫는 `---` 뒤에 줄바꿈 없이 끝났다면 그대로 둔다.
  const tail = raw && !/\r?\n$/.test(raw) ? '' : eol;
  return `${bom}---${eol}${text}${eol}---${tail}${body}`;
}

// 되쓰기를 하면 위젯이 통째로 다시 그려진다. 방금 쓰던 칸으로 커서를 되돌리기 위한 자리.
let pendingFocus = null;
const defer = run => (globalThis.requestAnimationFrame ?? (fn => setTimeout(fn, 0)))(run);
const focusTarget = (key, className) => `[data-key="${String(key).replace(/["\\]/g, '\\$&')}"] .${className}`;

/// 속성 표를 편집 가능한 엘리먼트로 만든다. 문자열이 아니라 DOM 을 돌려주는 이유는
/// 입력 컨트롤과 이벤트가 필요해서다.
export function propertiesElement(source, options = {}) {
  const { readOnly = false, onChange, onNavigate } = options;
  let current = source;
  const root = document.createElement('details');
  root.className = 'properties';
  root.open = true;
  if (readOnly) root.dataset.readonly = 'true';
  const summary = document.createElement('summary');
  summary.textContent = '속성';
  const rows = document.createElement('div');
  root.append(summary, rows);

  function commit(mutate, focus = null) {
    if (readOnly) return;
    const next = writeProperties(current, mutate);
    if (next === current) return;
    current = next;
    pendingFocus = focus;
    onChange?.(next);
    render();
  }

  function chip(key, items, index) {
    const el = document.createElement('span');
    el.className = 'prop-chip';
    const link = wikiLink(items[index]);
    if (link) {
      const anchor = document.createElement('a');
      anchor.href = '#';
      anchor.textContent = link.label;
      anchor.title = link.target;
      anchor.addEventListener('click', event => { event.preventDefault(); onNavigate?.(link.target); });
      el.append(anchor);
    } else {
      const label = document.createElement('span');
      label.textContent = String(items[index] ?? '');
      el.append(label);
    }
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'prop-x';
    remove.textContent = '✕';
    remove.title = '항목 제거';
    remove.addEventListener('click', () => commit(setProperty(key, items.filter((_, i) => i !== index))));
    el.append(remove);
    return el;
  }

  function controls(key, value) {
    const type = propertyType(value);
    if (type === 'list') {
      const items = value;
      const nodes = items.map((_, index) => chip(key, items, index));
      const add = document.createElement('input');
      add.type = 'text';
      add.className = 'prop-add';
      add.placeholder = '추가';
      add.setAttribute('aria-label', `${key} 항목 추가`);
      // 태그를 여러 개 이어 넣는 흐름이라 Enter 뒤에도 같은 칸에 커서를 돌려놓는다.
      add.addEventListener('keydown', event => {
        if (event.key !== 'Enter') return;
        event.preventDefault();
        const text = add.value.trim();
        if (text) commit(setProperty(key, [...items, text]), focusTarget(key, 'prop-add'));
      });
      nodes.push(add);
      return nodes;
    }
    if (type === 'checkbox') {
      const box = document.createElement('input');
      box.type = 'checkbox';
      box.checked = value === true;
      box.setAttribute('aria-label', key);
      box.addEventListener('change', () => commit(setProperty(key, box.checked)));
      return [box];
    }
    const input = document.createElement('input');
    input.type = type === 'number' ? 'number' : type === 'date' ? 'date' : 'text';
    input.value = value == null ? '' : String(value);
    input.setAttribute('aria-label', key);
    // 키 입력마다 쓰면 문서가 바뀌어 위젯이 재생성되고 조합 중인 한글이 끊긴다.
    input.addEventListener('change', () => {
      const text = input.value;
      commit(setProperty(key, type === 'number' ? (text === '' ? null : Number(text)) : text));
    });
    return [input];
  }

  function row(key, value) {
    const el = document.createElement('div');
    el.className = 'prop-row';
    el.dataset.key = key;
    const name = document.createElement('input');
    name.type = 'text';
    name.className = 'prop-key';
    name.value = key;
    name.setAttribute('aria-label', `${key} 속성 이름`);
    name.addEventListener('change', () => {
      const next = name.value.trim();
      if (!next || next === key) { name.value = key; return; }
      commit(renameProperty(key, next), focusTarget(next, 'prop-key'));
    });
    const value_ = document.createElement('div');
    value_.className = 'prop-value';
    value_.append(...controls(key, value));
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'prop-del';
    remove.textContent = '✕';
    remove.title = `${key} 속성 삭제`;
    remove.addEventListener('click', () => commit(deleteProperty(key)));
    el.append(name, value_, remove);
    return el;
  }

  function addButton(properties) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'prop-new';
    button.textContent = '+ 속성 추가';
    button.addEventListener('click', () => {
      let key = '새 속성';
      for (let n = 2; key in properties; n++) key = `새 속성 ${n}`;
      commit(setProperty(key, ''), focusTarget(key, 'prop-key'));
    });
    return button;
  }

  function render() {
    const { properties, error } = splitFrontmatter(current);
    rows.textContent = '';
    if (error) {
      // 깨진 YAML 을 편집 UI 로 덮으면 고칠 방법이 사라진다. editor.js 가 원문을 노출한다.
      const banner = document.createElement('aside');
      banner.className = 'error';
      banner.textContent = `속성 YAML 오류: ${error}`;
      rows.append(banner);
      return;
    }
    for (const [key, value] of Object.entries(properties)) rows.append(row(key, value));
    if (!readOnly) rows.append(addButton(properties));
    if (!pendingFocus) return;
    const selector = pendingFocus;
    pendingFocus = null;
    // 이 시점의 root 는 아직 문서에 붙기 전일 수 있다 (CodeMirror 위젯 재생성).
    defer(() => root.querySelector(selector)?.focus());
  }

  render();
  return root;
}
