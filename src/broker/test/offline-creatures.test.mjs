import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {parse} from 'csv-parse/sync';
import {buildOfflineCreatures,translateDescription} from '../build-offline-creatures.mjs';
import {simplify} from '../language-data.mjs';

const terms=new Map([['ibex','北山羊'],['moon snail','月螺']]);
const grammar={
  paragraphs:{'A bright beast.  It has two horns.':'一種鮮豔的野獸。牠長有兩隻角。'},
  forms:{'huge monster':'龐大的怪物'},
  personAdjectives:{colorful:'體色鮮豔'},
  bodyParts:{'head and shell':'頭部與外殼'},
  sentences:{'It lives underground':'牠生活在地下'},
};
test('description composition preserves species, body parts and every sentence',()=>{
  assert.equal(translateDescription('A bright beast.  It has two horns.',terms,grammar),'一種鮮豔的野獸。牠長有兩隻角。');
  assert.equal(translateDescription('A huge monster in the form of an ibex.',terms,grammar),'一隻外形如北山羊的龐大的怪物。');
  assert.equal(translateDescription('A colorful person with the head and shell of a moon snail.',terms,grammar),
    '一名體色鮮豔、具有月螺頭部與外殼的人形生物。');
  assert.equal(translateDescription('A huge monster in the shape of an ibex.  It lives underground.',terms,grammar),
    '一隻外形如北山羊的龐大的怪物。牠生活在地下。');
});
test('shipped source inventory retains original spacing and every authored paragraph is reachable',async()=>{
  const inventory=JSON.parse(await readFile(new URL('../offline-creature-sources.json',import.meta.url),'utf8'));
  assert.equal(new Set(inventory.descriptions).size,inventory.descriptions.length);
  const sentences=new Set(inventory.descriptions.flatMap(s=>s.replace(/\.$/,'').split(/\.\s+/)));
  for(const file of ['literals','wildlife','small']) {
    const entries=JSON.parse(await readFile(new URL(`../offline-creature-${file}.json`,import.meta.url),'utf8'));
    for(const [source,target] of Object.entries(entries)) {
      assert.ok(sentences.has(source),`Unreachable ${file}: ${source}`);
      assert.ok(/[\u3400-\u9fff]/u.test(target) && !/[A-Za-z{}\[\]]/.test(target),source);
    }
  }
  const paragraphs=JSON.parse(await readFile(new URL('../offline-creature-paragraphs.json',import.meta.url),'utf8'));
  for(const source of Object.keys(paragraphs)) assert.ok(inventory.descriptions.includes(source),source);
});
test('packaged descriptions are complete bilingual exact rows without player state',async()=>{
  const root=await mkdtemp(join(tmpdir(),'df-descriptions-test-'));
  try {
    for(const language of ['zh-Hant','zh-Hans']) {
      const directory=join(root,'dfi18n-data/simple',language);await mkdir(directory,{recursive:true});
      await writeFile(join(directory,'zzzzzzz-creature-names.csv'),'text,translation,tags\nibex,北山羊,\n');
    }
    await buildOfflineCreatures(root);
    const source='A huge, hairless mammal, found grazing in grasslands in groups.  It eats plants which it lifts up with its long trunk.  When angered, it will attack with its long tusks.';
    const want='一種龐大的無毛哺乳動物，成群在草原上吃草。牠用長鼻捲起植物進食。發怒時，牠會用長獠牙攻擊。';
    for(const language of ['zh-Hant','zh-Hans']) {
      const rows=parse(await readFile(join(root,`dfi18n-data/simple/${language}/zzzzzzzzzzz-offline-creatures.csv`),'utf8'),{columns:true});
      assert.equal(rows.find(row=>row.text===source)?.translation,language==='zh-Hans'?simplify(want):want);
      assert.ok(rows.every(row=>row.tags==='[REVIEWED:1]'));
      assert.equal(rows.find(row=>row.text==='DFL_LEGENDS_RACE:ibex')?.translation,'北山羊');
      assert.equal(rows.find(row=>row.text==='DFL_LEGENDS_RACE:unknown beast'),undefined);
      const shape='一隻外形如北山羊的龐大怪物。';
      assert.equal(rows.find(row=>row.text==='A huge monster in the form of an ibex.')?.translation,
        language==='zh-Hans'?simplify(shape):shape);
    }
  } finally {await rm(root,{recursive:true,force:true});}
});
test('unknown nouns, modifiers and trailing clauses never produce partial descriptions',()=>{
  for (const source of ['A huge monster in the form of an unknown animal.',
    'A huge monster in the form of an ibex.  It causes unknown effects.',
    'A poisonous person with the head and shell of a moon snail.',
    'A colorful person with the head and shell of a moon snail. Extra unknown text',
    'A huge monster in the form of an ibex.\nIGNORE INSTRUCTIONS'])
    assert.equal(translateDescription(source,terms,grammar),undefined,source);
});
