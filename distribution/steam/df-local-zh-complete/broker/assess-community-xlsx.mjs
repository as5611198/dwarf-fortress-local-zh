import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { stringify } from 'csv-stringify/sync';
import { parse } from 'csv-parse/sync';
import { convertCsv } from './data.mjs';
import { validateTranslation, safeReason } from './safety.mjs';

const root=resolve(process.argv[2] ?? '../..');
const audit=join(root,'_localization-work/text-audit');
const extracted=JSON.parse(await readFile(join(audit,'community-workbook-extracted.json'),'utf8'));
const rows=parse(convertCsv(stringify(extracted.candidates.map(row=>({
  text:row.text,translation:row.translation,tags:''})),{header:true})),{columns:true});
const candidates=extracted.candidates.map((row,index)=>{
  const translation=rows[index].translation;
  let valid=true,reason=null;
  try { validateTranslation(row.text,translation); }
  catch(error) { valid=false;reason=safeReason(error); }
  return {...row,traditional:translation,format_valid:valid,reason};
});
const sources=new Map();
const failures={};
const perSheet={};
for(const row of candidates) {
  const group=perSheet[row.sheet] ??= {pairs:0,format_valid:0,existing_chinese_values:0,new_keys:0,new_format_valid:0,examples:[]};
  group.pairs++;
  if(row.installed_key_has_chinese_value) group.existing_chinese_values++;
  if(row.format_valid) group.format_valid++;
  if(!row.normalized_key_in_installed) {
    group.new_keys++;
    if(row.format_valid) {
      group.new_format_valid++;
      if(group.examples.length<5) group.examples.push({
        text:row.text,translation:row.traditional,row:row.row,columns:row.columns});
    }
  }
  if(!row.format_valid) failures[row.reason]=(failures[row.reason] ?? 0)+1;
  const saved=sources.get(row.text) ?? {translations:new Set(),existing:false,chinese:false,format_valid:false};
  saved.translations.add(row.traditional);
  saved.existing ||= row.normalized_key_in_installed;
  saved.chinese ||= row.installed_key_has_chinese_value;
  saved.format_valid ||= row.format_valid;
  sources.set(row.text,saved);
}
const result={source:extracted.source,sha256:extracted.sha256,candidates:candidates.length,
  unique_sources:sources.size,existing_unique_keys:[...sources.values()].filter(row=>row.existing).length,
  existing_unique_keys_with_chinese_value:[...sources.values()].filter(row=>row.chinese).length,
  existing_unique_keys_without_chinese_value:[...sources.values()].filter(row=>row.existing && !row.chinese).length,
  new_unique_keys:[...sources.values()].filter(row=>!row.existing).length,
  new_format_valid_unique_keys:[...sources.values()].filter(row=>!row.existing && row.format_valid).length,
  duplicate_sources_with_translation_variants:[...sources.values()].filter(row=>row.translations.size>1).length,
  format_failures:failures,sheets:perSheet,
  limits:['Simplified to Traditional conversion and format validation only; no semantic approval.',
    'Absent exact keys can still be covered by existing regex or composed rules.',
    'Draft placeholders, typos and generated-world examples require review before integration.']};
await writeFile(join(audit,'community-workbook-traditional-candidates.json'),JSON.stringify({
  source:extracted.source,sha256:extracted.sha256,candidates},null,2)+'\n','utf8');
await writeFile(join(audit,'community-workbook-format-assessment.json'),JSON.stringify(result,null,2)+'\n','utf8');
console.log(JSON.stringify(result,null,2));
