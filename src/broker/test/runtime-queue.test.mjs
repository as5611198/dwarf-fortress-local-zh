import test from 'node:test';
import assert from 'node:assert/strict';
import { appendFile, mkdtemp, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { RuntimeQueue } from '../runtime-queue.mjs';

test('cached text completes while an earlier AI request still occupies the worker', async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-runtime-cache-priority-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  let release;
  const slow=new Promise(resolve=>{release=resolve;});
  const calls=[];
  const queue=new RuntimeQueue({directory,currentWorld:()=> 'region3',
    limits:()=>({concurrency:1,maxRetries:0,retryBaseMs:1000}),
    translate:async source=>{calls.push(source);await slow;return '稍後才翻譯的內容';},
    lookupCached:source=>source==='Known dwarf text' ? '已快取的矮人文字' : undefined});
  t.after(()=>release());
  await queue.load();
  await appendFile(queue.requests,JSON.stringify({world:'region3',text:'Unknown dwarf text'})+'\n');
  await queue.ingest();
  queue.dispatch();
  assert.equal(queue.activeJobs.size,1);
  await appendFile(queue.requests,JSON.stringify({world:'region3',text:'Known dwarf text'})+'\n');
  await queue.ingest();
  const content=await readFile(queue.responses,'utf8').catch(error=>{
    if(error.code==='ENOENT') return '';
    throw error;
  });
  assert.match(content,/已快取的矮人文字/,
    'The cache hit must be published before the unrelated AI job completes');
  assert.deepEqual(calls,['Unknown dwarf text']);
  release();
  await Promise.all([...queue.activeJobs.values()].map(job=>job.work));
});

test('cached lookup is isolated by world and skips identity-bound requests', async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-runtime-cache-scope-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const lookedUp=[];
  const queue=new RuntimeQueue({directory,currentWorld:()=> 'region3',
    lookupCached:(source,row)=>{lookedUp.push([source,row.world]);return '快取譯文';},
    translate:async()=> '依身分翻譯的文字'});
  await queue.load();
  await appendFile(queue.requests,[
    {world:'region2',text:'Old world text'},
    {world:'region3',text:'Figure description',figureId:7},
    {world:'region3',text:'Known plain text'},
  ].map(row=>JSON.stringify(row)).join('\n')+'\n');
  await queue.drain();
  assert.deepEqual(lookedUp,[['Known plain text','region3']]);
  const rows=(await readFile(queue.responses,'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(rows.find(row=>row.text==='Known plain text')?.translation,'快取譯文');
  assert.equal(rows.find(row=>row.text==='Figure description')?.translation,'依身分翻譯的文字');
  assert.equal(rows.some(row=>row.world==='region2'),false);
});

test('rich runtime results preserve validated links across helper restart', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-rich-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const row = {world: 'region1', kind: 'legends-paragraph', subjectId: 20,
    text: '{{DFL0}} arrived in 12.', links: [{type: 0, id: 20, text: 'Vadane'}]};
  const create = () => new RuntimeQueue({directory, currentWorld: () => 'region1',
    translate: async () => ({translation: '{{DFL0}}於12年抵達。', links: [{translation: '荒霧瓦丹'}]})});
  const queue = create();
  await queue.load();
  await appendFile(queue.requests, JSON.stringify(row) + '\n');
  await queue.drain();
  const result = JSON.parse((await readFile(queue.responses, 'utf8')).trim());
  assert.equal(result.kind, 'legends-paragraph');
  assert.deepEqual(result.requestLinks, row.links);
  assert.deepEqual(result.links, [{translation: '荒霧瓦丹'}]);
  const restarted = create();
  await restarted.load();
  await restarted.drain();
  assert.equal(restarted.stats.attempted, 0);
});

