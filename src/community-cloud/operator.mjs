// Operator-only utility. Secrets stay outside the source tree and are never printed.
import {readFile,writeFile} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
const [environment,action,...args]=process.argv.slice(2);
if(!['staging','production'].includes(environment) || !['run','withdraw'].includes(action))throw Error('Usage: node operator.mjs staging|production run|withdraw [candidate-id reason]');
const secret=JSON.parse(await readFile(join(homedir(),'.df-zh-publisher',`consensus-${environment}-secrets.json`),'utf8'));
const endpoint=`https://df-zh-consensus${environment==='staging'?'-staging':''}.g402111111.workers.dev`;
const body=action==='run'?{forcePublish:environment==='staging'}:{id:args[0],reason:args[1]};
const start=performance.now();
const response=await fetch(endpoint+'/admin/'+action,{method:'POST',redirect:'error',signal:AbortSignal.timeout(115000),
  headers:{'content-type':'application/json',authorization:'Bearer '+secret.ADMIN_TOKEN},body:JSON.stringify(body)});
const result={environment,action,status:response.status,elapsedMs:Math.round(performance.now()-start),result:await response.json()};
await writeFile(new URL(`../text-audit/phase2-${environment}-${action}-${Date.now()}.json`,import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result,null,2));if(!response.ok)process.exitCode=1;
