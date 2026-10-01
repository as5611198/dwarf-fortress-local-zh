import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';
import { WorldNames } from '../names.mjs';
import { cacheKey } from '../safety.mjs';

test('live caption composition checks world and figure aliases before using a durable name', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-live-caption-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  const text = 'Vadane Native Era, "Vadane Wildmists the Massive", female roc';
  await writeFile(path, JSON.stringify({ world: 'region1', entities: [{
    id: 'figure:20', preferred: 'Vadane Wildmists the Massive',
    aliases: ['Vadane Native Era', 'Vadane Wildmists the Massive'],
  }] }));
  const names = new WorldNames(path);
  const broker = new TranslationBroker({ directory, language: 'zh-Hant',
    glossary: { 'Vadane Wildmists the Massive': '巨型者荒霧瓦達內' },
    provider: () => { throw new Error('caption composition must not call AI'); } });
  await broker.load();
  broker.cache.set(cacheKey(text, 'zh-Hant'), '瓦達內，「瓦丹」，雌性大鵬');
  const races = { roc: '大鵬' };
  assert.equal(await names.translateCaption({ world: 'region1', figureId: 20, text }, broker, races),
    '巨型者荒霧瓦達內，「巨型者荒霧瓦達內」，女性大鵬');
  await assert.rejects(names.translateCaption({ world: 'region2', figureId: 20, text }, broker, races), /world/);
  await assert.rejects(names.translateCaption({ world: 'region1', figureId: 21, text }, broker, races), /identity/);
  await assert.rejects(names.translateCaption({ world: 'region1', figureId: 20,
    text: 'Another Native, "Another Name", female roc' }, broker, races), /identity/);
});

test('native and English aliases use the same durable canonical entity name', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-world-names-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({ world: 'fixture', entities: [
    { id: 'figure:1', aliases: ['Urist Aban', 'Urist Tower'], preferred: 'Urist Tower' },
  ] }));
  const names = new WorldNames(path, { Urist: '烏瑞斯特' });
  const calls = [];
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Urist: '烏瑞斯特' }, provider: async source => {
    calls.push(source);
    if (source === '{{DFE0}} Tower') return '{{DFE0}}之塔';
    assert.equal(source, '{{DFE0}} arrived in {{DFN0}}.');
    return '{{DFE0}}於 {{DFN0}} 年抵達。';
  } });
  await broker.load();
  broker.resolveNames = source => names.resolve(source, broker);
  assert.equal(await broker.translate('Urist Aban arrived in 12.'), '烏瑞斯特之塔於 12 年抵達。');
  assert.equal(await broker.translate('Urist Tower arrived in 13.'), '烏瑞斯特之塔於 13 年抵達。');
  assert.equal(calls.length, 2);
  const restarted = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Urist: '烏瑞斯特' }, provider: () => { throw new Error('offline'); } });
  await restarted.load();
  const reloadedNames = new WorldNames(path, { Urist: '烏瑞斯特' });
  restarted.resolveNames = source => reloadedNames.resolve(source, restarted);
  assert.equal(await restarted.translate('Urist Aban arrived in 14.'), '烏瑞斯特之塔於 14 年抵達。');
});

test('a generated name keeps its exact cached spelling across restarts', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-pinned-name-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  const entity = { id: 'figure:0', aliases: ['Sarvesh Native', 'Sarvesh Warmthpearls'], preferred: 'Sarvesh Warmthpearls' };
  await writeFile(path, JSON.stringify({ world: 'region2', entities: [entity] }));
  const first = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Sarvesh: '薩維石' },
    provider: async source => source === '{{DFE0}} Warmthpearls' ? '{{DFE0}} 暖珠' : '薩維石・暖珠' });
  await first.load();
  assert.equal(await first.translate('Sarvesh Warmthpearls', { resolveNames: false }), '薩維石 暖珠');
  const names = new WorldNames(path);
  first.resolveNames = source => names.resolve(source, first);
  assert.equal(await first.translate('Sarvesh Native'), '薩維石 暖珠');
  first.matchNames = source => names.match(source);
  const exact = new TranslationBroker({ directory, language: 'zh-Hant', glossary: {},
    provider: async () => '薩維石・暖珠' });
  await exact.load();
  assert.equal(await exact.translate('Sarvesh Warmthpearls'), '薩維石・暖珠');
  await first.load();
  assert.equal(await first.translate('Sarvesh Native'), '薩維石 暖珠');
  assert.equal(await first.translate('Sarvesh Warmthpearls'), '薩維石 暖珠');

  const restarted = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Sarvesh: '薩維石' },
    provider: async () => { throw new Error('offline'); } });
  await restarted.load();
  const reloadedNames = new WorldNames(path);
  restarted.resolveNames = source => reloadedNames.resolve(source, restarted);
  restarted.matchNames = source => reloadedNames.match(source);
  assert.equal(await restarted.translate('Sarvesh Native'), '薩維石 暖珠');
  assert.equal(await restarted.translate('Sarvesh Warmthpearls'), '薩維石 暖珠');
});

test('a stale caption must contain the canonical name for each alias occurrence', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-caption-alias-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({ world: 'region2', entities: [
    { id: 'figure:19', aliases: ['Luloagak Native', 'Washpuzzles the Coastal Sea Owl of Hexes',
      'Washpuzzles the Coastal Sea-Owl of Hexes'], preferred: 'Washpuzzles the Coastal Sea Owl of Hexes' },
  ] }));
  const source = 'Luloagak Native, "Washpuzzles the Coastal Sea-Owl of Hexes", forgotten beast';
  const canonical = '蜂謎，咒語之海岸海鴞';
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary: {}, provider: async template => {
    assert.equal(template, '{{DFE0}}, "{{DFE1}}", forgotten beast');
    return '{{DFE0}}, "{{DFE1}}", 被遺忘的野獸';
  } });
  await broker.load();
  broker.cache.set(cacheKey('Washpuzzles the Coastal Sea Owl of Hexes', 'zh-Hant'), canonical);
  broker.cache.set(cacheKey(source, 'zh-Hant'), `${canonical}, "另一個譯名", 被遺忘的野獸`);
  const names = new WorldNames(path);
  broker.resolveNames = text => names.resolve(text, broker);
  broker.matchNames = text => names.match(text);
  assert.equal(await broker.translate(source), `${canonical}, "${canonical}", 被遺忘的野獸`);
});

test('explicit figure pin survives an alias shared with a first-name record', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-shared-alias-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({ world: 'region2', entities: [
    { id: 'first:Uxu', kind: 'first', aliases: ['Uxu'], preferred: 'Uxu' },
    { id: 'figure:11', aliases: ['Uxu', 'Uxu'], preferred: 'Uxu' },
  ] }));
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', provider: async () => '烏旭' });
  await broker.load();
  const names = new WorldNames(path);
  assert.equal(await names.pinFigure('figure:11', broker), '烏旭');
  const journal = (await readFile(join(directory, 'translations.jsonl'), 'utf8'))
    .split('\n').filter(Boolean).map(JSON.parse);
  assert.equal(JSON.parse(journal.find(row => row.kind === 'name').source)[1], 'figure:11');
  assert.equal(await names.pinFigure('figure:11', broker), '烏旭');
  assert.equal(await names.pinFigure('figure:12', broker), null);
});
