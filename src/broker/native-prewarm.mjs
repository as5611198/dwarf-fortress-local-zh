import { readFile,writeFile,rename,stat,mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join,resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parse } from 'csv-parse/sync';
import { validateTranslation, hasRuntimeAlias } from './safety.mjs';
import { simplifyTree } from './language-data.mjs';

const alias=/^(?:L[A-Za-z0-9]{3}_+|L[A-Za-z0-9]{6}_+|L(?=[A-Za-z0-9]{0,5}\d)[A-Za-z0-9]{6}|P_____)[ \t]*$/;
const unmark=text=>text.replace(/\[C:\d+:\d+:\d+\]/g,'');
export function unitDisplayRows(rows,names=new Set()) {
  const fingerprint=rows.findLast(row=>row.language==='zh-Hant' && row.fingerprint)?.fingerprint;
  const latest=new Map();
  for(const row of rows) {
    if(row.language==='zh-Hant' && row.fingerprint===fingerprint &&
      ['plain','markup'].includes(row.kind) && typeof row.original==='string') latest.set(row.original,row);
  }
  const sources=[],bindings=[],fragments=new Map();
  for(const row of latest.values()) {
    if(row.status!=='translated' || !row.original || row.original.length>8000) continue;
    const text=row.original;
    if(text.startsWith('[C:')) {
      const match=/^\[C:([0-7]):([0-7]):([01])\](.+)$/.exec(text);
      if(!match || !alias.test(match[4]) || !row.translation.startsWith(match[0].slice(0,-match[4].length))) continue;
      const translation=unmark(row.translation);
      if(!translation || /[A-Za-z{}\[\]]/.test(translation)) continue;
      const color=Number(match[1])+8*Number(match[2])+64*Number(match[3]);
      fragments.set(JSON.stringify([color,translation]),{translation,color,key:match[4]});
    } else if(names.has(text) || /^(?:He|She|His|Her)\b|^Overall, (?:he|she)\b/.test(text)) {
      if(/\blikes\b/.test(text)) continue;
      try {
        const translation=validateTranslation(text,row.translation);
        (names.has(text) ? bindings : sources).push({text,translation});
      } catch { /* Keep only complete known Chinese text. */ }
    }
  }
  const byText=(a,b)=>a.text.localeCompare(b.text,'en');
  return {sources:sources.sort(byText),names:bindings.sort(byText),fragments:[...fragments.values()]};
}
export function nativePrewarmRows(rows,names=new Set()) {
  const fingerprint=rows.findLast(row=>row.language==='zh-Hant' && row.fingerprint)?.fingerprint;
  const latest=new Map();
  for(const row of rows) {
    if(row.language==='zh-Hant' && row.fingerprint===fingerprint &&
      ['plain','markup'].includes(row.kind) && typeof row.original==='string') latest.set(row.original,row);
  }
  const result=[];
  for(const row of latest.values()) {
    const text=row.original,plain=unmark(text);
    if(row.status!=='translated' || !text || text.length>8000 || !/[A-Za-z]/.test(plain) ||
      hasRuntimeAlias(plain) || /DFLIVE_|\{[^}]*\}/.test(plain) || names.has(plain) ||
      /^(?:He|She|His|Her)\b|^Overall, (?:he|she)\b|\blikes\b/.test(plain)) continue;
    try {
      result.push({text,translation:validateTranslation(text,row.translation),kind:row.kind,
        ...(['center','right'].includes(row.alignment) ? {alignment:row.alignment} : {})});
    } catch { /* Native logs can contain partial or mixed translations. */ }
  }
  return result.sort((a,b)=>a.text.localeCompare(b.text,'en'));
}

