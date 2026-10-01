import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TranslationBroker} from '../broker.mjs';
import {lookupLiteral} from '../literal-lookup.mjs';

test('displayed hotkeys and resolutions never use the model or stale translations',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-ui-literal-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  let calls=0;
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async()=>{calls++;return '錯誤快捷鍵';}});
  for(const text of ['p: ','r: ','ESC: ','Ctrl+g','Ctrl+Shift+A','2560 x 1440','[C:2:0:1]r: ']) {
    assert.equal(broker.peekCached(text),text,text);
    assert.equal(await broker.translate(text),text,text);
  }
  assert.equal(calls,0,'local controls must not consume model slots');
  assert.equal(broker.stats.accepted,0);
  for(const text of ['An','r','The dwarf presses r: to rest.','Ctrl+g opens a menu.','2560 x 1440 tiles'])
    assert.equal(lookupLiteral(text,new Map(),new Map()),undefined,text);
});
