import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,mkdir,copyFile,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {OfficialLibrary,verifyManifest} from '../broker/official-library.mjs';
import {OFFICIAL_TRUST} from '../broker/official-trust.mjs';
const previous=JSON.parse(await readFile(new URL('../text-audit/phase2-staging-download.json',import.meta.url),'utf8'));
const keys=JSON.parse(await readFile(new URL('public-keys.json',import.meta.url),'utf8')),trust={...OFFICIAL_TRUST,...keys};
const endpoint='https://df-zh-consensus-staging.g402111111.workers.dev/manifest.json';
const envelope=Buffer.from(await (await fetch(endpoint)).arrayBuffer()),manifest=verifyManifest(envelope,trust);
assert.ok(manifest.withdrawn.includes(previous.version));assert.ok(manifest.sequence>previous.sequence);
// Recreate the previously verified installation in a fresh isolated state,
// so this verification can be repeated after the first run changed its pointer.
const directory=await mkdtemp(join(tmpdir(),'df-consensus-withdraw-'));await mkdir(join(directory,'official'));
const priorEnvelope=await readFile(join(previous.directory,'official',`${previous.version}-${previous.sequence}.manifest.json`));
const prior=verifyManifest(priorEnvelope,trust),state={schema:1,highestSequence:prior.sequence,languages:{}};
for(const descriptor of prior.packages){
 const packageFile=`${prior.version}-${descriptor.language}-${descriptor.sha256}.json`,manifestFile=`${prior.version}-${prior.sequence}.manifest.json`;
 await copyFile(join(previous.directory,'official',packageFile),join(directory,'official',packageFile));
 await writeFile(join(directory,'official',manifestFile),priorEnvelope);
 state.languages[descriptor.language]={active:{version:prior.version,sequence:prior.sequence,sha256:descriptor.sha256,packageFile,manifestFile}};
}
await writeFile(join(directory,'official','state.json'),JSON.stringify(state));
const library=new OfficialLibrary({directory,endpoint,trust,canActivate:()=>false,retries:0});await library.load();
const source='He feels lonely after being unable to socialize.';assert.ok(library.lookup(source,'zh-Hant'));
assert.equal((await library.sync('zh-Hant')).phase,'pending');assert.ok(library.lookup(source,'zh-Hant'),'Existing description snapshot remains stable');
const next=new OfficialLibrary({directory,endpoint,trust,canActivate:()=>true,retries:0});await next.load();
assert.equal(next.lookup(source,'zh-Hant'),undefined);assert.equal(next.status('zh-Hant').entries,502);
assert.equal(next.state.languages['zh-Hant'].previous?.version,undefined,'Withdrawn version is unavailable as fallback');
const result={passed:true,previous:previous.version,replacement:manifest.version,sequence:manifest.sequence,entries:502,pendingPreservesSnapshot:true,withdrawnFallbackRemoved:true};
await writeFile(new URL('../text-audit/phase2-staging-withdrawal.json',import.meta.url),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
