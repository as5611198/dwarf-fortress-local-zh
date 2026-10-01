import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { start, createBrokerServer } from '../server.mjs';
import { TranslationBroker } from '../broker.mjs';
import { applyStaticDictionaryRows } from '../server.mjs';

test('native requests select their captured language and reject an unsupported language', async t => {
  const brokers = new Map();
  for (const [language, translation] of [['zh-Hant', '鐵製品'], ['zh-Hans', '铁制品']]) {
    const broker = new TranslationBroker({ directory: 'unused', language,
      provider: async () => { throw new Error('language request reached AI'); } });
    applyStaticDictionaryRows(broker, [{ text: 'Iron items', translation }], { literal: true });
    brokers.set(language, broker);
  }
  const selected = [];
  const server = createBrokerServer(brokers.get('zh-Hant'), { selectBroker: async (language, world) => {
    selected.push({ language, world }); return brokers.get(language);
  } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const request = language => fetch(`http://127.0.0.1:${server.address().port}/v2/translate`, {
    method: 'POST', body: JSON.stringify({ text: 'Iron items', language, world: 'region3' }),
  });
  const response = await request('zh-Hans');
  assert.equal((await response.json()).translation, '铁制品');
  assert.deepEqual(selected, [{ language: 'zh-Hans', world: 'region3' }]);
  assert.equal((await request('invalid-language')).status, 400);
});

test('Broker loads only dictionaries for its selected language and serves literal hits without a provider', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'df-language-dictionaries-'));
  try {
    await writeFile(join(directory, 'hant.csv'), 'text,translation,tags\nIron items,鐵製品,\n');
    await writeFile(join(directory, 'hans.csv'), 'text,translation,tags\nIron items,铁制品,\n');
    for (const language of ['zh-Hant', 'zh-Hans']) {
      await writeFile(join(directory, 'config.json'), JSON.stringify({ language, port: 0,
        dataDirectory: 'state-'+language, staticDictionaryLanguage: 'zh-Hant',
        staticDictionaries: ['hant.csv'],
        staticDictionariesByLanguage: { 'zh-Hans': ['hans.csv'] },
        literalDictionaries: ['hant.csv', 'hans.csv'],
      }));
      const { server, broker } = await start(join(directory, 'config.json'));
      try {
        broker.provider = async () => { throw new Error('local hit reached provider'); };
        broker.resolveNames = async () => { throw new Error('literal hit reached name resolver'); };
        assert.equal(await broker.translate('Iron items'), language === 'zh-Hans' ? '铁制品' : '鐵製品');
        assert.equal(broker.literalStatic.size, 1);
        assert.equal(broker.pending.size, 0);
      } finally {
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
