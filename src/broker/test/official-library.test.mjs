import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {generateKeyPairSync,createHash,sign} from 'node:crypto';
import {OfficialLibrary,validatePackage,verifyManifest,MAX_PACKAGE_BYTES} from '../official-library.mjs';
import {TranslationBroker} from '../broker.mjs';
import {applyStaticDictionaryRows} from '../server.mjs';
import {cacheKey,POLICY_VERSION} from '../safety.mjs';
import {SettingsStore,SettingsService} from '../settings.mjs';

const keys=generateKeyPairSync('ed25519');
const trust={fixture:keys.publicKey.export({type:'spki',format:'pem'})};
const entry=(text='She is not distracted after leading an unexciting life.',translation='她沒有因為生活平淡無奇而分心。')=>({text,translation,context:'general',kind:'exact',origin:'vanilla',source:'owned-review',review:'reviewed'});
function fixture(sequence=1,entries=[entry()],language='zh-Hant') {
  const version=`test-${sequence}`;
  const pack=Buffer.from(JSON.stringify({schema:1,version,language,rules:POLICY_VERSION,entries}));
  const payload={schema:1,sequence,version,rules:POLICY_VERSION,publishedAt:'2026-10-01T00:00:00Z',withdrawn:[],packages:[{language,path:`releases/${version}/${language}.json`,entries:entries.length,bytes:pack.length,sha256:createHash('sha256').update(pack).digest('hex'),format:'json',delta:null}]};
  const bytes=Buffer.from(JSON.stringify(payload));
  const envelope=Buffer.from(JSON.stringify({keyId:'fixture',payload:bytes.toString('base64'),signature:sign(null,bytes,keys.privateKey).toString('base64')}));
  return {payload,pack,envelope};
}
function resign(f) {
  const bytes=Buffer.from(JSON.stringify(f.payload));f.envelope=Buffer.from(JSON.stringify({keyId:'fixture',payload:bytes.toString('base64'),signature:sign(null,bytes,keys.privateKey).toString('base64')}));return f;
}
async function setup(t,{canActivate=()=>true,...options}={}) {
  const directory=await mkdtemp(join(tmpdir(),'df-official-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  let remote=fixture(),calls=0;
  const fetcher=async(url)=>{calls++;return new Response(String(url).endsWith('manifest.json')?remote.envelope:remote.pack);};
  const library=new OfficialLibrary({directory,endpoint:'https://fixture.example/manifest.json',trust,fetcher,canActivate,retryBaseMs:1,...options});
  await library.load();
  return {directory,library,setRemote:value=>remote=value,calls:()=>calls};
}
test('signed install works without AI, offline restart, language isolation and source marker',async t=>{
  const {library,directory}=await setup(t);await library.sync('zh-Hant');
  const broker=new TranslationBroker({directory:join(directory,'ai'),language:'zh-Hant',provider:null});await broker.load();broker.official=library;
  assert.equal(await broker.translate(entry().text),entry().translation);
  assert.equal(library.lookup(entry().text,'zh-Hans'),undefined);
  assert.equal(library.status('zh-Hant').entries,1);
  const offline=new OfficialLibrary({directory,endpoint:'https://fixture.example/manifest.json',trust,fetcher:()=>{throw Error('offline');}});
  await offline.load();assert.equal(offline.lookup(entry().text,'zh-Hant'),entry().translation);
  await offline.sync('zh-Hant');assert.equal(offline.lookup(entry().text,'zh-Hant'),entry().translation);
});
test('user pins and builtins beat official and model; late model cannot replace official',async t=>{
  const {library,directory}=await setup(t);await library.sync('zh-Hant');
  const broker=new TranslationBroker({directory,language:'zh-Hant'});broker.official=library;
  broker.cache.set(cacheKey(entry().text,'zh-Hant'),'模型譯文');
  assert.equal(broker.peekCached(entry().text),entry().translation);
  const markup='[P][C:7:0:0]'+entry().text;broker.cache.set(cacheKey(markup,'zh-Hant'),'[P][C:7:0:0]舊模型。');
  assert.equal(await broker.translate(markup),'[P][C:7:0:0]'+entry().translation);
  applyStaticDictionaryRows(broker,[{text:entry().text,translation:'內建校正'}]);assert.equal(await broker.translate(entry().text),'內建校正');
  broker.fixed.set(entry().text,'使用者固定校正');assert.equal(await broker.translate(entry().text),'使用者固定校正');
});
test('untrusted signatures, hash, incompatible rules, malformed content preserve active',async t=>{
  const {library,setRemote}=await setup(t);await library.sync('zh-Hant');
  const bad=fixture(2);bad.pack=Buffer.from('corrupt');setRemote(bad);await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').installedVersion,'test-1');
  const forged=fixture(2);const env=JSON.parse(forged.envelope);env.signature=Buffer.alloc(64).toString('base64');forged.envelope=Buffer.from(JSON.stringify(env));setRemote(forged);await library.sync('zh-Hant');assert.equal(library.lookup(entry().text,'zh-Hant'),entry().translation);
  assert.throws(()=>verifyManifest(forged.envelope,trust),/signature/);
  assert.throws(()=>validatePackage(Buffer.from('{'),fixture().payload.packages[0],fixture().payload));
  const invalid={...JSON.parse(fixture().pack),rules:'future'};assert.throws(()=>validatePackage(Buffer.from(JSON.stringify(invalid)),fixture().payload.packages[0],fixture().payload));
});
test('unsafe names, aliases, fragments and template types rejected',()=>{
  for(const text of ['World: Enramul','DFLIVE_abcd','L123abc____','Folder: region1','He is not distracted after being unable to pray to']) {
    const f=fixture(1,[entry(text,'錯誤共享名稱')]);assert.throws(()=>validatePackage(f.pack,f.payload.packages[0],f.payload),text);
  }
  const f=fixture(1,[{...entry('{DWARF_NAME} likes chicory.','{DWARF_NAME}喜歡菊苣。'),kind:'entity'}]);
  assert.equal(validatePackage(f.pack,f.payload.packages[0],f.payload).entries.length,1);
});
test('deduplicated background download remains pending until safe restart',async t=>{
  let safe=true;const {library,directory,setRemote,calls}=await setup(t,{canActivate:()=>safe});await library.sync('zh-Hant');safe=false;
  setRemote(fixture(2,[entry(entry().text,'新版通用譯文')]));const before=calls();await Promise.all([library.sync('zh-Hant'),library.sync('zh-Hant')]);assert.equal(calls()-before,2);
  assert.equal(library.status('zh-Hant').phase,'pending');assert.equal(library.lookup(entry().text,'zh-Hant'),entry().translation);
  const next=new OfficialLibrary({directory,trust,canActivate:()=>true});await next.load();assert.equal(next.lookup(entry().text,'zh-Hant'),'新版通用譯文');
});
test('anti rollback, signed withdrawal and previous version recovery',async t=>{
  const {library,setRemote,directory}=await setup(t);await library.sync('zh-Hant');setRemote(fixture(2));await library.sync('zh-Hant');setRemote(fixture(1));await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').installedVersion,'test-2');
  const state=JSON.parse(await readFile(join(directory,'official/state.json')));await writeFile(join(directory,'official',state.languages['zh-Hant'].active.packageFile),'{broken');
  const next=new OfficialLibrary({directory,trust});await next.load();assert.equal(next.status('zh-Hant').installedVersion,'test-1');assert.equal(next.state.highestSequence,2);
});
test('interrupted stream and disk failure retain the prior snapshot',async t=>{
  const {library,setRemote}=await setup(t);await library.sync('zh-Hant');setRemote(fixture(2));
  library.writeFile=async()=>{throw Object.assign(Error('disk failure'),{code:'ENOSPC'});};await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').installedVersion,'test-1');
  library.fetcher=async()=>new Response(new ReadableStream({start(controller){controller.enqueue(new Uint8Array([123]));controller.error(Error('disconnected'));}}));
  await library.sync('zh-Hant');assert.equal(library.lookup(entry().text,'zh-Hant'),entry().translation);
});
test('signed withdrawal replaces a bad release and never recovers the withdrawn previous',async t=>{
  const {library,setRemote,directory}=await setup(t);await library.sync('zh-Hant');
  const replacement=fixture(2);replacement.payload.withdrawn=['test-1'];setRemote(resign(replacement));await library.sync('zh-Hant');
  assert.equal(library.state.languages['zh-Hant'].previous,undefined);
  await writeFile(join(directory,'official',library.state.languages['zh-Hant'].active.packageFile),'{');
  const next=new OfficialLibrary({directory,trust});await next.load();assert.equal(next.lookup(entry().text,'zh-Hant'),undefined);
  assert.equal(next.state.highestSequence,2);
});
test('withdrawal staged during gameplay cannot resurrect a revoked fallback at a safe restart',async t=>{
  let safe=true;const {library,setRemote,directory}=await setup(t,{canActivate:()=>safe});await library.sync('zh-Hant');safe=false;
  const replacement=fixture(2);replacement.payload.withdrawn=['test-1'];setRemote(resign(replacement));await library.sync('zh-Hant');
  assert.equal(library.status('zh-Hant').phase,'pending');assert.equal(library.lookup(entry().text,'zh-Hant'),entry().translation);
  const next=new OfficialLibrary({directory,trust,canActivate:()=>true});await next.load();assert.equal(next.state.languages['zh-Hant'].previous,undefined);
  await writeFile(join(directory,'official',next.state.languages['zh-Hant'].active.packageFile),'{broken');
  const broken=new OfficialLibrary({directory,trust,canActivate:()=>true});await broken.load();assert.equal(broken.lookup(entry().text,'zh-Hant'),undefined);
});
test('corrupt staged replacement still honors its signed withdrawal of the active release',async t=>{
  let safe=true;const {library,setRemote,directory}=await setup(t,{canActivate:()=>safe});await library.sync('zh-Hant');safe=false;
  const replacement=fixture(2);replacement.payload.withdrawn=['test-1'];setRemote(resign(replacement));await library.sync('zh-Hant');
  await writeFile(join(directory,'official',library.state.languages['zh-Hant'].pending.packageFile),'{broken');
  const next=new OfficialLibrary({directory,trust,canActivate:()=>true});await next.load();assert.equal(next.lookup(entry().text,'zh-Hant'),undefined);
});
test('signed incompatible rules, invalid content, oversized descriptors and HTTP are rejected',async t=>{
  const {library,setRemote}=await setup(t);await library.sync('zh-Hant');
  const future=fixture(2);future.payload.rules='future';setRemote(resign(future));await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').installedVersion,'test-1');
  const unsafe=fixture(2,[entry('DFLIVE_private','錯誤資料')]);setRemote(unsafe);await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').installedVersion,'test-1');
  const large=fixture(2);large.payload.packages[0].bytes=MAX_PACKAGE_BYTES+1;assert.throws(()=>verifyManifest(resign(large).envelope,trust),/metadata/);
  library.endpoint='http://fixture.example/manifest.json';await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').installedVersion,'test-1');
});
test('download toggle scope, cancel, sync acknowledgements and startup preserve private bytes',async t=>{
  const {directory}=await setup(t);const store=new SettingsStore(directory);await store.load();
  await store.apply({scope:'global',settings:{officialAutoDownload:false}});
  await store.apply({scope:'save',world:'region-fixture',settings:{officialAutoDownload:true}});
  assert.equal(store.effective('').officialAutoDownload,false);assert.equal(store.effective('region-fixture').officialAutoDownload,true);
  const before=await readFile(join(directory,'settings.json'));const keyBefore=await readFile(join(directory,'api-profiles.private.json'));
  const draft={...store.effective(''),officialAutoDownload:true};assert.equal(store.effective('').officialAutoDownload,false);assert.equal(draft.officialAutoDownload,true);
  let synced;const service=new SettingsService(store,{onSync:language=>synced=language});
  const result=await service.handle({id:'sync-fixture',action:'official-sync',language:'zh-Hans'});assert.equal(result.ok,true);assert.equal(result.snapshot,undefined);assert.equal(synced,'zh-Hans');
  const next=new SettingsStore(directory);await next.load();assert.deepEqual(await readFile(join(directory,'settings.json')),before);assert.deepEqual(await readFile(join(directory,'api-profiles.private.json')),keyBefore);
});
test('a late AI completion and clearing AI cache do not alter official lookup',async t=>{
  const {library,directory}=await setup(t);let resolve;const promise=new Promise(r=>resolve=r);
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:()=>promise});
  const work=broker.translate(entry().text);await new Promise(r=>setImmediate(r));await library.sync('zh-Hant');broker.official=library;
  resolve('晚到模型結果。');assert.equal(await work,entry().translation);broker.cache.clear();assert.equal(await broker.translate(entry().text),entry().translation);
});
test('stalled fetch and stalled response body have bounded deadlines',async t=>{
  const {library}=await setup(t,{timeoutMs:25,retries:0});
  library.fetcher=()=>new Promise(()=>{});const begin=Date.now();await library.sync('zh-Hant');assert.ok(Date.now()-begin<500);assert.equal(library.status('zh-Hant').phase,'error');
  library.fetcher=async()=>new Response(new ReadableStream({start(){}}));await library.sync('zh-Hant');assert.equal(library.status('zh-Hant').phase,'error');
});


