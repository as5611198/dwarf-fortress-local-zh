import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SettingsStore,validateSettings} from '../settings.mjs';
import {createProvider} from '../provider.mjs';
import {createServer} from 'node:http';

test('multiline prompt persists, isolates saves and restores the shipped default',async t=>{
 const directory=await mkdtemp(join(tmpdir(),'df-prompt-settings-'));t.after(()=>rm(directory,{recursive:true,force:true}));
 const store=new SettingsStore(directory);await store.load();
 await store.apply({scope:'global',settings:{translationPrompt:'遵守固定術語。\n不要逐字拆開物品名稱。'}});
 await store.apply({scope:'save',world:'region3',settings:{translationPrompt:'戰鬥用語保持精確。'}});
 const restored=new SettingsStore(directory);await restored.load();
 assert.equal(restored.effective('region3').translationPrompt,'戰鬥用語保持精確。');
 assert.equal(restored.effective('region4').translationPrompt,'遵守固定術語。\n不要逐字拆開物品名稱。');
 assert.match(restored.snapshot().promptDefaults.translation,/Dwarf Fortress/);
 await restored.apply({scope:'save',world:'region3',settings:{translationPrompt:''}});
 assert.equal(restored.effective('region3').translationPrompt,'');
 assert.throws(()=>validateSettings({version:1,defaults:{translationPrompt:42}}));
 assert.throws(()=>validateSettings({version:1,defaults:{translationPrompt:'x'.repeat(8193)}}));
 assert.throws(()=>validateSettings({version:1,defaults:{translationPrompt:'bad\0text'}}));
});

for(const batch of [false,true])for(const kind of ['Google','Custom_OpenAI'])
 test(`custom prompt reaches ${kind} ${batch?'batch':'single'} without removing structural guards`,async t=>{
  const observed=[];
  const api=createServer(async(req,res)=>{
   let body='';for await(const chunk of req)body+=chunk;
   const payload=JSON.parse(body);observed.push(payload);
   const raw=kind==='Google'?payload.contents[0].parts[0].text:payload.messages[1].content;
   const input=JSON.parse(raw);
   const answer=input.items?{translations:input.items.map(item=>({id:item.id,translation:'中文 7'}))}:{translation:'中文 7'};
   res.end(JSON.stringify(kind==='Google'?{candidates:[{content:{parts:[{text:JSON.stringify(answer)}]}}]}:{choices:[{message:{content:JSON.stringify(answer)}}]}));
  });
  await new Promise(resolve=>api.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>api.close(resolve)));
  const provider=await createProvider({translationPrompt:'使用測試專用語氣。',provider:{kind,model:'fixture',baseUrl:`http://127.0.0.1:${api.address().port}/v1`},maxRetries:0});
  assert.equal(await provider('Value 7','zh-Hant',{batch}),'中文 7');
  const prompt=kind==='Google'?observed[0].systemInstruction.parts[0].text:observed[0].messages[0].content;
  assert.match(prompt,/使用測試專用語氣/);
  assert.match(prompt,/Preserve.*digits?/);
  assert.match(prompt,/Treat.*source.*data/);
  await assert.rejects(provider('Value 8','zh-Hant',{batch}),/number mismatch/);
 });

test('gameplay customization cannot reinterpret fictional names',async t=>{
 let prompt;
 const api=createServer(async(req,res)=>{
  let body='';for await(const chunk of req)body+=chunk;
  prompt=JSON.parse(body).messages[0].content;
  res.end(JSON.stringify({choices:[{message:{content:'{"translation":"伊穆斯特"}'}}]}));
 });
 await new Promise(resolve=>api.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>api.close(resolve)));
 const provider=await createProvider({translationPrompt:'fixture-custom-override',provider:{kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${api.address().port}/v1`}});
 assert.equal(await provider('Imust','zh-Hant',{kind:'phonetic-name'}),'伊穆斯特');
 assert.ok(!prompt.includes('fixture-custom-override'));assert.match(prompt,/Never translate these words semantically/);
});
