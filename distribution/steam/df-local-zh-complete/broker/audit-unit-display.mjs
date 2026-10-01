import { readFile, writeFile } from 'node:fs/promises';
import { parse } from 'csv-parse/sync';
import { resolve } from 'node:path';

const root=resolve('..');
const rows=(await readFile(resolve(root,'text-audit/unit-display-current.jsonl'),'utf8'))
  .trim().split('\n').map(line=>JSON.parse(line));
const cache=parse(await readFile(resolve(root,'../dfi18n-data/cache/translation-cache.csv'),'utf8'),
  {columns:true,skip_empty_lines:true});
const results=[];
for(const box of rows.filter(row=>row.field==='personality_raw_str' && row.source)) {
  for(let i=0;i<box.lines.length;i++) {
    const line=box.lines[i];
    if(!line.text) continue;
    let source='',previous;
    for(let offset=0;offset<Math.min(line.text.length,line.color.length);offset++) {
      const byte=line.color.charCodeAt(offset);
      const tag=`[C:${byte%8}:${Math.floor(byte/8)%8}:${Math.floor(byte/64)%2}]`;
      if(tag!==previous) {source+=tag;previous=tag;}
      source+=line.text[offset];
    }
    const rendered=cache.filter(row=>row.kind==='markup' && row.original===source).at(-1);
    results.push({field_id:`personality_box[${box.id}].line[${i}]`,type:'color_text_boxst',
      source:box.source,alias:line.text,render_source:source,status:rendered?.status??'unobserved',
      translation:rendered?.translation??null});
  }
}
await writeFile(resolve(root,'text-audit/unit-render-status.jsonl'),
  results.map(row=>JSON.stringify(row)).join('\n')+'\n');
const displayed=rows[0].focus.some(focus=>focus.includes('/UNIT/Personality/'));
const translated=results.filter(row=>row.status==='translated' &&
  typeof row.translation==='string' && !/[A-Za-z]/.test(row.translation.replace(/\[C:\d+:\d+:\d+\]/g,''))).length;
const summary={focus:rows[0].focus,unit_id:rows[0].unit_id,displayed,
  rows:results.length,translated:results.filter(row=>row.status==='translated').length,
  missing:results.filter(row=>row.status==='missing').length,
  unobserved:results.filter(row=>row.status==='unobserved').length,
  chinese_render_rows:translated,
  coverage_percent:displayed && results.length ? Math.round(translated/results.length*10000)/100 : null};
await writeFile(resolve(root,'text-audit/unit-render-summary.json'),JSON.stringify(summary,null,2)+'\n');
console.log(JSON.stringify(summary));
