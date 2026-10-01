import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {contributionIdentity} from '../shared-policy.mjs';
import {DEFAULT_SETTINGS,SettingsStore,SettingsService} from '../settings.mjs';
import {TranslationBroker} from '../broker.mjs';
const mod=await import('../shared-outbox.mjs').catch(()=>({}));
const row={schema:1,rules:'df-zh-3',language:'zh-Hant',context:'general',kind:'exact',origin:'vanilla',text:'He feels lonely after being unable to socialize.',translation:'他因為無法社交而感到孤單。',model:'fixture-model',license:'CC0-1.0'};
async function setup(t,options={}){assert.equal(typeof mod.SharedOutbox,'function');const directory=await mkdtemp(join(tmpdir(),'df-share-'));t.after(()=>rm(directory,{recursive:true,force:true}));const outbox=new mod.SharedOutbox({directory,isEnabled:()=>true,...options});await outbox.load();return {outbox,directory};}
test('consent defaults off and disabled scopes never queue or upload',async t=>{
  assert.equal(DEFAULT_SETTINGS.sharedContributions,false);let calls=0;const {outbox}=await setup(t,{isEnabled:()=>false,fetcher:async()=>{calls++;}});
  assert.equal(await outbox.capture(row,''),false);await outbox.flush();assert.equal(calls,0);assert.equal(outbox.status().pending,0);
});
test('outbox persists only sanitized candidate fields, deduplicates and supports offline restart',async t=>{
  const {outbox,directory}=await setup(t);assert.equal(await outbox.capture(row,'local-save'),true);await outbox.capture(row,'local-save');
  assert.equal(outbox.status().pending,1);assert.equal(await outbox.capture({...row,text:'Urist feels lonely.'},''),false);
  const saved=await readFile(join(directory,'shared/state.json'),'utf8');assert.doesNotMatch(saved,/Urist/);
  const restart=new mod.SharedOutbox({directory,isEnabled:()=>true,fetcher:async()=>{throw Error('offline');},retryMs:1});await restart.load();
  await restart.flush();assert.equal(restart.status().pending,1);assert.equal(restart.status().phase,'error');
});
test('outbox batches and sends no local scope or private fields, deduplicates simultaneous flush and retains on bad receipts',async t=>{
  let calls=0,payload;const {outbox}=await setup(t,{fetcher:async(url,options)=>{calls++;payload=JSON.parse(options.body);return new Response(JSON.stringify({accepted:payload.entries.map(()=>({id:'forged',counted:true}))}),{status:202});}});
  await outbox.capture(row,'private-save');await Promise.all([outbox.flush(),outbox.flush()]);assert.equal(calls,1);
  assert.doesNotMatch(JSON.stringify(payload),/private-save|scope|world|key|settings/);assert.equal(outbox.status().pending,1);
});
test('outbox write failures roll back capture, clear leaves model journal untouched',async t=>{
  const {outbox,directory}=await setup(t);outbox.writeFile=async()=>{throw Error('disk full');};await assert.rejects(()=>outbox.capture(row,''));assert.equal(outbox.status().pending,0);
  outbox.writeFile=(await import('node:fs/promises')).writeFile;await outbox.capture(row,'');await outbox.clear();assert.equal(outbox.status().pending,0);
  await assert.rejects(readFile(join(directory,'translations.jsonl')));
});
test('fresh AI completions capture templates in background, high-priority and cached results do not contribute',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-share-hook-'));t.after(()=>rm(directory,{recursive:true,force:true}));let captures=0;
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async()=>row.translation});await broker.load();
  broker.captureShared=async(source,translation,kind)=>{assert.equal(source,row.text);assert.equal(translation,row.translation);assert.equal(kind,'exact');captures++;};
  await broker.translate(row.text);await new Promise(resolve=>setImmediate(resolve));assert.equal(captures,1);
  await broker.translate(row.text);assert.equal(captures,1);broker.fixed.set('Health','固定健康');await broker.translate('Health');assert.equal(captures,1);
});
test('consent obeys global/save scopes and clear acknowledgement leaves API prompt drafts alone',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-share-settings-'));t.after(()=>rm(directory,{recursive:true,force:true}));const store=new SettingsStore(directory);await store.load();
  assert.equal(store.effective('').sharedContributions,false);await store.apply({scope:'global',settings:{sharedContributions:true}});
  await store.apply({scope:'save',world:'one',settings:{sharedContributions:false}});assert.equal(store.effective('one').sharedContributions,false);assert.equal(store.effective('two').sharedContributions,true);
  let cleared=0;const service=new SettingsService(store,{onClearShared:async()=>cleared++});const result=await service.handle({id:'clear-one',action:'shared-clear'});
  assert.equal(result.ok,true);assert.equal(cleared,1);assert.equal(result.snapshot,undefined);
});
test('a genuine receipt clears persisted jobs once, and an expired job never uploads',async t=>{
 let calls=0;const {outbox,directory}=await setup(t,{fetcher:async(url,options)=>{calls++;const payload=JSON.parse(options.body);
  return Response.json({accepted:payload.entries.map(entry=>({id:createHash('sha256').update(JSON.stringify([contributionIdentity(entry),entry.translation])).digest('hex'),counted:true}))},{status:202});}});
 await outbox.capture(row,'');await outbox.flush();assert.equal(outbox.status().sent,1);assert.equal(outbox.status().pending,0);
 const saved=JSON.parse(await readFile(join(directory,'shared/state.json'),'utf8'));assert.equal(saved.entries.length,0);
 await outbox.capture(row,'');outbox.state.entries[0].created-=8*86400000;await outbox.flush();assert.equal(calls,1);
});
test('stalled upload and receipt bodies have a deadline, preserve jobs and can be stopped',async t=>{
 for(const fetcher of [()=>new Promise(()=>{}),async()=>new Response(new ReadableStream({pull:()=>new Promise(()=>{}),cancel:()=>new Promise(()=>{})}),{status:202})]){
  const {outbox}=await setup(t,{fetcher,timeoutMs:30});await outbox.capture(row,'');
  const keepalive=setInterval(()=>{},100);try{await outbox.flush();assert.equal(outbox.status().phase,'error');assert.equal(outbox.status().pending,1);}finally{clearInterval(keepalive);outbox.stop();}
 }
});
test('revoking consent while the status is being persisted prevents starting an upload',async t=>{
 let enabled=true,calls=0;const {outbox}=await setup(t,{isEnabled:()=>enabled,fetcher:async()=>{calls++;throw Error('should not upload');}});
 await outbox.capture(row,'');const publish=outbox.publish.bind(outbox);outbox.publish=async()=>{if(outbox.phase==='sending')enabled=false;await publish();};
 await outbox.flush();assert.equal(calls,0);assert.equal(outbox.status().pending,1);
});
