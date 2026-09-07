import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import mark from 'markdown-it-mark';
import createDOMPurify from 'dompurify';
import { parseDocument } from 'yaml';
import katex from 'katex';
import hljs from 'highlight.js/lib/common';

export const escapeHTML = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function splitFrontmatter(source) {
  const match = source.match(/^\uFEFF?---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
  if (!match) return { properties: {}, raw: '', yaml: '', body: source };
  const doc = parseDocument(match[1]);
  // `yaml` 은 구분선을 뺀 원문이다. 되쓸 때 본문을 건드리지 않고 이 구간만 갈아끼운다.
  return { properties: doc.errors.length ? {} : doc.toJS() ?? {}, raw: match[0], yaml: match[1], body: source.slice(match[0].length), error: doc.errors[0]?.message };
}
export const markdown = new MarkdownIt({ html: true, breaks: true, linkify: true, highlight: (code, language) => {
  return language && hljs.getLanguage(language) ? hljs.highlight(code, { language }).value : '';
}}).use(footnote).use(mark);

/// Obsidian 은 `[ ]`·`[x]` 뿐 아니라 `[/]`, `[!]`, `[?]` 같은 임의 표식을 쓰고,
/// vault 의 checkboxes 스니펫이 `[data-task="!"]` 로 그 표식을 겨냥한다.
/// markdown-it-task-lists 는 표식을 버리고 두 종류만 처리해서 직접 만든다.
markdown.core.ruler.after('inline', 'obsidian-tasks', state => {
  const lines = state.src.split('\n');
  for (let i = 0; i < state.tokens.length; i++) {
    const item = state.tokens[i];
    if (item.type !== 'list_item_open' || !item.map) continue;
    const task = lines[item.map[0]]?.match(/^\s*(?:[-*+]|\d+[.)])\s+\[(.)\]\s/)?.[1];
    if (task == null) continue;
    const inline = state.tokens[i + 2];
    if (inline?.type !== 'inline') continue;
    item.attrJoin('class', 'task-list-item');
    item.attrSet('data-task', task);
    for (let j = i - 1; j >= 0; j--) {
      const list = state.tokens[j];
      if (list.type !== 'bullet_list_open' && list.type !== 'ordered_list_open') continue;
      if (list.level >= item.level) continue;
      if (!/\bcontains-task-list\b/.test(list.attrGet('class') ?? '')) list.attrJoin('class', 'contains-task-list');
      break;
    }
    const box = new state.Token('html_inline', '', 0);
    // 공백이 아닌 표식은 모두 «완료» 상태로 그린다 — 스니펫이 `input:checked` 로 겨냥한다.
    box.content = `<input class="task-list-item-checkbox" type="checkbox" data-task="${escapeHTML(task)}"${task === ' ' ? '' : ' checked'} disabled>`;
    const first = inline.children[0];
    if (first?.type === 'text') first.content = first.content.replace(/^\[.\]\s*/, '');
    inline.content = inline.content.replace(/^\[.\]\s*/, '');
    inline.children.unshift(box);
  }
});