test('figure captions retain identity and cannot reuse generic native responses', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-caption-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const calls = [];
  const queue = new RuntimeQueue({ directory, currentWorld: () => 'region1',
    translate: async (text, row = {}) => {
      calls.push(row);
      return row.figureId === 20 ? '瓦達內，「瓦達內」，女性大鵬' : '瓦達內，「瓦丹」，雌性大鵬';
    } });
  await queue.load();
  const base = { world: 'region1', text: 'Two figure aliases, female roc' };
  await appendFile(queue.requests, JSON.stringify(base) + '\n');
  await queue.drain();
  await appendFile(queue.requests, JSON.stringify({ ...base, figureId: 20 }) + '\n');
  await queue.drain();
  const responses = (await readFile(queue.responses, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(responses.length, 2);
  assert.equal(calls[1].figureId, 20);
  assert.equal(responses[1].figureId, 20);
  assert.notEqual(responses[0].key, responses[1].key);
  const restarted = new RuntimeQueue({ directory, currentWorld: () => 'region1',
    translate: () => { throw new Error('already composed'); } });
  await restarted.load();
  await restarted.drain();
  assert.equal(restarted.stats.attempted, 0);
});

test('runtime queue translates complete requests once and isolates worlds', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-queue-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let world = 'region2';
  const calls = [];
  const translate = async source => { calls.push(source); return '凡世邪惡'; };
  const queue = new RuntimeQueue({ directory, translate, currentWorld: () => world });
  await queue.load();
  const requestPath = join(directory, 'runtime-requests.jsonl');
  const responsePath = join(directory, 'runtime-responses.jsonl');
  const request = (source, requestWorld = world) => JSON.stringify({ world: requestWorld, text: source }) + '\n';

  await appendFile(requestPath, request('The Mortal Immorality') +
    request('The Mortal Immorality') + request('Old world name', 'region1') +
    '{"world":"region2","text":"Incomplete', 'utf8');
  await queue.drain();
  assert.deepEqual(calls, ['The Mortal Immorality']);
  let responses = (await readFile(responsePath, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(responses.length, 1);
  assert.equal(responses[0].translation, '凡世邪惡');
  assert.match(responses[0].key, /^DFLIVE_[0-9a-f]{64}$/);
  assert.equal(responses[0].world, 'region2');

  await appendFile(requestPath, ' name"}\n', 'utf8');
  await queue.drain();
  assert.deepEqual(calls, ['The Mortal Immorality', 'Incomplete name']);

  const restarted = new RuntimeQueue({ directory, translate, currentWorld: () => world });
  await restarted.load();
  await restarted.drain();
  assert.equal(calls.length, 2);
  world = 'region1';
  await appendFile(requestPath, request('The Mortal Immorality'), 'utf8');
  await restarted.drain();
  responses = (await readFile(responsePath, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(responses.length, 3);
  assert.notEqual(responses[0].key, responses[2].key);
});

test('idle ingestion reads only appended request bytes and accepts split UTF-8 rows', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-tail-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const queue = new RuntimeQueue({ directory, currentWorld: () => 'region3',
    translate: async () => '中文' });
  const first = JSON.stringify({ world: 'region3', text: 'First request' }) + '\n';
  await appendFile(queue.requests, first);
  await queue.ingest();
  assert.equal(queue.stats.requestBytesRead, Buffer.byteLength(first));
  for (let i = 0; i < 20; i++) await queue.ingest();
  assert.equal(queue.stats.requestBytesRead, Buffer.byteLength(first),
    'Idle ticks must not reread the historical request log');
  const second = Buffer.from(JSON.stringify({ world: 'region3', text: '花崗岩 blocks' }) + '\n');
  const split = second.indexOf(Buffer.from('花')[0]) + 1;
  await appendFile(queue.requests, second.subarray(0, split));
  await queue.ingest();
  assert.equal(queue.jobs.size, 1, 'An incomplete UTF-8 row must remain pending');
  await appendFile(queue.requests, second.subarray(split));
  await queue.ingest();
  assert.equal(queue.jobs.size, 2);
  assert.equal(queue.stats.requestBytesRead, Buffer.byteLength(first) + second.length);
});

test('request cursor resets after truncation, same-size rewrite, and replacement', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-reset-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const queue = new RuntimeQueue({ directory, currentWorld: () => 'region3',
    translate: async () => '中文' });
  const row = text => JSON.stringify({ world: 'region3', text }) + '\n';
  const original = row('Original request');
  await writeFile(queue.requests, original);
  await queue.ingest();
  assert.equal(queue.jobs.size, 1);

  await writeFile(queue.requests, row('Short'));
  await queue.ingest();
  assert.equal(queue.jobs.size, 2, 'Truncated logs must be read from byte zero');

  const sameSize = row('Other');
  assert.equal(sameSize.length, row('Short').length);
  await writeFile(queue.requests, sameSize);
  await queue.ingest();
  assert.equal(queue.jobs.size, 3, 'A same-size rewrite must reset the cursor');

  const replacement = join(directory, 'replacement.jsonl');
  await writeFile(replacement, row('Replacement'));
  await rename(replacement, queue.requests);
  await queue.ingest();
  assert.equal(queue.jobs.size, 4, 'A replaced log must reset the cursor');
});

test('runtime queue does not publish failed or malformed translations', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-queue-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const queue = new RuntimeQueue({ directory, translate: async () => { throw new Error('provider unavailable'); }, currentWorld: () => 'region2' });
  await queue.load();
  await appendFile(join(directory, 'runtime-requests.jsonl'),
    '{"world":"region2","text":"Valid source"}\n' +
    '{"world":"region2","text":""}\n' +
    'not json\n', 'utf8');
  await queue.drain();
  await assert.rejects(readFile(join(directory, 'runtime-responses.jsonl'), 'utf8'), { code: 'ENOENT' });
});

test('runtime queue ignores rendered lookup aliases without dropping short names', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-queue-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const calls = [];
  const queue = new RuntimeQueue({ directory,
    translate: async source => { calls.push(source); return '百合'; },
    currentWorld: () => 'region2',
  });
  await queue.load();
  await appendFile(join(directory, 'runtime-requests.jsonl'),
    ['L007______  ', 'L000007_', 'L000008', 'P_____',
      'L0009Ss________ L0009Su________ L0009St________',
      '[C:7:0:1]L0009Ss________ [C:2:0:0]L0009Su________',
      'Lily', 'Love', 'Laborer', 'Lithium'].map(text =>
      JSON.stringify({ world: 'region2', text })).join('\n') + '\n', 'utf8');
  await queue.drain();
  assert.deepEqual(calls, ['Lily', 'Love', 'Laborer', 'Lithium']);
  const responses = (await readFile(join(directory, 'runtime-responses.jsonl'), 'utf8'))
    .trim().split('\n').map(JSON.parse);
  assert.deepEqual(responses.map(row => row.text).sort(), ['Lily', 'Love', 'Laborer', 'Lithium'].sort());
});

