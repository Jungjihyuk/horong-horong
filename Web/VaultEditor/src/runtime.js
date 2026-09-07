import mermaid from 'mermaid';
import { VaultIndex, makeDataview, executeJS } from './dataview.js';
import { escapeHTML } from './markdown.js';

const index = new VaultIndex(), reads = new Map(), blocks = new Map();
let origin = '', nextRead = 0, serial = Promise.resolve();
const send = data => parent.postMessage({ channel:'vault-runtime', ...data }, '*');
const read = path => new Promise((resolve,reject) => { const id = ++nextRead; reads.set(id,{resolve,reject}); send({type:'read',id,path}); });
const open = path => send({type:'open',path});
mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'neutral' });

function publish(id, container) {
  let ordinal=0;
  for (const el of container.querySelectorAll('*')) el.dataset.runtimeEvent = id + ':' + ordinal++;
  send({type:'result',id,html:container.innerHTML});
}
async function run(job) {
  send({type:'started',id:job.id});
  const container = document.createElement('section');
  document.body.append(container); blocks.get(job.id)?.remove(); blocks.set(job.id,container);
  try {
    if (job.language === 'mermaid') container.innerHTML = (await mermaid.render('mermaid'+job.id.replace(/\W/g,''),job.source)).svg;
    else {
      const dv = makeDataview(index,origin,container,read,open);
      if (job.language === 'dataview') await dv.execute(job.source);
      else await executeJS(job.source,dv);
    }
  } catch(error) { container.innerHTML = `<aside class="error">${escapeHTML(error.message)}<details><summary>원문 보기</summary><pre>${escapeHTML(job.source)}</pre></details></aside>`; }
  publish(job.id,container);
  send({type:'finished',id:job.id});
}
window.addEventListener('message', event => {
  if (event.source !== parent || event.data?.channel !== 'vault-host') return;
  const message = event.data;
  if (message.type === 'ping') {
    send({type:'ready'});
  } else if (message.type === 'read-result') {
    const pending = reads.get(message.id); reads.delete(message.id);
    if (message.error) pending?.reject(Error(message.error)); else pending?.resolve(message.text);
  } else if (message.type === 'configure') {
    serial = serial.then(() => { origin=message.path; index.update(message.documents); });
  } else if (message.type === 'run') serial = serial.then(() => run(message.job));
  else if (message.type === 'event') {
    const target = document.querySelector(`[data-runtime-event="${CSS.escape(message.id)}"]`);
    if (!target) return;
    if ('value' in target && message.value != null) target.value=message.value;
    if ('checked' in target && message.checked != null) target.checked=message.checked;
    target.dispatchEvent(new Event(message.event,{bubbles:true}));
    setTimeout(() => { for(const [id,container] of blocks) publish(id,container); },100);
  }
});
send({type:'ready'});