// 코드와 이스케이프 내부의 기호를 바꾸지 않도록 인라인 구문 단계에서 처리한다.
markdown.inline.ruler.before('link', 'wiki', (state, silent) => {
  const match = state.src.slice(state.pos).match(/^(!?)\[\[([^\]\n]+)\]\]/);
  if (!match) return false;
  if (!silent) {
    const [target, label] = match[2].split('|');
    const token = state.push(match[1] ? 'vault_embed' : 'vault_link', '', 0);
    token.meta = { target, label: label ?? target.split('#')[0] };
  }
  state.pos += match[0].length;
  return true;
});
markdown.renderer.rules.vault_link = (tokens, i) => {
  const { target, label } = tokens[i].meta;
  return `<a class="internal-link" data-link="${escapeHTML(target)}" href="#">${escapeHTML(label)}</a>`;
};
markdown.renderer.rules.vault_embed = (tokens, i) => {
  const { target, label } = tokens[i].meta;
  return `<span class="vault-embed" data-embed="${escapeHTML(target)}" data-size="${escapeHTML(label)}"></span>`;
};
markdown.inline.ruler.before('emphasis', 'comment', (state) => {
  if (!state.src.startsWith('%%', state.pos)) return false;
  const end = state.src.indexOf('%%', state.pos + 2);
  if (end < 0) return false;
  state.pos = end + 2; return true;
});
markdown.inline.ruler.before('escape', 'math', (state, silent) => {
  if (state.src[state.pos] !== '$') return false;
  const delimiter = state.src.startsWith('$$', state.pos) ? '$$' : '$';
  const end = state.src.indexOf(delimiter, state.pos + delimiter.length);
  if (end < 0 || end === state.pos + delimiter.length) return false;
  if (!silent) {
    const token = state.push('math', '', 0);
    token.content = state.src.slice(state.pos + delimiter.length, end);
    token.meta = { displayMode: delimiter.length === 2 };
  }
  state.pos = end + delimiter.length; return true;
});
markdown.renderer.rules.math = (tokens, i) => katex.renderToString(tokens[i].content, { ...tokens[i].meta, throwOnError: false, trust: false });
const fence = markdown.renderer.rules.fence;
const special = new Set(['mermaid', 'dataview', 'dataviewjs', 'tasks', 'chartsview', 'tracker', 'query', 'table-of-contents']);
markdown.renderer.rules.fence = (tokens, i, options, env, renderer) => {
  const language = tokens[i].info.trim().split(/\s/)[0];
  if (!special.has(language)) return fence(tokens, i, options, env, renderer);
  return `<div class="special-block" data-language="${language}"><pre>${escapeHTML(tokens[i].content)}</pre></div>`;
};
markdown.core.ruler.after('inline', 'anchors-callouts', state => {
  for (let i = 0; i < state.tokens.length; i++) {
    const token = state.tokens[i];
    if (token.type === 'heading_open') token.attrSet('id', state.tokens[i + 1]?.content ?? '');
    if (token.type !== 'blockquote_open') continue;
    const inline = state.tokens[i + 2];
    const match = inline?.content?.match(/^\[!([\w-]+)\]([+-]?)[ \t]*([^\n]*)/);
    if (!match) continue;
    let depth = 1, end = i + 1;
    for (; end < state.tokens.length; end++) {
      if (state.tokens[end].type === 'blockquote_open') depth++;
      if (state.tokens[end].type === 'blockquote_close' && --depth === 0) break;
      if (state.tokens[end].type !== 'blockquote_close') depth += 0;
    }
    const title = match[3] || match[1];
    token.type = 'html_block';
    // 콜아웃 스니펫들이 `> .callout-title`, `> .callout-content`, `.callout-title-inner` 를
    // 겨냥하므로 Obsidian 과 같은 뼈대를 낸다.
    const head = `<div class="callout-icon"></div><div class="callout-title-inner">${escapeHTML(title)}</div>`;
    token.content = match[2]
      ? `<details class="callout" data-callout="${match[1]}" ${match[2] === '+' ? 'open' : ''}><summary class="callout-title">${head}</summary><div class="callout-content">`
      : `<aside class="callout" data-callout="${match[1]}"><div class="callout-title">${head}</div><div class="callout-content">`;
    if (state.tokens[end]) { state.tokens[end].type = 'html_block'; state.tokens[end].content = match[2] ? '</div></details>' : '</div></aside>'; }
    inline.content = inline.content.slice(match[0].length).replace(/^\n/, '');
    inline.children = [];
    state.md.inline.parse(inline.content, state.md, state.env, inline.children);
  }
});

export function sanitize(html) {
  return createDOMPurify(window).sanitize(html, { ADD_TAGS: ['annotation', 'semantics'], ADD_ATTR: ['data-link', 'data-embed', 'data-size', 'data-language', 'data-callout', 'data-task'], FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'form'] });
}
export function renderMarkdown(source) {
  return sanitize(markdown.render(source));
}
export function renderInline(source) { return sanitize(markdown.renderInline(String(source ?? ''))); }
