import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createProvider} from '../provider.mjs';
import {safeReason} from '../safety.mjs';

for(const batch of [false,true]) {
  test(`connection reset is distinguished from model timeout (batch=${batch})`,async t=>{
    const server=createServer(req=>req.socket.destroy());
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    t.after(()=>{server.closeAllConnections();return new Promise(resolve=>server.close(resolve));});
    const provider=await createProvider({maxRetries:0,provider:{kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${server.address().port}/v1`}});
    await assert.rejects(provider('The gate is open.','zh-Hant',{batch}),{message:'provider connection failed'});
    assert.equal(safeReason(new Error('provider connection failed')),'provider connection failed');
  });
  test(`deadline covers JSON body after response headers (batch=${batch})`,async t=>{
    const server=createServer((req,res)=>{
      res.writeHead(200,{'Content-Type':'application/json'});
      res.flushHeaders();
      const timer=setTimeout(()=>res.end('{}'),500);
      res.on('close',()=>clearTimeout(timer));
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    t.after(()=>{server.closeAllConnections();return new Promise(resolve=>server.close(resolve));});
    const provider=await createProvider({timeoutMs:100,maxRetries:0,provider:{kind:'Custom_OpenAI',model:'fixture',baseUrl:`http://127.0.0.1:${server.address().port}/v1`}});
    await assert.rejects(provider('The gate is open.','zh-Hant',{batch}),{message:'provider timeout'});
  });
}
