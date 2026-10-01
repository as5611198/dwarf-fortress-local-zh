import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join, dirname, relative } from 'node:path';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import TOML from '@iarna/toml';
import { simplify, simplifyTree } from './language-data.mjs';

async function convertDirectory(source,target,extension) {
  await mkdir(target,{recursive:true});let count=0;
  for(const item of await readdir(source,{withFileTypes:true})) {
    if(item.isDirectory()) count+=await convertDirectory(join(source,item.name),join(target,item.name),extension);
    else if(item.name.endsWith(extension) && item.name!=='zzzzzz-community-workbook.csv') {
      const content=await readFile(join(source,item.name),'utf8');
      let output;
      if(extension==='.csv') {
        const rows=parse(content,{columns:true,skip_empty_lines:true,bom:true});
        for(const row of rows) row.translation=simplify(row.translation);
        output=stringify(rows,{header:true,columns:['text','translation','tags']});count+=rows.length;
      } else {output=TOML.stringify(simplifyTree(TOML.parse(content)));count++;}
      await writeFile(join(target,item.name),output,'utf8');
    }
  }
  return count;
}
export async function buildSimplified(packageRoot) {
  const core=join(packageRoot,'dfi18n-data'),broker=join(packageRoot,'broker');
  const rows=await convertDirectory(join(core,'simple/zh-Hant'),join(core,'simple/zh-Hans'),'.csv');
  const rules=await convertDirectory(join(core,'rulesets/zh-Hant'),join(core,'rulesets/zh-Hans'),'.toml');
  const config=JSON.parse(await readFile(join(broker,'config.json'),'utf8'));
  const files=[...(config.staticDictionaries ?? []),config.reviewedDictionary].filter(Boolean);
  const generated=[];
  for(const file of new Set(files)) {
    const target=file.replace(/\.csv$/,'-zh-Hans.csv');
    const source=parse(await readFile(join(broker,file),'utf8'),{columns:true,skip_empty_lines:true,bom:true});
    for(const row of source) row.translation=simplify(row.translation);
    await mkdir(dirname(join(broker,target)),{recursive:true});
    await writeFile(join(broker,target),stringify(source,{header:true,columns:['text','translation','tags']}),'utf8');
    generated.push(target);
    if((config.literalDictionaries ?? []).includes(file) || ['data/fortress-ui.csv','data/community-reviewed.csv'].includes(file)) {
      config.literalDictionaries.push(target);
    }
  }
  await convertDirectory(join(broker,'data/announcement-rules'),join(broker,'data/announcement-rules-zh-Hans'),'.toml');
  config.literalDictionaries=[...new Set(config.literalDictionaries)];
  config.staticDictionariesByLanguage['zh-Hans']=[...new Set([...generated,
    ...(config.staticDictionariesByLanguage['zh-Hans'] ?? [])])];
  await writeFile(join(broker,'config.json'),JSON.stringify(config,null,2)+'\n');
  return {simpleRows:rows,rulesets:rules,brokerDictionaries:generated.length};
}
