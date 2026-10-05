import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parse} from 'csv-parse/sync';
import {buildCreatureDictionaries} from '../build-creature-dictionaries.mjs';
import {simplify} from '../language-data.mjs';

test('caste names are immediate, preserve gender/plural and retain reviewed species terminology',async()=>{
  const root=await mkdtemp(join(tmpdir(),'df-caste-test-'));
  try {
    await mkdir(join(root,'broker/data'),{recursive:true});await mkdir(join(root,'self-tests'));
    await writeFile(join(root,'broker/data/race-map.json'),JSON.stringify({races:{}}));
    await writeFile(join(root,'broker/config.json'),JSON.stringify({staticDictionariesByLanguage:{},literalDictionaries:[]}));
    for (const lang of ['zh-Hant','zh-Hans']) {
      const rules=join(root,'dfi18n-data/rulesets',lang,'creatures');await mkdir(rules,{recursive:true});
      await mkdir(join(root,'dfi18n-data/simple',lang),{recursive:true});
      await writeFile(join(rules,'name.toml'),'[[rulesets]]\nname="singular"\n[rulesets.rules]\n"stoat man"="白鼬人"\n');
      await writeFile(join(rules,'caste.toml'),'[[rulesets]]\nname="singular"\n[rulesets.rules]\n"stoat man"="雄白鼬人"\n"stoat woman"="雌白鼬人"\n');
      await writeFile(join(root,`broker/data/community-workbook-${lang}.csv`),'text,translation,tags\n');
    }
    await buildCreatureDictionaries(root);
    for(const lang of ['zh-Hant','zh-Hans']) {
      const rows=parse(await readFile(join(root,`dfi18n-data/simple/${lang}/zzzzzzz-creature-names.csv`),'utf8'),{columns:true});
      const bySource=new Map(rows.map(row=>[row.text,row]));
      assert.equal(bySource.get('stoat woman')?.translation,'雌白鼬人');
      assert.equal(bySource.get('Stoat Women')?.translation,'雌白鼬人');
      assert.equal(bySource.get('stoat man')?.translation,'白鼬人');
      assert.match(bySource.get('stoat woman').tags,/\[CREATURE:1\]/);
      // Complete vanilla labels include irregular plurals and newer female castes.
      for(const [source,target] of [['guineahens','母珍珠雞'],['tyrannosaurus women','雌霸王龍人'],
        ['dodo hens','雌渡渡鳥'],['glyptodon boars','雄雕齒獸']])
        assert.equal(bySource.get(source)?.translation,lang==='zh-Hans'?simplify(target):target,source);
    }
  } finally {await rm(root,{recursive:true,force:true});}
});

test('release race map contains only vanilla IDs and supplemental names are real raw labels',async()=>{
  const inventory=JSON.parse(await readFile(new URL('../offline-creature-sources.json',import.meta.url),'utf8'));
  const races=JSON.parse(await readFile(new URL('../data/race-map.json',import.meta.url),'utf8'));
  assert.ok(Array.isArray(inventory.creatureIds) && inventory.creatureIds.length>900);
  const ids=new Set(inventory.creatureIds);
  for(const id of Object.keys(races.races)) assert.ok(ids.has(id),`Non-vanilla race ID: ${id}`);
  const labels=new Set(inventory.creatureLabels);
  const supplemental=JSON.parse(await readFile(new URL('../offline-creature-labels.json',import.meta.url),'utf8'));
  for(const [source,target] of Object.entries(supplemental)) {
    assert.ok(labels.has(source),source);
    assert.ok(/[\u3400-\u9fff]/u.test(target) && !/[A-Za-z\ufffd]/u.test(target),source);
  }
});
