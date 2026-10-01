import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import TOML from '@iarna/toml';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';

const game=resolve(fileURLToPath(new URL('../../',import.meta.url)));
const active=process.argv[2];
if(!active) throw Error('Usage: node audit-fortress-gaps.mjs <active-mod>');
const audit=join(game,'_localization-work/text-audit');
const summary=JSON.parse(await readFile(join(audit,'latest-summary.json'),'utf8'));
const raw=(await readFile(summary.full_log,'utf8')).split(/\r?\n/).filter(Boolean)
  .map(line=>JSON.parse(line)).filter(row=>typeof row.text==='string' && typeof row.field_id==='string');
const grouped=new Map();
for(const row of raw) {
  const match=row.field_id.match(/^(.*)\.text\[(\d+)\]\.value$/);
  const id=match?.[1] ?? row.field_id;
  const group=grouped.get(id) ?? [];
  group.push({...row,index:match ? Number(match[2]) : 0});grouped.set(id,group);
}
const candidates=[...grouped].map(([field,rows])=>({field,category:rows[0].category,
  text:rows.sort((a,b)=>a.index-b.index).map(row=>row.text).join(''),rows:rows.length}));
const chinese=text=>typeof text==='string' && /\p{Script=Han}/u.test(text) &&
  !/\p{Script=Latin}/u.test(text.replace(/\[C:[0-7]:[0-7]:[01]\]|\[[BPR]\]/g,''));
const dictionary=new Map();
async function dataFiles(dir,extension) {
  const result=[];
  for(const entry of (await readdir(dir,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
    const path=join(dir,entry.name);
    if(entry.isDirectory()) result.push(...await dataFiles(path,extension));
    else if(entry.name.endsWith(extension)) result.push(path);
  }
  return result;
}
for(const path of await dataFiles(join(active,'dfi18n-data/simple/zh-Hant'),'.csv')) {
  for(const row of parse(await readFile(path,'utf8'),{columns:true,skip_empty_lines:true,bom:true}))
    if(row.text && chinese(row.translation)) dictionary.set(row.text,{translation:row.translation,method:'static-dictionary'});
}
for(const path of await dataFiles(join(active,'dfi18n-data/rulesets/zh-Hant'),'.toml')) {
  const data=TOML.parse(await readFile(path,'utf8'));
  for(const ruleset of data.rulesets ?? []) {
    for(const [text,translation] of Object.entries(ruleset.rules ?? {})) {
      if(!/[{}%]/.test(text) && chinese(translation) && !dictionary.has(text))
        dictionary.set(text,{translation,method:'literal-rule-candidate'});
    }
  }
}
const privateData=join(game,'dfhack-config/mods/df-local-zh-complete/data');
for(const filename of ['unit-display-cache.jsonl','runtime-responses.jsonl']) {
  for(const line of (await readFile(join(privateData,filename),'utf8')).split(/\r?\n/)) {
    try {
      const row=JSON.parse(line);
      if(row.world===summary.world && row.text && chinese(row.translation))
        dictionary.set(row.text,{translation:row.translation,method:'world-journal'});
    } catch {}
  }
}
const unknown=candidates.filter(row=>!dictionary.has(row.text) && /[A-Za-z]/.test(row.text));
const input=join(audit,'fortress-gap-rules-input.csv');
await writeFile(input,stringify(unknown.map(row=>({text:row.text})),{header:true}),'utf8');
const rows=candidates.filter(row=>/[A-Za-z]/.test(row.text)).map(row=>({...row,
  context:/\.hover_instruction\.(?:ADVENTURE_|ARENA_|OPEN_ANNOUNCEMENTS_FROM_ADV|TRACK_TOGGLE)/.test(row.field)
    ? 'other-mode-shared-buffer' : 'fortress-candidate',
  ...(dictionary.get(row.text) ?? {}),status:dictionary.has(row.text) ? 'KNOWN' : 'CANDIDATE'}));
const sourceByField=new Map([...grouped].map(([field,parts])=>[field,parts]));
const hoverFits=rows.filter(row=>row.field.includes('.hover_instruction.') && row.translation).map(row=>{
  const width=Math.max(...sourceByField.get(row.field).map(part=>part.text.length));
  return {field:row.field,text:row.text,translation:row.translation,width,rows:row.rows,
    fits:width>=8 && [...row.translation].length<=Math.floor(width/2)*row.rows};
});
const result={time:new Date().toISOString(),world:summary.world,scope:'observed-source-offline-coverage',
  sourceRows:raw.length,paragraphs:rows.length,known:rows.filter(row=>row.status==='KNOWN').length,
  unresolved:rows.filter(row=>row.status==='CANDIDATE').length,
  fortressCandidates:rows.filter(row=>row.status==='CANDIDATE' && row.context==='fortress-candidate').length,
  otherModeCandidates:rows.filter(row=>row.status==='CANDIDATE' && row.context==='other-mode-shared-buffer').length,
  limitation:'Includes hidden original buffers. Literal subrules may require an enclosing grammar. Dynamic grammar is unchecked. Candidates are not confirmed displayed misses; dictionary matches do not prove render readiness.',
  ruleDiagnostics:['Dynamic grammar not executed; bounded structural dictionary comparison only.'],rows};
await writeFile(join(audit,'fortress-gaps.json'),JSON.stringify(result,null,2)+'\n','utf8');
await writeFile(join(audit,'fortress-hover-fit.json'),JSON.stringify({total:hoverFits.length,
  fits:hoverFits.filter(row=>row.fits).length,failures:hoverFits.filter(row=>!row.fits)},null,2)+'\n','utf8');
await writeFile(join(audit,'fortress-gaps-unresolved.csv'),stringify(rows.filter(row=>row.status==='CANDIDATE'),
  {header:true,columns:['field','category','text','rows']}),'utf8');
console.log(JSON.stringify({sourceRows:result.sourceRows,paragraphs:result.paragraphs,known:result.known,
  unresolved:result.unresolved,fortressCandidates:result.fortressCandidates,otherModeCandidates:result.otherModeCandidates,
  hoverFit:{total:hoverFits.length,failure:hoverFits.filter(row=>!row.fits).length},log:join(audit,'fortress-gaps.json')}));
