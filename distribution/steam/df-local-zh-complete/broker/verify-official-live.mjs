import {mkdir,writeFile,mkdtemp,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import assert from 'node:assert/strict';
import {OfficialLibrary} from './official-library.mjs';
import {TranslationBroker} from './broker.mjs';
const directory=await mkdtemp(join(tmpdir(),'df-official-real-download-'));
const library=new OfficialLibrary({directory,canActivate:()=>true});await library.load();
const results=[];
for(const language of ['zh-Hant','zh-Hans']) {
  const start=performance.now();const status=await library.sync(language);assert.equal(status.phase,'complete',JSON.stringify(status));assert.equal(status.entries,502);
  const downloadedMs=performance.now()-start;
  const offline=new OfficialLibrary({directory,fetcher:()=>{throw Error('offline fixture: network disabled');},canActivate:()=>true});
  const loadStart=performance.now();await offline.load();const loadedMs=performance.now()-loadStart;
  const broker=new TranslationBroker({directory:join(directory,'ai'),language,provider:null});broker.official=offline;await broker.load();
  const text='She is not distracted after leading an unexciting life.';
  assert.equal(await broker.translate(text),language==='zh-Hant'?'她沒有因為生活平淡無奇而分心。':'她没有因为生活平淡无奇而分心。');
  assert.equal(broker.cache.size,0);assert.equal(broker.stats.accepted,0);
  let hits=0;const queries=performance.now();for(const row of offline.snapshots.get(language).entries) {assert.equal(await broker.translate(row.text),row.translation);hits++;}
  results.push({language,downloadedMs,loadedMs,queryAllMs:performance.now()-queries,hits,status});
}
// Local observed display sources are measured, never uploaded or copied into the corpus.
const observed=resolve('dfhack-config/mods/df-local-zh-complete/data/unit-display-cache.jsonl');
let sampled=0,covered=0,excludedNames=0;
try {
  const seen=new Set();for(const line of (await readFile(observed,'utf8')).split('\n')) {
    let row;try{row=JSON.parse(line)}catch{continue}
    const text=row.text ?? row.source ?? row.original;if(typeof text!=='string' || seen.has(text))continue;seen.add(text);
    if(/\blikes\b/.test(text) && !text.startsWith('{DWARF_NAME}')) {excludedNames++;continue}
    sampled++;if(library.lookup(text,'zh-Hant')!==undefined || library.lookup(text,'zh-Hant',{kind:'entity'})!==undefined)covered++;
  }
}catch{}
await mkdir(resolve('_localization-work/text-audit'),{recursive:true});
const report={directory,results,coverage:{sampled,covered,excludedNames,scope:'unique locally observed unit-display sources; exact official hits only; no universal coverage claim'}};
await writeFile(resolve('_localization-work/text-audit/official-live-download.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