export class NativePrewarmExporter {
  constructor({cachePath,registryPath,directory,staticRows=[],literalRows=[]}) {
    this.cachePath=cachePath;this.registryPath=registryPath;
    this.output=join(directory,'native-prewarm.json');
    this.directory=directory;this.stamp=null;this.revision=null;this.running=null;this.timer=null;
    this.stats={rows:0,updates:0,errors:0};
    this.staticRows=staticRows;
    this.literalRows=literalRows;
  }
  async refresh() {
    if(this.running) return this.running;
    this.running=this.export();
    try {return await this.running;} finally {this.running=null;}
  }
  async export() {
    const [cacheInfo,registryInfo]=await Promise.all([stat(this.cachePath),stat(this.registryPath)]);
    const stamp=JSON.stringify([cacheInfo.mtimeMs,cacheInfo.size,registryInfo.mtimeMs,registryInfo.size]);
    if(stamp===this.stamp) return {...this.stats};
    const [cache,registry]=await Promise.all([readFile(this.cachePath,'utf8'),readFile(this.registryPath,'utf8')]);
    const data=JSON.parse(registry);
    if(typeof data.world!=='string' || !data.world || !Array.isArray(data.entities)) throw new Error('world registry unavailable');
    const names=new Set(data.entities.flatMap(row=>[row.preferred,...(row.aliases ?? []),...(row.shortAliases ?? [])]).filter(v=>typeof v==='string'));
    const parsed=parse(cache,{columns:true,skip_empty_lines:true,bom:true});
    const localRows=this.staticRows.map(row=>({language:'zh-Hant',fingerprint:'reviewed',
      kind:'plain',status:'translated',original:row.text,translation:row.translation}));
    const combined=new Map(nativePrewarmRows(localRows,names).map(row=>[row.text,row]));
    for(const row of nativePrewarmRows(parsed,names)) combined.set(row.text,row);
    const literals=this.literalRows.map(row=>({language:'zh-Hant',fingerprint:'reviewed',
      kind:'plain',status:'translated',original:row.text,translation:row.translation}));
    for(const row of nativePrewarmRows(literals,names)) combined.set(row.text,row);
    const rows=[...combined.values()].sort((a,b)=>a.text.localeCompare(b.text,'en'));
    const unit=unitDisplayRows(parsed,names);
    const revision=createHash('sha256').update(JSON.stringify([1,data.world,rows,unit])).digest('hex');
    if(revision!==this.revision) {
      await mkdir(this.directory,{recursive:true});
      const temporary=this.output+`.${process.pid}.tmp`;
      await writeFile(temporary,JSON.stringify({version:1,world:data.world,revision,rows,unit})+'\n','utf8');
      await rename(temporary,this.output);
      const simplified=simplifyTree(rows),simplifiedUnit=simplifyTree(unit);
      const hansOutput=join(this.directory,'native-prewarm-zh-Hans.json');
      await writeFile(hansOutput+'.tmp',JSON.stringify({version:1,world:data.world,language:'zh-Hans',
        revision:createHash('sha256').update(JSON.stringify([rows,unit,'zh-Hans'])).digest('hex'),
        rows:simplified,unit:simplifiedUnit})+'\n','utf8');
      await rename(hansOutput+'.tmp',hansOutput);
      // Runtime names and color aliases need only this small section. Keep the
      // bulk JSON for the DLL's native worker rather than parsing it in Lua.
      for(const [language,value,hash] of [['zh-Hant',unit,revision],
        ['zh-Hans',simplifiedUnit,createHash('sha256').update(JSON.stringify([rows,unit,'zh-Hans'])).digest('hex')]]) {
        const path=join(this.directory,`native-prewarm-unit${language==='zh-Hans'?'-zh-Hans':''}.json`);
        await writeFile(path+'.tmp',JSON.stringify({version:1,world:data.world,language,revision:hash,unit:value})+'\n','utf8');
        await rename(path+'.tmp',path);
      }
      this.revision=revision;this.stats.updates++;
    }
    this.stats.rows=rows.length;this.stamp=stamp;
    return {...this.stats};
  }
  start(intervalMs=2000) {
    if(this.timer) return;
    const tick=()=>{void this.refresh().catch(()=>{this.stats.errors++;});};
    this.timer=setInterval(tick,intervalMs);tick();
  }
  stop() {if(this.timer) clearInterval(this.timer);this.timer=null;}
}

if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const [cachePath,registryPath,directory,watch]=process.argv.slice(2);
  if(!cachePath || !registryPath || !directory) throw new Error('Usage: node native-prewarm.mjs <native-cache.csv> <world-names.json> <state-data-directory> [--watch=game-pid]');
  const exporter=new NativePrewarmExporter({cachePath,registryPath,directory});
  console.log(JSON.stringify(await exporter.refresh()));
  if(watch) {
    if(!/^--watch=\d+$/.test(watch)) throw new Error('Invalid game process ID');
    const pid=Number(watch.slice(8));
    const alive=()=>{try {process.kill(pid,0);return true;} catch(error) {return error.code==='EPERM';}};
    if(alive()) {
      exporter.start();
      const timer=setInterval(()=>{if(!alive()) {exporter.stop();clearInterval(timer);}},2000);
    }
  }
}
