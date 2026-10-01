import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';

test('a fixed dwarf-name token survives entity masking, cache reuse and restart', async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-preference-template-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  let calls=0;
  const source='{DWARF_NAME} likes chicory.';
  const create=provider=>new TranslationBroker({directory,language:'zh-Hant',
    glossary:{chicory:'菊苣'},provider});
  const broker=create(async text=>{
    calls++;
    assert.equal(text,'{DWARF_NAME} likes {{DFE0}}.');
    return '{DWARF_NAME}喜歡{{DFE0}}。';
  });
  await broker.load();
  const translated=await broker.translate(source);
  assert.equal(translated,'{DWARF_NAME}喜歡菊苣。');
  assert.equal(await broker.translate(source),translated);
  const restarted=create(()=>{throw new Error('offline');});
  await restarted.load();
  assert.equal(await restarted.translate(source),translated);
  assert.equal(calls,1);
});
