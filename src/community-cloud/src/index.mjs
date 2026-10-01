import {timingSafeEqual} from 'node:crypto';
import {isIP} from 'node:net';
import {MAX_BODY,MAX_BATCH,validateContribution} from '../../broker/shared-policy.mjs';
import {ConsensusStore} from './store.mjs';
import {reviewCandidate,REVIEW_MODEL,REVIEW_POLICY} from './reviewer.mjs';
import {publishApproved} from './publisher.mjs';
import distribution from '../../official-cloud/src/index.mjs';
const reply=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
async function bodyJson(request,limit=MAX_BODY) {
  if(Number(request.headers.get('content-length'))>limit)throw Error('too large');
  if(!request.body)throw Error('invalid body');
  const reader=request.body.getReader(),chunks=[];let bytes=0,timer;
  try {
    return await Promise.race([(async()=>{for(;;){const {done,value}=await reader.read();if(done)break;bytes+=value.length;if(bytes>limit)throw Error('too large');chunks.push(value);}
      const result=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){result.set(chunk,offset);offset+=chunk.length;}return JSON.parse(new TextDecoder().decode(result));})(),
      new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('body deadline')),10000);timer.unref?.();})]);
  }finally {clearTimeout(timer);void reader.cancel().catch(()=>{});}
}
async function hmac(secret,value){
  if(typeof secret!=='string' || secret.length<16)throw Error('unavailable');
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(value)))].map(b=>b.toString(16).padStart(2,'0')).join('');
}
export function networkGroup(ip) {
  if(typeof ip!=='string')throw Error('unavailable');
  if(ip.startsWith('::ffff:') && isIP(ip.slice(7))===4)ip=ip.slice(7);
  if(isIP(ip)===4)return ip.split('.').slice(0,3).join('.')+'.0/24';
  if(isIP(ip)===6){const [left,right]=ip.toLowerCase().split('::'),a=left?left.split(':'):[],b=right?right.split(':'):[];
    const full=right===undefined?a:[...a,...Array(8-a.length-b.length).fill('0'),...b];return full.slice(0,4).map(p=>p.padStart(4,'0')).join(':')+'::/64';}
  throw Error('unavailable');
}
async function operator(request,env) {
  const supplied=request.headers.get('authorization')?.replace(/^Bearer /,'')??'';
  if(!env.ADMIN_TOKEN || supplied.length>256)return false;
  const hash=async value=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)));
  return timingSafeEqual(await hash(supplied),await hash(env.ADMIN_TOKEN));
}
export async function runPipeline(env,{forcePublish=false}={}) {
  const store=new ConsensusStore(env.DB),owner=crypto.randomUUID(),now=Date.now();
  if(!await store.acquireLease('review-loop',owner,now,5*60000))return {busy:true};
  const reviews=[];
  try {
    if(env.REVIEW_ENABLED==='true')for(let i=0;i<2;i++){
      const claim=await store.claimReview(Date.now(),20);if(!claim)break;
      const result=await reviewCandidate(env,claim.entry);await store.finishReview(claim,result);
      reviews.push({id:claim.id,verdict:result.verdict,approved:result.approved,elapsedMs:result.elapsedMs});
    }
    const publication=await publishApproved(env,store,Date.now(),{force:forcePublish});await store.clean();
    return {reviews,publication};
  }finally {await store.releaseLease('review-loop',owner);}
}
export default {
  async fetch(request,env,ctx) {
    const path=new URL(request.url).pathname;
    if(env.DISTRIBUTION_READ==='true' && request.method==='GET' && (path==='/manifest.json' || path.startsWith('/releases/')))return distribution.fetch(request,env);
    if(path==='/health' && request.method==='GET')return reply({service:'df-zh-consensus',schema:1,reviewer:REVIEW_MODEL,reviewPolicy:REVIEW_POLICY,
      reviewEnabled:env.REVIEW_ENABLED==='true',publishEnabled:env.PUBLISH_ENABLED==='true',consensusDevices:3,consensusNetworks:3,dailyReviewLimit:20,
      provenance:'AI reviewed, not human reviewed',staging:env.STAGING==='true'});
    if(request.headers.get('origin'))return reply({error:'browser submissions disabled'},403);
    if(path==='/v1/contributions' && request.method==='POST') {
      if(env.COLLECTION_ENABLED==='false')return reply({error:'collection paused'},503);
      if(!request.headers.get('content-type')?.startsWith('application/json'))return reply({error:'JSON required'},415);
      try {
        const body=await bodyJson(request);
        if(!body || Object.keys(body).some(k=>!['schema','deviceId','batchId','entries'].includes(k)) || body.schema!==1 ||
          !/^[a-f0-9]{64}$/.test(body.deviceId) || !/^[a-f0-9-]{36}$/.test(body.batchId) || !Array.isArray(body.entries) ||
          body.entries.length<1 || body.entries.length>MAX_BATCH)throw Error('unsafe contribution');
        const entries=body.entries.map(validateContribution);
        const network=await hmac(env.HMAC_SECRET,'network:'+networkGroup(request.headers.get('CF-Connecting-IP')));
        const device=await hmac(env.HMAC_SECRET,'device:'+body.deviceId);
        const store=new ConsensusStore(env.DB),accepted=[];
        for(const entry of entries)accepted.push(await store.ingest(entry,{device,network}));
        return reply({accepted},202);
      }catch(error){return reply({error:error.message==='rate limited'?'rate limited':error.message==='too large'?'payload too large':error.message==='unavailable'?'temporarily unavailable':'invalid contribution'},
        error.message==='rate limited'?429:error.message==='too large'?413:error.message==='unavailable'?503:422);}
    }
    if(path==='/admin/run' && request.method==='POST') {
      if(!await operator(request,env))return reply({error:'forbidden'},403);
      try {const options=await bodyJson(request,2048);if(Object.keys(options).some(k=>k!=='forcePublish') || options.forcePublish!==undefined && typeof options.forcePublish!=='boolean')return reply({error:'invalid action'},422);
        return reply(await runPipeline(env,options));}catch{return reply({error:'pipeline failed'},503);}
    }
    if(path==='/admin/withdraw' && request.method==='POST') {
      if(!await operator(request,env))return reply({error:'forbidden'},403);
      try {const input=await bodyJson(request,2048);if(!/^[a-f0-9]{64}$/.test(input.id) || typeof input.reason!=='string' || input.reason.length<8 || input.reason.length>300)return reply({error:'invalid withdrawal'},422);
        await new ConsensusStore(env.DB).withdraw(input.id,input.reason);return reply(await runPipeline(env,{forcePublish:true}));}catch{return reply({error:'withdrawal failed'},503);}
    }
    return reply({error:'not found'},404);
  },
  async scheduled(controller,env,ctx) {
    ctx.waitUntil(runPipeline(env).catch(()=>{console.error(JSON.stringify({service:'df-zh-consensus',error:'pipeline_failed'}));}));
  },
};
