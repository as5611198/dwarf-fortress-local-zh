import {execFileSync} from 'node:child_process';
import {mkdir,readdir,readFile,writeFile,cp} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const metadata=JSON.parse(execFileSync('cargo',['metadata','--format-version=1','--filter-platform','x86_64-pc-windows-msvc'],{cwd:join(root,'src/df-local-zh-native'),encoding:'utf8',maxBuffer:32*1024*1024}));
const packages=new Map(metadata.packages.map(p=>[p.id,p]));
const nodes=new Map(metadata.resolve.nodes.map(n=>[n.id,n]));
const seen=new Set();
function visit(id){if(seen.has(id))return;seen.add(id);for(const dep of nodes.get(id)?.deps??[])if(dep.dep_kinds.some(k=>k.kind!=='dev'))visit(dep.pkg);}
for(const p of metadata.packages)if(['df-local-zh-broker','df_local_zh_core'].includes(p.name))visit(p.id);
const destination=join(root,'src/df-local-zh-native/third-party-licenses/rust-broker');
await mkdir(destination,{recursive:true});
const records=[];
for(const id of [...seen].sort()){
 const p=packages.get(id);if(!p.source)continue;
 const dir=dirname(p.manifest_path);const licenses=(await readdir(dir)).filter(name=>/^(?:LICEN[CS]E|COPYING|NOTICE|UNLICENSE)(?:[._-]|$)/i.test(name));
 const files=[];for(const name of licenses){try{const data=await readFile(join(dir,name));if(data.length>512*1024)throw Error('license too large');const target=`${p.name}-${p.version}/${name}`;await mkdir(dirname(join(destination,target)),{recursive:true});await cp(join(dir,name),join(destination,target));files.push(target);}catch(error){if(error.code!=='EISDIR')throw error;}}
 if(p.license_file&&!files.some(n=>n.endsWith('/'+p.license_file))){const target=`${p.name}-${p.version}/LICENSE-upstream.txt`;await mkdir(dirname(join(destination,target)),{recursive:true});await cp(join(dir,p.license_file),join(destination,target));files.push(target);}
 if(!files.length){
   const simple=p.license?.split(/\s+OR\s+/).includes('Apache-2.0')?'LICENSE-APACHE':p.license==='MIT'?'LICENSE-MIT':null;
   const donor=metadata.packages.find(other=>other.name==='serde' || other.name==='anyhow');
   if(!simple || !donor)throw Error(`Missing dependency license: ${p.name} ${p.version}`);
   const target=`${p.name}-${p.version}/LICENSE-SPDX-${p.license}.txt`;
   await mkdir(dirname(join(destination,target)),{recursive:true});
   if(simple==='LICENSE-MIT') {
     const license=await readFile(join(dirname(donor.manifest_path),simple),'utf8');
     await writeFile(join(destination,target),license.replace(/^Copyright.*$/m,`Copyright ${p.authors?.join('; ') || p.name+' contributors'}`));
   } else await cp(join(dirname(donor.manifest_path),simple),join(destination,target));files.push(target);
 }
 records.push({name:p.name,version:p.version,license:p.license,repository:p.repository,files});
}
await writeFile(join(destination,'DEPENDENCIES.json'),JSON.stringify({schema:1,target:'x86_64-pc-windows-msvc',packages:records},null,2)+'\n');
console.log(`Collected licenses for ${records.length} Rust dependencies.`);
