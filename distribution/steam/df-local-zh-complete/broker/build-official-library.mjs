import {readFile,writeFile,mkdir,readdir,stat} from 'node:fs/promises';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash,sign,createPrivateKey} from 'node:crypto';
import {parse} from 'csv-parse/sync';
import {ownedRows} from './official-owned.mjs';
import {simplify} from './language-data.mjs';
import {POLICY_VERSION} from './safety.mjs';
import {sharedIdentity,validatePackage} from './official-library.mjs';
const root=dirname(fileURLToPath(import.meta.url));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function immutable(path,content) {
  const bytes=Buffer.from(content);
  try {if(!(await readFile(path)).equals(bytes))throw Error('immutable release conflict');}
  catch(error){if(error.code!=='ENOENT')throw error;await writeFile(path,bytes);}
}
export async function buildOfficial({output,version,sequence,keyPath,keyId='df-official-20261001',publishedAt}) {
  const sources=[];
  for(const name of ['corrections.csv','reviewed.csv',...(await readdir(join(root,'data'))).filter(name=>/\.csv$|\.jsonl$|corrections\.json$/.test(name)).sort().map(name=>'data/'+name)]) {
    const path=join(root,name),info=await stat(path);let rows;
    if(name.endsWith('.csv')) {try{rows=parse(await readFile(path,'utf8'),{columns:true,bom:true,skip_empty_lines:true}).length;}catch{}}
    sources.push({path:name,bytes:info.size,rows:rows ?? null,disposition:'excluded',reason:/prewarmed|translations|runtime|legends|case/.test(name)?'model-unreviewed-or-private-context':'redistribution-or-provenance-not-confirmed'});
  }
  const owned=ownedRows(),conflicts=[],duplicates=[];
  const unique=new Map();
  for(const row of owned) {
    const key=sharedIdentity(row,'zh-Hant'),previous=unique.get(key);
    if(previous) {if(previous.translation!==row.translation) conflicts.push({text:row.text,decision:'lexicographic-source-first'});else duplicates.push(row.text);continue;}
    unique.set(key,row);
  }
  if(conflicts.length)throw Error('owned source conflicts require explicit review');
  const entries=[...unique.values()].sort((a,b)=>Buffer.compare(Buffer.from(sharedIdentity(a,'zh-Hant')),Buffer.from(sharedIdentity(b,'zh-Hant'))));
  const manifest={schema:1,sequence,version,rules:POLICY_VERSION,publishedAt,withdrawn:[],packages:[]};
  const release=join(output,'releases',version);await mkdir(release,{recursive:true});
  for(const language of ['zh-Hant','zh-Hans']) {
    const rows=language==='zh-Hant'?entries:entries.map(row=>({...row,translation:simplify(row.translation),conversion:'zh-Hant-opencc-unreviewed-terminology'}));
    const bytes=Buffer.from(JSON.stringify({schema:1,version,language,rules:POLICY_VERSION,entries:rows})+'\n');
    const descriptor={language,path:`releases/${version}/${language}.json`,entries:rows.length,bytes:bytes.length,sha256:hash(bytes),format:'json',delta:null};
    validatePackage(bytes,descriptor,manifest);manifest.packages.push(descriptor);
    const path=join(release,language+'.json');
    try{const old=await readFile(path);if(!old.equals(bytes))throw Error('immutable release already exists');}catch(e){if(e.code!=='ENOENT')throw e;await writeFile(path,bytes);}
  }
  const privateKey=createPrivateKey(await readFile(keyPath)),payload=Buffer.from(JSON.stringify(manifest));
  const envelope={keyId,payload:payload.toString('base64'),signature:sign(null,payload,privateKey).toString('base64')};
  await immutable(join(release,'manifest.json'),JSON.stringify(envelope)+'\n');await writeFile(join(output,'manifest.json'),JSON.stringify(envelope)+'\n');
  await immutable(join(release,'LICENSE.txt'),'Project-authored Chinese translations: CC0-1.0. https://creativecommons.org/publicdomain/zero/1.0/\nNo upstream Chinese Workshop data, AI caches or private world state is included.\n');
  const report={version,rules:POLICY_VERSION,sources:[{path:'official-owned.mjs',sha256:hash(await readFile(join(root,'official-owned.mjs'))),license:'CC0-1.0',disposition:'included',entries:entries.length,review:'independent editorial review; structural validation is not semantic proof'},...sources],included:entries.length,excludedSources:sources.length,conflicts,duplicates,conversion:'zh-Hans from reviewed zh-Hant using opencc-js; terminology not separately reviewed'};
  await immutable(join(release,'source-report.json'),JSON.stringify(report,null,2)+'\n');
  return {manifest,report};
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const [output,version,sequence,keyPath,publishedAt]=process.argv.slice(2);
  if(!output || !version || !sequence || !keyPath || !publishedAt)throw Error('Usage: output version sequence private-key-path published-at');
  const {manifest,report}=await buildOfficial({output,version,sequence:Number(sequence),keyPath,publishedAt});
  console.log(JSON.stringify({manifest,included:report.included,excludedSources:report.excludedSources,conflicts:report.conflicts.length}));
}
