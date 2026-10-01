import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,appendFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TranslationBroker} from '../broker.mjs';
import {WorldNames} from '../names.mjs';
import {RuntimeQueue} from '../runtime-queue.mjs';

test('site list names pin native spelling, never the English semantic gloss',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-site-name-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const world='region1',native='Kacufensast Nedorsiga';
  const path=join(directory,'world.json');
  await writeFile(path,JSON.stringify({world,entities:[{id:'site:1',
    preferred:'Dripscarred the Crazy Depth',nativeName:native,
    aliases:[native,'Dripscarred the Crazy Depth']}]}));
  const calls=[];
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async(source,language,options)=>{
    calls.push({source,options});return '卡庫芬薩斯特 涅多爾西加';
  }});
  await broker.load();
  const names=new WorldNames(path);
  const row={world,kind:'legends-name',entityKind:'site',entityId:1,text:native,namePolicy:'native-v2'};
  assert.equal(await names.translateListName(row,broker),'卡庫芬薩斯特 涅多爾西加');
  assert.equal(calls.length,1);
  assert.equal(calls[0].source,native);
  assert.equal(calls[0].options.kind,'phonetic-name');
  const restarted=new TranslationBroker({directory,language:'zh-Hant',
    provider:()=>{throw Error('cached name expected');}});
  await restarted.load();
  assert.equal(await new WorldNames(path).translateListName(row,restarted),'卡庫芬薩斯特 涅多爾西加');
  await assert.rejects(names.translateListName({...row,text:'Wrong Native'},broker),/identity/);
});

test('typed list response keeps site ID separate from figure ID',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-list-key-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const world='region1';
  const make=()=>new RuntimeQueue({directory,currentWorld:()=>world,
    translate:async(source)=>source==='Site Native'?'地點':'人物'});
  const queue=make();await queue.load();
  await appendFile(queue.requests,[
    {world,text:'Site Native',kind:'legends-name',entityKind:'site',entityId:1,namePolicy:'native-v2'},
    {world,text:'Site Native',figureId:1,namePolicy:'native-v2'},
  ].map(JSON.stringify).join('\n')+'\n');
  await queue.drain();
  const rows=(await readFile(queue.responses,'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,2);
  assert.notEqual(rows[0].key,rows[1].key);
  assert.equal(rows.find(row=>row.kind==='legends-name').entityKind,'site');
  const restarted=make();await restarted.load();await restarted.drain();
  assert.equal(restarted.stats.attempted,0);
});
