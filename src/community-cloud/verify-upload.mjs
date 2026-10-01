import assert from 'node:assert/strict';
import {mkdtemp,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SharedOutbox} from '../broker/shared-outbox.mjs';
const directory=await mkdtemp(join(tmpdir(),'df-consensus-upload-'));
const outbox=new SharedOutbox({directory,isEnabled:()=>true,endpoint:'https://df-zh-consensus-staging.g402111111.workers.dev/v1/contributions'});
await outbox.load();
await outbox.capture({schema:1,rules:'df-zh-3',language:'zh-Hant',context:'general',kind:'exact',origin:'vanilla',
 text:'They feel lonely after being unable to socialize.',translation:'他們因為無法社交而感到孤單。',model:'synthetic-staging-http-only',license:'CC0-1.0'},'isolated-private-fixture');
const start=performance.now();await outbox.flush();const elapsedMs=performance.now()-start;
assert.equal(outbox.status().sent,1);assert.equal(outbox.status().pending,0);outbox.stop();
const result={passed:true,staging:true,synthetic:true,elapsedMs,sent:1,pending:0,realHTTPSReceipt:true};
await writeFile(new URL('../text-audit/phase2-staging-upload.json',import.meta.url),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
