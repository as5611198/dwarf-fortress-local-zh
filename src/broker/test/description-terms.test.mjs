import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';
import { buildDescriptionGlossary } from '../description-terms.mjs';
import { cacheKey } from '../safety.mjs';

test('creature descriptions reuse one sentence template and canonical race names', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-descriptions-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const races = {
    BIRD_BLUEJAY: { source: 'blue jay', translation: '冠藍鴉' },
    BLUEJAY_MAN: { source: 'bluejay man', translation: '冠藍鴉人' },
    GIANT_BLUEJAY: { source: 'giant bluejay', translation: '巨型冠藍鴉' },
    BIRD_CARDINAL: { source: 'cardinal', translation: '紅衣鳳頭鳥' },
    CARDINAL_MAN: { source: 'cardinal man', translation: '紅衣鳳頭鳥人' },
  };
  const bluejay = 'A person with the head and wings of a bluejay.';
  const cardinal = 'A person with the head and wings of a cardinal.';
  const giant = 'A huge monster in the form of a bluejay.';
  const terms = buildDescriptionGlossary([
    { text: bluejay, creatureId: 'BLUEJAY_MAN' },
    { text: cardinal, creatureId: 'CARDINAL_MAN' },
    { text: giant, creatureId: 'GIANT_BLUEJAY' },
  ], races);
  assert.deepEqual(terms.get(bluejay), { bluejay: '冠藍鴉' });
  assert.deepEqual(terms.get(cardinal), { cardinal: '紅衣鳳頭鳥' });
  assert.deepEqual(terms.get(giant), { bluejay: '冠藍鴉' });

  const calls = [];
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', descriptionGlossary: terms,
    provider: async source => {
      calls.push(source);
      if (source === 'A person with the head and wings of a {{DFE0}}.') {
        return '一個長著{{DFE0}}頭部與翅膀的人。';
      }
      if (source === 'A huge monster in the form of a {{DFE0}}.') {
        return '一隻{{DFE0}}形態的巨大怪物。';
      }
      throw new Error('unexpected template');
    },
  });
  await broker.load();
  broker.cache.set(cacheKey(giant, 'zh-Hant'), '一隻巨大的藍松鴉形態怪物。');
  assert.equal(await broker.translate(bluejay), '一個長著冠藍鴉頭部與翅膀的人。');
  assert.equal(await broker.translate(cardinal), '一個長著紅衣鳳頭鳥頭部與翅膀的人。');
  assert.equal(await broker.translate(giant), '一隻冠藍鴉形態的巨大怪物。');
  assert.deepEqual(calls, [
    'A person with the head and wings of a {{DFE0}}.',
    'A huge monster in the form of a {{DFE0}}.',
  ]);
});

test('raw descriptions do not mistake an article for a world figure name', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-description-article-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const source = 'An oceanic fish.';
  const terms = buildDescriptionGlossary([{ text: source, creatureId: 'FISH' }], {});
  const broker = new TranslationBroker({ directory, language: 'zh-Hant',
    glossary: { An: '安' }, descriptionGlossary: terms,
    provider: async text => {
      assert.equal(text, source);
      return '一種海洋魚類。';
    },
  });
  await broker.load();
  broker.resolveNames = async () => { throw new Error('article resolved as a figure name'); };
  broker.matchNames = () => ['An'];
  assert.equal(await broker.translate(source), '一種海洋魚類。');
});

test('world name aliases cannot mutate the provider terminology', () => {
  const fixed = { Urist: '烏瑞斯特' };
  const broker = new TranslationBroker({ directory: 'unused', language: 'zh-Hant',
    glossary: fixed, provider: null });
  broker.glossary.An = '安';
  assert.deepEqual(fixed, { Urist: '烏瑞斯特' });
});
