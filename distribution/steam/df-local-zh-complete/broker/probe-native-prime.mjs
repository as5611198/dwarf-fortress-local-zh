import {readFile,appendFile} from 'node:fs/promises';
import {parse} from 'csv-parse/sync';
import {stringify} from 'csv-stringify/sync';
const [cachePath,probePath]=process.argv.slice(2);
const rows=parse(await readFile(cachePath,'utf8'),{columns:true,skip_empty_lines:true,bom:true});
const current=rows.findLast(row=>row.language==='zh-Hant');
if(!current || current.version!=='2') throw Error('Unsupported native cache format');
const probe=JSON.parse(await readFile(probePath,'utf8'));
if(!/^DFLOCAL_PRIME_\d+$/.test(probe.source)) throw Error('Unexpected probe source');
const added=[];
for(const kind of ['plain','markup']) for(const tag of ['','[C:7:0:1]']) {
  added.push({...current,kind,rules_first:'false',original:tag+probe.source,
    status:'translated',translation:tag+probe.translation,alignment:'left'});
}
await appendFile(cachePath,stringify(added,{columns:Object.keys(current)}),'utf8');
console.log(JSON.stringify({fingerprint:current.fingerprint,added:added.length}));
