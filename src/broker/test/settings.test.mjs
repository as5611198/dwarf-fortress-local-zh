import test from 'node:test';
import assert from 'node:assert/strict';
import { validateSettings, effectiveSettings, validateProfiles, publicProfile } from '../settings.mjs';
import * as settings from '../settings.mjs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('deleting a profile removes its key and all references without changing other active APIs',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-api-delete-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const store=new settings.SettingsStore(directory);
  await store.load({kind:'Custom_OpenAI',baseUrl:'http://localhost:1234/v1',model:'fixture',key:'deleted-secret'});
  await store.apply({scope:'global',profiles:[{id:'second',baseUrl:'http://localhost:1235/v1',model:'local',key:'retained-secret'}]});
  await store.apply({scope:'save',world:'pooled',settings:{apiProfiles:['legacy','second'],concurrency:8}});
  await store.apply({scope:'save',world:'single',settings:{apiProfile:'second',timeoutMs:30000}});
  await store.apply({scope:'global',deleteProfiles:['legacy']});
  assert.equal(Object.hasOwn(store.profiles.profiles,'legacy'),false);
  assert.equal(store.profiles.profiles.second.key,'retained-secret');
  assert.deepEqual(store.effective('').apiProfiles,[]);
  assert.equal(store.effective('').apiPoolEnabled,true,'Deleting the active legacy API must not activate another');
  assert.deepEqual(store.effective('pooled').apiProfiles,['second']);
  const single=store.effective('single');
  assert.deepEqual(single.apiPoolEnabled ? single.apiProfiles : [single.apiProfile],['second']);
  assert.equal(single.timeoutMs,30000);
  const restored=new settings.SettingsStore(directory);await restored.load();
  assert.equal(Object.hasOwn(restored.snapshot().profiles,'legacy'),false);
  assert.ok(!(await readFile(join(directory,'api-profiles.private.json'),'utf8')).includes('deleted-secret'));
  const before=JSON.stringify(restored.snapshot());
  for(const deleteProfiles of [['missing'],['second','second'],['__proto__'],'second']) {
    await assert.rejects(restored.apply({scope:'global',deleteProfiles}));
    assert.equal(JSON.stringify(restored.snapshot()),before);
  }
  await assert.rejects(restored.apply({scope:'global',deleteProfiles:['second'],profiles:[{id:'second',model:'conflict'}]}));
});

test('deleting the last profile keeps an empty offline pool across reload and allows a new local API',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-api-delete-last-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const store=new settings.SettingsStore(directory);
  await store.load({kind:'Custom_OpenAI',baseUrl:'http://localhost:1234/v1',model:'fixture',key:'last-secret'});
  await store.apply({scope:'save',world:'saved',settings:{concurrency:4}});
  await store.apply({scope:'global',deleteProfiles:['legacy']});
  assert.deepEqual(store.snapshot().profiles,{});
  assert.equal(store.effective('saved').apiPoolEnabled,true);
  assert.deepEqual(store.effective('saved').apiProfiles,[]);
  const restored=new settings.SettingsStore(directory);await restored.load();
  assert.deepEqual(restored.snapshot().profiles,{});
  await assert.rejects(restored.apply({scope:'global',settings:{apiProfiles:['legacy']}}));
  await restored.apply({scope:'global',profiles:[{id:'local',baseUrl:'http://localhost:11434/v1',model:'fixture',key:''}],
    settings:{apiProfile:'local',apiProfiles:['local']}});
  assert.deepEqual(restored.effective('saved').apiProfiles,['local']);
  assert.equal(restored.snapshot().profiles.local.hasKey,false);
});

test('global defaults merge with save overrides without changing unrelated saves', () => {
  const document=validateSettings({ version: 1, defaults: { language: 'zh-Hans', concurrency: 1 },
    saves: { region3: { language: 'zh-Hant', apiProfile: 'local-model', timeoutMs: 10000 } } });
  assert.equal(effectiveSettings(document, 'C:/saves/region3').language, 'zh-Hant');
  assert.equal(effectiveSettings(document, 'region3').concurrency, 1);
  assert.equal(effectiveSettings(document, 'region3').apiProfile, 'local-model');
  assert.equal(effectiveSettings(document, 'region4').language, 'zh-Hans');
  assert.equal(effectiveSettings(document, '').language, 'zh-Hans');
});

