import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parse } from 'csv-parse/sync';
import { TranslationBroker } from '../broker.mjs';
import { applyStaticDictionaryRows } from '../server.mjs';
import { validateTranslation } from '../safety.mjs';

test('announcement tabs use reviewed literal Chinese without a provider or name inference', async () => {
  const csv = await readFile(new URL('../data/fortress-ui.csv', import.meta.url), 'utf8')
    .catch(error => { if (error.code === 'ENOENT') return 'text,translation,tags\n'; throw error; });
  const rows = parse(csv, { columns: true, skip_empty_lines: true });
  const broker = new TranslationBroker({directory:'unused',language:'zh-Hant',glossary:{}});
  broker.resolveNames = () => { throw new Error('Static tabs must not infer entity names'); };
  applyStaticDictionaryRows(broker, rows, {literal:true});
  for (const text of ['Fighting','Profession changes','Important','Medical alerts','Masterpieces',
    'Job failures','Death','General','World','Environment','Arrivals','Attacks','Creatures',
    'Strange moods','Animal','Life changes','Trade','Nobles','Wildlife','Labor','Ghosts',
    'Military','Mental state','Hunting','All','Combat','Sparring','Crime','Curses','Announcements']) {
    const row = rows.find(row => row.text === text);
    assert.ok(row, `Missing reviewed tab: ${text}`);
    assert.equal(await broker.translate(text), row.translation);
  }
});

test('all reviewed hover phrases match their generated manifest and bypass model inference',async()=>{
  const rows=parse(await readFile(new URL('../data/fortress-ui.csv',import.meta.url),'utf8'),{columns:true});
  const manifest=JSON.parse(await readFile(new URL('../data/fortress-hover.json',import.meta.url),'utf8'));
  assert.equal(manifest.version,1);
  assert.equal(Object.keys(manifest.translations).length,rows.length,'Duplicate source or stale hover manifest');
  const broker=new TranslationBroker({directory:'unused',language:'zh-Hant',glossary:{}});
  broker.resolveNames=()=>{throw Error('Reviewed tooltip must bypass entity inference');};
  applyStaticDictionaryRows(broker,rows,{literal:true});
  for(const row of rows) {
    assert.equal(manifest.translations[row.text],validateTranslation(row.text,row.translation));
    assert.equal(await broker.translate(row.text),row.translation);
  }
});

test('announcement labels are included in startup, native compilation and release packaging', async () => {
  const config = JSON.parse(await readFile(new URL('../config.json',import.meta.url),'utf8'));
  assert.ok(config.staticDictionaries.includes('data/fortress-ui.csv'));
  for (const file of ['compile-data.mjs','prepare-workshop-package.mjs']) {
    assert.match(await readFile(new URL('../'+file,import.meta.url),'utf8'), /data\/fortress-ui\.csv/);
  }
});
