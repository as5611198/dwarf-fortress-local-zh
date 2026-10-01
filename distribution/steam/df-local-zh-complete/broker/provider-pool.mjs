import {createProvider} from './provider.mjs';

// A physical request ceiling shared by every member, including its batch path.
function physicalGate(limit) {
  let active=0;
  const waiting=[];
  const pump=()=>{
    while(active<limit && waiting.length) {
      const row=waiting.shift();clearTimeout(row.timer);
      if(Date.now()>=row.deadline) {row.reject(new Error('provider timeout'));continue;}
      active++;row.resolve();
    }
  };
  return {
    get active(){return active;},
    async run(action,deadline) {
      await new Promise((resolve,reject)=>{
        const row={resolve,reject,deadline};
        row.timer=setTimeout(()=>{
          const index=waiting.indexOf(row);
          if(index>=0) {waiting.splice(index,1);reject(new Error('provider timeout'));}
        },Math.max(1,deadline-Date.now()));
        waiting.push(row);pump();
      });
      try {return await action();} finally {active--;pump();}
    },
  };
}

export async function createProviderPool({profiles=[],concurrency=2,...config}) {
  if(!Number.isSafeInteger(concurrency) || concurrency<1 || concurrency>32) throw new Error('invalid pool concurrency');
  const gate=physicalGate(concurrency);
  const enabled=profiles.filter(row=>row.profile?.enabled);
  const members=[];
  for(const {id,profile} of enabled) {
    const capacity=profile.concurrency ?? 2;
    const provider=await createProvider({...config,provider:profile,concurrency:capacity,
      // Preserve single-API repair/retry behavior; multi-API retries belong to the pool.
      maxRetries:enabled.length>1 ? 0 : config.maxRetries,
      physicalLimiter:(action,deadline)=>gate.run(action,deadline)});
    if(provider) members.push({id,capacity,provider,active:0,requests:0,completed:0,failed:0,cooldownUntil:0});
  }
  if(!members.length) return null;
  let cursor=0,failovers=0;
  const pool=async(text,language,options={})=>{
    const deadline=Math.min(options.deadline ?? Infinity,Date.now()+(config.timeoutMs ?? 25000));
    const tried=new Set();let lastError;
    const attempts=members.length===1 ? 1 : Math.min(members.length,(config.maxRetries ?? 2)+1);
    for(let attempt=0;attempt<attempts;attempt++) {
      if(Date.now()>=deadline) throw new Error('provider timeout');
      const candidates=members.map((member,index)=>({member,index}))
        .filter(({member})=>!tried.has(member.id) && member.cooldownUntil<=Date.now())
        .sort((a,b)=>a.member.active/a.member.capacity-b.member.active/b.member.capacity ||
          (a.index-cursor+members.length)%members.length-(b.index-cursor+members.length)%members.length);
      const selected=candidates[0];
      if(!selected) throw lastError ?? new Error('provider temporarily unavailable');
      const {member,index}=selected;cursor=(index+1)%members.length;
      tried.add(member.id);member.active++;member.requests++;
      try {
        const value=await member.provider(text,language,{...options,deadline});
        member.completed++;return value;
      } catch(error) {
        lastError=error;member.failed++;
        if(/^provider (?:HTTP \d+|timeout|connection failed|response invalid)$/.test(error.message)) {
          member.cooldownUntil=Date.now()+(/HTTP (?:401|403)/.test(error.message) ? 60000 : /HTTP 429/.test(error.message) ? 20000 : 5000);
        }
        if(attempt+1<attempts && members.some(row=>!tried.has(row.id) && row.cooldownUntil<=Date.now())) failovers++;
      } finally {member.active--;}
    }
    throw lastError;
  };
  Object.defineProperty(pool,'batchStats',{get:()=>{
    const result={requests:0,items:0,active:0,queued:0,rejected:0,http429:0,httpActive:gate.active};
    for(const member of members) for(const key of Object.keys(result)) {
      if(key!=='httpActive') result[key]+=member.provider.batchStats?.[key] ?? 0;
    }
    return result;
  }});
  Object.defineProperty(pool,'poolStats',{get:()=>({concurrency,httpActive:gate.active,failovers,
    profiles:members.map(({id,capacity,active,requests,completed,failed,cooldownUntil})=>
      ({id,concurrency:capacity,active,requests,completed,failed,coolingDown:cooldownUntil>Date.now()}))})});
  return pool;
}
