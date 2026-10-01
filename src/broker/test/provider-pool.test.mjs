import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createProviderPool} from '../provider-pool.mjs';

async function fixture(t,{failFirst=false}={}) {
  const counts=[0,0,0],active=[0,0,0],peak=[0,0,0];let total=0,totalPeak=0;
  const apis=await Promise.all(counts.map(async(_,index)=>{
    const server=createServer(async(req,res)=>{
      counts[index]++;active[index]++;total++;
      peak[index]=Math.max(peak[index],active[index]);totalPeak=Math.max(totalPeak,total);
      try {
        let raw='';for await(const chunk of req)raw+=chunk;
        if(index===0 && failFirst) {res.writeHead(429,{'retry-after':'1'});res.end('{}');return;}
        const body=JSON.parse(raw);const input=JSON.parse(body.messages[1].content);
        await new Promise(resolve=>setTimeout(resolve,30));
        const translated=text=>'敘述'+(text.match(/\d+/)?.[0] ?? '')+'。';
        const result=input.items ? {translations:input.items.map(item=>({id:item.id,translation:translated(item.text)}))} : {translation:translated(input.source)};
        res.end(JSON.stringify({choices:[{message:{content:JSON.stringify(result)}}]}));
      } finally {active[index]--;total--;}
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    t.after(()=>{server.closeAllConnections();return new Promise(resolve=>server.close(resolve));});
    return {id:'api-'+index,profile:{enabled:index!==2,kind:'Custom_OpenAI',model:'fixture',
      key:'private-fixture-'+index,baseUrl:`http://127.0.0.1:${server.address().port}/v1`,concurrency:index===1 ? 2 : 1}};
  }));
  return {apis,counts,peak,get totalPeak(){return totalPeak;}};
}

test('pool uses both APIs within per-profile and aggregate HTTP limits',async t=>{
  const state=await fixture(t);
  const provider=await createProviderPool({profiles:state.apis,concurrency:3,timeoutMs:2000,maxRetries:0});
  const values=await Promise.all(Array.from({length:9},(_,i)=>provider('Source '+i+'.','zh-Hant')));
  assert.deepEqual(values,Array.from({length:9},(_,i)=>'敘述'+i+'。'));
  assert.ok(state.counts[0]>0 && state.counts[1]>0);
  assert.equal(state.counts[2],0);
  assert.equal(state.totalPeak,3);
  assert.ok(state.peak[0]<=1 && state.peak[1]<=2);
  assert.equal(provider.poolStats.profiles.length,2);
  assert.ok(!JSON.stringify(provider.poolStats).includes('private-fixture'));
  assert.equal(provider.poolStats.profiles.reduce((sum,row)=>sum+row.active,0),0);
});

test('batching remains enabled across pooled providers with a shared total ceiling',async t=>{
  const state=await fixture(t);
  const provider=await createProviderPool({profiles:state.apis,concurrency:1,timeoutMs:2000,maxRetries:0});
  const values=await Promise.all(Array.from({length:20},(_,i)=>provider('Source '+i+'.','zh-Hant',{batch:true})));
  assert.deepEqual(values,Array.from({length:20},(_,i)=>'敘述'+i+'。'));
  assert.ok(state.counts[0]>0 && state.counts[1]>0);
  assert.equal(state.totalPeak,1);
  assert.equal(provider.batchStats.items,20);
  assert.ok(provider.batchStats.requests<20);
});

test('fast failing API falls back once and cools down while healthy API continues',async t=>{
  const state=await fixture(t,{failFirst:true});
  const provider=await createProviderPool({profiles:state.apis,concurrency:3,timeoutMs:2000,maxRetries:1});
  assert.equal(await provider('Source 1.','zh-Hant',{batch:true}),'敘述1。');
  assert.equal(await provider('Source 2.','zh-Hant',{batch:true}),'敘述2。');
  assert.equal(state.counts[0],1);
  assert.equal(state.counts[1],2);
  assert.equal(provider.poolStats.failovers,1);
});

test('all-disabled pool stays offline and an expired deadline sends no request',async t=>{
  const state=await fixture(t);
  assert.equal(await createProviderPool({profiles:state.apis.map(row=>({...row,profile:{...row.profile,enabled:false}})),concurrency:2}),null);
  const provider=await createProviderPool({profiles:state.apis,concurrency:2,maxRetries:0});
  await assert.rejects(provider('Source 1.','zh-Hant',{deadline:Date.now()-1}),/provider timeout/);
  assert.deepEqual(state.counts,[0,0,0]);
});
