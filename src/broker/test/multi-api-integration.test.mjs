import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {start} from '../server.mjs';

test('multi-API settings hot-apply through service with save isolation and redacted health',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-pool-integration-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  const calls=[0,0];
  const apis=await Promise.all(calls.map(async(_,index)=>{
    const api=createServer(async(req,res)=>{
      calls[index]++;
      let body='';for await(const chunk of req)body+=chunk;
      await new Promise(resolve=>setTimeout(resolve,20));
      res.end(JSON.stringify({choices:[{message:{content:'{"translation":"測試敘述。"}'}}]}));
    });
    await new Promise(resolve=>api.listen(0,'127.0.0.1',resolve));
    t.after(()=>{api.closeAllConnections();return new Promise(resolve=>api.close(resolve));});
    return {kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${api.address().port}/v1`,key:'integration-private-'+index};
  }));
  const config=join(directory,'config.json');
  await mkdir(join(directory,'state/data'),{recursive:true});
  await writeFile(config,JSON.stringify({port:0,provider:apis[0]}));
  const service=await start(config,join(directory,'state'));t.after(()=>new Promise(resolve=>service.server.close(resolve)));
  // This fixture selects save scopes directly without a real game's context
  // mailbox. A title-screen status poll would legitimately restore global
  // settings in the middle of a selected region3 assertion.
  service.statusBridge.stop();service.runtimeQueue.stop();
  if(service.statusBridge.running) await service.statusBridge.running;
  const updated=await service.settingsService.handle({id:'pool-apply',action:'save',scope:'save',world:'region3',
    settings:{apiProfiles:['legacy','second'],concurrency:6},profiles:[{id:'legacy',concurrency:3},{id:'second',...apis[1],enabled:true,concurrency:3}]});
  assert.equal(updated.ok,true);
  const broker=await service.selectBroker('zh-Hant','region3');
  await Promise.all(['Unique first tale.','Unique second tale.','Unique third tale.','Unique fourth tale.'].map(text=>broker.translate(text)));
  assert.ok(calls[0]>0 && calls[1]>0);
  assert.equal(broker.provider.poolStats.concurrency,6);
  assert.deepEqual(broker.provider.poolStats.profiles.map(row=>row.id),['legacy','second']);
  assert.ok(!JSON.stringify(broker.provider.poolStats).includes('integration-private'));
  const other=await service.selectBroker('zh-Hant','region4');
  assert.deepEqual(other.provider.poolStats.profiles.map(row=>row.id),['legacy']);
  // A first request burst after a scope change must share one configured pool.
  await service.settingsStore.apply({scope:'save',world:'region3',settings:{concurrency:1}});
  const providers=await Promise.all(Array.from({length:6},async()=>{
    const selected=await service.selectBroker('zh-Hant','region3');return selected.provider;
  }));
  assert.ok(providers.every(provider=>provider===providers[0]));
  await service.settingsService.handle({id:'pool-empty',action:'save',scope:'save',world:'region3',settings:{apiProfiles:[]}});
  assert.equal((await service.selectBroker('zh-Hant','region3')).provider,null);
  await service.settingsService.handle({id:'pool-off',action:'save',scope:'save',world:'region3',settings:{apiEnabled:false}});
  assert.equal((await service.selectBroker('zh-Hant','region3')).provider,null);
});
