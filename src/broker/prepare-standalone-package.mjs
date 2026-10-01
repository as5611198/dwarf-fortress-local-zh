import {cp, mkdir, readFile, readdir, rm, writeFile, stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {dirname, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parse} from 'csv-parse/sync';
import {stringify} from 'csv-stringify/sync';
import {convertCsv, convertRules, mergeTraditionalRuleOverride, canonicalizeCreatureRules} from './data.mjs';
import {buildSimplified} from './build-language-data.mjs';
import {buildCreatureDictionaries} from './build-creature-dictionaries.mjs';
import {ownedRows} from './official-owned.mjs';
import {simplify} from './language-data.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const args = Object.fromEntries(process.argv.slice(2).map(value => {
  const split = value.indexOf('=');
  if (split < 3 || !value.startsWith('--')) throw new Error(`Expected --name=value: ${value}`);
  return [value.slice(2, split), value.slice(split + 1)];
}));
const version = args.version ?? '0.4.1';
if (!/^\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(version)) throw new Error('Invalid version');
const output = resolve(args.output ?? join(root, 'distribution/steam/df-local-zh-complete'));
const core = resolve(args['native-dll'] ?? join(root, 'src/df-local-zh-native/target/release/df_local_zh_core.dll'));
const launcher = resolve(args['launcher-dll'] ?? join(here, 'df-broker-launch.dll'));
const rustBroker = resolve(args['broker-exe'] ?? join(root,'src/df-local-zh-native/target/release/df-local-zh-broker.exe'));
// No active mod, cache or player state is a package input.
const vendor = join(root, 'vendor/dfi18n-data-zh-hans');
const metadata = JSON.parse(await readFile(join(vendor, 'SOURCE.json'), 'utf8'));
const licenses = JSON.parse(await readFile(join(here, 'LICENSE-STATUS.json'), 'utf8'));
const approved = licenses.upstreamChineseDataRepositories.find(row => row.repository === metadata.repository && row.commit === metadata.commit);
if (!approved?.redistributionApproved) throw new Error('Pinned GitHub source has no recorded redistribution permission');
async function files(directory) {
  const result=[];
  for(const entry of await readdir(directory,{withFileTypes:true})) {
    const path=join(directory,entry.name);
    if(entry.isDirectory()) result.push(...await files(path));
    else if(entry.isFile()) result.push(path);
    else throw new Error(`Unexpected source entry: ${path}`);
  }
  return result.sort();
}
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
for(const entry of metadata.files) {
  if(sha256(await readFile(join(vendor,entry.path))) !== entry.sha256) throw new Error(`Changed pinned source: ${entry.path}`);
}
if((await files(vendor)).length !== metadata.files.length+1) throw new Error('Untracked files in pinned source');
for(const path of [core, launcher,rustBroker]) if(!(await stat(path)).isFile()) throw new Error(`Missing compiled runtime: ${path}`);
// Restrict deletion to a dedicated package output, never a source or state root.
if(!output.endsWith('df-local-zh-complete') || output === root || output.startsWith(join(root,'src')) || output.startsWith(join(root,'vendor'))) {
  throw new Error('Output must be a dedicated df-local-zh-complete package directory');
}
await rm(output,{recursive:true,force:true});
const data=join(output,'dfi18n-data');
await mkdir(join(output,'broker/data'),{recursive:true});
await mkdir(join(output,'libs'),{recursive:true});
await mkdir(join(output,'self-tests'),{recursive:true});
await cp(core,join(output,'libs/df_local_zh_core.dll'));
await cp(launcher,join(output,'broker/df-broker-launch.dll'));
await cp(rustBroker,join(output,'broker/df-local-zh-broker.exe'));
await cp(join(root,'src/df-local-zh-native/mod/df-local-zh-complete/scripts_modinstalled'),join(output,'scripts_modinstalled'),{recursive:true});
await rm(join(output,'scripts_modinstalled/df-local-zh-test.lua'),{force:true});
for(const path of await files(here)) {
  const name=relative(here,path).replaceAll('\\','/');
  // Explicit source-only allowlist: runtime files are never copied.
  const topLevel=!name.includes('/');
  const modules=topLevel && ['LICENSE-STATUS.json','glossary.json','glossary-zh-Hans.json','name-dictionary.json','reviewed.csv','corrections.csv','unit-prewarm.json'].includes(name);
  const staticData=/^data\/(?:announcement-rules\/.*\.toml|race-map\.json|fortress-hover\.json|fortress-ui\.csv|community-reviewed\.csv|community-workbook-zh-Ha(?:nt|ns)\.csv|prewarmed-(?:raw-states|reaction-names|case-variants|unresolved)\.csv|reviewed-raw-names\.csv)$/.test(name);
  if(modules||staticData) {await mkdir(dirname(join(output,'broker',name)),{recursive:true});await cp(path,join(output,'broker',name));}
}
for(const name of ['ATTRIBUTION.md','DFI18N-DATA-ZH-HANS-LICENSE.md','LICENSE.md','NOTICE.md']) await cp(join(root,name),join(output,name));
await cp(join(root,'src/df-local-zh-native/LICENSE'),join(output,'NATIVE-LICENSE.txt'));
await cp(join(root,'src/df-local-zh-native/third-party-licenses'),join(output,'third-party-licenses'),{recursive:true});
await cp(join(vendor,'LICENSE.md'),join(output,'third-party-licenses/dfi18n-data-CC-BY-NC-4.0.md'));
await cp(join(root,'docs/WORKSHOP-PUBLISHING.md'),join(output,'WORKSHOP-PUBLISHING.md'));
await cp(join(root,'assets/workshop-preview.png'),join(output,'preview.png'));

