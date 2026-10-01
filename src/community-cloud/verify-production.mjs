import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {OfficialLibrary,verifyManifest} from '../broker/official-library.mjs';
import {OFFICIAL_ENDPOINT} from '../broker/official-trust.mjs';
const sha=value=>createHash('sha256').update(value).digest('hex');
const bytes=Buffer.from(await (await fetch(OFFICIAL_ENDPOINT)).arrayBuffer());
assert.equal(sha(bytes),sha(await readFile(new URL('../official-cloud/public/manifest.json',import.meta.url))),'Production baseline must not be contaminated by synthetic staging candidates');
const manifest=verifyManifest(bytes),directory=await mkdtemp(join(tmpdir(),'df-consensus-production-'));
const library=new OfficialLibrary({directory,canActivate:()=>true,retries:0});await library.load();
const timings={};for(const language of ['zh-Hant','zh-Hans']){const value=await library.sync(language);assert.equal(value.phase,'complete');assert.equal(value.entries,502);timings[language]=value.syncMs;}
const offline=new OfficialLibrary({directory,canActivate:()=>true,fetcher:async()=>{throw Error('offline');}});
const start=performance.now();await offline.load();timings.offlineLoadMs=performance.now()-start;
assert.equal(offline.lookup('Health','zh-Hant'),'健康');assert.equal(offline.lookup('Health','zh-Hans'),'健康');
const response=await fetch('https://df-zh-consensus.g402111111.workers.dev/health'),health=await response.json();assert.equal(health.publishEnabled,true);assert.equal(health.reviewEnabled,true);assert.equal(health.staging,false);
const result={passed:true,directory,manifestSha256:sha(bytes),version:manifest.version,entries:{'zh-Hant':502,'zh-Hans':502},timings,health};
await writeFile(new URL('../text-audit/phase2-production-verification.json',import.meta.url),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
