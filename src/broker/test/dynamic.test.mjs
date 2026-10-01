import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { TranslationBroker } from '../broker.mjs';

test('different years and amounts share one persisted template without changing numbers', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-dynamic-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let calls = 0;
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', provider: async source => {
    calls++;
    assert.equal(source, 'In {{DFN0}}, Urist made {{DFN1}} axes.');
    return '在 {{DFN0}} 年，烏瑞斯特製作了 {{DFN1}} 把斧頭。';
  } });
  await broker.load();
  assert.equal(await broker.translate('In 123, Urist made 2 axes.'), '在 123 年，烏瑞斯特製作了 2 把斧頭。');
  assert.equal(await broker.translate('In 124, Urist made 17 axes.'), '在 124 年，烏瑞斯特製作了 17 把斧頭。');
  assert.equal(calls, 1);
  const restarted = new TranslationBroker({ directory, language: 'zh-Hant', provider: () => { throw new Error('offline'); } });
  await restarted.load();
  assert.equal(await restarted.translate('In 250, Urist made 99 axes.'), '在 250 年，烏瑞斯特製作了 99 把斧頭。');
});

test('known names share templates, stay canonical, and survive restarts', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-names-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const glossary = { Urist: '烏瑞斯特', Domas: '多瑪', 'Urist Tower': '烏瑞斯特之塔' };
  let calls = 0;
  const provider = async source => {
    calls++;
    assert.equal(source, 'In {{DFN0}}, {{DFE0}} met {{DFE1}} at {{DFE2}}.');
    return '在 {{DFN0}} 年，{{DFE0}} 在 {{DFE2}} 遇見了 {{DFE1}}。';
  };
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary, provider });
  await broker.load();
  assert.equal(await broker.translate('In 123, Urist met Domas at Urist Tower.'), '在 123 年，烏瑞斯特 在 烏瑞斯特之塔 遇見了 多瑪。');
  assert.equal(await broker.translate('In 124, Domas met Urist at Urist Tower.'), '在 124 年，多瑪 在 烏瑞斯特之塔 遇見了 烏瑞斯特。');
  assert.equal(await broker.translate('Urist'), '烏瑞斯特');
  assert.equal(calls, 1);
  const restarted = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { ...glossary, Urist: '烏里斯特' }, provider: () => { throw new Error('offline'); } });
  await restarted.load();
  assert.equal(await restarted.translate('In 200, Urist met Domas at Urist Tower.'), '在 200 年，烏里斯特 在 烏瑞斯特之塔 遇見了 多瑪。');
});

test('numeric templates preserve printf tokens and do not match name substrings', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-token-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary: { Urist: '烏瑞斯特' }, provider: async source => {
    assert.equal(source, 'Uristan has {{DFN0}} axes: %2$04d [COLOR:2].');
    return '烏瑞斯坦有 {{DFN0}} 把斧頭：%2$04d [COLOR:2]。';
  } });
  await broker.load();
  assert.equal(await broker.translate('Uristan has 2 axes: %2$04d [COLOR:2].'), '烏瑞斯坦有 2 把斧頭：%2$04d [COLOR:2]。');
});

test('restores explicit narrative year units even when AI omits the unit', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-year-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', provider: async () =>
    '在{{DFN0}}的仲冬，他製作了{{DFN1}}把斧頭。' });
  await broker.load();
  assert.equal(await broker.translate('In the midwinter of 15, he made 2 axes.'), '在15年的仲冬，他製作了2把斧頭。');
});

test('Legends death-year abbreviations use a reviewed rule for any year', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-death-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', provider: () => { throw new Error('offline'); } });
  await broker.load();
  assert.equal(await broker.translate('d. 28'), '卒於28年');
  assert.equal(await broker.translate('d. 81'), '卒於81年');
});

test('name and race fragments compose deterministically without asking AI for protected tokens', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-caption-fragment-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const broker = new TranslationBroker({ directory, language: 'zh-Hant',
    glossary: { 'Atu Seducelong': '阿圖·誘惑長', goblin: '哥布林', dwarf: '矮人' },
    provider: () => { throw new Error('Names and articles need no provider call'); },
  });
  await broker.load();
  assert.equal(await broker.translate('Atu Seducelong the goblin,'), '阿圖·誘惑長 哥布林,');
  assert.equal(await broker.translate('the goblin Atu Seducelong'), '哥布林 阿圖·誘惑長');
  assert.equal(await broker.translate('a dwarf'), '矮人');
  assert.equal(await broker.translate('an Atu Seducelong'), '阿圖·誘惑長');
  assert.equal(broker.stats.accepted, 0);
  await assert.rejects(broker.translate('Atu Seducelong attacked a dwarf'), /provider call/);
});
