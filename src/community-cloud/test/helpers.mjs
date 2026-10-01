import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
export const contribution={schema:1,rules:'df-zh-3',language:'zh-Hant',context:'general',kind:'exact',origin:'vanilla',
  text:'He feels lonely after being unable to socialize.',translation:'他因為無法社交而感到孤單。',model:'fixture-model',license:'CC0-1.0'};
export function database() {
  const sqlite=new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../migrations/0001-consensus.sql',import.meta.url),'utf8'));
  const adapter={sqlite,prepare(sql){return {sql,args:[],bind(...args){this.args=args;return this;},
    async run(){const result=sqlite.prepare(sql).run(...this.args);return {success:true,meta:{changes:Number(result.changes)}};},
    async first(){return sqlite.prepare(sql).get(...this.args)??null;},
    async all(){return {results:sqlite.prepare(sql).all(...this.args)};}};},
    async batch(statements){sqlite.exec('BEGIN IMMEDIATE');try{const results=[];for(const s of statements){const r=sqlite.prepare(s.sql).run(...s.args);results.push({success:true,meta:{changes:Number(r.changes)}});}sqlite.exec('COMMIT');return results;}catch(e){sqlite.exec('ROLLBACK');throw e;}}};
  return adapter;
}
export const review={verdict:'approve',confidence:0.99,meaning:true,gameContext:true,terminology:true,language:true,privacy:true,placeholder:true,abuse:true,
  reason:'Correct Dwarf Fortress social need meaning.',approved:true,retryable:false,model:'@cf/openai/gpt-oss-120b',policy:'df-semantic-review-1'};
export async function support(store,row=contribution,n=3,start=0){let id;for(let i=0;i<n;i++)id=(await store.ingest(row,{device:'d'+(start+i),network:'n'+(start+i),now:1000})).id;return id;}
export class Bucket {
  constructor(){this.values=new Map();this.failKey=null;}
  async get(key){const bytes=this.values.get(key);let used=false;const take=()=>{if(used)throw Error('R2 body already used');used=true;return bytes;};return bytes===undefined?null:{arrayBuffer:async()=>Uint8Array.from(take()).buffer,text:async()=>Buffer.from(take()).toString('utf8'),size:bytes.length,body:Uint8Array.from(bytes),etag:'fixture',httpEtag:'"fixture"'};}
  async put(key,data,options){if(options?.onlyIf && options.onlyIf.etagMatches!=='fixture')throw TypeError('Invalid R2 conditional etag');if(key===this.failKey)throw Error('R2 write failure');this.values.set(key,typeof data==='string'?Buffer.from(data):Buffer.from(data));}
}
