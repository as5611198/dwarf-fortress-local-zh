import { readFile, writeFile, copyFile, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { constants } from 'node:fs';
import TOML from '@iarna/toml';
import { mergeTraditionalRuleOverride } from './data.mjs';

const [activeArg, backupArg] = process.argv.slice(2);
if (!activeArg || !backupArg) throw new Error('Usage: node apply-fortress-ui.mjs <active-mod> <backup>');
const active = resolve(activeArg), backup = resolve(backupArg);
const game = fileURLToPath(new URL('../../', import.meta.url));
const rule = 'dfi18n-data/rulesets/zh-Hant/tiles.toml';
const patch = await readFile(join(game,'_localization-work/local-patch',rule),'utf8');
const merged = mergeTraditionalRuleOverride(await readFile(join(active,rule),'utf8'),patch);
for (const file of [rule,'dfi18n-data/rulesets/zh-Hant/index.toml','broker/config.json','broker/server.mjs',
  'scripts_modinstalled/df-local-zh.lua','scripts_modinstalled/df-local-zh-runtime.lua',
  'scripts_modinstalled/df-local-zh-reports.lua','scripts_modinstalled/df-local-zh-status-ui.lua']) {
  await mkdir(resolve(backup,file,'..'),{recursive:true});
  await copyFile(join(active,file),join(backup,file),constants.COPYFILE_EXCL)
    .catch(error=>{if(error.code!=='EEXIST') throw error;});
}
for (const target of [active,join(game,'_localization-work/traditional-patch')]) {
  await writeFile(join(target,rule),merged,'utf8');
  await copyFile(new URL('./data/fortress-ui.csv',import.meta.url),
    join(target,'dfi18n-data/simple/zh-Hant/zzzzz-fortress-ui.csv'));
  const indexPath=join(target,'dfi18n-data/rulesets/zh-Hant/index.toml');
  const indexData=TOML.parse(await readFile(indexPath,'utf8'));
  indexData.rulesets=indexData.rulesets.filter(row=>
    !['announcement_day','announcement_suffix','announcement_month'].includes(row.name));
  for(const row of indexData.rulesets) delete row.rules?.['Date: {announcement_day}, {%number}'];
  await writeFile(indexPath,mergeTraditionalRuleOverride(TOML.stringify(indexData),
    await readFile(new URL('./data/announcement-rules/index.toml',import.meta.url),'utf8')),'utf8');
  await copyFile(new URL('./data/announcement-rules/announcement_date.toml',import.meta.url),
    join(target,'dfi18n-data/rulesets/zh-Hant/announcement_date.toml'));
}
const configPath=join(active,'broker/config.json');
const config=JSON.parse(await readFile(configPath,'utf8'));
config.staticDictionaries=[...new Set([...(config.staticDictionaries ?? []),'data/fortress-ui.csv'])];
await writeFile(configPath,JSON.stringify(config,null,2)+'\n','utf8');
await copyFile(new URL('./server.mjs',import.meta.url),join(active,'broker/server.mjs'));
await copyFile(new URL('./data/fortress-ui.csv',import.meta.url),join(active,'broker/data/fortress-ui.csv'));
await mkdir(join(active,'broker/data/announcement-rules'),{recursive:true});
await copyFile(new URL('./data/announcement-rules/index.toml',import.meta.url),
  join(active,'broker/data/announcement-rules/index.toml'));
await copyFile(new URL('./data/announcement-rules/announcement_date.toml',import.meta.url),
  join(active,'broker/data/announcement-rules/announcement_date.toml'));
for (const script of ['df-local-zh-runtime.lua','df-local-zh-reports.lua','df-local-zh-status-ui.lua']) {
  await copyFile(join(game,'hack/scripts',script),join(active,'scripts_modinstalled',script));
}
await copyFile(join(game,'hack/scripts/df-local-zh.lua'),join(active,'scripts_modinstalled/df-local-zh.lua'));
console.log(JSON.stringify({active,backup,ruleMerged:true}));
