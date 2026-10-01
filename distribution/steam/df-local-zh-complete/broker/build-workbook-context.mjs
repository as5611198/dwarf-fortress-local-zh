import { readFile,writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import TOML from '@iarna/toml';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import { convertCsv } from './data.mjs';
import { validateTranslation } from './safety.mjs';

export async function buildWorkbookContextRules(packageRoot,candidates,corrections={}) {
  const result={};
  const traditional=parse(convertCsv(stringify(candidates.map(row=>({text:row.text,
    translation:row.translation,tags:''})),{header:true})),{columns:true});
  for(const language of ['zh-Hant','zh-Hans']) {
    let updated=0;
    for(const [sheet,kind] of [['拼接-形容词','adj'],['拼接-名词','none']]) {
      const path=join(packageRoot,'dfi18n-data/rulesets',language,'english_name',kind+'.toml');
      const doc=TOML.parse(await readFile(path,'utf8'));
      const rules=doc.rulesets.find(row=>row.name==='main').rules;
      for(const [index,row] of candidates.entries()) {
        if(row.sheet!==sheet || !Object.hasOwn(rules,row.text)) continue;
        try {
          const translation=validateTranslation(row.text,corrections[row.text]?.[language] ??
            (language==='zh-Hant' ? traditional[index].translation : row.translation));
          rules[row.text]=translation;updated++;
        } catch { /* Draft/invalid entries retain the original rule and audit decision. */ }
      }
      await writeFile(path,TOML.stringify(doc));
    }
    result[language]=updated;
  }
  return result;
}
