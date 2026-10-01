import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, appendFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';
import { RuntimeQueue } from '../runtime-queue.mjs';

const turn = () => new Promise(resolve => setTimeout(resolve, 20));
test('foreground uses reserved slot and promotes duplicate background work', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-priority-'));
  t.after(() => rm(directory, {recursive:true, force:true}));
  const calls=[], releases=[];
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:source => {
    calls.push(source); return new Promise(resolve => releases.push(() => resolve('中文')));
  }});
  await broker.load();
  const a=broker.withPriority('background',()=>broker.translate('Background A'));
  const b=broker.withPriority('background',()=>broker.translate('Background B'));
  await turn();
  assert.deepEqual(calls,['Background A']);
  const visible=broker.translate('Background B');
  await turn();
  assert.deepEqual(calls,['Background A','Background B']);
  releases.forEach(fn=>fn());
  await Promise.all([a,b,visible]);
  assert.equal(broker.stats.accepted,2);
});

test('journal accepts foreground while a background translation is running', {timeout:3000}, async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-journal-priority-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const calls=[]; let release;
  let startedBackground,startedVisible;
  const backgroundStarted=new Promise(resolve=>startedBackground=resolve);
  const visibleStarted=new Promise(resolve=>startedVisible=resolve);
  const queue=new RuntimeQueue({directory,currentWorld:()=> 'region1', translate:async (source)=> {
    calls.push(source);
    if(source==='Background') {
      await new Promise(resolve=> {release=resolve;startedBackground();});
    } else startedVisible();
    return '中文';
  }});
  await queue.load();
  const request=(text,priority)=>JSON.stringify({world:'region1',text,priority})+'\n';
  await appendFile(queue.requests,request('Background','background'));
  const first=queue.drain();
  await backgroundStarted;
  await appendFile(queue.requests,request('Visible','foreground'));
  const second=queue.drain();
  await visibleStarted;
  assert.deepEqual(calls,['Background','Visible']);
  release(); await Promise.all([first,second]);
});

test('Legends foreground work supplies a batch window without widening normal work', async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-legends-window-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const calls=[];let release;
  const gate=new Promise(resolve=>release=resolve);
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:(source,language,options)=>{
    calls.push({source,batch:options?.batch});return gate.then(()=> '中文');
  }});
  await broker.load();
  const legends=broker.withPriority('foreground',()=>Promise.all(
    Array.from({length:12},(_,i)=>broker.translate(`Visible ${String.fromCharCode(65+i)}`))), 'legends', {batch:true});
  await turn();
  assert.equal(calls.length,12);
  assert.ok(calls.every(row=>row.batch===true));
  const ordinary=broker.translate('Fortress row');
  await turn();
  assert.ok(calls.some(row=>row.source==='Fortress row' && row.batch!==true));
  release();await Promise.all([legends,ordinary]);
});

test('runtime starts visible Legends rows together while limiting regular rows', async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-runtime-window-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const calls=[];let release;
  const gate=new Promise(resolve=>release=resolve);
  const queue=new RuntimeQueue({directory,currentWorld:()=> 'region1',
    isBatchable:row=>row.figureId!==undefined,
    translate:(source)=> {calls.push(source);return gate.then(()=> '中文');}});
  await queue.load();
  const rows=Array.from({length:12},(_,i)=>({world:'region1',
    figureId:i,text:`Figure ${String.fromCharCode(65+i)}`,priority:'foreground'}));
  await appendFile(queue.requests,rows.map(row=>JSON.stringify(row)).join('\n')+'\n');
  const draining=queue.drain();
  const deadline=Date.now()+2000;
  while(calls.length<12 && Date.now()<deadline) await turn();
  assert.equal(calls.length,12);
  release();await draining;
});
