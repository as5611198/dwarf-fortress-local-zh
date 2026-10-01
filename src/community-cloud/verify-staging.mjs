// Real HTTPS download into a clean fixture, with staging trust supplied ONLY here.
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {OfficialLibrary,verifyManifest} from '../broker/official-library.mjs';
import {OFFICIAL_TRUST} from '../broker/official-trust.mjs';
import {TranslationBroker} from '../broker/broker.mjs';
const keys=JSON.parse(await readFile(new URL('public-keys.json',import.meta.url),'utf8'));
const trust={...OFFICIAL_TRUST,...keys},endpoint='https://df-zh-consensus-staging.g402111111.workers.dev/manifest.json';
const envelope=Buffer.from(await (await fetch(endpoint)).arrayBuffer());
const manifest=verifyManifest(envelope,trust);assert.ok(manifest.sequence>1);
assert.throws(()=>verifyManifest(envelope,OFFICIAL_TRUST),/unknown/,'Staging key must not be trusted by player builds');
const directory=await mkdtemp(join(tmpdir(),'df-consensus-cloud-'));
const library=new OfficialLibrary({directory,endpoint,trust,canActivate:()=>true,retries:0});
const start=performance.now();await library.load();const loadEmptyMs=performance.now()-start;
const timings={loadEmptyMs};
for(const language of ['zh-Hant','zh-Hans']){
 const status=await library.sync(language);assert.equal(status.phase,'complete');assert.equal(status.entries,language==='zh-Hant'?503:502);timings[language]=status.syncMs;
}
const text='He feels lonely after being unable to socialize.',translation='他因為無法社交而感到孤單。';
const broker=new TranslationBroker({directory,language:'zh-Hant',provider:null});await broker.load();broker.official=library;
assert.equal(await broker.translate(text),translation);assert.equal(broker.stats.accepted,0);
assert.equal(library.lookup(text,'zh-Hans'),undefined,'Traditional community row must not enter Simplified pack');
broker.builtin.set(text,'內建優先');assert.equal(await broker.translate(text),'內建優先');broker.fixed.set(text,'使用者優先');assert.equal(await broker.translate(text),'使用者優先');
assert.equal(library.lookup('Urist feels lonely.','zh-Hant'),undefined);
const offline=new OfficialLibrary({directory,endpoint,trust,canActivate:()=>true,retries:0,fetcher:async()=>{throw Error('offline');}});
const started=performance.now();await offline.load();timings.offlineLoadMs=performance.now()-started;
assert.equal(offline.lookup(text,'zh-Hant'),translation);assert.equal((await offline.sync('zh-Hant')).phase,'error');assert.equal(offline.lookup(text,'zh-Hant'),translation);
const report={passed:true,syntheticConsensus:true,directory,version:manifest.version,sequence:manifest.sequence,entries:{'zh-Hant':503,'zh-Hans':502},timings,
 verified:['real HTTPS signature/hash/content','no API offline Broker result','language separation','builtin and user priority','no private names','offline restart','staging key excluded from player trust']};
await writeFile(new URL('../text-audit/phase2-staging-download.json',import.meta.url),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
