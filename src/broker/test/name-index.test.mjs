import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';
import { WorldNames } from '../names.mjs';

test('changing worlds discards aliases from the previous world', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-world-switch-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const registry = join(directory, 'world-names.json');
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Urist: '烏瑞斯特' },
    provider: async source => source === 'Copperhold' ? '銅堡' : source === 'Ironhold' ? '鐵堡' : '陌生地方。' });
  await broker.load();
  const names = new WorldNames(registry);
  broker.resolveNames = source => names.resolve(source, broker);
  broker.matchNames = source => names.match(source);
  await writeFile(registry, JSON.stringify({ world: 'one', entities: [
    { id: 'site:1', aliases: ['Alol', 'Copperhold'], preferred: 'Copperhold' },
  ] }));
  assert.equal(await broker.translate('Alol'), '銅堡');
  assert.equal(broker.glossary.Alol, '銅堡');
  await writeFile(registry, JSON.stringify({ world: 'two', entities: [
    { id: 'site:2', aliases: ['Alol', 'Ironhold'], preferred: 'Ironhold' },
  ] }));
  assert.equal(await broker.translate('Alol'), '鐵堡');
  assert.equal(broker.glossary.Alol, '鐵堡');
  assert.equal(broker.glossary.Copperhold, undefined);
  assert.equal(broker.glossary.Urist, '烏瑞斯特');
});

test('name matcher selects only whole names and longest overlapping alias', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-world-index-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const registry = join(directory, 'world-names.json');
  await writeFile(registry, JSON.stringify({ world: 'one', entities: [
    { id: 'figure:1', aliases: ['Urist', 'Urist Tower'], preferred: 'Urist Tower' },
  ] }));
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Urist: '烏瑞斯特' },
    provider: async () => '烏瑞斯特之塔' });
  await broker.load();
  const names = new WorldNames(registry);
  broker.resolveNames = source => names.resolve(source, broker);
  broker.matchNames = source => names.match(source);
  await names.refresh(broker);
  assert.deepEqual(names.match('Uristan visited Urist Tower.'), ['Urist Tower']);
  assert.deepEqual(names.match('Urist visited the tower.'), ['Urist']);
  assert.deepEqual(names.match('{{TAG:Urist}} Urist'), ['Urist']);
});
