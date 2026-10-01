import test from 'node:test';
import assert from 'node:assert/strict';
import {appendFile,mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {RuntimeQueue} from '../runtime-queue.mjs';

test('offscreen queued Legends names yield to the latest viewport',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-visibility-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const world='region1',calls=[];
  const queue=new RuntimeQueue({directory,currentWorld:()=>world,visibleOnly:true,
    isBatchable:row=>row.kind==='legends-name',
    translate:async source=>{calls.push(source);return '中文';}});
  await queue.load();
  const row=(text,id)=>({world,text,kind:'legends-name',entityKind:'site',entityId:id,
    namePolicy:'native-v2',visibilityId:`site:${id}`,priority:'foreground'});
  await appendFile(queue.requests,[row('Old A',1),row('Old B',2),row('Visible C',3)]
    .map(JSON.stringify).join('\n')+'\n');
  await writeFile(join(directory,'runtime-visible.json'),JSON.stringify({world,ids:['site:3']}));
  await queue.drain();
  assert.deepEqual(calls,['Visible C']);
  assert.equal(queue.jobs.size,0);
});

test('viewport change removes work waiting behind occupied slots',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-visibility-change-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const world='region1',calls=[];let release;
  const hold=new Promise(resolve=>release=resolve);
  const queue=new RuntimeQueue({directory,currentWorld:()=>world,visibleOnly:true,
    isBatchable:row=>row.kind==='legends-name',
    translate:async source=>{calls.push(source);await hold;return '中文';}});
  await queue.load();
  const row=(text,id)=>({world,text,kind:'legends-name',entityKind:'site',entityId:id,
    namePolicy:'native-v2',visibilityId:`site:${id}`,priority:'foreground'});
  const requests=[row('Busy',0),...Array.from({length:16},(_,i)=>row(`Old ${i}`,i+1))];
  await writeFile(join(directory,'runtime-visible.json'),JSON.stringify({world,
    ids:requests.map(item=>item.visibilityId)}));
  await appendFile(queue.requests,requests.map(JSON.stringify).join('\n')+'\n');
  const draining=queue.drain();
  await new Promise(resolve=>setTimeout(resolve,30));
  await writeFile(join(directory,'runtime-visible.json'),JSON.stringify({world,ids:['site:17']}));
  await appendFile(queue.requests,JSON.stringify(row('New',17))+'\n');
  await queue.ingest();queue.dispatch();
  assert.deepEqual([...queue.jobs.values()].map(item=>item.text),['New']);
  release();await draining;
  assert.ok(calls.includes('New'));
  assert.ok(!calls.includes('Old 15'));
});
