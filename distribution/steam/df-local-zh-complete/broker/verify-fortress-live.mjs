import assert from 'node:assert/strict';
import { readFile,writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join,resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const active=process.argv[2];
assert.ok(active,'Active mod directory required');
const game=resolve(fileURLToPath(new URL('../../',import.meta.url)));
const manifest=JSON.parse(await readFile(new URL('./data/fortress-hover.json',import.meta.url),'utf8'));
const health=async()=>await (await fetch('http://127.0.0.1:19753/health')).json();
const before=await health();
const rows=[];
for(const [text,translation] of Object.entries(manifest.translations)) {
  const response=await fetch('http://127.0.0.1:19753/v2/translate',{method:'POST',
    headers:{'Content-Type':'application/json'},body:JSON.stringify({text}),signal:AbortSignal.timeout(10000)});
  assert.ok(response.ok,`${text}: HTTP ${response.status}`);
  const actual=(await response.json()).translation;
  assert.equal(actual,translation,text);
  rows.push({text,translation:actual});
}
const after=await health();
const files=[...['df-local-zh-runtime.lua','df-local-zh-text-overlay.lua','df-local-zh-hover-text.lua','df-local-zh-test.lua']
  .map(name=>['hack/scripts/'+name,'scripts_modinstalled/'+name]),
  ...['dynamic.mjs','compile-data.mjs','prepare-workshop-package.mjs','data/fortress-ui.csv','data/fortress-hover.json']
    .map(name=>['_localization-work/broker/'+name,'broker/'+name]),
  ['_localization-work/broker/data/fortress-ui.csv','dfi18n-data/simple/zh-Hant/zzzzz-fortress-ui.csv']];
const hashes=[];
for(const [source,target] of files) {
  const hash=async path=>createHash('sha256').update(await readFile(path)).digest('hex');
  const sourceHash=await hash(join(game,source));
  assert.equal(await hash(join(active,target)),sourceHash,target);
  hashes.push({target,sha256:sourceHash});
}
const result={time:new Date().toISOString(),status:'PASS',brokerRows:rows.length,
  providerAcceptedDelta:after.accepted-before.accepted,providerRejectedDelta:after.rejected-before.rejected,
  cacheHitDelta:after.cacheHits-before.cacheHits,hashes,rows};
const log=join(game,'_localization-work/text-audit/fortress-literal-live.json');
await writeFile(log,JSON.stringify(result,null,2)+'\n','utf8');
console.log(JSON.stringify({status:result.status,brokerRows:result.brokerRows,files:hashes.length,
  providerAcceptedDelta:result.providerAcceptedDelta,providerRejectedDelta:result.providerRejectedDelta,
  cacheHitDelta:result.cacheHitDelta,log}));
