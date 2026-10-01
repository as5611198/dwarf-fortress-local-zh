import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {TranslationBroker} from '../broker.mjs';
import {WorldNames} from '../names.mjs';

test('English articles in health and item prose cannot become world names',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-article-name-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const registry=join(directory,'world-names.json');
  await writeFile(registry,JSON.stringify({world:'one',entities:[
    {id:'first:An',kind:'first',preferred:'An',aliases:['An']},
    {id:'figure:1',preferred:'An Tower',aliases:['An Tower']},
  ]}));
  const broker=new TranslationBroker({directory,language:'zh-Hant',glossary:{An:'安',A:'阿',The:'瑟'},
    provider:async source=>{
      assert.equal(source,'An artery has been opened by the attack!');
      return '動脈因這次攻擊而破裂！';
    }});
  await broker.load();
  const names=new WorldNames(registry,{An:'安'});
  broker.resolveNames=source=>names.resolve(source,broker);
  broker.matchNames=source=>names.match(source);
  await names.refresh(broker);
  for(const source of ['An artery has been opened by the attack!',
    'The left eye tooth needs setting. An artery has been opened by the attack!',
    'A motor nerve has been severed!','The shield is made from wood.']) {
    assert.deepEqual(names.match(source),[],source);
  }
  assert.deepEqual(names.match('[C:7:0:1]An artery has been opened by the attack!'),[]);
  assert.deepEqual(names.match('An'),['An'],'Isolated explicit names must stay available');
  assert.deepEqual(names.match('An Tower arrived.'),['An Tower'],'Full names must still win over an article');
  assert.equal(await broker.translate('An artery has been opened by the attack!'),'動脈因這次攻擊而破裂！');
  const restarted=new TranslationBroker({directory,language:'zh-Hant',provider:()=>{throw new Error('offline');}});
  await restarted.load();
  assert.equal(await restarted.translate('An artery has been opened by the attack!'),'動脈因這次攻擊而破裂！');
});
