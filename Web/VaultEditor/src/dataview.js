import { parsePage } from 'data-import/markdown-file';
import { DataArray } from 'api/data-array';
import { Link, Values } from 'data-model/value';
import { DEFAULT_QUERY_SETTINGS } from 'settings';
import { parseQuery } from 'query/parse';
import { executeTable, executeList, executeTask, executeInline, defaultLinkHandler } from 'query/engine';
import { matchingSourcePaths } from 'data-index/resolver';
import { EXPRESSION } from 'expression/parse';
import { Context } from 'expression/context';
import { DEFAULT_FUNCTIONS, Functions } from 'expression/functions';
import * as luxon from 'luxon';
import moment from 'moment';
import { markdown, splitFrontmatter, renderMarkdown, renderInline, escapeHTML } from './markdown.js';

export function normalizePath(path, origin = '') {
  const parts = (path.startsWith('./') || path.startsWith('../') ? origin.split('/').slice(0,-1).join('/') + '/' + path : path).split('/');
  const result = [];
  for (const part of parts) { if (part === '..') { if (!result.length) throw Error('vault 밖의 경로입니다.'); result.pop(); } else if (part && part !== '.') result.push(part); }
  return result.join('/');
}
function metadata(text) {
  const { raw, properties } = splitFrontmatter(text);
  const body = raw.replace(/[^\r\n]/g, ' ') + text.slice(raw.length);
  const tokens = markdown.parse(body, {}), lines = body.split('\n');
  const result = { frontmatter: properties, sections: [], headings: [], listItems: [], links: [], embeds: [], tags: [] };
  const pos = (start, end = start) => ({ start: { line: start, col: 0, offset: 0 }, end: { line: end, col: lines[end]?.length ?? 0, offset: 0 } });
  const stack = [];
  const excluded = new Set();
  for (const t of tokens) {
    if (!t.map) continue;
    const [start, end] = t.map;
    if (['fence','code_block','html_block'].includes(t.type)) { for(let i=start;i<end;i++) excluded.add(i); continue; }
    if (t.type === 'heading_open') result.headings.push({ heading: lines[start].replace(/^#+\s*/, ''), level: Number(t.tag.slice(1)), position: pos(start,end-1) });
    if (['paragraph_open','heading_open','bullet_list_open','ordered_list_open'].includes(t.type)) result.sections.push({ type: t.type.includes('list') ? 'list' : 'paragraph', position: pos(start,end-1) });
    if (t.type === 'list_item_open') {
      const indent = lines[start].search(/\S/);
      while (stack.length && stack.at(-1).indent >= indent) stack.pop();
      const task = lines[start].match(/^\s*(?:[-*+]|\d+[.)])\s+\[(.)\]/)?.[1];
      result.listItems.push({ position: pos(start,start), parent: stack.at(-1)?.line ?? -1, task });
      stack.push({ indent, line: start });
    }
  }
  lines.forEach((line, number) => {
    if (excluded.has(number)) return;
    for (const match of line.matchAll(/(!?)\[\[([^\]]+)\]\]/g)) {
      const [link, displayText] = match[2].split('|');
      result[match[1] ? 'embeds' : 'links'].push({ link, displayText, position: pos(number) });
    }
    for (const match of line.matchAll(/(?:^|\s)(#[\p{L}\p{N}_/-]+)/gu)) result.tags.push({ tag: match[1], position: pos(number) });
  });
  result.frontmatterLinks = [...JSON.stringify(properties).matchAll(/\[\[([^\]]+)\]\]/g)].map(m => ({ link: m[1].split('|')[0] }));
  return result;
}
export class VaultIndex {
  pages = new Map();
  documents = new Map();
  inverseLinks = new Map();
  names = new Map();
  tags = { getInverse: tag => new Set([...this.pages].filter(([,p]) => p.fullTags().has(tag)).map(([path]) => path)) };
  links = { getInverse: path => this.inverseLinks.get(path) ?? new Set() };
  starred = { starred: () => false };
  vault = { getMarkdownFiles: () => [...this.pages.keys()].map(path => ({path})) };
  metadataCache = { getFirstLinkpathDest: (path, origin) => { const resolved = this.resolve(path, origin); return resolved ? { path: resolved } : null; }, resolvedLinks: {} };
  prefix = {
    nodeExists: folder => !folder || [...this.pages.keys()].some(p => p.startsWith(folder + '/')),
    get: (folder, filter) => new Set([...this.pages.keys()].filter(p => (!folder || p.startsWith(folder + '/')) && (!filter || filter(p)))),
    pathExists: path => this.pages.has(path),
    resolveRelative: normalizePath
  };
  update(documents) {
    const paths = new Set(documents.map(d => d.path));
    for (const key of this.pages.keys()) if (!paths.has(key)) { this.pages.delete(key); this.documents.delete(key); }
    for (const doc of documents) {
      if (this.documents.get(doc.path)?.text === doc.text && this.documents.get(doc.path)?.modified === doc.modified) continue;
      this.documents.set(doc.path, doc);
      this.pages.set(doc.path, parsePage(doc.path, doc.text.replace(/\r\n/g, '\n'), { ctime: doc.created, mtime: doc.modified, size: doc.size }, metadata(doc.text.replace(/\r\n/g,'\n'))));
    }
    this.names.clear();
    for (const [path,page] of this.pages) {
      for(const name of [path.split('/').at(-1).replace(/\.md$/i,''),...page.aliases]) {
        if(!this.names.has(name))this.names.set(name,[]);
        this.names.get(name).push(path);
      }
    }
    this.inverseLinks.clear(); this.metadataCache.resolvedLinks = {};
    for (const [path, page] of this.pages) {
      const outgoing = {};
      for (const link of page.links) {
        const target = this.resolve(link.path, path) ?? link.path;
        if (!this.inverseLinks.has(target)) this.inverseLinks.set(target, new Set());
        this.inverseLinks.get(target).add(path); outgoing[target] = 1;
      }
      this.metadataCache.resolvedLinks[path] = outgoing;
    }
  }
  resolve(link, origin = '') {
    let target = String(link?.path ?? link).split('|')[0].split('#')[0];
    try { target = decodeURIComponent(target); } catch {}
    if (!target) return origin || null;
    const normalized = normalizePath(target, origin);
    const relative = normalizePath('./' + target, origin);
    for (const p of [normalized, normalized + '.md', relative, relative + '.md']) if (this.pages.has(p)) return p;
    const candidates = [...(this.names.get(target.replace(/\.md$/i,'')) ?? [])];
    const folder = origin.split('/').slice(0,-1).join('/');
    return candidates.sort((a,b) => Number(b.split('/').slice(0,-1).join('/') === folder) - Number(a.split('/').slice(0,-1).join('/') === folder) || a.length-b.length || a.localeCompare(b))[0] ?? null;
  }
}
const settings = DEFAULT_QUERY_SETTINGS;
function wrap(value) {
  if (Array.isArray(value)) return DataArray.from(value.map(wrap), settings);
  if (value && Object.getPrototypeOf(value) === Object.prototype) return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,wrap(v)]));
  return value;
}
export function installDOMHelpers() {
  const proto = HTMLElement.prototype;
  if (proto.createEl) return;
  proto.createEl = function(tag, options = {}, callback) {
    if (typeof options === 'string') options = {text:options};
    const el = document.createElement(tag);
    if (options.text != null) el.textContent = options.text;
    if (options.cls) el.className = Array.isArray(options.cls) ? options.cls.join(' ') : options.cls;
    for (const [key,value] of Object.entries(options.attr ?? {})) el.setAttribute(key,String(value));
    this.appendChild(el); callback?.(el); return el;
  };
  proto.createDiv = function(options, callback) { return this.createEl('div', options, callback); };
  proto.createSpan = function(options, callback) { return this.createEl('span', options, callback); };
  proto.empty = function() { this.replaceChildren(); };
  proto.addClass = function(...names) { this.classList.add(...names); };
  proto.setText = function(text) { this.textContent = text; };
}
export function makeDataview(index, origin, container, read, open) {
  installDOMHelpers();
  const valueHTML = value => {
    if (value == null) return '—';
    if (Values.isLink(value)) return `<a class="internal-link" data-link="${escapeHTML(value.path + (value.subpath ? '#' + value.subpath : ''))}" href="#">${escapeHTML(value.display ?? value.path.split('/').at(-1).replace(/\.md$/,''))}</a>`;
    if (luxon.DateTime.isDateTime(value)) return escapeHTML(value.toISODate());
    if (DataArray.isDataArray(value) || Array.isArray(value)) return Array.from(value).map(valueHTML).join(', ');
    return renderInline(typeof value === 'object' ? JSON.stringify(value) : String(value));
  };
  const append = (tag, value) => { const el = document.createElement(tag); el.innerHTML = valueHTML(value); container.append(el); return el; };
  const dv = {
    container, luxon, settings,
    current: () => dv.page(origin),
    page: path => { const p = index.resolve(path, origin); return p ? wrap(index.pages.get(p).serialize(index)) : undefined; },
    pages: source => {
      const paths = source ? matchingSourcePaths(EXPRESSION.source.tryParse(source), index, origin).orElseThrow() : new Set(index.pages.keys());
      return DataArray.from([...paths].map(path => dv.page(path)), settings);
    },
    array: value => DataArray.from(value ?? [], settings), isArray: value => Array.isArray(value) || DataArray.isDataArray(value),
    fileLink: (path, embed = false, display) => Link.file(path, embed, display),
    date: value => value === 'today' ? luxon.DateTime.now().startOf('day') : value === 'now' ? luxon.DateTime.now() : luxon.DateTime.isDateTime(value) ? value : EXPRESSION.date.tryParse(String(value)),
    duration: value => EXPRESSION.duration.tryParse(String(value)),
    paragraph: value => append('p', value), span: value => append('span', value), header: (level,value) => append('h'+Math.min(6,Math.max(1,level)), value),
    el: (tag,value,options = {}) => { const el = append(tag,value); if (options.cls) el.className = options.cls; for (const [k,v] of Object.entries(options.attr ?? {})) el.setAttribute(k,String(v)); return el; },
    list: values => { const ul = document.createElement('ul'); for (const value of values ?? []) { const li = document.createElement('li'); li.innerHTML=valueHTML(value); ul.append(li); } container.append(ul); },
    table: (headers,rows) => { const wrapper = document.createElement('div'); wrapper.className='table-scroll'; wrapper.innerHTML=`<table><thead><tr>${headers.map(h=>`<th>${valueHTML(h)}</th>`).join('')}</tr></thead><tbody>${Array.from(rows ?? []).map(row=>`<tr>${Array.from(row).map(cell=>`<td>${valueHTML(cell)}</td>`).join('')}</tr>`).join('')}</tbody></table>`; container.append(wrapper); },
    io: { load: async path => { const resolved = index.resolve(path,origin) ?? normalizePath(path,origin); return index.documents.get(resolved)?.text ?? await read(resolved); }, normalize: path => index.resolve(path,origin) ?? normalizePath(path,origin) },
    view: async (path,input) => { let source; try { source = await read(normalizePath(path + '.js',origin)); } catch { source = await read(normalizePath(path + '/view.js',origin)); try { const style = document.createElement('style'); style.textContent = await read(normalizePath(path + '/view.css',origin)); container.append(style); } catch {} } await executeJS(source,dv,input); },
    execute: async source => {
      const query = parseQuery(source).orElseThrow();
      if (query.header.type === 'table') { const r=(await executeTable(query,index,origin,settings)).orElseThrow(); dv.table(r.names,r.data); }
      else if (query.header.type === 'list') dv.list((await executeList(query,index,origin,settings)).orElseThrow().data);
      else if (query.header.type === 'task') { const r=(await executeTask(query,index,origin,settings)).orElseThrow(); dv.list(r.tasks.map(t=>t.text)); }
      else throw Error('이 Dataview 출력 형식은 지원하지 않습니다.');
    },
  };
  const context = new Context(defaultLinkHandler(index,origin),settings,{this:index.pages.get(origin)?.serialize(index) ?? {}});
  dv.func = Functions.bindAll(DEFAULT_FUNCTIONS,context);
  dv.evaluate = source => executeInline(EXPRESSION.field.tryParse(source),origin,index,settings);
  dv.app = {
    vault: { adapter: { read: path => read(normalizePath(path,origin)) }, getAbstractFileByPath: path => index.pages.has(path) ? {path} : null },
    metadataCache: index.metadataCache,
    workspace: { getLeaf: () => ({ openFile: file => open(file.path) }) }
  };
  return dv;
}
export async function executeJS(source,dv,input) {
  const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
  return await new AsyncFunction('dv','dataview','input','app','moment',source).call({container:dv.container},dv,dv,input,dv.app,moment);
}
