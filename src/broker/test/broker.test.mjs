import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, appendFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';
import { cacheKey } from '../safety.mjs';
import { createBrokerServer, runtimeDataPath, worldNamesPath } from '../server.mjs';

test('Workshop state keeps the exported world registry under its data directory', () => {
  assert.equal(worldNamesPath('C:/mod-state', 'C:/mod-state'), join('C:/mod-state', 'data', 'world-names.json'));
  assert.equal(worldNamesPath('C:/broker/data', undefined), join('C:/broker/data', 'world-names.json'));
  assert.equal(runtimeDataPath('C:/mod-state', 'C:/mod-state'), join('C:/mod-state', 'data'));
  assert.equal(runtimeDataPath('C:/broker/data', undefined), 'C:/broker/data');
});

async function fixture(t, provider) {
  const dir = await mkdtemp(join(tmpdir(), 'df-broker-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const broker = new TranslationBroker({ directory: dir, language: 'zh-Hant', provider, numericTemplates: false });
  await broker.load();
  return { broker, dir };
}

test('deduplicates simultaneous requests and reuses persisted translations', async t => {
  let calls = 0;
  const provider = async () => { calls++; await new Promise(r => setTimeout(r, 15)); return '在 123 年，烏瑞斯特出生了。'; };
  const { broker, dir } = await fixture(t, provider);
  const source = 'In 123, Urist was born.';
  assert.deepEqual(await Promise.all([broker.translate(source), broker.translate(source)]), ['在 123 年，烏瑞斯特出生了。', '在 123 年，烏瑞斯特出生了。']);
  assert.equal(calls, 1);
  const restarted = new TranslationBroker({ directory: dir, language: 'zh-Hant', provider: () => { throw new Error('offline'); } });
  await restarted.load();
  assert.equal(await restarted.translate(source), '在 123 年，烏瑞斯特出生了。');
});

test('exact cached text can be read without entering provider scheduling',async t=>{
  let calls=0;
  const {broker}=await fixture(t,async()=>{calls++;return '已翻譯的文字';});
  assert.equal(broker.peekCached('Known dwarf text'),undefined);
  assert.equal(await broker.translate('Known dwarf text'),'已翻譯的文字');
  assert.equal(broker.peekCached('Known dwarf text'),'已翻譯的文字');
  broker.literalStatic.set('Known title','已知標題');
  assert.equal(broker.peekCached('Known title'),'已知標題');
  assert.equal(calls,1);
});

test('equipment noun wins over a poisoned cached verb without invoking AI',async t=>{
  let calls=0;
  const {broker}=await fixture(t,async()=>{calls++;return '鐵 拾取了 [3]';});
  broker.equipmentTerms={materials:new Map([['iron','鐵'],['steel','鋼']]),
    nouns:new Map([['pick','十字鎬'],['picks','十字鎬'],['battle axes','戰斧']])};
  broker.cache.set(cacheKey('Iron picks [3]','zh-Hant'),'鐵 拾取了 [3]');
  assert.equal(await broker.translate('Iron picks [3]'),'鐵十字鎬 [3]');
  assert.equal(await broker.translate('Steel pick'),'鋼十字鎬');
  assert.equal(await broker.translate('Steel battle axes [2]'),'鋼戰斧 [2]');
  assert.equal(calls,0);
  assert.equal(broker.peekCached('Iron picks [3]'),'鐵十字鎬 [3]');
});

test('cached text with an unresolved world name stays on the name resolution path',async t=>{
  const {broker}=await fixture(t,async()=> '舊譯文');
  await broker.translate('Urist was promoted.');
  broker.matchNames=()=>['Urist'];
  assert.equal(broker.peekCached('Urist was promoted.'),undefined);
  broker.glossary.Urist='烏瑞斯特';
  assert.equal(broker.peekCached('Urist was promoted.'),undefined);
});

test('Simplified mode reuses a validated Traditional cache without contacting AI', async t => {
  const {broker,dir}=await fixture(t,async()=> '鐵製高腳杯。');
  const source='Iron goblet.';
  await broker.translate(source);
  const hans=new TranslationBroker({directory:dir,language:'zh-Hans',provider:()=>{throw new Error('conversion reached AI');}});
  await hans.load();
  assert.equal(await hans.translate(source),'铁制高脚杯。');
  assert.equal(hans.stats.accepted,0);
});
test('rejects invalid output and permits a fresh retry without caching failure', async t => {
  let calls = 0;
  const { broker, dir } = await fixture(t, async () => ++calls === 1 ? 'Urist 出生了。' : '烏瑞斯特出生了。');
  await assert.rejects(broker.translate('Urist was born.'), /English/);
  assert.equal(await broker.translate('Urist was born.'), '烏瑞斯特出生了。');
  const rows = (await readFile(join(dir, 'translations.jsonl'), 'utf8')).trim().split('\n');
  assert.equal(rows.length, 1);
});
test('rejects corrupt cache entries and recovers a truncated trailing journal row', async t => {
  const { dir } = await fixture(t, async () => '矮人。');
  await appendFile(join(dir, 'translations.jsonl'), '{"key":"bad","translation":"English"}\n{"interrupted":', 'utf8');
  const restarted = new TranslationBroker({ directory: dir, language: 'zh-Hant', provider: async () => '矮人。' });
  await restarted.load();
  assert.equal(await restarted.translate('Dwarf.'), '矮人。');
  const again = new TranslationBroker({ directory: dir, language: 'zh-Hant', provider: async () => { throw new Error('offline'); } });
  await again.load();
  assert.equal(await again.translate('Dwarf.'), '矮人。');
});
test('implements actual DFI18n text request and translation response, limits body size', async t => {
  const { broker } = await fixture(t, async () => '在 123 年，烏瑞斯特出生了。');
  const server = createBrokerServer(broker);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/v2/translate`;
  const response = await fetch(url, { method: 'POST', body: JSON.stringify({ text: 'In 123, Urist was born.' }) });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { translation: '在 123 年，烏瑞斯特出生了。' });
  assert.equal((await fetch(url, { method: 'POST', body: '{}' })).status, 400);
  assert.equal((await fetch(url, { method: 'POST', body: 'x'.repeat(40000) })).status, 413);
});

test('internal figure pin endpoint accepts only registered figure IDs', async t => {
  const { broker } = await fixture(t, async () => '烏旭');
  broker.pinFigure = async id => id === 'figure:11' ? '烏旭' : null;
  const server = createBrokerServer(broker);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = `http://127.0.0.1:${server.address().port}/v2/pin-figure`;
  const request = id => fetch(url, { method: 'POST', body: JSON.stringify({ id }) });
  const response = await request('figure:11');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { translation: '烏旭' });
  assert.equal((await request('figure:12')).status, 404);
  assert.equal((await request('../figure:11')).status, 400);
  assert.equal((await fetch(url, { method: 'POST', headers: { Origin: 'https://example.com' },
    body: JSON.stringify({ id: 'figure:11' }) })).status, 403);
});
