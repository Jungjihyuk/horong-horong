import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
const dom=new JSDOM('<!doctype html><body/>',{url:'https://vault.invalid'});
Object.assign(globalThis,{window:dom.window,document:dom.window.document,HTMLElement:dom.window.HTMLElement});
const {VaultIndex,makeDataview,executeJS}=await import('../test-bundle.mjs');
const doc=(path,text)=>({path,text,created:1700000000000,modified:1700000000000,size:text.length});
function setup(){
  const index=new VaultIndex();
  index.update([doc('2. Study/MOC.md','# Dashboard'),doc('2. Study/Tools/One.md','---\ntags: [Study]\npriority: 2\naliases: [First]\n---\n# One\n- [x] Done [score:: 4]\n- [ ] Pending\n[[MOC]]'),doc('2. Study/Tools/Two.md','---\npriority: 1\n---\n# Two')]);
  const container=document.createElement('div');
  const dv=makeDataview(index,'2. Study/MOC.md',container,async path=>path.endsWith('.js')?'dv.paragraph(input.label);':'{"value":3}',()=>{});
  return {index,dv,container};
}
test('folder queries, aliases, task and backlink metadata match Dataview semantics',()=>{
  const {index,dv}=setup();
  assert.equal(dv.pages('"2. Study"').where(p=>p.file.folder.startsWith('2. Study/Tools')).length,2);
  assert.equal(index.resolve('First','2. Study/MOC.md'),'2. Study/Tools/One.md');
  assert.equal(dv.page('First').file.tasks.where(t=>t.completed).length,1);
  assert.equal(dv.page('First').file.tasks[0].score,4);
  assert.equal(dv.current().file.inlinks.length,1);
  assert.equal(dv.pages('#Study').length,1);
});
test('DQL executes fields, filtering and sorting using upstream engine',async()=>{
  const {dv,container}=setup();
  await dv.execute('TABLE WITHOUT ID file.link AS "Note", priority AS "Priority" FROM "2. Study/Tools" WHERE priority > 0 SORT priority asc');
  assert.equal(container.querySelectorAll('tbody tr').length,2);
  assert.match(container.querySelector('tbody tr').textContent,/Two/);
});
test('DataviewJS renders formatted tables and supports shared views and read-only JSON',async()=>{
  const {dv,container}=setup();
  await executeJS('const n=dv.pages("\\\"2. Study/Tools\\\"").length; dv.table(["Area","Count"],[["**Tools**",n]]); const data=JSON.parse(await dv.io.load(".my-wiki/test.json")); dv.paragraph(data.value); await dv.view("views/shared",{label:"shared view"});',dv);
  assert.equal(container.querySelector('strong').textContent,'Tools');
  assert.match(container.textContent,/shared view/);
  assert.match(container.textContent,/3/);
});
test('index refresh removes deleted pages and preserves date operations',()=>{
  const {index,dv}=setup();
  assert.equal(dv.date('2026-09-07').plus({days:7}).toISODate(),'2026-09-14');
  index.update([doc('2. Study/MOC.md','# only')]);
  assert.equal(dv.pages().length,1);
  assert.equal(dv.page('First'),undefined);
});