test('failed runtime requests use durable exponential backoff and redact errors', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-backoff-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let now = 1000;
  let calls = 0;
  let failing = true;
  const translate = async () => {
    calls++;
    if (failing) throw new Error('private-provider-key-should-not-be-logged');
    return '穩定譯文';
  };
  const create = () => new RuntimeQueue({ directory, translate, currentWorld: () => 'region2',
    now: () => now, retryBaseMs: 100, retryMaxMs: 400 });
  let queue = create();
  await queue.load();
  const requestPath = join(directory, 'runtime-requests.jsonl');
  const request = JSON.stringify({world: 'region2', text: 'A repeated failing source'}) + '\n';
  await appendFile(requestPath, request + request + request, 'utf8');
  await queue.drain();
  assert.equal(calls, 1, 'Duplicate failures must not immediately repeat a provider call');
  const journal = await readFile(join(directory, 'runtime-failures.jsonl'), 'utf8');
  assert.ok(!journal.includes('private-provider-key'));
  const failure = JSON.parse(journal.trim());
  assert.equal(failure.reason, 'translation failed');
  assert.equal(failure.attempts, 1);
  assert.equal(failure.retryAt, 1100);

  queue = create();
  await queue.load();
  await queue.drain();
  assert.equal(calls, 1, 'A restart must retain the cooldown');
  now = 1100;
  await appendFile(requestPath, request, 'utf8');
  await queue.drain();
  assert.equal(calls, 2);
  now = 1200;
  await appendFile(requestPath, request, 'utf8');
  await queue.drain();
  assert.equal(calls, 2, 'Second failure must double the delay');
  now = 1300;
  failing = false;
  await appendFile(requestPath, request, 'utf8');
  await queue.drain();
  assert.equal(calls, 3);
  assert.equal(queue.failures.size, 0);
  const response = JSON.parse((await readFile(join(directory, 'runtime-responses.jsonl'), 'utf8')).trim());
  assert.equal(response.translation, '穩定譯文');
});

test('a world switch during translation does not publish an obsolete result', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-runtime-world-switch-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let world = 'region2';
  const queue = new RuntimeQueue({ directory, currentWorld: () => world,
    translate: async () => { world = 'region1'; return '舊世界譯文'; },
  });
  await queue.load();
  await appendFile(join(directory, 'runtime-requests.jsonl'),
    JSON.stringify({ world, text: 'A previous-world name' }) + '\n', 'utf8');
  await queue.drain();
  await assert.rejects(readFile(join(directory, 'runtime-responses.jsonl'), 'utf8'), {code: 'ENOENT'});
});
