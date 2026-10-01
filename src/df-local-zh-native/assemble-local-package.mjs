import { cp, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from '../broker/node_modules/csv-parse/lib/sync.js';
import { buildSimplified } from '../broker/build-language-data.mjs';
import { buildCreatureDictionaries } from '../broker/build-creature-dictionaries.mjs';
import { buildArenaCorrections } from '../broker/build-arena-corrections.mjs';
import { loadEquipmentTerms, translateEquipmentName } from '../broker/equipment-names.mjs';
import { buildWorkbookContextRules } from '../broker/build-workbook-context.mjs';
import {fixedNeeds} from '../broker/unit-prewarm.mjs';
import {ownedRows} from '../broker/official-owned.mjs';
import {stringify} from '../broker/node_modules/csv-stringify/lib/sync.js';

const root = dirname(fileURLToPath(import.meta.url));
const output = resolve(process.argv[2] ?? join(root, '../standalone/df-local-zh-complete'));
const base = JSON.parse(await readFile(join(output, 'PACKAGE-MANIFEST.json'), 'utf8'));
if (base.package !== 'df-local-zh-complete' || !base.privateRuntimeExcluded) throw new Error('Prepare the local base package first');
await cp(join(root, 'mod/df-local-zh-complete/scripts_modinstalled'), join(output, 'scripts_modinstalled'), { recursive: true });
await cp(join(root, 'self-tests'), join(output, 'self-tests'), { recursive: true });
await mkdir(join(output, 'libs'), { recursive: true });
// A live Lua/Broker deployment must retain the DLL currently attached to DF.
await cp(process.env.DF_LOCAL_ZH_NATIVE_DLL ?? join(root, 'target/release/df_local_zh_core.dll'), join(output, 'libs/df_local_zh_core.dll'));
await cp(join(root, 'LICENSE'), join(output, 'NATIVE-LICENSE.txt'));
await cp(join(root, 'NOTICE.md'), join(output, 'NATIVE-NOTICE.md'));
await cp(join(root, 'DFI18N-DATA-ZH-HANS-LICENSE.md'), join(output, 'DFI18N-DATA-ZH-HANS-LICENSE.md'));
await cp(join(root, 'ATTRIBUTION.md'), join(output, 'ATTRIBUTION.md'));
await cp(join(root, 'third-party-licenses'), join(output, 'third-party-licenses'), {recursive:true});
await cp(join(root, 'OWNED-CORE.md'), join(output, 'README.md'));
await cp(join(root, '../WORKSHOP-PUBLISHING.md'), join(output, 'WORKSHOP-PUBLISHING.md'));
await mkdir(join(output, 'native-source'), { recursive: true });
for (const name of ['dfi18n', 'crates', 'translation-tool', 'mod', 'resources', 'self-tests', 'third-party-licenses', 'Cargo.toml', 'Cargo.lock', 'LICENSE', 'NOTICE.md', 'DFI18N-DATA-ZH-HANS-LICENSE.md', 'ATTRIBUTION.md', 'rust-toolchain.toml', 'rustfmt.toml', 'OWNED-CORE.md', 'assemble-local-package.mjs']) {
  await cp(join(root, name), join(output, 'native-source', name), { recursive: true });
}
await writeFile(join(output, 'info.txt'), `[ID:df-local-zh-complete]
[NUMERIC_VERSION:1]
[DISPLAYED_VERSION:0.3.0-local]
[AUTHOR:Local Traditional Chinese contributors; DFI18n MIT contributors]
[NAME:Local Traditional Chinese (Owned Core)]
[DESCRIPTION:Own native translation core, Traditional Chinese dictionaries and local Broker. Requires DFHack. Local use only.]
`, 'utf8');
const configPath = join(output, 'broker/config.json');
const config = JSON.parse(await readFile(configPath, 'utf8'));
await cp(join(root, '../broker/data/community-reviewed.csv'), join(output, 'broker/data/community-reviewed.csv'));
if (!config.staticDictionaries.includes('data/community-reviewed.csv')) config.staticDictionaries.push('data/community-reviewed.csv');
for (const file of ['server.mjs', 'broker.mjs', 'names.mjs', 'provider.mjs', 'prompts.mjs', 'clipboard.mjs', 'settings.mjs', 'language-data.mjs',
  'equipment-names.mjs', 'safety.mjs','provider-pool.mjs','build-workbook-context.mjs','import-workbook-supplement.mjs','workbook-expansion.mjs',
  'build-language-data.mjs','build-creature-dictionaries.mjs','build-arena-corrections.mjs','literal-lookup.mjs','runtime-queue.mjs','status.mjs','native-prewarm.mjs',
  'compile-data.mjs', 'workbook-supplement.mjs', 'glossary-zh-Hans.json',
  'official-library.mjs','official-trust.mjs','shared-policy.mjs','shared-outbox.mjs',
  'official-owned.mjs','unit-prewarm.mjs','LICENSE-STATUS.json','README.md',
  'data/community-workbook-corrections.json']) {
  await cp(join(root, '../broker', file), join(output, 'broker', file));
}
config.staticDictionaryLanguage = 'zh-Hant';
config.staticDictionariesByLanguage ??= {};
config.literalDictionaries ??= [];
const workbookFixtures = {};
for (const language of ['zh-Hant', 'zh-Hans']) {
  const file = `data/community-workbook-${language}.csv`;
  await cp(join(root, '../broker', file), join(output, 'broker', file));
  const directory = join(output, 'dfi18n-data/simple', language);
  await mkdir(directory, { recursive: true });
  await cp(join(root, '../broker', file), join(directory, 'zzzzzz-community-workbook.csv'));
  workbookFixtures[language] = parse(await readFile(join(root, '../broker', file), 'utf8'), { columns: true });
  config.staticDictionariesByLanguage[language] = [...new Set([
    ...(config.staticDictionariesByLanguage[language] ?? []), file])];
  if (!config.literalDictionaries.includes(file)) config.literalDictionaries.push(file);
}
config.glossaryPathsByLanguage = { ...config.glossaryPathsByLanguage, 'zh-Hans': 'glossary-zh-Hans.json' };
config.equipmentRulesDirectory = '../dfi18n-data/rulesets';
await cp(join(output, 'dfi18n-data/fonts/zh-Hant'), join(output, 'dfi18n-data/fonts/zh-Hans'), { recursive: true });
config.releaseMode = 'owned-core-local';
config.requiresUpstreamChineseWorkshopData = false;
await writeFile(configPath, JSON.stringify(config, null, 2) + '\n');
const simplified=await buildSimplified(output);
let workbookSource;
try {workbookSource=JSON.parse(await readFile(join(root,'../text-audit/community-workbook-extracted.json'),'utf8'));}
catch(error) {
  if(error.code!=='ENOENT') throw error;
  workbookSource=JSON.parse(await readFile(join(output,'broker/data/community-workbook-source.json'),'utf8'));
}
await writeFile(join(output,'broker/data/community-workbook-source.json'),JSON.stringify({
  sha256:workbookSource.sha256,candidates:workbookSource.candidates.map(({text,translation,sheet,row,columns})=>
    ({text,translation,sheet,row,columns}))})+'\n');
const workbookCorrections=JSON.parse(await readFile(join(root,'../broker/data/community-workbook-corrections.json'),'utf8'));
console.log('WORKBOOK_CONTEXT '+JSON.stringify(await buildWorkbookContextRules(output,workbookSource.candidates,workbookCorrections)));
console.log('CREATURE_DICTIONARIES '+JSON.stringify(await buildCreatureDictionaries(output)));
console.log('ARENA_CORRECTIONS '+JSON.stringify(await buildArenaCorrections(output)));
// Compile the finite local Needs corrections that overlap the official schema.
// This stays local: no upstream rules or Chinese data enter the published corpus.
// An exact dictionary hit preserves rule precedence without a main-thread rule scan.
const officialSources=new Set(ownedRows().map(row=>row.text));
for(const language of ['zh-Hant','zh-Hans']) {
  const rules=join(output,'dfi18n-data/rulesets',language);
  const rows=fixedNeeds(await readFile(join(rules,'plain_needs.toml'),'utf8'),
    await readFile(join(rules,'psychology/needs.toml'),'utf8')).filter(row=>officialSources.has(row.text))
    .map(row=>({...row,tags:'[REVIEWED:1]'}));
  const content=stringify(rows,{header:true,columns:['text','translation','tags']});
  const filename=`data/official-local-rules-${language}.csv`;
  await writeFile(join(output,'broker',filename),content);
  await writeFile(join(output,'dfi18n-data/simple',language,'zzzzzzzzz-official-local-rules.csv'),content);
  config.staticDictionariesByLanguage[language]=[...new Set([...config.staticDictionariesByLanguage[language],filename])];
  if(!config.literalDictionaries.includes(filename))config.literalDictionaries.push(filename);
  console.log(`OFFICIAL_LOCAL_RULES ${language} rows=${rows.length}`);
}
await writeFile(configPath,JSON.stringify(config,null,2)+'\n');
for (const language of ['zh-Hant', 'zh-Hans']) {
  const suffix = language === 'zh-Hans' ? '-zh-Hans' : '';
  const reviewed = parse(await readFile(join(output, `broker/data/fortress-ui${suffix}.csv`), 'utf8'), { columns: true });
  const reviewedBySource = new Map(reviewed.map(row => [row.text, row.translation]));
  // Expected workbook results follow the same reviewed overrides as the runtime.
  // Preserve the original workbook spelling in workbookTranslation for provenance.
  for (const name of ['creature-names', 'arena-corrections']) {
    const corrections = parse(await readFile(join(output, `broker/data/${name}-${language}.csv`), 'utf8'), { columns: true });
    for (const row of corrections) reviewedBySource.set(row.text, row.translation);
  }
  const equipment = await loadEquipmentTerms(join(output, 'dfi18n-data/rulesets', language));
  workbookFixtures[language] = workbookFixtures[language].map(row => {
    const translation = translateEquipmentName(row.text, equipment) ?? reviewedBySource.get(row.text);
    return translation === undefined ? row : { ...row, workbookTranslation: row.translation, translation };
  });
}
await writeFile(join(output, 'self-tests/workbook-dictionaries.json'), JSON.stringify(workbookFixtures) + '\n');
console.log('SIMPLIFIED_DATA '+JSON.stringify(simplified));
const files = [];
async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) await walk(path);
    else if (path !== join(output, 'PACKAGE-MANIFEST.json')) files.push(path);
  }
}
await walk(output);
const manifest = [];
for (const path of files.sort()) {
  const name = relative(output, path).replaceAll('\\', '/');
  if (/(?:world-names\.json|translations\.jsonl|native-cache.*jsonl|runtime-(?:requests|responses)|server\.(?:stdout|stderr)|provider\.json|api-profiles\.private\.json|settings-(?:request|response|public)\.json|active-context\.json|(?:shared|official)\/(?:state|status[^/]*)\.json|\.pem$|secrets\.json|\.git\/|target\/)/i.test(name)) throw new Error(`Private/generated runtime artifact: ${name}`);
  manifest.push({ path: name, sha256: createHash('sha256').update(await readFile(path)).digest('hex') });
}
const licenseStatus = JSON.parse(await readFile(join(root, '../broker/LICENSE-STATUS.json'), 'utf8'));
await writeFile(join(output, 'PACKAGE-MANIFEST.json'), JSON.stringify({
  package: base.package, version: '0.3.0-local', generatedAt: new Date().toISOString(),
  releaseMode: 'owned-core-local', localOnly: true, privateRuntimeExcluded: true,
  requiresOriginalEngine: false, requiresOriginalDataSubscription: false,
  upstreamDataBundled: true, upstreamRedistributionApproved: false,
  upstreamLicenseMetadata: licenseStatus.upstreamChineseDataRepositories ?? [],
  nativeSourceIncluded: true, files: manifest,
}, null, 2) + '\n');
console.log(`OWNED_PACKAGE files=${manifest.length} original_engine_dependency=false private_state_excluded=true source_included=true output=${output}`);
