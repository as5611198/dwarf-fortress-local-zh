import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {DEFAULT_SETTINGS} from '../settings.mjs';
import {cacheKey,POLICY_VERSION} from '../safety.mjs';
const packageRoot=process.env.DF_LOCAL_ZH_PACKAGE_TEST_ROOT??fileURLToPath(new URL('../../../distribution/steam/df-local-zh-complete/',import.meta.url));
async function availablePort(){const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));return port;}
async function launch(t,{state,config=join(packageRoot,'broker/config.json')}){
 const port=await availablePort(),url=`http://127.0.0.1:${port}`;
 const child=spawn(join(packageRoot,'broker/df-local-zh-broker.exe'),[config,state,'--port',String(port)],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,PATH:process.env.SystemRoot+'/System32',DF_LOCAL_ZH_GAME_ROOT:''}});
 let output='';child.stdout.on('data',v=>{output+=v;});child.stderr.on('data',v=>{output+=v;});
 const stop=async()=>{if(child.exitCode===null&&child.signalCode===null){const exited=new Promise(r=>child.once('exit',r));child.kill();await exited;}};t.after(stop);
 const start=performance.now();let health;
 while(performance.now()-start<15000){try{health=await (await fetch(url+'/health',{signal:AbortSignal.timeout(1000)})).json();if(health.engine==='rust')break;}catch{}if(child.exitCode!==null)throw Error(output);await new Promise(r=>setTimeout(r,50));}
 assert.equal(health?.engine,'rust',output);t.diagnostic(`Rust package start ${(performance.now()-start).toFixed(2)} ms; Node excluded from PATH`);
 return {url,child,stop,post:async body=>{const response=await fetch(url+'/v2/translate',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});return {status:response.status,body:await response.json()};}};
}
async function fixture(t){const state=await mkdtemp(join(tmpdir(),'df-rust-release-'));t.after(()=>rm(state,{recursive:true,force:true}));await writeFile(join(state,'settings.json'),JSON.stringify({version:1,defaults:{...DEFAULT_SETTINGS,apiEnabled:false,officialAutoDownload:false},saves:{}}));return state;}
test('actual Steam EXE translates both languages offline and preserves fixed and legacy cache data',async t=>{
 const state=await fixture(t);await writeFile(join(state,'fixed-zh-Hant.json'),JSON.stringify({Health:'自訂健康'}));
 const source='She is calm.',translation='她很冷靜。';await writeFile(join(state,'translations.jsonl'),JSON.stringify({policy:POLICY_VERSION,kind:'exact',language:'zh-Hant',source,translation,key:cacheKey(source,'zh-Hant')})+'\n');
 const settings=await readFile(join(state,'settings.json'));let runtime=await launch(t,{state});
 for(const language of ['zh-Hant','zh-Hans']){assert.equal((await runtime.post({text:'Change to standard dig mode.',language})).body.translation,language==='zh-Hant'?'切換至一般挖掘模式。':'切换至一般挖掘模式。');}
 assert.equal((await runtime.post({text:'Health',language:'zh-Hant'})).body.translation,'自訂健康');assert.equal((await runtime.post({text:source,language:'zh-Hant'})).body.translation,translation);
 const profiles=await readFile(join(state,'api-profiles.private.json'));await runtime.stop();runtime=await launch(t,{state});assert.equal((await runtime.post({text:source,language:'zh-Hant'})).body.translation,translation);assert.deepEqual(await readFile(join(state,'settings.json')),settings);assert.deepEqual(await readFile(join(state,'api-profiles.private.json')),profiles);assert.equal((await (await fetch(runtime.url+'/health')).json()).providerBatch.requests,0);
});
test('Lua file protocol saves scoped settings and sync acknowledgement never overwrites drafts',async t=>{
 const state=await fixture(t);const runtime=await launch(t,{state});let number=0;
 const request=async body=>{const id='fixture-'+(++number);await writeFile(join(state,'settings-request.json'),JSON.stringify({id,...body}));for(let n=0;n<100;n++){try{const response=JSON.parse(await readFile(join(state,'settings-response.json')));if(response.id===id)return response;}catch{}await new Promise(r=>setTimeout(r,50));}throw Error('settings response deadline');};
 assert.equal((await request({action:'save',scope:'save',world:'region-fixture',settings:{language:'zh-Hans',translationPrompt:'My unapplied-independent prompt.'}})).ok,true);
 const before=await readFile(join(state,'settings.json'));const answer=await request({action:'official-sync',language:'zh-Hant'});assert.equal(answer.ok,true);assert.equal(answer.snapshot,undefined);assert.deepEqual(await readFile(join(state,'settings.json')),before);
 const wrong=await request({action:'save',scope:'global',settings:{language:'en'}});assert.equal(wrong.ok,false);assert.deepEqual(await readFile(join(state,'settings.json')),before);
});
test('Rust EXE downloads real signed cloud packages then reuses them without AI or auto-network', {skip:process.env.DF_LOCAL_ZH_LIVE_CLOUD!=='1'},async t=>{
 const state=await fixture(t);const source=join(state,'minimal-source');await mkdir(source);const config=join(source,'config.json');await writeFile(config,JSON.stringify({language:'zh-Hant',port:19754}));
 let runtime=await launch(t,{state,config});
 for(const language of ['zh-Hant','zh-Hans']){
  const start=performance.now();await writeFile(join(state,'settings-request.json'),JSON.stringify({id:'live-'+language,action:'official-sync',language}));let status;
  for(let n=0;n<800;n++){try{status=JSON.parse(await readFile(join(state,`official/status-${language}.json`)));if(status.phase==='pending'||status.phase==='error')break;}catch{}await new Promise(r=>setTimeout(r,50));}
  assert.equal(status?.phase,'pending',JSON.stringify(status));t.diagnostic(`${language} real signed download ${(performance.now()-start).toFixed(2)} ms`);
 }
 await runtime.stop();runtime=await launch(t,{state,config});
 for(const language of ['zh-Hant','zh-Hans']){const status=JSON.parse(await readFile(join(state,`official/status-${language}.json`)));assert.equal(status.phase,'complete');assert.equal(status.entries,502);const result=await runtime.post({text:'Health',language});assert.equal(result.status,200);assert.equal(result.body.translation,'健康');t.diagnostic(`${language} installed=${status.installedVersion} entries=${status.entries} load=${status.loadMs.toFixed(2)} ms`);}
 assert.equal((await (await fetch(runtime.url+'/health')).json()).providerBatch.requests,0);
});
