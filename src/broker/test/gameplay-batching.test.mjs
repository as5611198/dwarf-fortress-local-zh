import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TranslationBroker} from '../broker.mjs';
import {createBrokerServer} from '../server.mjs';
import {createProvider} from '../provider.mjs';

test('concurrent ordinary game text uses one validated model batch',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-game-batch-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const requests=[];
  const values={'The gate is open.':'大門開著。','The shield is broken.':'盾牌破損了。'};
  const model=createServer(async(req,res)=>{
    let raw='';for await(const part of req) raw+=part;
    const input=JSON.parse(JSON.parse(raw).messages[1].content);
    requests.push(input);
    const output=input.items ? {translations:input.items.map(item=>({id:item.id,translation:values[item.text]}))} :
      {translation:values[input.source]};
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({choices:[{message:{content:JSON.stringify(output)}}]}));
  });
  await new Promise(resolve=>model.listen(0,'127.0.0.1',resolve));
  t.after(()=>{model.closeAllConnections();return new Promise(resolve=>model.close(resolve));});
  const provider=await createProvider({provider:{kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${model.address().port}/v1`}});
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider});
  await broker.load();
  const server=createBrokerServer(broker);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{server.closeAllConnections();return new Promise(resolve=>server.close(resolve));});
  const responses=await Promise.all(Object.keys(values).map(async text=>{
    const response=await fetch(`http://127.0.0.1:${server.address().port}/v2/translate`,{
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});
    assert.equal(response.status,200);
    return (await response.json()).translation;
  }));
  assert.deepEqual(responses,Object.values(values));
  assert.equal(requests.length,1,'short visible texts should share one HTTP round trip');
  assert.equal(requests[0].items.length,2);
  const health=await (await fetch(`http://127.0.0.1:${server.address().port}/health`)).json();
  assert.equal(health.providerBatch.requests,1);
  assert.equal(health.providerBatch.items,2);
});
