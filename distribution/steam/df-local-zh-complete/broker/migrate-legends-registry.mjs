import {readFile,writeFile,rename,copyFile,constants} from 'node:fs/promises';

const [path,auditPath,flag]=process.argv.slice(2);
if (!path || !auditPath || (flag && flag!=='--apply')) {
  throw Error('Usage: node migrate-legends-registry.mjs REGISTRY LIVE_AUDIT [--apply]');
}

const data=JSON.parse(await readFile(path,'utf8'));
const audit=JSON.parse(await readFile(auditPath,'utf8'));
if (!data.world || data.world!==audit.world) throw Error('World mismatch');
if (!Array.isArray(data.entities) || !Array.isArray(audit.samples) || !audit.samples.length) {
  throw Error('Registry or live audit is empty');
}
const byId=new Map(data.entities.map(row=>[row.id,row]));
const kinds=new Set(['site','artifact','region','entity','layer']);
for (const sample of audit.samples) {
  const row=byId.get(sample.id);
  if (!row || row.aliases?.[0]!==sample.native) {
    throw Error(`Native alias mismatch: ${sample.id}`);
  }
}
for (const kind of kinds) {
  if (data.entities.some(row=>row.id?.startsWith(`${kind}:`)) &&
      !audit.samples.some(row=>row.id?.startsWith(`${kind}:`))) {
    throw Error(`Missing live native sample: ${kind}`);
  }
}

let updated=0;
for (const row of data.entities) {
  const kind=row.id?.split(':',1)[0];
  if (kinds.has(kind) && typeof row.aliases?.[0]==='string' && row.aliases[0] &&
      row.nativeName!==row.aliases[0]) {
    row.nativeName=row.aliases[0];
    updated++;
  }
}
if (flag==='--apply' && updated) {
  await copyFile(path,path+'.before-native-list',constants.COPYFILE_EXCL);
  const temporary=path+'.native-list.tmp';
  await writeFile(temporary,JSON.stringify(data),'utf8');
  await rename(temporary,path);
}
console.log(JSON.stringify({world:data.world,samples:audit.samples.length,updated,
  applied:flag==='--apply'}));
