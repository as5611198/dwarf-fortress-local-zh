/// <reference path="../worker-configuration.d.ts" />
import worker from './index.mjs';
declare global {
  interface Env { SIGNING_KEY_PEM: string; HMAC_SECRET: string; ADMIN_TOKEN: string; }
}
// Compile against the current generated Workerd binding contracts.
const handler: ExportedHandler<Env> = worker;
export default handler;
export function bindingContracts(env: Env) {
  const review = env.AI.run('@cf/openai/gpt-oss-120b', {
    messages: [{role:'system',content:'Contract check only; never executed.'}],
    temperature:0,max_tokens:2048,response_format:{type:'json_object'},
  });
  const conditionalWrite = env.OFFICIAL.put('contract-only',new Uint8Array(),{onlyIf:{etagMatches:'raw-etag'}});
  const prepared = env.DB.prepare('SELECT 1').bind();
  return {review,conditionalWrite,prepared};
}