test('multiple active API IDs and higher total concurrency persist with save isolation and private keys',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'df-api-pool-settings-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const store=new settings.SettingsStore(directory);
  await store.load({kind:'Custom_OpenAI',baseUrl:'http://localhost:1234/v1',model:'fixture',key:'pool-private-key'});
  assert.deepEqual(store.effective('').apiProfiles,[]);
  await store.apply({scope:'save',world:'region3',settings:{apiProfiles:['legacy','second'],concurrency:8},
    profiles:[{id:'legacy',concurrency:3},{id:'second',enabled:true,baseUrl:'http://localhost:1235/v1',model:'fixture',concurrency:5}]});
  assert.deepEqual(store.effective('region3').apiProfiles,['legacy','second']);
  assert.deepEqual(store.effective('region4').apiProfiles,[]);
  assert.equal(store.effective('region3').concurrency,8);
  assert.equal(store.snapshot().profiles.legacy.concurrency,3);
  assert.equal(store.profiles.profiles.legacy.key,'pool-private-key');
  assert.ok(!JSON.stringify(store.snapshot()).includes('pool-private-key'));
  const before=JSON.stringify(store.snapshot('region3'));
  for(const apiProfiles of [['missing'],['legacy','legacy'],['__proto__'],'legacy',Array(17).fill('legacy')]) {
    await assert.rejects(store.apply({scope:'save',world:'region3',settings:{apiProfiles}}));
    assert.equal(JSON.stringify(store.snapshot('region3')),before);
  }
  for(const concurrency of [0,17,1.5]) await assert.rejects(store.apply({scope:'global',profile:{id:'legacy',concurrency}}));
  const restored=new settings.SettingsStore(directory);await restored.load();
  assert.deepEqual(restored.effective('region3').apiProfiles,['legacy','second']);
  assert.equal(restored.profiles.profiles.second.concurrency,5);
  await restored.apply({scope:'save',world:'region3',settings:{apiProfiles:[]}});
  assert.equal(restored.effective('region3').apiPoolEnabled,true,'An explicitly empty pool must not reactivate legacy');
});

test('settings store persists overrides and private profiles, retaining an unchanged key', async () => {
  assert.equal(typeof settings.SettingsStore, 'function', 'persistent settings store is required');
  const directory=await mkdtemp(join(tmpdir(), 'df-settings-'));
  try {
    const store=new settings.SettingsStore(directory);
    await store.load({ kind:'Custom_OpenAI', baseUrl:'http://127.0.0.1:1234/v1', model:'fixture', key:'private-fixture' });
    await store.apply({ scope:'save', world:'E:/save/region3', settings:{language:'zh-Hans'},
      profile:{id:'legacy', model:'changed'} });
    assert.equal(store.effective('region3').language, 'zh-Hans');
    assert.equal(store.effective('region4').language, 'zh-Hant');
    assert.equal(store.profiles.profiles.legacy.key, 'private-fixture');
    assert.ok(!JSON.stringify(store.snapshot('region3')).includes('private-fixture'));
    assert.ok(!(await readFile(join(directory,'settings.json'),'utf8')).includes('private-fixture'));
    const restored=new settings.SettingsStore(directory);
    await restored.load();
    assert.equal(restored.effective('region3').language, 'zh-Hans');
    assert.equal(restored.profiles.profiles.legacy.model, 'changed');
    await restored.apply({scope:'save',world:'region3',reset:true});
    assert.equal(restored.effective('region3').language, 'zh-Hant');
  } finally { await rm(directory,{recursive:true,force:true}); }
});

