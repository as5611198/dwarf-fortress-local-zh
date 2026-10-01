import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TranslationBroker} from '../broker.mjs';
import {createBrokerServer} from '../server.mjs';

test('cropped Needs rows release native requests without using model or resolving names',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-display-fragments-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  let calls=0,names=0;
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async source=>{
    calls++;
    return source.startsWith('She') ? '她在未能獨處後並未分心。' : '他在無法向伊特拉祈禱後並未分心。';
  }});
  await broker.load();
  broker.resolveNames=async()=>{names++;};
  const server=createBrokerServer(broker);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{server.closeAllConnections();return new Promise(resolve=>server.close(resolve));});
  const submit=text=>fetch(`http://127.0.0.1:${server.address().port}/v2/translate`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});
  for(const text of ['[C:7:0:0]He is not distracted after being unable to be',
    '[P][C:7:0:0]He is not distracted after being unable to pray to',
    'She is not distracted after being unable to pray to ']) {
    const response=await submit(text);
    assert.equal(response.status,503);
    assert.deepEqual(await response.json(),{error:'incomplete display fragment'});
  }
  assert.equal(calls,0);assert.equal(names,0);
  assert.equal(broker.pending.size,0);
  assert.equal(broker.stats.skippedFragments,3);
  // A full sentence, including the same dangling words inside it, must continue translating.
  for(const text of ['He is not distracted after being unable to pray to Istrath.',
    'She is not distracted after being unable to be alone.']) {
    const response=await submit(text);
    assert.equal(response.status,200);
    assert.match((await response.json()).translation,/並未分心/);
  }
  assert.equal(calls,2);assert.equal(names,2);
  // Explicit local dictionaries remain authoritative even for a clipped string.
  const known='He is not distracted after being unable to be';
  broker.literalStatic.set(known,'他未能');
  assert.equal(await broker.translate(known),'他未能');
  assert.equal(calls,2);
});
