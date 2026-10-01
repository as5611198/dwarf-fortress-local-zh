import test from 'node:test';
import assert from 'node:assert/strict';
import { applyStaticDictionaryRows, staticDictionaryFiles } from '../server.mjs';
import { cacheKey } from '../safety.mjs';

test('a validated static material translation replaces an older AI cache entry', () => {
  const source = 'frozen bark scorpion venom';
  const key = cacheKey(source, 'zh-Hant');
  const broker = { language: 'zh-Hant', glossary: {}, cache: new Map([[key, '冰凍蠍毒']]) };
  applyStaticDictionaryRows(broker, [{ text: source, translation: '冰凍樹皮蠍毒液' }]);
  assert.equal(broker.cache.get(key), '冰凍樹皮蠍毒液');
});

test('static rows cannot replace a conflicting pinned proper name', () => {
  const broker = { language: 'zh-Hant', glossary: { Sarvesh: '薩維石' }, cache: new Map() };
  applyStaticDictionaryRows(broker, [{ text: 'Sarvesh', translation: '薩維什' }]);
  assert.equal(broker.cache.size, 0);
});

test('a name fragment inside another word does not block a static row', () => {
  const broker = { language: 'zh-Hant', glossary: { Bosa: '波薩' }, cache: new Map() };
  applyStaticDictionaryRows(broker, [{ text: 'Bosaustu', translation: '堡壘' }]);
  assert.equal(broker.cache.get(cacheKey('Bosaustu', 'zh-Hant')), '堡壘');
});

test('reviewed fortress UI wins over workbook translations in both languages', () => {
  for (const language of ['zh-Hant', 'zh-Hans']) {
    const ui = language === 'zh-Hant' ? 'data/fortress-ui.csv' : 'data/fortress-ui-zh-Hans.csv';
    const workbook = `data/community-workbook-${language}.csv`;
    const config = {
      staticDictionaryLanguage: 'zh-Hant',
      staticDictionaries: ['data/fortress-ui.csv'],
      staticDictionariesByLanguage: {
        'zh-Hant': [workbook], 'zh-Hans': [workbook, ui],
      },
    };
    const files = staticDictionaryFiles(config, language);
    assert.equal(files.at(-1), ui);
    const broker = { language, glossary: {}, cache: new Map(), literalStatic: new Map() };
    for (const file of files) {
      const translation = file === workbook ? '将军' : language === 'zh-Hant' ? '常規' : '常规';
      applyStaticDictionaryRows(broker, [{ text: 'General', translation }], { literal: true });
    }
    assert.equal(broker.literalStatic.get('General'), language === 'zh-Hant' ? '常規' : '常规');
  }
});
