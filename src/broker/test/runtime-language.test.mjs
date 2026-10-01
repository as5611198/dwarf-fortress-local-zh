import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { RuntimeQueue } from '../runtime-queue.mjs';

test('identical requests in two languages publish separate durable response keys', async () => {
  const directory=await mkdtemp(join(tmpdir(),'df-language-'));
  try {
    await writeFile(join(directory,'runtime-requests.jsonl'),[
      {world:'region3',text:'An iron goblet.',language:'zh-Hant',priority:'foreground'},
      {world:'region3',text:'An iron goblet.',language:'zh-Hans',priority:'foreground'},
    ].map(row=>JSON.stringify(row)+'\n').join(''));
    const queue=new RuntimeQueue({directory,currentWorld:async()=>'region3',
      translate:async(_,row)=>row.language==='zh-Hans' ? '鐵製高腳杯。'.replaceAll('鐵','铁').replaceAll('製','制').replaceAll('腳','脚') : '鐵製高腳杯。'});
    await queue.load();await queue.drain();
    const rows=(await readFile(join(directory,'runtime-responses.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(rows.length,2,'language must be part of job identity');
    assert.notEqual(rows[0].key,rows[1].key);
    assert.deepEqual(new Set(rows.map(row=>row.language)),new Set(['zh-Hant','zh-Hans']));
    const restored=new RuntimeQueue({directory,currentWorld:async()=>'region3',translate:()=>{throw new Error('cache resubmitted');}});
    await restored.load();await restored.drain();assert.equal(restored.seen.size,2);
  } finally {await rm(directory,{recursive:true,force:true});}
});
