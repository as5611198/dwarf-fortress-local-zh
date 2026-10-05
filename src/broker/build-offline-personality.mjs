import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {stringify} from 'csv-stringify/sync';
import {simplify} from './language-data.mjs';
import {fixedThoughts} from './unit-prewarm.mjs';

export function personalityRows(data,extra={},abilities={},conflicts={},preferences={},mannerisms={},quotes={}) {
  const rows=new Map();
  const add=(text,translation,kind)=> {
    if (/[{}]/.test(text+translation)) throw new Error(`Unresolved pronoun: ${text}`);
    if (rows.has(text) && rows.get(text).translation!==translation) throw new Error(`Conflicting offline sentence: ${text}`);
    rows.set(text,{text,translation,tags:`[REVIEWED:1][PROSE:${kind}]`});
  };
  for (const [he,his,him,himself,zh] of [['he','his','him','himself','他'],['she','her','her','herself','她'],['it','its','it','itself','牠']]) {
    const pronouns={He:he[0].toUpperCase()+he.slice(1),he,his,him,himself};
    const en=s=>s.replace(/\{(He|he|his|him|himself)\}/g,(_,p)=>pronouns[p]);
    const cn=s=>s.replace(/\{(He|he|his|him|himself)\}/g,()=>zh);
    const exactSentences=new Set(data.sentences.map(([s])=>en(s)));
    for (const [s,t] of Object.entries(extra.traits ?? {})) add(en(`{He} ${s}.`),cn(`{He}${t}。`),'sentence');
    for (const [s,t] of Object.entries(extra.values ?? {})) add(en(s),cn(t),'value');
    for (const [s,t] of Object.entries(abilities)) add(en(s),cn(t),'ability');
    for (const [s,t] of Object.entries(mannerisms.standalone ?? {})) add(en(`{He} ${s}.`),cn(`{He}${t}。`),'sentence');
    for (const [action,t] of Object.entries(mannerisms.actions ?? {})) {
      for (const [condition,c] of Object.entries(mannerisms.conditions ?? {})) {
        for (const join of ['when','whenever']) {
          const source=en(`{He} ${action} ${join} ${condition}.`);
          // Existing hand-polished full sentences take precedence over generated wording.
          if (!exactSentences.has(source)) add(source,cn(`{He}${c}會${t}。`),'sentence');
        }
      }
    }
    const tails={...(conflicts.standalone ?? {})};
    for (const [head,t] of Object.entries(conflicts.heads ?? {})) {
      for (const [reason,r] of Object.entries(conflicts.reasons ?? {}))
        tails[`{he} ${head} {he} ${reason}`]=`{he}${t}{he}${r}`;
    }
    for (const [join,zhJoin] of [['and','而'],['though','但'],['although','儘管'],['even though','即使']]) {
      for (const [s,t] of Object.entries(tails)) add(en(`${join} ${s}.`),cn(`${zhJoin}${t}。`),'tail');
    }
    for (const [source,target] of data.sentences) add(
      source.replace(/\{(He|he|his|him|himself)\}/g,(_,p)=>pronouns[p]),
      target.replace(/\{(He|he|his|him|himself)\}/g,()=>zh),'sentence');
  }
  for (const [source,target] of data.values) add(source,target,'value');
  for (const [source,target] of data.abilities ?? []) add(source,target,'ability');
  for (const [source,target] of data.literals ?? []) add(source,target,'literal');
  for (const {text,translation} of fixedThoughts()) add(text,translation,'literal');
  for (const [source,target] of Object.entries(quotes)) {
    if (!/^[A-Z][\s\S]*[.!?]$/.test(source) || source!==source.trim() || /["{}]/.test(source))
      throw new Error(`Expected complete quote: ${source}`);
    const text=`"${source}"`;
    // Preserve prior hand-polished full quotes when inventories overlap.
    if (!rows.has(text)) add(text,`「${target}」`,'literal');
  }
  for (const [s,t] of Object.entries(preferences)) add(s,t,'literal');
  return [...rows.values()];
}
export async function buildOfflinePersonality(output) {
  const inputs=await Promise.all(['offline-personality','offline-personality-extra','offline-abilities','offline-conflicts','offline-preference-terms','offline-mannerisms','offline-current-quotes']
    .map(async name=>JSON.parse(await readFile(new URL(`./${name}.json`,import.meta.url),'utf8'))));
  const rows=personalityRows(...inputs);
  for (const language of ['zh-Hant','zh-Hans']) {
    const localized=rows.map(row=>({...row,translation:language==='zh-Hans'?simplify(row.translation):row.translation}));
    await writeFile(join(output,'dfi18n-data/simple',language,'zzzzzzzzz-offline-personality.csv'),stringify(localized,{header:true,columns:['text','translation','tags']}));
  }
  return rows.length;
}
