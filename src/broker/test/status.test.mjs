import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TranslationBroker} from '../broker.mjs';
import {RuntimeQueue} from '../runtime-queue.mjs';
import {StatusBridge} from '../status.mjs';

test('status separates journal tasks from provider jobs and counts current-world failures', async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-status-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async()=> '中文'});
  const queue=new RuntimeQueue({directory,currentWorld:()=> 'fortress',translate:()=> '中文'});
  queue.jobs.set('visible',{world:'fortress',priority:'foreground'});
  queue.jobs.set('background',{world:'fortress',priority:'background'});
  queue.activeJobs.set('working',{row:{world:'fortress',priority:'foreground'}});
  queue.failures.set('old',{world:'old-world'});
  queue.failures.set('current',{world:'fortress'});
  const bridge=new StatusBridge(directory,broker,queue,()=> 'fortress');
  await bridge.publish();
  const data=JSON.parse(await readFile(join(directory,'broker-status.json'),'utf8'));
  assert.equal(data.runtime.foregroundQueued,1);
  assert.equal(data.runtime.backgroundQueued,1);
  assert.equal(data.runtime.foregroundActive,1);
  assert.equal(data.runtime.unresolved,1);
  assert.equal(data.runtime.retainedFailures,2);
  assert.equal(data.providerQueued,0);
});

test('persistent pause blocks journal background dispatch and leaves foreground available',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-pause-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const calls=[];
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async()=> '中文'});
  const queue=new RuntimeQueue({directory,currentWorld:()=> 'fortress',translate:async text=>{
    calls.push(text);return '中文';}});
  queue.jobs.set('background',{world:'fortress',text:'Background',priority:'background'});
  const bridge=new StatusBridge(directory,broker,queue,()=> 'fortress');
  await writeFile(join(directory,'translation-controls.json'),JSON.stringify({version:1,backgroundPaused:true}));
  await bridge.publish();
  await queue.drain();
  assert.deepEqual(calls,[]);
  queue.jobs.set('visible',{world:'fortress',text:'Visible',priority:'foreground'});
  await queue.drain();
  assert.deepEqual(calls,['Visible']);
  await writeFile(join(directory,'translation-controls.json'),'{partial');
  await bridge.publish();
  assert.equal(broker.backgroundPaused,true);
  await writeFile(join(directory,'translation-controls.json'),JSON.stringify({version:1,backgroundPaused:false}));
  await bridge.publish();
  await queue.drain();
  assert.deepEqual(calls,['Visible','Background']);
});
