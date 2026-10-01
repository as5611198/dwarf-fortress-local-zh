import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createProvider} from '../provider.mjs';

for(const batch of [false,true]) test(`gameplay ${batch?'batch':'single'} transmits canonical terms and rejects synonyms`,async t=>{
  const observed=[];
  const server=createServer(async(req,res)=>{
    let body='';for await(const chunk of req)body+=chunk;
    const payload=JSON.parse(body);observed.push(payload);
    const input=JSON.parse(payload.messages[1].content);
    const translation='肉盔菇菌種袋';
    const response=input.items?{translations:input.items.map(item=>({id:item.id,translation}))}:{translation};
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({choices:[{message:{content:JSON.stringify(response)}}]}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const provider=await createProvider({maxRetries:0,glossary:{Unrelated:'無關'},provider:{
    kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${server.address().port}/v1`}});
  assert.equal(await provider('plump helmet spawn Bag','zh-Hant',{batch,glossary:{'plump helmet spawn':'肉盔菇菌種'}}),'肉盔菇菌種袋');
  const prompt=observed[0].messages[0].content;
  assert.match(prompt,/spawn is fungal planting material/);
  assert.match(prompt,/never reinterpret an invented name as an English word/);
  assert.match(prompt,/do not invent the missing tail/);
  const input=JSON.parse(observed[0].messages[1].content);
  assert.deepEqual((batch?input.items[0]:input).mandatoryGlossary,{'plump helmet spawn':'肉盔菇菌種'});
  await assert.rejects(provider('plump helmet spawn Bag','zh-Hant',{batch,glossary:{'plump helmet spawn':'指定菌種'}}),/mandatory glossary mismatch/);
});