test('invalid changes leave the last valid settings intact', async () => {
  assert.equal(typeof settings.SettingsStore, 'function');
  const directory=await mkdtemp(join(tmpdir(), 'df-settings-invalid-'));
  try {
    const store=new settings.SettingsStore(directory);await store.load();
    const original=JSON.stringify(store.snapshot('region3'));
    await assert.rejects(store.apply({scope:'save',world:'',settings:{language:'zh-Hans'}}));
    await assert.rejects(store.apply({scope:'global',settings:{apiProfile:'absent'}}));
    await assert.rejects(store.apply({scope:'global',settings:{concurrency:999}}));
    assert.equal(JSON.stringify(store.snapshot('region3')),original);
  } finally { await rm(directory,{recursive:true,force:true}); }
});

test('invalid settings, credentials in save overrides and prototype keys are rejected', () => {
  for (const change of [{ concurrency: 0 }, { timeoutMs: -1 }, { maxRetries: 8 },
    { language: 'en' }, { apiProfile: '../secret' }, { apiKey: 'secret' }]) {
    assert.throws(() => validateSettings({ version: 1, defaults: {}, saves: { region3: change } }));
  }
  assert.throws(() => validateSettings(JSON.parse('{"version":1,"saves":{"__proto__":{}}}')));
});

test('private API profiles validate URLs and expose metadata without their secret', () => {
  const profiles=validateProfiles({ version: 1, profiles: { local: {
    label: 'Local model', enabled: true, kind: 'Custom_OpenAI',
    baseUrl: 'http://127.0.0.1:1234/v1', model: 'fixture', key: 'fixture-private-key',
  } } });
  const profile=publicProfile(profiles.profiles.local);
  assert.equal(profile.hasKey, true);
  assert.ok(!JSON.stringify(profile).includes('fixture-private-key'));
  for (const baseUrl of ['http://remote.example/v1', 'https://user:secret@example.com/v1', 'https://example.com/v1?key=secret']) {
    assert.throws(() => validateProfiles({ version: 1, profiles: { invalid: { kind: 'Custom_OpenAI',
      baseUrl, model: 'fixture', enabled: true } } }));
  }
});
test('one Apply saves multiple edited profiles together and retains untouched keys', async () => {
  const directory=await mkdtemp(join(tmpdir(),'df-settings-multi-'));
  try {
    const store=new settings.SettingsStore(directory);
    await store.load({kind:'DeepSeek',baseUrl:'https://api.deepseek.com/v1',model:'deepseek-chat',key:'original-private-key'});
    await store.apply({scope:'global',settings:{apiProfile:'local'},profiles:[
      {id:'legacy',model:'edited-deepseek'},
      {id:'local',enabled:true,baseUrl:'http://localhost:1234/v1',model:'edited-local'},
    ]});
    assert.equal(store.profiles.profiles.legacy.model,'edited-deepseek');
    assert.equal(store.profiles.profiles.legacy.key,'original-private-key');
    assert.equal(store.profiles.profiles.local.model,'edited-local');
    assert.equal(store.document.defaults.apiProfile,'local');
    await assert.rejects(store.apply({scope:'global',profiles:[{id:'legacy',model:'must-not-apply'},{id:'bad',enabled:true}]}));
    assert.equal(store.profiles.profiles.legacy.model,'edited-deepseek');
  } finally {await rm(directory,{recursive:true,force:true});}
});

test('replacing save overrides lets unchanged fields follow later global defaults', async () => {
  const directory=await mkdtemp(join(tmpdir(),'df-settings-inherit-'));
  try {
    const store=new settings.SettingsStore(directory);await store.load();
    await store.apply({scope:'save',world:'region3',settings:{language:'zh-Hans',concurrency:1}});
    await store.apply({scope:'save',world:'region3',reset:true,settings:{language:'zh-Hans'}});
    assert.deepEqual(store.document.saves.region3,{language:'zh-Hans'});
    await store.apply({scope:'global',settings:{concurrency:3}});
    assert.equal(store.effective('region3').concurrency,3);
    assert.equal(store.effective('region3').language,'zh-Hans');
  } finally {await rm(directory,{recursive:true,force:true});}
});