test('clear removes downloaded bilingual packages and permits same release reinstall without rollback',async t=>{
  const {library,directory,setRemote}=await setup(t);
  await library.sync('zh-Hant');
  const current=fixture(2,undefined,'zh-Hans');setRemote(current);await library.sync('zh-Hans');
  const files=Object.values(library.state.languages).map(row=>row.active.packageFile);
  await writeFile(join(directory,'translations.jsonl'),'private AI fixture');
  await library.clear();
  assert.equal(library.status('zh-Hant').entries,0);
  assert.equal(library.status('zh-Hans').entries,0);
  assert.equal(library.status('zh-Hant').phase,'cleared');
  assert.equal(library.lookup(entry().text,'zh-Hant'),undefined);
  for(const file of files)await assert.rejects(readFile(join(directory,'official',file)),{code:'ENOENT'});
  assert.equal(await readFile(join(directory,'translations.jsonl'),'utf8'),'private AI fixture');
  const next=new OfficialLibrary({directory,trust,canActivate:()=>true,fetcher:library.fetcher,retries:0});
  await next.load();assert.equal(next.state.highestSequence,2);assert.equal(next.status('zh-Hans').entries,0);
  await next.sync('zh-Hans');assert.equal(next.status('zh-Hans').entries,1);
  setRemote(fixture());await next.sync('zh-Hant');assert.equal(next.status('zh-Hant').phase,'error');
  assert.equal(next.status('zh-Hant').entries,0);
});

test('clear waits for in-flight download and suppresses queued language sync',async t=>{
  assert.equal(typeof OfficialLibrary.prototype.clear,'function');
  const {library,directory}=await setup(t);
  const remote=fixture();let release,started;
  const entered=new Promise(resolve=>started=resolve);
  library.fetcher=async url=>{if(String(url).endsWith('manifest.json')){started();await new Promise(resolve=>release=resolve);}return new Response(String(url).endsWith('manifest.json')?remote.envelope:remote.pack);};
  const running=library.sync('zh-Hant');await entered;
  const queued=library.sync('zh-Hans');const clearing=library.clear();release();
  await Promise.all([running,queued,clearing]);
  assert.deepEqual(library.state.languages,{});assert.equal(library.status('zh-Hant').entries,0);
  const disk=JSON.parse(await readFile(join(directory,'official/state.json')));assert.deepEqual(disk.languages,{});
});
