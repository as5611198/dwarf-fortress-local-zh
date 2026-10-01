import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import TOML from '@iarna/toml';
import { buildWorkbookContextRules } from '../build-workbook-context.mjs';

test('the same English word retains its adjective and noun meanings in separate rule groups',async()=>{
  const root=await mkdtemp(join(tmpdir(),'df-workbook-context-'));
  try {
    for(const language of ['zh-Hant','zh-Hans']) {
      const dir=join(root,'dfi18n-data/rulesets',language,'english_name');
      await mkdir(dir,{recursive:true});
      for(const kind of ['adj','none']) await writeFile(join(dir,kind+'.toml'),
        TOML.stringify({base:`english_name::${kind}`,rulesets:[{name:'main',rules:{Ancient:'Ancient'}}]}));
    }
    await buildWorkbookContextRules(root,[
      {text:'Ancient',translation:'古老的',sheet:'拼接-形容词'},
      {text:'Ancient',translation:'古代',sheet:'拼接-名词'},
    ]);
    for(const language of ['zh-Hant','zh-Hans']) for(const [kind,expected] of [['adj','古老的'],['none','古代']]) {
      const doc=TOML.parse(await readFile(join(root,'dfi18n-data/rulesets',language,'english_name',kind+'.toml'),'utf8'));
      assert.equal(doc.rulesets[0].rules.Ancient,expected);
    }
  } finally {await rm(root,{recursive:true,force:true});}
});
