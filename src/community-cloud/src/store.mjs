import {validateContribution,contributionIdentity,CONSENSUS_DEVICES,CONSENSUS_NETWORKS} from '../../broker/shared-policy.mjs';
import {validateReview,REVIEW_MODEL,REVIEW_POLICY} from './reviewer.mjs';
export async function digest(value) {return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(b=>b.toString(16).padStart(2,'0')).join('');}
const day=now=>new Date(now).toISOString().slice(0,10);
export class ConsensusStore {
  constructor(db){this.db=db;}
  statement(sql,...args){return this.db.prepare(sql).bind(...args);}
  async get(id){const row=await this.statement('SELECT * FROM candidates WHERE id=?',id).first();return row?{...row,entry:JSON.parse(row.row_json)}:null;}
  async ingest(input,{device,network,now=Date.now()}) {
    const row=validateContribution(input),identity=contributionIdentity(row);
    const id=await digest(JSON.stringify([identity,row.translation]));
    const ticket=crypto.randomUUID(),quota=`upload:${day(now)}:${network}`;
    const admitted='EXISTS(SELECT 1 FROM quotas WHERE key=? AND last_ticket=?)';
    const results=await this.db.batch([
      this.statement('INSERT INTO quotas(key,count,expires,last_ticket) VALUES(?,1,?,?) ON CONFLICT(key) DO UPDATE SET count=count+1,last_ticket=excluded.last_ticket WHERE count<200',quota,now+2*86400000,ticket),
      this.statement(`INSERT INTO candidates(id,identity,row_json,created,updated) SELECT ?,?,?,?,? WHERE ${admitted} AND (SELECT COUNT(*) FROM candidates)<50000 ON CONFLICT(id) DO NOTHING`,id,identity,JSON.stringify(row),now,now,quota,ticket),
      this.statement(`INSERT INTO supports(identity,device_hash,candidate_id,network_hash,created) SELECT ?,?,?,?,? WHERE ${admitted} AND EXISTS(SELECT 1 FROM candidates WHERE id=?) ON CONFLICT(identity,device_hash) DO NOTHING`,identity,device,id,network,now,quota,ticket,id),
      this.statement(`UPDATE candidates SET devices=(SELECT COUNT(*) FROM supports WHERE candidate_id=?),networks=(SELECT COUNT(DISTINCT network_hash) FROM supports WHERE candidate_id=?),updated=? WHERE id=?`,id,id,now,id),
      this.statement(`UPDATE candidates SET state='ready' WHERE id=? AND state='pending' AND devices>=? AND networks>=?`,id,CONSENSUS_DEVICES,CONSENSUS_NETWORKS),
      this.statement(`UPDATE candidates SET state='blocked' WHERE identity=? AND state='ready' AND EXISTS(SELECT 1 FROM candidates other WHERE other.identity=? AND other.id<>candidates.id AND other.state='approved')`,identity,identity),
      this.statement(`UPDATE candidates SET state='blocked' WHERE identity=? AND state IN ('ready','reviewing') AND (SELECT COUNT(*) FROM candidates other WHERE other.identity=? AND other.state IN ('ready','reviewing'))>1`,identity,identity),
    ]);
    if(!results[0].meta.changes)throw Error('rate limited');
    if(!await this.get(id))throw Error('candidate capacity');
    return {id,counted:results[2].meta.changes===1};
  }
  async claimReview(now=Date.now(),dailyLimit=20) {
    const owner=crypto.randomUUID(),quota=`review:${day(now)}`;
    const eligible="(state='ready' OR (state='reviewing' AND lease_until<=?)) AND retry_at<=? AND attempts<3";
    await this.db.batch([
      this.statement(`INSERT INTO quotas(key,count,expires,last_ticket) SELECT ?,1,?,? WHERE EXISTS(SELECT 1 FROM candidates WHERE ${eligible}) ON CONFLICT(key) DO UPDATE SET count=count+1,last_ticket=excluded.last_ticket WHERE count<?`,quota,now+2*86400000,owner,now,now,dailyLimit),
      this.statement(`UPDATE candidates SET state='reviewing',review_owner=?,lease_until=?,attempts=attempts+1,updated=? WHERE id=(SELECT id FROM candidates WHERE ${eligible} ORDER BY devices DESC,created,id LIMIT 1) AND EXISTS(SELECT 1 FROM quotas WHERE key=? AND last_ticket=?)`,owner,now+15*60000,now,now,now,quota,owner),
    ]);
    const row=await this.statement('SELECT * FROM candidates WHERE review_owner=? AND state=\'reviewing\'',owner).first();
    return row?{...row,owner,entry:JSON.parse(row.row_json)}:null;
  }
  async finishReview(claim,result,now=Date.now()) {
    const fields=['verdict','confidence','meaning','gameContext','terminology','language','privacy','placeholder','abuse','reason'];
    const verified=validateReview(Object.fromEntries(fields.filter(k=>k in result).map(k=>[k,result[k]])));
    const approved=verified.approved && result.model===REVIEW_MODEL && result.policy===REVIEW_POLICY;
    const retry=result.retryable===true || verified.retryable===true;
    const state=approved?'approved':retry?(claim.attempts>=3?'stalled':'ready'):'rejected';
    const results=await this.statement(`UPDATE candidates SET state=?,review_json=?,reviewed_at=?,retry_at=?,review_owner=NULL,lease_until=0,updated=? WHERE id=? AND state='reviewing' AND review_owner=? AND lease_until>? AND (?!='approved' OR NOT EXISTS(SELECT 1 FROM candidates other WHERE other.identity=candidates.identity AND other.id<>candidates.id AND other.state='approved'))`,
      state,JSON.stringify({...result,approved}),now,retry?now+Math.min(86400000,3600000*2**(claim.attempts-1)):0,now,claim.id,claim.owner,now,state).run();
    return results.meta.changes===1;
  }
  async approved(){return (await this.statement("SELECT * FROM candidates WHERE state='approved' ORDER BY identity,id").all()).results.map(row=>({...row,entry:JSON.parse(row.row_json),review:JSON.parse(row.review_json)}));}
  async acquireLease(key,owner,now,ttl) {
    const result=await this.statement('INSERT INTO leases(key,owner,expires) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET owner=excluded.owner,expires=excluded.expires WHERE leases.expires<=?',key,owner,now+ttl,now).run();
    return result.meta.changes===1;
  }
  async releaseLease(key,owner){await this.statement('DELETE FROM leases WHERE key=? AND owner=?',key,owner).run();}
  async publication(){return await this.statement("SELECT * FROM publication WHERE key='official'").first()??{sequence:0,last_at:0,digest:''};}
  async reserveSequence(minimum) {
    await this.statement("INSERT INTO publication(key,sequence) VALUES('official',?) ON CONFLICT(key) DO UPDATE SET sequence=MAX(publication.sequence+1,excluded.sequence)",minimum).run();
    return (await this.publication()).sequence;
  }
  async published(sequence,version,hash,now){await this.statement("UPDATE publication SET last_at=?,version=?,digest=? WHERE key='official' AND sequence=?",now,version,hash,sequence).run();}
  async markEntriesPublished(version,ids){if(ids.length)await this.db.batch(ids.flatMap(id=>[
    this.statement("UPDATE candidates SET published_version=? WHERE id=? AND state='approved'",version,id),
    this.statement('INSERT INTO release_entries(candidate_id,version) VALUES(?,?) ON CONFLICT DO NOTHING',id,version)]));}
  async withdrawals(){return (await this.statement('SELECT version FROM withdrawals ORDER BY version').all()).results.map(r=>r.version);}
  async withdraw(id,reason,now=Date.now()) {
    const row=await this.get(id);if(!row)throw Error('unknown candidate');
    const statements=[this.statement("UPDATE candidates SET state='withdrawn',updated=? WHERE id=?",now,id)];
    statements.push(this.statement('INSERT INTO withdrawals(version,reason,created) SELECT version,?,? FROM release_entries WHERE candidate_id=? ON CONFLICT(version) DO NOTHING',reason,now,id));
    if(row.published_version)statements.push(this.statement('INSERT INTO withdrawals(version,reason,created) VALUES(?,?,?) ON CONFLICT(version) DO NOTHING',row.published_version,reason,now));
    await this.db.batch(statements);
  }
  async clean(now=Date.now()){
    await this.db.batch([this.statement('DELETE FROM quotas WHERE expires<?',now),this.statement('DELETE FROM leases WHERE expires<?',now)]);
  }
}
