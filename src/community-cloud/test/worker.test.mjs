import test from 'node:test';
import assert from 'node:assert/strict';
import {database,contribution,review,support} from './helpers.mjs';
import {ConsensusStore} from '../src/store.mjs';
const mod=await import('../src/index.mjs').catch(()=>({}));
const env=()=>({DB:database(),HMAC_SECRET:'fixture-hmac-salt',ADMIN_TOKEN:'fixture-operator-token',REVIEW_ENABLED:'true',PUBLISH_ENABLED:'false',AI:{run:async()=>({response:JSON.stringify(Object.fromEntries(Object.entries(review).filter(([k])=>!['approved','retryable','model','policy'].includes(k))))})}});
const request=(body,headers={})=>new Request('https://fixture.example/v1/contributions',{method:'POST',headers:{'content-type':'application/json','CF-Connecting-IP':'192.0.2.10',...headers},body:JSON.stringify(body)});
const batch=()=>({schema:1,deviceId:'a'.repeat(64),batchId:crypto.randomUUID(),entries:[contribution]});
test('Worker accepts safe consent payload and never stores raw device ID or IP',async()=>{
  assert.ok(mod.default);const bindings=env();const response=await mod.default.fetch(request(batch()),bindings,{});assert.equal(response.status,202);
  const stored=bindings.DB.sqlite.prepare('SELECT * FROM supports').get();assert.notEqual(stored.device_hash,'a'.repeat(64));assert.doesNotMatch(stored.network_hash,/192\.0/);
});
test('Worker rejects browser, oversized, unknown fields, names, wrong rules and absent source address',async()=>{
  assert.ok(mod.default);const bindings=env();
  assert.equal((await mod.default.fetch(request(batch(),{origin:'https://evil.example'}),bindings,{})).status,403);
  for(const payload of [{...batch(),settings:{key:'private'}},{...batch(),entries:[{...contribution,text:'Urist feels lonely.'}]},{...batch(),entries:[{...contribution,rules:'df-zh-999'}]},{...batch(),entries:Array(9).fill(contribution)}])
    assert.equal((await mod.default.fetch(request(payload),bindings,{})).status,422);
  assert.equal((await mod.default.fetch(request({...batch(),extra:'x'.repeat(40000)}),bindings,{})).status,413);
  const missing=request(batch());missing.headers.delete('CF-Connecting-IP');assert.equal((await mod.default.fetch(missing,bindings,{})).status,503);
  assert.equal(bindings.DB.sqlite.prepare('SELECT COUNT(*) AS count FROM supports').get().count,0);
});
test('background runner performs actual semantic gate and never approves AI false or partial output',async()=>{
  assert.equal(typeof mod.runPipeline,'function');const bindings=env();const store=new ConsensusStore(bindings.DB);const id=await support(store);
  await mod.runPipeline(bindings);assert.equal((await store.get(id)).state,'approved');
  const rejected=env();rejected.AI.run=async()=>({response:JSON.stringify({...Object.fromEntries(Object.entries(review).filter(([k])=>!['approved','retryable','model','policy'].includes(k))),verdict:'reject',meaning:false})});
  const store2=new ConsensusStore(rejected.DB);const id2=await support(store2);await mod.runPipeline(rejected);assert.equal((await store2.get(id2)).state,'rejected');
});
test('operator endpoints require secret, expose no candidate data through health, and have no testing bypass',async()=>{
  assert.ok(mod.default);const bindings=env();
  assert.equal((await mod.default.fetch(new Request('https://fixture.example/admin/run',{method:'POST',body:'{}'}),bindings,{})).status,403);
  assert.equal((await mod.default.fetch(new Request('https://fixture.example/internal/test',{method:'POST'}),bindings,{})).status,404);
  const response=await mod.default.fetch(new Request('https://fixture.example/health'),bindings,{});assert.equal(response.status,200);assert.doesNotMatch(await response.text(),/fixture-hmac|operator-token|lonely/);
});
