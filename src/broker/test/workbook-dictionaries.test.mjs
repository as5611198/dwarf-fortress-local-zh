import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse } from 'csv-parse/sync';
import { TranslationBroker } from '../broker.mjs';
import { applyStaticDictionaryRows, staticDictionaryFiles } from '../server.mjs';
import { validateTranslation } from '../safety.mjs';

test('every workbook dictionary row is local, safe and isolated to its selected language', async () => {
  const config = JSON.parse(await readFile(new URL('../config.json', import.meta.url), 'utf8'));
  for (const language of ['zh-Hant', 'zh-Hans']) {
    const file = `data/community-workbook-${language}.csv`;
    assert.ok(staticDictionaryFiles(config, language).includes(file));
    assert.ok(!staticDictionaryFiles(config, language).includes(
      `data/community-workbook-${language === 'zh-Hant' ? 'zh-Hans' : 'zh-Hant'}.csv`));
    const rows = parse(await readFile(new URL('../' + file, import.meta.url), 'utf8'), { columns: true });
    const glossaryPath = config.glossaryPathsByLanguage?.[language] ?? config.glossaryPath;
    const glossary = JSON.parse(await readFile(new URL('../' + glossaryPath, import.meta.url), 'utf8'));
    const broker = new TranslationBroker({ directory: 'unused', language, glossary,
      provider: async () => { throw new Error('workbook row reached AI'); } });
    broker.resolveNames = async () => { throw new Error('literal workbook row reached names'); };
    assert.equal(applyStaticDictionaryRows(broker, rows, { literal: true }).length, rows.length);
    for (const row of rows) {
      assert.equal(validateTranslation(row.text, row.translation), row.translation);
      assert.equal(await broker.translate(row.text), row.translation, row.text);
    }
    assert.equal(broker.pending.size, 0);
    assert.equal(broker.stats.accepted, 0);
    const bySource = new Map(rows.map(row => [row.text, row.translation]));
    assert.equal(bySource.get('Charge'), language === 'zh-Hans' ? '冲锋' : '衝鋒');
    assert.equal(bySource.get('Sheet roller items'), language === 'zh-Hans' ? '卷轴轴心' : '卷軸軸心');
  }
});
