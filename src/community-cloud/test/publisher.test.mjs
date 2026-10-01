import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,createHash} from 'node:crypto';
import {database,contribution,review,support,Bucket} from './helpers.mjs';
import {ConsensusStore} from '../src/store.mjs';
import {verifyManifest,validatePackage} from '../../broker/official-library.mjs';
const publisher=await import('../src/publisher.mjs').catch(()=>({}));
const pair=generateKeyPairSync('ed25519'),trust={fixture:pair.publicKey.export({type:'spki',format:'pem'})};
const hash=b=>createHash('sha256').update(b).digest('hex');
async function setup(){
  const bucket=new Bucket(),store=new ConsensusStore(database());
  const manifest={schema:1,version:'base',rules:'df-zh-3',sequence:1,publishedAt:'2026-10-01T00:00:00Z',withdrawn:[],packages:[]};
  for(const language of ['zh-Hant','zh-Hans']){
    const pack=Buffer.from(JSON.stringify({schema:1,version:'base',language,rules:'df-zh-3',entries:[{text:'Health',translation:'健康',context:'general',kind:'exact',origin:'vanilla',source:'owned',review:'reviewed'}]})+'\n');
    const path=`releases/base/${language}.json`;await bucket.put(path,pack);manifest.packages.push({language,path,entries:1,bytes:pack.length,sha256:hash(pack),format:'json',delta:null});
  }
  const payload=Buffer.from(JSON.stringify(manifest));await bucket.put('manifest.json',JSON.stringify({keyId:'fixture',payload:payload.toString('base64'),signature:sign(null,payload,pair.privateKey).toString('base64')}));
  return {store,bucket,env:{DB:store.db,OFFICIAL:bucket,TRUST_JSON:JSON.stringify(trust),SIGNING_KEY_ID:'fixture',SIGNING_KEY_PEM:pair.privateKey.export({type:'pkcs8',format:'pem'}),PUBLISH_ENABLED:'true'}};
}
async function approve(store,row=contribution){const id=await support(store,row);const claim=await store.claimReview(1000);await store.finishReview(claim,review,2000);return id;}
test('automatic publisher signs complete language packages and marks AI provenance, preserving owned rows',async()=>{
  assert.equal(typeof publisher.publishApproved,'function');const {store,bucket,env}=await setup();await approve(store);
  const result=await publisher.publishApproved(env,store,4000000);assert.equal(result.published,true);
  const control=verifyManifest(bucket.values.get('manifest.json'),trust);assert.equal(control.sequence,2);
  const descriptor=control.packages.find(p=>p.language==='zh-Hant');const pack=validatePackage(bucket.values.get(descriptor.path),descriptor,control);
  assert.equal(pack.entries.length,2);assert.equal(pack.entries.find(r=>r.text===contribution.text).review,'ai-reviewed');
  assert.equal(control.packages.find(p=>p.language==='zh-Hans').entries,1);
  assert.equal((await publisher.publishApproved(env,store,8000000)).published,false);
});
test('R2 interrupted publication retains the old signed manifest and permits a later higher-sequence retry',async()=>{
  assert.equal(typeof publisher.publishApproved,'function');const {store,bucket,env}=await setup();await approve(store);
  const old=Buffer.from(bucket.values.get('manifest.json'));bucket.failKey='manifest.json';
  await assert.rejects(()=>publisher.publishApproved(env,store,4000000));assert.deepEqual(bucket.values.get('manifest.json'),old);
  bucket.failKey=null;assert.equal((await publisher.publishApproved(env,store,5000000)).published,true);
  assert.ok(verifyManifest(bucket.values.get('manifest.json'),trust).sequence>2);
});
test('withdrawal removes community rows, adds signed revocation and preserves original reviewed corpus',async()=>{
  assert.equal(typeof publisher.publishApproved,'function');const {store,bucket,env}=await setup();const id=await approve(store);
  const first=await publisher.publishApproved(env,store,4000000);await store.withdraw(id,'semantic regression',5000000);
  const next=await publisher.publishApproved(env,store,8000000);assert.equal(next.published,true);
  const control=verifyManifest(bucket.values.get('manifest.json'),trust);assert.ok(control.withdrawn.includes(first.version));
  for(const p of control.packages)assert.equal(validatePackage(bucket.values.get(p.path),p,control).entries.length,1);
});
test('publish cannot replace trusted reviewed Health or run without explicit enabling',async()=>{
  assert.equal(typeof publisher.publishApproved,'function');const {store,bucket,env}=await setup();await approve(store,{...contribution,text:'Health',translation:'生命值'});
  assert.equal((await publisher.publishApproved({...env,PUBLISH_ENABLED:'false'},store,4000000)).published,false);
  await publisher.publishApproved(env,store,4000000);const control=verifyManifest(bucket.values.get('manifest.json'),trust);
  const p=control.packages[0];assert.equal(validatePackage(bucket.values.get(p.path),p,control).entries[0].translation,'健康');
});
test('a D1 provenance write failure cannot activate an untracked release',async()=>{
 const {store,bucket,env}=await setup();await approve(store);const old=Buffer.from(bucket.values.get('manifest.json'));
 store.markEntriesPublished=async()=>{throw Error('D1 write failure');};
 await assert.rejects(()=>publisher.publishApproved(env,store,4000000));assert.deepEqual(bucket.values.get('manifest.json'),old);
});
