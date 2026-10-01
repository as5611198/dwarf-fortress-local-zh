import {Buffer} from 'node:buffer';
import {verifyManifest,validatePackage,sharedIdentity} from '../../broker/official-library.mjs';
import {validateContribution} from '../../broker/shared-policy.mjs';
import {digest} from './store.mjs';
const sha=bytes=>crypto.subtle.digest('SHA-256',bytes).then(result=>Buffer.from(result).toString('hex'));
const encode=value=>new TextEncoder().encode(JSON.stringify(value)+'\n');
async function bounded(object,limit){if(!object || object.size>limit)throw Error('missing or oversized official object');const bytes=new Uint8Array(await object.arrayBuffer());if(bytes.length>limit)throw Error('official object too large');return bytes;}
async function immutable(bucket,key,bytes) {
  const existing=await bucket.get(key);
  if(existing){if(await sha(await bounded(existing,32*1024*1024))!==await sha(bytes))throw Error('immutable release conflict');return;}
  await bucket.put(key,bytes,{httpMetadata:{contentType:key.endsWith('.txt')?'text/plain; charset=utf-8':'application/json; charset=utf-8'}});
}
export async function publishApproved(env,store,now=Date.now(),{force=false}={}) {
  if(env.PUBLISH_ENABLED!=='true')return {published:false,reason:'disabled'};
  const owner=crypto.randomUUID();if(!await store.acquireLease('publish',owner,now,10*60000))return {published:false,reason:'busy'};
  let phase='base';
  try {
    const last=await store.publication();if(!force && last.last_at && now-last.last_at<3600000)return {published:false,reason:'hourly limit'};
    const bucket=env.OFFICIAL,controlObject=await bucket.get('manifest.json');
    const trust=JSON.parse(env.TRUST_JSON);
    const currentBytes=await bounded(controlObject,128*1024);
    const current=verifyManifest(Buffer.from(currentBytes),trust);
    const originals=new Map(),currentRows=new Map();
    for(const descriptor of current.packages){
      const pack=validatePackage(Buffer.from(await bounded(await bucket.get(descriptor.path),32*1024*1024)),descriptor,current);
      currentRows.set(descriptor.language,pack.entries);
      originals.set(descriptor.language,pack.entries.filter(row=>row.review!=='ai-reviewed'));
    }
    if(!originals.has('zh-Hant') || !originals.has('zh-Hans'))throw Error('complete base languages required');
    phase='candidates';
    const approved=await store.approved(),included=[],sources=[];
    const nextRows=new Map([...originals].map(([language,rows])=>[language,[...rows]]));
    const seen=new Set([...originals].flatMap(([language,rows])=>rows.map(row=>sharedIdentity(row,language))));
    for(const candidate of approved) {
      const input=validateContribution(candidate.entry),identity=sharedIdentity(input,input.language);
      if(seen.has(identity))continue;seen.add(identity);
      const row={text:input.text,translation:input.translation,context:input.context,kind:input.kind,origin:input.origin,
        source:'community-'+candidate.id.slice(0,24),review:'ai-reviewed'};
      nextRows.get(input.language).push(row);included.push(candidate.id);
      sources.push({source:row.source,language:input.language,license:input.license,review:'AI semantic review; not human review',
        devices:candidate.devices,networkSignals:candidate.networks,modelClaim:input.model,reviewer:candidate.review,
        reviewedAt:new Date(candidate.reviewed_at).toISOString(),limitations:'consensus and AI are not semantic proof or verified independent people'});
    }
    const sortRows=rows=>rows.sort((a,b)=>Buffer.compare(Buffer.from(sharedIdentity(a,'ordering')),Buffer.from(sharedIdentity(b,'ordering'))));
    for(const rows of nextRows.values())sortRows(rows);
    const withdrawn=[...new Set([...current.withdrawn,...await store.withdrawals()])].sort();
    const contentDigest=await digest(JSON.stringify({rows:[...nextRows],withdrawn}));
    const currentDigest=await digest(JSON.stringify({rows:[...currentRows].map(([lang,rows])=>[lang,sortRows([...rows])]),withdrawn:current.withdrawn}));
    if(contentDigest===currentDigest){await store.markEntriesPublished(current.version,included);return {published:false,reason:'unchanged',version:current.version};}
    if(withdrawn.length>1000)throw Error('withdrawal capacity');
    phase='sequence';
    const sequence=await store.reserveSequence(current.sequence+1);
    const version=new Date(now).toISOString().slice(0,10).replaceAll('-','.')+'.auto-'+sequence;
    const manifest={schema:1,version,rules:current.rules,sequence,publishedAt:new Date(now).toISOString(),withdrawn,packages:[]};
    phase='packages';
    for(const [language,entries] of nextRows){
      const bytes=encode({schema:1,version,language,rules:current.rules,entries});
      const descriptor={language,path:`releases/${version}/${language}.json`,entries:entries.length,bytes:bytes.length,sha256:await sha(bytes),format:'json',delta:null};
      validatePackage(Buffer.from(bytes),descriptor,manifest);manifest.packages.push(descriptor);
      await immutable(bucket,descriptor.path,bytes);
    }
    phase='signing';
    const payload=encode(manifest),keyDer=Buffer.from(env.SIGNING_KEY_PEM.replace(/-----[^-]+-----|\s/g,''),'base64');
    const key=await crypto.subtle.importKey('pkcs8',keyDer,{name:'Ed25519'},false,['sign']);
    const signature=await crypto.subtle.sign('Ed25519',key,payload);
    const envelope=encode({keyId:env.SIGNING_KEY_ID,payload:Buffer.from(payload).toString('base64'),signature:Buffer.from(signature).toString('base64')});
    verifyManifest(Buffer.from(envelope),trust);
    phase='release';
    await immutable(bucket,`releases/${version}/manifest.json`,envelope);
    await immutable(bucket,`releases/${version}/source-report.json`,encode({version,rules:current.rules,baseOwnedCounts:Object.fromEntries([...originals].map(([lang,rows])=>[lang,rows.length])),
      included:sources.length,sources,semanticCorrectnessGuaranteed:false}));
    await immutable(bucket,`releases/${version}/LICENSE.txt`,new TextEncoder().encode('Base project translations and opted-in community contributions: CC0-1.0. AI-reviewed is not human-reviewed. No private game state included.\n'));
    // Track every candidate before making the pointer reachable. If D1 fails,
    // the release stays inactive; if R2 fails, tracking an unused release is safe.
    phase='record';
    await store.markEntriesPublished(version,included);
    phase='switch';
    const latest=await bucket.get('manifest.json');
    if(!latest || await sha(await bounded(latest,128*1024))!==await sha(currentBytes))throw Error('publication head changed');
    const switched=await bucket.put('manifest.json',envelope,{onlyIf:{etagMatches:latest.etag},httpMetadata:{contentType:'application/json; charset=utf-8'}});
    if(switched===null)throw Error('publication head changed');
    phase='record';
    await store.published(sequence,version,contentDigest,now);
    return {published:true,version,sequence,entries:Object.fromEntries(manifest.packages.map(p=>[p.language,p.entries])),aiReviewed:sources.length};
  } catch(error) {
    // Never log secrets, request data, upstream messages, IPs or player text.
    const known=['publication head changed','immutable release conflict','package hash/size invalid','unsafe shared entry','missing or oversized official object','signature invalid'];
    console.error(JSON.stringify({service:'df-zh-consensus',error:'publication_failed',phase,code:known.includes(error.message)?error.message:/etag/i.test(error.message)?'invalid-etag':/body.*used/i.test(error.message)?'body-used':'runtime',type:error.name}));
    throw error;
  } finally {await store.releaseLease('publish',owner);}
}
