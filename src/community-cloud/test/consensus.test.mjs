import test from 'node:test';
import assert from 'node:assert/strict';
import {database,contribution,review,support} from './helpers.mjs';
const {ConsensusStore}=await import('../src/store.mjs').catch(()=>({}));
test('three forged devices from the same network do not reach consensus',async()=>{
  assert.equal(typeof ConsensusStore,'function');const store=new ConsensusStore(database());let id;
  for(let i=0;i<3;i++)id=(await store.ingest(contribution,{device:'d'+i,network:'one-network',now:1000})).id;
  assert.equal((await store.get(id)).state,'pending');assert.equal(await store.claimReview(1000),null);
});
test('three separate network signals trigger review, retries and single-device alternatives are deduplicated',async()=>{
  assert.equal(typeof ConsensusStore,'function');const store=new ConsensusStore(database());const id=await support(store);
  const repeat=await store.ingest(contribution,{device:'d0',network:'n0',now:1000});assert.equal(repeat.counted,false);
  const other=await store.ingest({...contribution,translation:'他無法社交，因此覺得孤單。'},{device:'d0',network:'fake-network',now:1000});assert.equal(other.counted,false);
  assert.equal((await store.get(id)).devices,3);assert.equal((await store.get(id)).state,'ready');
  const claim=await store.claimReview(1000);assert.equal(claim.id,id);assert.equal(await store.claimReview(1000),null);
  await store.finishReview(claim,review,2000);assert.equal((await store.get(id)).state,'approved');
});
test('different Chinese never merges, and competing consensus blocks both before approval',async()=>{
  assert.equal(typeof ConsensusStore,'function');const store=new ConsensusStore(database());const first=await support(store);
  const second=await support(store,{...contribution,translation:'他無法社交，因此覺得孤單。'},3,3);
  assert.notEqual(first,second);assert.equal((await store.get(first)).state,'blocked');assert.equal((await store.get(second)).state,'blocked');
  assert.equal(await store.claimReview(1000),null);
});
test('AI day quota and expired leases prevent concurrent duplicate or runaway review',async()=>{
  assert.equal(typeof ConsensusStore,'function');const store=new ConsensusStore(database());await support(store);
  await support(store,{...contribution,text:'She feels lonely after being unable to socialize.',translation:'她因為無法社交而感到孤單。'},3,3);
  const [a,b]=await Promise.all([store.claimReview(1000,1),store.claimReview(1000,1)]);
  assert.equal([a,b].filter(Boolean).length,1);
  assert.equal(await store.claimReview(1000+16*60000,1),null);
  assert.ok(await store.claimReview(86400000+1000,1));
});
test('AI failure stays pending with backoff, reject cannot approve, stale lease cannot finish',async()=>{
  assert.equal(typeof ConsensusStore,'function');const store=new ConsensusStore(database());const id=await support(store);const claim=await store.claimReview(1000);
  await store.finishReview({...claim,owner:'stale'},review,2000);assert.equal((await store.get(id)).state,'reviewing');
  await store.finishReview(claim,{approved:false,retryable:true,verdict:'uncertain',reason:'offline'},2000);assert.equal((await store.get(id)).state,'ready');
  assert.equal(await store.claimReview(2000),null);const retry=await store.claimReview(4000000);
  await store.finishReview(retry,{...review,approved:false,verdict:'reject',meaning:false},4000001);assert.equal((await store.get(id)).state,'rejected');
});
test('publication lease is exclusive, released by owner only and recovers after expiry',async()=>{
  assert.equal(typeof ConsensusStore,'function');const store=new ConsensusStore(database());assert.equal(await store.acquireLease('publish','one',1000,100),true);
  assert.equal(await store.acquireLease('publish','two',1000,100),false);await store.releaseLease('publish','two');
  assert.equal(await store.acquireLease('publish','two',1001,100),false);assert.equal(await store.acquireLease('publish','two',1101,100),true);
});