await mkdir(join(data,'simple/zh-Hant'),{recursive:true});
await mkdir(join(data,'simple/zh-Hans'),{recursive:true});
const upstreamData=join(vendor,'dfi18n-data');
const upstreamCsv=(await readFile(join(upstreamData,'simple/zh-Hans.csv'),'utf8'))
  .replace(/^Macro, Save,宏，保存,$/m,'"Macro, Save",宏，保存,')
  .replace(/^"Adventure: move view\/cursor down \(z\), fast","冒险模式: 向下移动视野\/光标 \(z\)，快速,$/m,
    '"Adventure: move view/cursor down (z), fast",冒险模式: 向下移动视野/光标 (z)，快速,');
await writeFile(join(data,'simple/zh-Hant/00-upstream.csv'),convertCsv(upstreamCsv));
await writeFile(join(data,'simple/zh-Hans/00-upstream.csv'),upstreamCsv);
for(const path of await files(join(upstreamData,'rulesets/zh-Hans'))) {
  const name=relative(join(upstreamData,'rulesets/zh-Hans'),path);
  await mkdir(dirname(join(data,'rulesets/zh-Hant',name)),{recursive:true});
  await writeFile(join(data,'rulesets/zh-Hant',name),convertRules(await readFile(path,'utf8')));
}
const patches=join(root,'src/data-patches');
const patchFiles=await files(patches);
for(const path of patchFiles) {
  const name=relative(patches,path).replaceAll('\\','/');
  if(name.startsWith('rulesets/zh-Hant/')) {
    const target=join(data,name), incoming=await readFile(path,'utf8');
    await mkdir(dirname(target),{recursive:true});
    let previous;
    try {previous=await readFile(target,'utf8');} catch(error) {if(error.code!=='ENOENT')throw error;}
    await writeFile(target,previous ? mergeTraditionalRuleOverride(previous,incoming) : incoming);
  } else if(/^simple\/zh-Hant\/.*\.csv$/.test(name)) await cp(path,join(data,name));
}
const creatures=join(data,'rulesets/zh-Hant/creatures/name.toml');
await writeFile(creatures,canonicalizeCreatureRules(await readFile(creatures,'utf8')));
const index=join(data,'rulesets/zh-Hant/index.toml');
await writeFile(index,mergeTraditionalRuleOverride(await readFile(index,'utf8'),await readFile(join(here,'data/announcement-rules/index.toml'),'utf8')));
await cp(join(here,'data/announcement-rules/announcement_date.toml'),join(data,'rulesets/zh-Hant/announcement_date.toml'));
for(const language of ['zh-Hant','zh-Hans']) {
  await cp(join(upstreamData,'fonts/zh-Hans'),join(data,'fonts',language),{recursive:true});
}
await writeFile(join(data,'dfi18n.txt'),'[FONT:fonts]\n[DATA:simple:simple]\n[DATA:rulesets:rulesets]\n');

