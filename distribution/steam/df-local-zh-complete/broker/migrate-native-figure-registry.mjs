import {readFile,writeFile,rename} from 'node:fs/promises';
const [path,auditPath]=process.argv.slice(2);
if (!path || !auditPath) throw Error('Registry path and live text audit required');
const data=JSON.parse(await readFile(path,'utf8'));
const audit=JSON.parse(await readFile(auditPath,'utf8'));
if (data.world!==audit.world) throw Error('World mismatch');
const byId=new Map(data.entities.map(row=>[row.id,row]));
const samples=audit.rows.filter(row=>row.type==='figure_name');
if (!samples.length || samples.some(row=>byId.get('figure:'+row.id)?.aliases[0]!==row.native)) {
  throw Error('Native alias ordering could not be verified against live figures');
}
let count=0;
for (const row of data.entities) {
  if (row.id.startsWith('figure:') && typeof row.aliases[0]==='string' && row.aliases[0]) {
    row.nativeName=row.aliases[0];count++;
  }
}
await writeFile(path+'.native-v2.tmp',JSON.stringify(data),'utf8');
await rename(path+'.native-v2.tmp',path);
console.log(JSON.stringify({world:data.world,figures:count,verifiedSamples:samples.length}));
