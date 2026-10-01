import {readFile,writeFile,mkdir,rename,rm,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {validateContribution,contributionIdentity,MAX_BATCH} from './shared-policy.mjs';
export const SHARED_ENDPOINT='https://df-zh-consensus.g402111111.workers.dev/v1/contributions';
const TTL=7*86400000,MAX_ENTRIES=500,MAX_FILE=4*1024*1024;
const rowId=row=>createHash('sha256').update(JSON.stringify([contributionIdentity(row),row.translation])).digest('hex');
export class SharedOutbox {
  constructor({directory,isEnabled=()=>false,statusScope=()=>'',endpoint=SHARED_ENDPOINT,fetcher=fetch,retryMs=60000,timeoutMs=10000}={}) {
    if(!endpoint.startsWith('https://'))throw Error('shared endpoint requires HTTPS');
    Object.assign(this,{root:join(directory,'shared'),isEnabled,statusScope,endpoint,fetcher,retryMs,timeoutMs});this.writeFile=writeFile;
    this.state={schema:1,deviceId:randomBytes(32).toString('hex'),entries:[],sent:0,lastSuccess:''};this.tail=Promise.resolve();this.phase='idle';this.stopped=false;
  }
  async atomic(name,value) {await mkdir(this.root,{recursive:true});const path=join(this.root,name),temporary=path+'.'+randomUUID()+'.tmp';
    try {const data=JSON.stringify(value)+'\n';if(Buffer.byteLength(data)>MAX_FILE)throw Error('outbox capacity');await this.writeFile(temporary,data,{mode:0o600});await rename(temporary,path);}finally {await rm(temporary,{force:true}).catch(()=>{});}}
  mutate(action){const job=this.tail.then(action);this.tail=job.catch(()=>{});return job;}
  async load() {
    try {if((await stat(join(this.root,'state.json'))).size>MAX_FILE)throw Error('outbox too large');const state=JSON.parse(await readFile(join(this.root,'state.json'),'utf8'));
      if(state.schema!==1 || !/^[a-f0-9]{64}$/.test(state.deviceId) || !Array.isArray(state.entries) || state.entries.length>MAX_ENTRIES)throw Error('outbox invalid');
      for(const job of state.entries){validateContribution(job.entry);if(job.id!==rowId(job.entry) || typeof job.scope!=='string' || job.scope.length>128 || !Number.isFinite(job.created))throw Error('outbox invalid');}
      this.state=state;
    }catch(error){if(error.code!=='ENOENT'){this.phase='error';this.error='待送資料損壞，請清除後再試';}}
    await this.publish();
  }
  status(scope=this.statusScope()) {return {schema:1,enabled:this.isEnabled(scope),pending:this.state.entries.length,sent:this.state.sent??0,
    lastSuccess:this.state.lastSuccess??'',phase:this.phase,...(this.error?{error:this.error}:{})};}
  async publish(scope=this.statusScope()){await this.atomic('status.json',this.status(scope));}
  async capture(input,scope='') {
    if(this.stopped || !this.isEnabled(scope))return false;
    let entry;try{entry=validateContribution(input);}catch{return false;}
    if(typeof scope!=='string' || scope.length>128 || /[\\/\0]/.test(scope))return false;
    return this.mutate(async()=>{
      if(this.stopped || !this.isEnabled(scope))return false;
      const before=structuredClone(this.state),now=Date.now(),id=rowId(entry);
      this.state.entries=this.state.entries.filter(job=>now-job.created<TTL);
      if(this.state.entries.some(job=>job.id===id) || this.state.entries.length>=MAX_ENTRIES)return false;
      this.state.entries.push({id,entry,scope,created:now,attempts:0,nextAttempt:0});
      try {await this.atomic('state.json',this.state);}catch(error){this.state=before;throw error;}
      this.phase='pending';this.error=undefined;await this.publish(scope);return true;
    });
  }
  flush(){if(this.running)return this.running;this.running=this.send().finally(()=>{this.running=null;});return this.running;}
  async send() {
    let jobs;
    await this.mutate(async()=>{const now=Date.now();jobs=this.state.entries.filter(job=>!this.stopped && !job.stalled && now-job.created<TTL &&
      this.isEnabled(job.scope) && (job.nextAttempt??0)<=now).slice(0,MAX_BATCH).map(job=>structuredClone(job));});
    if(!jobs.length)return;
    this.phase='sending';await this.publish();let timer;
    jobs=jobs.filter(job=>!this.stopped && this.isEnabled(job.scope));
    if(!jobs.length){this.phase=this.state.entries.length?'pending':'idle';await this.publish();return;}
    const controller=new AbortController();this.controller=controller;
    try {
      const payload={schema:1,deviceId:this.state.deviceId,batchId:randomUUID(),entries:jobs.map(job=>validateContribution(job.entry))};
      const response=await Promise.race([this.fetcher(this.endpoint,{method:'POST',redirect:'error',headers:{'content-type':'application/json'},body:JSON.stringify(payload),signal:controller.signal}),
        new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(Error('upload timeout'));},this.timeoutMs);timer.unref?.();})]);
      if(response.status!==202)throw Error('upload rejected');
      const reader=response.body?.getReader();if(!reader)throw Error('receipt missing');
      const text=await Promise.race([(async()=>{const chunks=[];let length=0;try{for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>8192)throw Error('receipt too large');chunks.push(value);}return Buffer.concat(chunks).toString('utf8');}finally{void reader.cancel().catch(()=>{});}})(),
        new Promise((_,reject)=>{if(controller.signal.aborted)return reject(Error('upload timeout'));controller.signal.addEventListener('abort',()=>reject(Error('upload timeout')),{once:true});})]);
      if(text.length>8192)throw Error('receipt too large');const result=JSON.parse(text);
      if(!Array.isArray(result.accepted) || result.accepted.length!==jobs.length || result.accepted.some((row,i)=>row.id!==jobs[i].id || typeof row.counted!=='boolean'))throw Error('receipt invalid');
      await this.mutate(async()=>{const previous=structuredClone(this.state),ids=new Set(jobs.map(job=>job.id));
        this.state.entries=this.state.entries.filter(job=>!ids.has(job.id));this.state.sent=(this.state.sent??0)+jobs.length;this.state.lastSuccess=new Date().toISOString();
        try{await this.atomic('state.json',this.state);}catch(error){this.state=previous;throw error;}});
      this.phase='complete';this.error=undefined;
    }catch{
      await this.mutate(async()=>{const previous=structuredClone(this.state),ids=new Set(jobs.map(job=>job.id));
        for(const job of this.state.entries)if(ids.has(job.id)){job.attempts=(job.attempts??0)+1;job.nextAttempt=Date.now()+Math.min(86400000,this.retryMs*2**Math.min(job.attempts-1,10));job.stalled=job.attempts>=6;}
        try{await this.atomic('state.json',this.state);}catch{this.state=previous;}});
      this.phase='error';this.error='共享上報失敗；保留待送資料稍後重試';
    }finally {clearTimeout(timer);this.controller=null;await this.publish();}
  }
  async clear(){this.controller?.abort();await this.mutate(async()=>{const previous=structuredClone(this.state);this.state.entries=[];
    try{await this.atomic('state.json',this.state);}catch(error){this.state=previous;throw error;}this.phase='idle';this.error=undefined;await this.publish();});}
  start(){if(this.timer)return;this.stopped=false;this.timer=setInterval(()=>void this.flush().catch(()=>{}),15000);this.timer.unref?.();void this.flush().catch(()=>{});}
  stop(){this.stopped=true;clearInterval(this.timer);this.timer=null;this.controller?.abort();}
  consentChanged(){this.controller?.abort();void this.publish().catch(()=>{});}
}