const config={language:'zh-Hant',releaseMode:'standalone-bilingual',requiresUpstreamChineseWorkshopData:false,
  port:19753,dataDirectory:'data',raceMap:'data/race-map.json',timeoutMs:25000,reviewedDictionary:'reviewed.csv',
  staticDictionaryLanguage:'zh-Hant',staticDictionaries:['data/prewarmed-raw-states.csv','data/reviewed-raw-names.csv',
    'data/prewarmed-reaction-names.csv','data/prewarmed-case-variants.csv','data/community-reviewed.csv','data/fortress-ui.csv'],
  staticDictionariesByLanguage:{'zh-Hant':[],'zh-Hans':[]},literalDictionaries:[],glossaryPath:'glossary.json',
  glossaryPathsByLanguage:{'zh-Hans':'glossary-zh-Hans.json'},equipmentRulesDirectory:'../dfi18n-data/rulesets',rimworldConfig:''};
for(const file of [...config.staticDictionaries,config.reviewedDictionary,'corrections.csv']) {
  await cp(join(here,file),join(data,'simple/zh-Hant',`zz-local-${file.split('/').at(-1)}`));
}
await writeFile(join(output,'broker/config.json'),JSON.stringify(config,null,2)+'\n');
const converted=await buildSimplified(output);
// Retain original Hans source rather than round-tripping it through Hant.
await writeFile(join(data,'simple/zh-Hans/00-upstream.csv'),upstreamCsv);
// The approved original rules are retained where no local patch applies.
for(const path of await files(join(upstreamData,'rulesets/zh-Hans'))) {
  const name=relative(join(upstreamData,'rulesets/zh-Hans'),path);
  if(!name.includes('creatures') && !patchFiles.some(p=>relative(patches,p).replaceAll('\\','/')===`rulesets/zh-Hant/${name.replaceAll('\\','/')}`)) {
    await cp(path,join(data,'rulesets/zh-Hans',name));
  }
}
// Hans index must still include local, converted rule entries.
// Use the established T2S converter, not the CN->TW rule converter, for Hans.
const {simplifyTree}=await import('./language-data.mjs');
const TOML=(await import('@iarna/toml')).default;
await writeFile(join(data,'rulesets/zh-Hans/index.toml'),TOML.stringify(simplifyTree(TOML.parse(await readFile(index,'utf8')))));
for(const language of ['zh-Hant','zh-Hans']) {
  const file=`data/community-workbook-${language}.csv`;
  await cp(join(here,file),join(data,'simple',language,'zzzzzz-community-workbook.csv'));
  const current=JSON.parse(await readFile(join(output,'broker/config.json'),'utf8'));
  current.staticDictionariesByLanguage[language].push(file);current.literalDictionaries.push(file);
  const rows=ownedRows().filter(row=>row.kind==='exact').map(row=>({text:row.text,translation:language==='zh-Hans'?simplify(row.translation):row.translation,tags:'[REVIEWED:1]'}));
  const ownedFile=`data/official-builtin-${language}.csv`;
  const content=stringify(rows,{header:true,columns:['text','translation','tags']});
  await writeFile(join(output,'broker',ownedFile),content);
  await writeFile(join(data,'simple',language,'zzzzz-official-builtin.csv'),content);
  current.staticDictionariesByLanguage[language].push(ownedFile);current.literalDictionaries.push(ownedFile);
  await writeFile(join(output,'broker/config.json'),JSON.stringify(current,null,2)+'\n');
}
const creatureCounts=await buildCreatureDictionaries(output);
await writeFile(join(output,'info.txt'),`[ID:df-local-zh-complete]\n[NUMERIC_VERSION:1]\n[DISPLAYED_VERSION:${version}]\n[EARLIEST_COMPATIBLE_NUMERIC_VERSION:1]\n[AUTHOR:Local Chinese contributors; DFI18n contributors; Chinese Wiki translation team]\n[NAME:矮人要塞中文化（繁體／簡體整合）]\n[DESCRIPTION:內含繁體與簡體資料、自有原生核心與 Rust 本機服務。需要 DFHack；不需要 Node.js 或另外訂閱中文資料包。]\n[STEAM_TITLE:矮人要塞中文化（繁體／簡體整合）]\n[STEAM_DESCRIPTION:Windows DF 53.16 / DFHack 53.16-r1.1。單一模組內含繁簡資料、原生核心與 Rust 背景服務，於設定切換。玩家無須安裝 Node.js；網路請求、AI 補譯及官方譯庫同步由隨包元件處理。靜態與已安裝譯庫可離線使用。請勿同時啟用其他 DFI18n 原生核心。來源採 MIT、CC BY-NC 4.0、OFL，詳見 ATTRIBUTION.md。]\n[STEAM_CHANGELOG:${version}：更正授權方向與下游開發者身分；繁簡與 Rust 執行功能保留。]\n[STEAM_TAG:dfhack]\n[STEAM_TAG:translation]\n[STEAM_TAG:chinese]\n`);
await cp(join(root,'docs/PLAYER-INSTALL.md'),join(output,'README.md'));
const counts={};
for(const language of ['zh-Hant','zh-Hans']) {
  let simpleRows=0;
  for(const path of await files(join(data,'simple',language))) simpleRows+=parse(await readFile(path,'utf8'),{columns:true,bom:true,skip_empty_lines:true}).length;
  counts[language]={simpleRows,rulesetFiles:(await files(join(data,'rulesets',language))).length,creatureRows:creatureCounts[language]};
}
const manifestFiles=[];
const binaryExtensions=/\.(?:dll|exe|node|otf|png|jpg|jpeg|gif|so|dylib|zip|bin)$/i;
for(const path of await files(output)) {
  const name=relative(output,path).replaceAll('\\','/');
  if(/(?:world-names\.json|translations\.jsonl|runtime-(?:requests|responses|failures)|\.private\.json|\.pem$|secrets\.json|\.git\/|(?:^|\/)target\/|\.log$)/i.test(name)) throw new Error(`Private artifact: ${name}`);
  // Release hashes must survive a Windows or Linux Git checkout.
  if(!binaryExtensions.test(name)) {
    const content=await readFile(path,'utf8');
    if(content.includes('\r\n'))await writeFile(path,content.replaceAll('\r\n','\n'));
  }
  manifestFiles.push({path:name,sha256:sha256(await readFile(path))});
}
const manifest={package:'df-local-zh-complete',version,generatedAt:new Date().toISOString(),releaseMode:'standalone-bilingual',
  runtime:'rust',requiresNode:false,brokerSha256:sha256(await readFile(rustBroker)),
  languages:['zh-Hant','zh-Hans'],requiresOriginalEngine:false,requiresOriginalDataSubscription:false,
  requiredWorkshopItems:[],requiresDFHack:true,privateRuntimeExcluded:true,upstreamDataBundled:true,upstreamRedistributionApproved:true,
  upstreamLicenseMetadata:[approved],sourceMetadata:metadata,changes:['CN->TW conversion with OpenCC and local terminology corrections',
    'Fixed missing CSV quoting in Macro, Save and Adventure down-fast rows; source vendor remains unchanged',
    'Hans original source retained; local Hant overrides converted with OpenCC T2S','Project static dictionaries and owned exact rows added'],
  counts,nativeCoreSha256:sha256(await readFile(core)),files:manifestFiles};
await writeFile(join(output,'PACKAGE-MANIFEST.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({output,files:manifestFiles.length,counts,converted},null,2));
