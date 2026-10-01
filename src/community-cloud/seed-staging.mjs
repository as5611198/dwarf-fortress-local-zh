// Generates synthetic supports ONLY for the isolated staging database. Not real players.
import {writeFile} from 'node:fs/promises';
import {contributionIdentity,validateContribution} from '../broker/shared-policy.mjs';
import {createHash} from 'node:crypto';
const examples=[
  ['valid-social','He feels lonely after being unable to socialize.','他因為無法社交而感到孤單。'],
  ['wrong-subject','She feels lonely after being unable to socialize.','肥碩頭盔因為無法社交而感到孤單。'],
  ['wrong-negation','He is not distracted after being unable to pray.','他因為無法祈禱而分心。'],
  ['wrong-medical','The dwarf needs bone setting.','這位矮人需要骨骼設定。'],
];
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
const hash=value=>createHash('sha256').update(value).digest('hex');
const sql=[],ids=[];const now=Date.now();
for(const [label,text,translation] of examples){
 const entry=validateContribution({schema:1,rules:'df-zh-3',language:'zh-Hant',context:'general',kind:'exact',origin:'vanilla',text,translation,model:'synthetic-staging-only',license:'CC0-1.0'});
 const identity=contributionIdentity(entry),id=hash(JSON.stringify([identity,entry.translation]));ids.push({label,id,text,translation});
 sql.push(`INSERT INTO candidates(id,identity,row_json,state,devices,networks,created,updated) VALUES(${[id,identity,JSON.stringify(entry),'ready',3,3,now,now].map(quote).join(',')}) ON CONFLICT(id) DO NOTHING;`);
 for(let i=0;i<3;i++)sql.push(`INSERT INTO supports(identity,device_hash,candidate_id,network_hash,created) VALUES(${[identity,hash('synthetic-device-'+i),id,hash('synthetic-network-'+i),now].map(quote).join(',')}) ON CONFLICT DO NOTHING;`);
}
await writeFile(new URL('staging-synthetic.sql',import.meta.url),sql.join('\n')+'\n');
await writeFile(new URL('../text-audit/phase2-synthetic-examples.json',import.meta.url),JSON.stringify({synthetic:true,environment:'staging',examples:ids},null,2)+'\n');
console.log('Generated 4 staging-only examples with 12 synthetic support signals; no real-player consensus claimed.');
