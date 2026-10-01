import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {start} from '../server.mjs';

test('saving a prompt hot-applies to the selected save and subsequent model requests',async t=>{
 const directory=await mkdtemp(join(tmpdir(),'df-prompt-live-'));t.after(()=>rm(directory,{recursive:true,force:true}));
 const prompts=[];
 const api=createServer(async(req,res)=>{
  let body='';for await(const chunk of req)body+=chunk;
  prompts.push(JSON.parse(body).messages[0].content);
  res.end(JSON.stringify({choices:[{message:{content:'{"translation":"測試敘述。"}'}}]}));
 });
 await new Promise(resolve=>api.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>api.close(resolve)));
 const config=join(directory,'config.json');
 await mkdir(join(directory,'state/data'),{recursive:true});
 await writeFile(config,JSON.stringify({port:0,provider:{kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${api.address().port}/v1`}}));
 const service=await start(config,join(directory,'state'));t.after(()=>new Promise(resolve=>service.server.close(resolve)));
 const first=await service.selectBroker('zh-Hant','region3');
 await first.translate('A unique uncached tale.');
 assert.ok(!prompts[0].includes('fixture-save-guidance'));
 const updated=await service.settingsService.handle({id:'prompt-apply',action:'save',scope:'save',world:'region3',settings:{translationPrompt:'fixture-save-guidance'}});
 assert.equal(updated.ok,true);
 const same=await service.selectBroker('zh-Hant','region3');
 await same.translate('Another unique uncached tale.');
 assert.match(prompts.at(-1),/fixture-save-guidance/);
 const other=await service.selectBroker('zh-Hant','region4');
 await other.translate('A third unique uncached tale.');
 assert.ok(!prompts.at(-1).includes('fixture-save-guidance'));
});
