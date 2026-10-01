import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';
import { WorldNames } from '../names.mjs';
import { cacheKey } from '../safety.mjs';

test('native figure names bypass old semantic pins and captions do not duplicate them', async t => {
  const directory=await mkdtemp(join(tmpdir(),'df-native-figure-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const entity={id:'figure:0',preferred:'Imust Rightsucked the Courageous',
    nativeName:'Imust Kìrareb Samam',aliases:['Imust Kìrareb Samam','Imust Rightsucked the Courageous']};
  const path=join(directory,'world.json');
  await writeFile(path,JSON.stringify({world:'region1',entities:[entity]}));
  const calls=[];
  const broker=new TranslationBroker({directory,language:'zh-Hant',provider:async (source,language,options)=> {
    calls.push({source,options}); return '伊穆斯特 基拉雷布 薩瑪姆';
  }});
  await broker.load();
  const old=await broker.canonicalName('region1',entity.id,entity.preferred,async()=> '我必須勇氣之吸吮者');
  assert.equal(old,'我必須勇氣之吸吮者');
  broker.cache.set(cacheKey(entity.nativeName,'zh-Hant'),'我必須勇氣之吸吮者');
  const names=new WorldNames(path);
  const caption={world:'region1',figureId:0,text:entity.aliases[0]+', "'+entity.aliases[1]+'", female hydra'};
  assert.equal(await names.translateCaption(caption,broker,{hydra:'七頭蛇'}),'伊穆斯特 基拉雷布 薩瑪姆，女性七頭蛇');
  assert.equal(calls.length,1);
  assert.equal(calls[0].source,entity.nativeName);
  assert.equal(calls[0].options.kind,'phonetic-name');
  const restarted=new TranslationBroker({directory,language:'zh-Hant',provider:()=> {throw Error('must use saved name');}});
  await restarted.load();
  assert.equal(await new WorldNames(path).translateCaption(caption,restarted,{hydra:'七頭蛇'}),
    '伊穆斯特 基拉雷布 薩瑪姆，女性七頭蛇');
});
