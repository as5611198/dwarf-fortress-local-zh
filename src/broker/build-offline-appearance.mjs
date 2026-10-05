import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import TOML from '@iarna/toml';
import {stringify} from 'csv-stringify/sync';
import {simplify} from './language-data.mjs';

const data=JSON.parse(await readFile(new URL('./offline-appearance.json',import.meta.url),'utf8'));

// Compile reviewed, typed vocabulary at package time. Runtime lookup does not
// scan this inventory or use a learned/player-specific translation cache.
export function appearanceRows(colors={}) {
  const rows=new Map();
  const add=(key,translation)=>{
    const text=`DFL_APPEARANCE:${key}`;
    if(rows.has(text) && rows.get(text).translation!==translation) throw new Error(`Conflicting appearance term: ${key}`);
    if(!translation || /[A-Za-z{}\[\]]/.test(translation)) throw new Error(`Invalid appearance target: ${key}`);
    rows.set(text,{text,translation,tags:'[REVIEWED:1][PROSE:appearance]'});
  };
  for(const [source,target] of Object.entries(data.subjects)) add(`subject:${source}`,target);
  for(const [part,predicates] of Object.entries(data.predicates))
    for(const [source,target] of Object.entries(predicates)) add(`predicate:${part}:${source}`,target);
  for(const [part,features] of Object.entries(data.features))
    for(const [source,target] of Object.entries(features)) add(`feature:${part}:${source}`,target);
  for(const [source,target] of Object.entries(data.has)) add(`has:${source}`,target);
  for(const [source,target] of Object.entries(data.self)) add(`self:${source}`,target);
  for(const [color,target] of Object.entries(colors)) {
    if(!/^[a-z][a-z -]*$/.test(color)) throw new Error(`Invalid appearance color: ${color}`);
    for(const part of ['hair','beard','moustache','sideburns','eyes','skin']) {
      add(`subject:${color} ${part}`,`${target}${data.subjects[part]}`);
      add(`predicate:${part}:${color}`,`呈${target}`);
    }
    for(const [modifier,zh] of Object.entries(data.eye_modifiers))
      add(`subject:${modifier} ${color} eyes`,`${zh}${target}${data.subjects.eyes}`);
  }
  if(rows.size>=16384) throw new Error('Appearance vocabulary exceeds runtime capacity');
  return [...rows.values()];
}

export async function buildOfflineAppearance(output) {
  const rules=TOML.parse(await readFile(join(output,'dfi18n-data/rulesets/zh-Hant/color.toml'),'utf8'));
  const colors=rules.rulesets.find(rule=>rule.name==='name')?.rules;
  if(!colors || !Object.keys(colors).length) throw new Error('Missing reviewed color rules');
  const rows=appearanceRows(colors);
  for(const language of ['zh-Hant','zh-Hans']) {
    const localized=rows.map(row=>({...row,translation:language==='zh-Hans'?simplify(row.translation):row.translation}));
    await writeFile(join(output,'dfi18n-data/simple',language,'zzzzzzzzzzz-offline-appearance.csv'),stringify(localized,{header:true,columns:['text','translation','tags']}));
  }
  return rows.length;
}
