import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as module from '../settings.mjs';
import { createServer } from 'node:http';

test('explicit prompt paste retrieves Unicode without changing settings',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-prompt-paste-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  const store=new module.SettingsStore(directory);await store.load();
  const before=JSON.stringify(store.document);
  const service=new module.SettingsService(store,{readClipboard:async()=> '肉盔菇菌種\n保持術語一致。'});
  const result=await service.handle({id:'clipboard-fixture',action:'clipboard'});
  assert.equal(result.ok,true);assert.equal(result.text,'肉盔菇菌種\n保持術語一致。');
  assert.equal(JSON.stringify(store.document),before);
});

test('settings mailbox publishes completion on a file event and removes request secrets', async () => {
  assert.equal(typeof module.SettingsService,'function','event driven settings service required');
  const directory=await mkdtemp(join(tmpdir(),'df-settings-events-'));
  const store=new module.SettingsStore(directory);await store.load();
  const service=new module.SettingsService(store,{onApply:async()=>{}});
  try {
    service.start();
    const complete=new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('settings event deadline')),3000);
      service.onComplete=row=>{clearTimeout(timer);resolve(row);};
    });
    await module.atomicJson(join(directory,'settings-request.json'),{id:'fixture-1',action:'save',
      scope:'global',settings:{language:'zh-Hans'},profile:{id:'fixture',enabled:true,
        baseUrl:'http://localhost:1234/v1',model:'fixture',key:'private-mailbox-key'}});
    const row=await complete;
    assert.equal(row.ok,true);assert.equal(row.snapshot.effective.language,'zh-Hans');
    assert.ok(!JSON.stringify(row).includes('private-mailbox-key'));
    assert.ok(!(await readFile(join(directory,'settings-request.json'),'utf8')).includes('private-mailbox-key'));
  } finally { service.stop();await rm(directory,{recursive:true,force:true}); }
});

test('connection test exercises the chosen draft API profile without storing it', async () => {
  assert.equal(typeof module.SettingsService,'function');
  const directory=await mkdtemp(join(tmpdir(),'df-settings-connection-'));
  let calls=0;
  const api=createServer(async(req,res)=>{
    let body='';for await(const chunk of req) body+=chunk;
    assert.equal(req.url,'/v1/chat/completions');
    assert.equal(JSON.parse(body).model,'fixture-model');calls++;
    res.end(JSON.stringify({choices:[{message:{content:'{"translation":"連線測試。"}'}}]}));
  });
  await new Promise(resolve=>api.listen(0,'127.0.0.1',resolve));
  try {
    const store=new module.SettingsStore(directory);await store.load();
    const service=new module.SettingsService(store);
    const result=await service.handle({id:'fixture-2',action:'test',world:'region3',
      profile:{id:'draft',enabled:true,baseUrl:`http://127.0.0.1:${api.address().port}/v1`,model:'fixture-model',key:'fixture-key'}});
    assert.equal(result.ok,true);assert.equal(calls,1);
    assert.ok(!store.profiles.profiles.draft);
    assert.ok(!JSON.stringify(result).includes('fixture-key'));
  } finally {await new Promise(resolve=>api.close(resolve));await rm(directory,{recursive:true,force:true});}
});
