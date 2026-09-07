import { EditorState, StateField, StateEffect } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown as markdownLanguage } from '@codemirror/lang-markdown';
import { defaultHighlightStyle, syntaxHighlighting } from '@codemirror/language';
import 'katex/dist/katex.min.css';
import { markdown, renderMarkdown, splitFrontmatter, escapeHTML, sanitize } from './markdown.js';
import { propertiesElement } from './properties.js';
import { VaultIndex, normalizePath } from './dataview.js';

const editorHost=document.querySelector('#editor'), readingHost=document.querySelector('#reading'), runtime=document.querySelector('#runtime');
const index = new VaultIndex(), jobs=new Map(), results=new Map(), requested=new Set(), pendingReads=new Map(), sessions=new Map();
let config={}, editor, ready=false, composing=false, nextRead=0, epoch=0;
const native = message => window.webkit?.messageHandlers.vault?.postMessage(message);
const sendRuntime = message => { try { runtime.contentWindow?.postMessage({channel:'vault-host',...message},'*'); } catch {} };
const read = path => new Promise((resolve,reject) => { const id=++nextRead;pendingReads.set(id,{resolve,reject});native({type:'read',id,path}); });
window.vaultReadResult = message => { const item=pendingReads.get(message.id);pendingReads.delete(message.id);message.error ? item?.reject(Error(message.error)) : item?.resolve(message.text); };
const refresh = StateEffect.define();
function hash(source) { let h=2166136261;for(let i=0;i<source.length;i++)h=Math.imul(h^source.charCodeAt(i),16777619);return (h>>>0).toString(16); }
function resourceURL(path) { return 'vault-resource://local/'+encodeURIComponent(path); }
function navigate(target) {
  const [file,anchor] = target.split('#');
  const path=index.resolve(file,config.path);
  if (path === config.path && anchor) {
    const el=document.getElementById(anchor);if(el){el.scrollIntoView();return;}
    const line=editor?.state.doc.toString().split('\n').findIndex(s=>s.replace(/^#+\s*/,'')===anchor || s.includes('^'+anchor.replace(/^\^/,'')));
    if(line>=0 && editor){const pos=editor.state.doc.line(line+1).from;editor.dispatch({selection:{anchor:pos},effects:EditorView.scrollIntoView(pos,{y:'start'})});editor.focus();}return;
  }
  if(path) native({type:'open',path,anchor:anchor??''});
  else native({type:'link',target});
}
function hydrate(container,depth=0) {
  for(const el of container.querySelectorAll('table')) if(el.parentElement?.className!=='table-scroll') {const wrapper=document.createElement('div');wrapper.className='table-scroll';el.replaceWith(wrapper);wrapper.append(el);}
  for(const block of container.querySelectorAll('.special-block')) {
    const language=block.dataset.language, source=jobs.get(block.dataset.blockId)?.source ?? block.textContent;
    const id=hash(config.path+'\n'+language+'\n'+source);
    block.dataset.blockId=id;
    jobs.set(id,{id,language,source});
    if(!['mermaid','dataview','dataviewjs'].includes(language)) { block.innerHTML=`<aside class="unsupported">${escapeHTML(language)} 플러그인은 아직 지원하지 않습니다.<details><summary>원문 보기</summary><pre>${escapeHTML(source)}</pre></details></aside>`;continue; }
    jobs.set(id,{id,language,source});
    if(config.disabledBlocks?.includes(id)) {block.innerHTML='<aside class="error">이 블록의 실행 시간이 초과되었습니다. 원문 편집은 계속할 수 있습니다.</aside>';continue;}
    if(results.has(id)) block.innerHTML=results.get(id);else block.innerHTML='<span class="muted">문서 출력 계산 중…</span>';
    if(ready && !requested.has(id)){requested.add(id);sendRuntime({type:'run',job:jobs.get(id)});}
  }
  for(const el of container.querySelectorAll('[data-embed]:not([data-loaded])')) {
    el.dataset.loaded='true'; const target=el.dataset.embed, [file,anchor]=target.split('#');
    const path=index.resolve(file,config.path) ?? normalizePath(file.startsWith('/')?file.slice(1):'./'+file,config.path);
    if(/\.md$/i.test(path) && depth<4 && path!==config.path) {
      let source=index.documents.get(path)?.text ?? '';
      if(anchor){const lines=source.split('\n');const start=lines.findIndex(l=>l.replace(/^#+\s*/,'')===anchor || l.includes('^'+anchor.replace(/^\^/,'')));if(start>=0){const heading=lines[start].match(/^#+/)?.[0].length;let end=start+1;if(heading){while(end<lines.length && !(new RegExp('^#{1,'+heading+'} ').test(lines[end])))end++;}source=lines.slice(start,end).join('\n');}else source='참조한 블록을 찾지 못했습니다.';}
      el.innerHTML=renderMarkdown(splitFrontmatter(source).body);hydrate(el,depth+1);
    } else {
      const ext=file.split('.').at(-1).toLowerCase();let media;
      if(['png','jpg','jpeg','gif','svg','webp','avif','bmp'].includes(ext)){media=document.createElement('img');media.alt=file;const width=parseInt(el.dataset.size);if(width>0)media.style.width=width+'px';}
      else if(ext==='pdf'){media=document.createElement('iframe');media.title=file;}
      else if(['mp3','wav','ogg','m4a','flac'].includes(ext)){media=document.createElement('audio');media.controls=true;}
      else if(['mp4','webm','mov'].includes(ext)){media=document.createElement('video');media.controls=true;}
      if(media){media.src=resourceURL(path)+(anchor?'#'+anchor:'');el.append(media);}else el.textContent='참조 파일: '+target;
    }
  }
  for(const image of container.querySelectorAll('img[src]')) {const src=image.getAttribute('src');if(!/^(https?:|data:|vault-resource:)/i.test(src))image.src=resourceURL(normalizePath('./'+decodeURIComponent(src),config.path));}
}
/// 속성 위젯이 만든 새 전문을 문서에 반영한다. frontmatter 구간만 갈아끼우므로
/// 본문 편집과 똑같이 updateListener → native change → 자동저장 경로를 탄다.
function writeSource(next){
  if(!editor)return;
  const current=editor.state.sliceDoc();
  if(next===current)return;
  editor.dispatch({changes:{from:0,to:splitFrontmatter(current).raw.length,insert:next.slice(0,splitFrontmatter(next).raw.length)}});
}
const propertiesFor = source => propertiesElement(source,{readOnly:!!config.readOnly,onNavigate:navigate,onChange:writeSource});
class Preview extends WidgetType {
  constructor(source,from,properties=false){super();this.source=source;this.from=from;this.properties=properties;}
  eq(other){return this.source===other.source && this.from===other.from && this.properties===other.properties;}
  toDOM(view){
    const el=document.createElement('div');el.className='markdown-body live-block';
    // 속성 위젯에는 커서 이동 핸들러를 달지 않는다 — 입력 칸을 눌렀을 뿐인데 원문으로 튀면 안 된다.
    if(this.properties){el.append(propertiesFor(this.source));return el;}
    el.innerHTML=renderMarkdown(this.source);hydrate(el);
    el.addEventListener('mousedown',event=>{if(event.target.closest('a,button,input,summary,[data-runtime-event],audio,video,iframe'))return;event.preventDefault();view.dispatch({selection:{anchor:this.from}});view.focus();});
    return el;
  }
  ignoreEvent(){return true;}
}
function decorations(state){
  if(config.readOnly)return Decoration.none;
  const text=state.doc.toString(), {raw,body,error}=splitFrontmatter(text), ranges=[];
  const active=(from,to)=>state.selection.ranges.some(r=>r.from<=to && r.to>=from);
  // 커서가 들어와도 속성 위젯을 유지한다 — 원문 YAML 문법을 알아야 편집되는 상태를 없앤다.
  // 단 YAML 이 깨졌으면 원문을 드러내야 고칠 수 있다.
  if(raw && !error)ranges.push(Decoration.replace({widget:new Preview(raw,0,true),block:true}).range(0,raw.length-1));
  else if(!raw)ranges.push(Decoration.widget({widget:new Preview('',0,true),block:true,side:-1}).range(0));
  const offsets=[raw.length];for(let i=0;i<body.length;i++)if(body[i]==='\n')offsets.push(raw.length+i+1);
  for(const token of markdown.parse(body,{})){
    if(!token.map || token.level!==0 || token.nesting===-1 || token.type==='inline')continue;
    const from=offsets[token.map[0]],to=Math.min(text.length,(offsets[token.map[1]] ?? text.length+1)-1);
    if(from==null||to<=from||active(from,to))continue;
    ranges.push(Decoration.replace({widget:new Preview(text.slice(from,to),from),block:true}).range(from,to));
  }
  return Decoration.set(ranges,true);
}
const previewField=StateField.define({create:decorations,update:(value,transaction)=>transaction.docChanged||transaction.selection||transaction.effects.some(e=>e.is(refresh))?decorations(transaction.state):value,provide:field=>EditorView.decorations.from(field)});
function changed(){if(editor&&!composing)native({type:'change',text:editor.state.sliceDoc(),path:config.path});}
function makeEditor(source){
  return new EditorView({parent:editorHost,state:EditorState.create({doc:source,extensions:[EditorState.lineSeparator.of(source.includes('\r\n')?'\r\n':'\n'),history(),keymap.of([{key:'Mod-s',run:()=>{changed();native({type:'save'});return true;}},...defaultKeymap,...historyKeymap]),markdownLanguage(),syntaxHighlighting(defaultHighlightStyle),EditorView.lineWrapping,previewField,EditorView.updateListener.of(update=>{if(update.docChanged)changed();}),EditorView.domEventHandlers({compositionstart:()=>{composing=true;},compositionend:()=>{composing=false;queueMicrotask(changed);}})]})});
}
window.setVaultState = next => {
  const documentChanged=next.path!==config.path||next.version!==config.version;
  const indexChanged=next.indexVersion!==config.indexVersion;
  if(documentChanged && editor && config.path)sessions.set(config.path,{state:editor.state,source:editor.state.sliceDoc(),scroll:editor.scrollDOM.scrollTop});
  config=next;
  for(const [key,value] of Object.entries(next.theme ?? {}))document.documentElement.style.setProperty('--'+key,value);
  if(indexChanged||documentChanged){index.update(next.documents??[]);requested.clear();results.clear();epoch++;if(ready)sendRuntime({type:'configure',path:config.path,documents:config.documents??[]});}
  const reading=next.reading||next.readOnly;
  readingHost.hidden=!reading;editorHost.hidden=reading;
  if(documentChanged||!editor){editor?.destroy();const session=sessions.get(next.path);editor=makeEditor(next.source??'');if(session?.source===next.source){editor.setState(session.state);editor.scrollDOM.scrollTop=session.scroll;}}
  if(reading){
    const {raw,body}=splitFrontmatter(next.source??'');
    readingHost.innerHTML=renderMarkdown(body);
    // 읽기 뷰에서는 속성이 있을 때만 표를 얹는다. 없는 문서에 «속성 추가»를 띄우는 건 편집 뷰 몫.
    if(raw)readingHost.prepend(propertiesFor(next.source??''));
    hydrate(readingHost);
  }
  else {editor.dispatch({effects:refresh.of(null)});hydrate(editorHost);}
  if(next.anchor)setTimeout(()=>navigate('#'+next.anchor),100);
};
window.addEventListener('message',async event=>{
  if(event.source!==runtime.contentWindow||event.data?.channel!=='vault-runtime')return;
  const message=event.data;
  if(message.type==='ready'){ready=true;if(config.path)sendRuntime({type:'configure',path:config.path,documents:config.documents??[]});for(const job of jobs.values())if(!requested.has(job.id)){requested.add(job.id);sendRuntime({type:'run',job});}}
  else if(message.type==='read'){try{sendRuntime({type:'read-result',id:message.id,text:await read(message.path)});}catch(error){sendRuntime({type:'read-result',id:message.id,error:error.message});}}
  else if(message.type==='open')navigate(message.path);
  else if(message.type==='started'||message.type==='finished')native({type:message.type,id:message.id});
  else if(message.type==='result'){const html=sanitize(message.html);results.set(message.id,html);for(const el of document.querySelectorAll(`[data-block-id="${CSS.escape(message.id)}"]`)){el.innerHTML=html;hydrate(el);}}
});
document.addEventListener('click',event=>{
  const link=event.target.closest('a');
  if(link){event.preventDefault();const target=link.dataset.link??link.getAttribute('href');if(/^https?:|^mailto:/i.test(target))native({type:'external',url:target});else navigate(target);return;}
  const el=event.target.closest('[data-runtime-event]');if(el){sendRuntime({type:'event',event:'click',id:el.dataset.runtimeEvent});}
});
document.addEventListener('change',event=>{const el=event.target.closest('[data-runtime-event]');if(el)sendRuntime({type:'event',event:'change',id:el.dataset.runtimeEvent,value:el.value,checked:el.checked});});
runtime.addEventListener('load', () => sendRuntime({type:'ping'}));
if(runtime.contentDocument?.readyState === 'complete') sendRuntime({type:'ping'});
native({type:'ready'});
