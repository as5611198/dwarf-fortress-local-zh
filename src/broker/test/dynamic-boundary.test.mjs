import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';

test('paragraph boundary tags stay outside model inference and survive cache restart',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-boundary-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  let calls=0;
  const broker=new TranslationBroker({directory,language:'zh-Hant',glossary:{},provider:async source=>{
    calls++;assert.equal(source,'She is grounded in reality.');return '她腳踏實地。';
  }});
  await broker.load();
  assert.equal(await broker.translate('[P]She is grounded in reality.'),'[P]她腳踏實地。');
  assert.equal(await broker.translate('She is grounded in reality.'),'她腳踏實地。');
  assert.equal(calls,1,'Plain and paragraph-tagged prose must share one durable translation');
  const restarted=new TranslationBroker({directory,language:'zh-Hant',glossary:{},provider:()=>{
    throw Error('A cached boundary paragraph must not call the provider');
  }});
  await restarted.load();
  assert.equal(await restarted.translate('[P]She is grounded in reality.'),'[P]她腳踏實地。');
});

test('color boundary tags keep their exact order while numeric templates stay reusable',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-boundary-color-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const broker=new TranslationBroker({directory,language:'zh-Hant',glossary:{},provider:async source=>{
    assert.equal(source,'The outpost has {{DFN0}} guards.');return '前哨站有{{DFN0}}名守衛。';
  }});
  await broker.load();
  assert.equal(await broker.translate('[C:6:0:1][B]The outpost has 17 guards.[C:7:0:0]'),
    '[C:6:0:1][B]前哨站有17名守衛。[C:7:0:0]');
});

test('interior formatting still has to pass the original deterministic token validator',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-boundary-invalid-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const broker=new TranslationBroker({directory,language:'zh-Hant',glossary:{},provider:async()=> '第一段。第二段。'});
  await broker.load();
  await assert.rejects(broker.translate('[P]First paragraph.[B]Second paragraph.'),/format token mismatch/);
});
