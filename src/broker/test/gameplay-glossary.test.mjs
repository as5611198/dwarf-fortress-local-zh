import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TranslationBroker} from '../broker.mjs';
import {cacheKey} from '../safety.mjs';

test('gameplay terms invalidate conflicting item prose even with a world-name resolver',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-game-terms-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const calls=[];
  const broker=new TranslationBroker({directory,language:'zh-Hant',
    gameplayGlossary:{'plump helmet spawn':'肉盔菇菌種'},
    provider:async source=>{calls.push(source);return '她偏好食用{{DFE0}}。';}});
  await broker.load();
  broker.matchNames=()=>[];
  const source='She prefers to consume plump helmet spawn.';
  broker.cache.set(cacheKey(source,'zh-Hant'),'她偏好食用矮人菇孢子。');
  assert.equal(broker.peekCached(source),undefined);
  assert.equal(await broker.translate(source),'她偏好食用肉盔菇菌種。');
  assert.deepEqual(calls,['She prefers to consume {{DFE0}}.']);
});
