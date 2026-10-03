import {readFile,writeFile,rename,mkdir,rm,stat,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash,verify} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {POLICY_VERSION,validateTranslation,hasRuntimeAlias,tokenPattern} from './safety.mjs';
import {OFFICIAL_ENDPOINT,OFFICIAL_TRUST} from './official-trust.mjs';

export const MAX_PACKAGE_BYTES=32*1024*1024;
const MAX_MANIFEST_BYTES=128*1024;
const hash=value=>createHash('sha256').update(value).digest('hex');
const languages=['zh-Hant','zh-Hans'];
const check=(condition,message)=>{if(!condition) throw Error(message);};
const version=value=>typeof value==='string' && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(value);
export function sharedIdentity(row,language) {
  return JSON.stringify([POLICY_VERSION,language,row.context,row.kind,row.origin,row.text]);
}
export function safeSharedSource(text,kind='exact') {
  if(typeof text!=='string' || !text.trim() || text.length>8000 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(text) || hasRuntimeAlias(text) ||
    /DFLIVE_|region\d+|\b(?:figure|entity|artifact):\d+|^(?:World|Folder|Portable Folder):|^In \d+,|\b(?:became the|was struck down by)\b/.test(text) ||
    /^(?:He|She) is not distracted after being unable to (?:be|pray to)$/.test(text) ||
    /\blikes\b/.test(text) && !text.includes('{DWARF_NAME}')) return false;
  const tokens=text.match(tokenPattern) ?? [];
  if(tokens.some(token=>token.startsWith('{') && !/^(?:\{DWARF_NAME\}|\{\{DF[NE]\d+\}\})$/.test(token))) return false;
  if(kind==='exact' && tokens.some(token=>token.startsWith('{'))) return false;
  if(kind==='entity' && !tokens.some(token=>/^\{DWARF_NAME\}|\{\{DFE\d+\}\}$/.test(token))) return false;
  if(kind==='numeric' && !tokens.some(token=>/^\{\{DFN\d+\}\}$/.test(token))) return false;
  return true;
}
export function verifyManifest(bytes,trust=OFFICIAL_TRUST) {
  check(bytes.length<=MAX_MANIFEST_BYTES,'manifest too large');
  const envelope=JSON.parse(bytes.toString('utf8'));
  check(typeof envelope.payload==='string' && typeof envelope.signature==='string' && Object.hasOwn(trust,envelope.keyId),'signature key unknown');
  const payloadBytes=Buffer.from(envelope.payload,'base64'),signature=Buffer.from(envelope.signature,'base64');
  check(payloadBytes.toString('base64')===envelope.payload && signature.toString('base64')===envelope.signature && signature.length===64,'signature encoding invalid');
  check(verify(null,payloadBytes,trust[envelope.keyId],signature),'signature invalid');
  const m=JSON.parse(payloadBytes.toString('utf8'));
  check(m.schema===1 && m.rules===POLICY_VERSION && Number.isSafeInteger(m.sequence) && m.sequence>0 && version(m.version) &&
    typeof m.publishedAt==='string' && Number.isFinite(Date.parse(m.publishedAt)),'manifest incompatible');
  check(Array.isArray(m.withdrawn) && m.withdrawn.length<=1000 && m.withdrawn.every(version),'withdrawal invalid');
  check(Array.isArray(m.packages) && m.packages.length>0 && m.packages.length<=2 && new Set(m.packages.map(p=>p.language)).size===m.packages.length,'packages invalid');
  for(const p of m.packages) {
    check(languages.includes(p.language) && p.path===`releases/${m.version}/${p.language}.json` && p.format==='json' && p.delta===null &&
      Number.isSafeInteger(p.entries) && p.entries>=0 && p.entries<=200000 && Number.isSafeInteger(p.bytes) && p.bytes>0 && p.bytes<=MAX_PACKAGE_BYTES &&
      typeof p.sha256==='string' && /^[0-9a-f]{64}$/.test(p.sha256),'package metadata invalid');
  }
  check(!m.withdrawn.includes(m.version),'release withdrawn');
  return m;
}
export function validatePackage(bytes,descriptor,manifest) {
  check(bytes.length===descriptor.bytes && bytes.length<=MAX_PACKAGE_BYTES && hash(bytes)===descriptor.sha256,'package hash/size invalid');
  const pack=JSON.parse(bytes.toString('utf8'));
  check(pack.schema===1 && pack.version===manifest.version && pack.language===descriptor.language && pack.rules===POLICY_VERSION &&
    Array.isArray(pack.entries) && pack.entries.length===descriptor.entries,'package incompatible');
  const seen=new Set();
  for(const row of pack.entries) {
    check(row && Object.keys(row).every(k=>['text','translation','context','kind','origin','source','review','conversion','alignment'].includes(k)) &&
      ['general','ui','description','name-template'].includes(row.context) && ['exact','numeric','entity'].includes(row.kind) &&
      row.origin==='vanilla' && ['reviewed','ai-reviewed'].includes(row.review) && version(row.source) &&
      (row.conversion===undefined || row.conversion==='zh-Hant-opencc-unreviewed-terminology') &&
      (row.alignment===undefined || ['left','center','right'].includes(row.alignment)) && safeSharedSource(row.text,row.kind),'unsafe shared entry');
    validateTranslation(row.text,row.translation);
    const identity=sharedIdentity(row,pack.language);check(!seen.has(identity),'duplicate shared identity');seen.add(identity);
  }
  return pack;
}

