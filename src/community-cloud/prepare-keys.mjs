// Local operator utility: secrets never enter the workspace or command arguments.
import {generateKeyPairSync,createPrivateKey,createPublicKey,randomBytes} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {OFFICIAL_TRUST} from '../broker/official-trust.mjs';
const directory=join(homedir(),'.df-zh-publisher');await mkdir(directory,{recursive:true});
const publicKeys={},paths={};
for(const mode of ['production','staging']) {
  const keyId=mode==='production'?'df-consensus-20261001':'df-consensus-staging-20261001';
  const pemPath=join(directory,keyId+'.pem');let privateKey;
  try {privateKey=createPrivateKey(await readFile(pemPath));}catch(error){if(error.code!=='ENOENT')throw error;
    privateKey=generateKeyPairSync('ed25519').privateKey;await writeFile(pemPath,privateKey.export({type:'pkcs8',format:'pem'}),{flag:'wx',mode:0o600});}
  publicKeys[keyId]=createPublicKey(privateKey).export({type:'spki',format:'pem'});
  const secretFile=join(directory,`consensus-${mode}-secrets.json`);
  try {await readFile(secretFile);}catch(error){if(error.code!=='ENOENT')throw error;await writeFile(secretFile,JSON.stringify({
    SIGNING_KEY_PEM:privateKey.export({type:'pkcs8',format:'pem'}),HMAC_SECRET:randomBytes(32).toString('hex'),ADMIN_TOKEN:randomBytes(32).toString('hex'),
  })+'\n',{flag:'wx',mode:0o600});}
  paths[mode]={keyId,privateKey:pemPath,secretFile};
}
const prodTrust={...OFFICIAL_TRUST,'df-consensus-20261001':publicKeys['df-consensus-20261001']};
const variables={COLLECTION_ENABLED:'true',REVIEW_ENABLED:'true',PUBLISH_ENABLED:'false',DISTRIBUTION_READ:'false',STAGING:'false',
  SIGNING_KEY_ID:'df-consensus-20261001',TRUST_JSON:JSON.stringify(prodTrust)};
const config={name:'df-zh-consensus',account_id:'f2dbbfd612c50e30e08872e40aeb247d',main:'src/index.mjs',compatibility_date:'2026-10-01',compatibility_flags:['nodejs_compat'],workers_dev:true,
  ai:{binding:'AI'},d1_databases:[{binding:'DB',database_name:'df-zh-consensus',database_id:'58f7a85b-4bf3-4f1a-bc67-7c742e8e20f8',migrations_dir:'migrations'}],
  r2_buckets:[{binding:'OFFICIAL',bucket_name:'df-zh-official-library'}],vars:variables,observability:{enabled:true,head_sampling_rate:0.1},
  triggers:{crons:['*/15 * * * *']},limits:{cpu_ms:10000},env:{staging:{name:'df-zh-consensus-staging',
    ai:{binding:'AI'},d1_databases:[{binding:'DB',database_name:'df-zh-consensus-staging',database_id:'f381abcc-e656-4781-b478-38925e5bffca',migrations_dir:'migrations'}],
    r2_buckets:[{binding:'OFFICIAL',bucket_name:'df-zh-consensus-staging'}],vars:{...variables,STAGING:'true',DISTRIBUTION_READ:'true',SIGNING_KEY_ID:'df-consensus-staging-20261001',
      TRUST_JSON:JSON.stringify({...prodTrust,'df-consensus-staging-20261001':publicKeys['df-consensus-staging-20261001']})},triggers:{crons:[]}}}};
await writeFile(resolve('_localization-work/community-cloud/wrangler.jsonc'),JSON.stringify(config,null,2)+'\n');
await writeFile(resolve('_localization-work/community-cloud/public-keys.json'),JSON.stringify(publicKeys,null,2)+'\n');
console.log(JSON.stringify({config:'_localization-work/community-cloud/wrangler.jsonc',paths,privateValuesPrinted:false},null,2));