// Separate from AI journals. Each commit points at complete immutable verified files.
// New versions may be staged during gameplay, but never enter the current snapshot.
export class OfficialLibrary {
  constructor({directory,endpoint=OFFICIAL_ENDPOINT,trust=OFFICIAL_TRUST,fetcher=fetch,canActivate=()=>false,
    timeoutMs=20000,retries=2,retryBaseMs=1000}={}) {
    this.root=join(directory,'official');this.endpoint=endpoint;this.trust=trust;this.fetcher=fetcher;this.canActivate=canActivate;
    this.timeoutMs=timeoutMs;this.retries=retries;this.retryBaseMs=retryBaseMs;this.writeFile=writeFile;
    this.state={schema:1,highestSequence:0,highestManifest:null,languages:{}};
    this.snapshots=new Map();this.progress=new Map();this.running=null;this.clearing=null;this.timer=null;this.withdrawn=new Set();
  }
  status(language) {
    const state=this.state.languages[language] ?? {},snapshot=this.snapshots.get(language);
    return {schema:1,language,installedVersion:state.active?.version ?? '',activeVersion:snapshot?.version ?? '',
      availableVersion:state.pending?.version ?? state.active?.version ?? '',entries:snapshot?.entries.length ?? 0,
      lastSuccess:state.lastSuccess ?? '',phase:state.pending?'pending':snapshot?'complete':this.state.cleared?'cleared':'idle',progress:state.pending||snapshot?100:0,
      activation:'遊戲執行中延後；關閉遊戲後重啟服務啟用',...(this.progress.get(language) ?? {})};
  }
  async publish(language) {
    await mkdir(this.root,{recursive:true});
    await this.atomic(join(this.root,`status-${language}.json`),this.status(language));
  }
  async atomic(path,value) {
    const temp=path+`.${process.pid}.tmp`;
    try {await this.writeFile(temp,JSON.stringify(value)+'\n',{encoding:'utf8',mode:0o600});await rename(temp,path);}
    finally {await rm(temp,{force:true}).catch(()=>{});}
  }
  async verifiedRecord(record,language) {
    check(record && version(record.version) && record.packageFile===`${record.version}-${language}-${record.sha256}.json` &&
      record.manifestFile===`${record.version}-${record.sequence}.manifest.json`,'local record invalid');
    check(!this.withdrawn.has(record.version),'release withdrawn');
    const manifestPath=join(this.root,record.manifestFile);
    check((await stat(manifestPath)).size<=MAX_MANIFEST_BYTES,'manifest too large');
    const m=verifyManifest(await readFile(manifestPath),this.trust);
    check(m.version===record.version && m.sequence===record.sequence,'local manifest mismatch');
    const p=m.packages.find(p=>p.language===language);check(p && p.sha256===record.sha256,'local descriptor invalid');
    const path=join(this.root,record.packageFile);check((await stat(path)).size<=MAX_PACKAGE_BYTES,'package too large');
    const pack=validatePackage(await readFile(path),p,m);
    this.state.highestSequence=Math.max(this.state.highestSequence,m.sequence);
    return pack;
  }
  async load() {
    const started=performance.now();await mkdir(this.root,{recursive:true});
    try {
      const state=JSON.parse(await readFile(join(this.root,'state.json'),'utf8'));
      check(state.schema===1 && Number.isSafeInteger(state.highestSequence) && state.highestSequence>=0 && state.languages && typeof state.languages==='object','local state invalid');
      this.state=state;
    } catch(e) {if(e.code!=='ENOENT') this.progress.set('zh-Hant',{phase:'error',error:'本機譯庫狀態損壞'});}
    // Read signed revocations separately from package contents. A damaged
    // replacement must never make a withdrawn old package usable again.
    for(const row of Object.values(this.state.languages)) for(const record of [row.active,row.pending,row.previous]) {
      if(!record || !version(record.version) || !Number.isSafeInteger(record.sequence) || record.manifestFile!==`${record.version}-${record.sequence}.manifest.json`)continue;
      try {
        const path=join(this.root,record.manifestFile);check((await stat(path)).size<=MAX_MANIFEST_BYTES,'manifest too large');
        const manifest=verifyManifest(await readFile(path),this.trust);
        check(manifest.version===record.version && manifest.sequence===record.sequence,'local manifest mismatch');
        for(const revoked of manifest.withdrawn)this.withdrawn.add(revoked);
      } catch { /* An invalid signature cannot supply revocations. */ }
    }
    const safe=await this.canActivate();
    for(const language of languages) {
      const state=this.state.languages[language];if(!state) continue;
      if(this.withdrawn.has(state.previous?.version))delete state.previous;
      if(state.pending && safe) {
        try {const pack=await this.verifiedRecord(state.pending,language);state.previous=this.withdrawn.has(state.active?.version)?undefined:state.active;state.active=state.pending;delete state.pending;this.snapshots.set(language,pack);}
        catch {this.progress.set(language,{phase:'error',error:'待啟用版本驗證失敗'});}
      }
      if(!this.snapshots.has(language) && state.active) {
        try {this.snapshots.set(language,await this.verifiedRecord(state.active,language));}
        catch {
          try {this.snapshots.set(language,await this.verifiedRecord(state.previous,language));state.active=state.previous;delete state.previous;this.progress.set(language,{phase:'recovered',error:'損壞版本已回復前版'});}
          catch {this.progress.set(language,{phase:'error',error:'已安裝譯庫驗證失敗'});}
        }
      }
    }
    for(const pack of this.snapshots.values()) this.index(pack);
    await this.atomic(join(this.root,'state.json'),this.state);
    for(const language of languages) {
      this.progress.set(language,{...this.progress.get(language),loadMs:performance.now()-started});await this.publish(language);
    }
  }
  index(pack) {pack.index=new Map(pack.entries.map(row=>[sharedIdentity(row,pack.language),row]));}
  lookup(text,language,{context='general',kind='exact',origin='vanilla'}={}) {
    return this.snapshots.get(language)?.index.get(sharedIdentity({text,context,kind,origin},language))?.translation;
  }
  async get(url,path,limit,language,phase) {
    const target=new URL(url);check(target.protocol==='https:' && !target.username && !target.password,'HTTPS required');
    const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),this.timeoutMs);
    const deadline=new Promise((_,reject)=>abort.signal.addEventListener('abort',()=>reject(Error('download timeout')),{once:true}));
    let response,reader;
    try {
      response=await Promise.race([this.fetcher(target,{method:'GET',redirect:'error',signal:abort.signal,headers:{Accept:'application/json'}}),deadline]);
      check(response.ok && response.body,'download HTTP failure');
      const advertised=Number(response.headers.get('content-length'));check(!advertised || advertised<=limit,'download too large');
      const chunks=[];let total=0,lastPublish=performance.now();
      reader=response.body.getReader();
      for(;;) {
        const {done,value:chunk}=await Promise.race([reader.read(),deadline]);if(done)break;
        total+=chunk.length;check(total<=limit,'download too large');chunks.push(Buffer.from(chunk));
        this.progress.set(language,{...this.progress.get(language),phase,downloadedBytes:total,totalBytes:limit,progress:Math.min(99,Math.floor(total/limit*100))});
        if(performance.now()-lastPublish>250) {await this.publish(language);lastPublish=performance.now();}
      }
      const bytes=Buffer.concat(chunks);await this.writeFile(path,bytes,{mode:0o600});return bytes;
    } finally {clearTimeout(timer);if(reader)void reader.cancel().catch(()=>{});else if(response?.body && !response.body.locked)void response.body.cancel().catch(()=>{});}
  }
  sync(language) {
    check(languages.includes(language),'language unsupported');
    if(this.clearing)return Promise.resolve(this.status(language));
    // One global task; switching languages queues the second without a parallel writer.
    if(this.running) return this.running.language===language ? this.running.promise : this.running.promise.then(()=>this.sync(language));
    const promise=this.download(language);this.running={language,promise};
    promise.finally(()=>{if(this.running?.promise===promise)this.running=null;}).catch(()=>{});return promise;
  }
  clear() {
    if(this.clearing)return this.clearing;
    const promise=(async()=>{
      await this.running?.promise;
      const state={...this.state,languages:{},cleared:true};
      await this.atomic(join(this.root,'state.json'),state);
      this.state=state;this.snapshots.clear();this.progress.clear();
      for(const name of await readdir(this.root)) {
        if(/^[a-zA-Z0-9._-]+-zh-(?:Hant|Hans)-[0-9a-f]{64}\.json$/.test(name) ||
          /^download-zh-(?:Hant|Hans)\.(?:manifest|package)\.tmp$/.test(name))await rm(join(this.root,name),{force:true});
      }
      for(const language of languages)await this.publish(language);
    })();
    this.clearing=promise;
    promise.finally(()=>{if(this.clearing===promise)this.clearing=null;}).catch(()=>{});
    return promise;
  }
  async download(language) {
    const started=performance.now();let error;
    const manifestTemp=join(this.root,`download-${language}.manifest.tmp`),packTemp=join(this.root,`download-${language}.package.tmp`);
    for(let attempt=0;attempt<=this.retries;attempt++) {
      try {
        await mkdir(this.root,{recursive:true});this.progress.set(language,{phase:'checking',progress:0});await this.publish(language);
        const envelope=await this.get(this.endpoint,manifestTemp,MAX_MANIFEST_BYTES,language,'checking');
        const m=verifyManifest(envelope,this.trust),digest=hash(envelope);
        check(m.sequence>=this.state.highestSequence && (m.sequence!==this.state.highestSequence || !this.state.highestManifest || this.state.highestManifest===digest),'untrusted rollback');
        this.progress.set(language,{phase:'downloading',availableVersion:m.version,progress:0});await this.publish(language);
        const p=m.packages.find(p=>p.language===language);check(p,'language package unavailable');
        const current=this.state.languages[language] ?? {};
        if((current.pending ?? current.active)?.sha256===p.sha256 && (current.pending ?? current.active)?.sequence===m.sequence) {
          this.progress.delete(language);await this.publish(language);return this.status(language);
        }
        const bytes=await this.get(new URL(p.path,this.endpoint),packTemp,p.bytes,language,'downloading');
        this.progress.set(language,{phase:'verifying',availableVersion:m.version,progress:100});await this.publish(language);
        const pack=validatePackage(bytes,p,m);
        const record={version:m.version,sequence:m.sequence,sha256:p.sha256,packageFile:`${m.version}-${language}-${p.sha256}.json`,manifestFile:`${m.version}-${m.sequence}.manifest.json`};
        // Files are committed before the pointer; partial writes are unreachable.
        await rename(packTemp,join(this.root,record.packageFile));await rename(manifestTemp,join(this.root,record.manifestFile));
        const state=structuredClone(this.state);state.highestSequence=m.sequence;state.highestManifest=digest;
        const row=state.languages[language] ??= {};const safe=await this.canActivate();
        if(safe) {row.previous=row.active;row.active=record;delete row.pending;}
        else row.pending=record;
        row.lastSuccess=new Date().toISOString();
        // A signed later release can withdraw an older release and authorize replacement.
        if(row.previous && m.withdrawn.includes(row.previous.version)) delete row.previous;
        await this.atomic(join(this.root,'state.json'),state);this.state=state;
        if(safe) {this.index(pack);this.snapshots.set(language,pack);this.onActivate?.(language);}
        this.progress.set(language,{phase:safe?'complete':'pending',progress:100,syncMs:performance.now()-started});
        await this.publish(language);return this.status(language);
      } catch(e) {
        error=e;
        if(attempt<this.retries) {await new Promise(resolve=>setTimeout(resolve,Math.min(10000,this.retryBaseMs*2**attempt)));}
      } finally {await Promise.all([rm(packTemp,{force:true}),rm(manifestTemp,{force:true})]).catch(()=>{});}
    }
    const reason=String(error?.message);
    const message=/signature/.test(reason)?'譯庫簽章驗證失敗':/rollback/.test(reason)?'拒絕舊版或衝突清單':/hash|size|too large/.test(reason)?'譯庫大小或雜湊不符':
      /incompatible|unsafe|duplicate/.test(reason)?'譯庫不相容或內容無效':/ENOSPC|EACCES|EPERM|disk/.test(reason+' '+error?.code)?'磁碟無法寫入；保留原版':'下載失敗或逾時；保留原版';
    this.progress.set(language,{phase:'error',error:message,progress:0,syncMs:performance.now()-started});await this.publish(language).catch(()=>{});return this.status(language);
  }
  start(settings,intervalMs=6*60*60*1000) {
    const tick=()=>{const value=settings();if(value.officialAutoDownload)void this.sync(value.language).catch(()=>{});};
    this.checkAuto=tick;
    this.timer=setInterval(tick,intervalMs);this.timer.unref?.();setImmediate(tick);
  }
  stop(){clearInterval(this.timer);this.timer=null;}
}
