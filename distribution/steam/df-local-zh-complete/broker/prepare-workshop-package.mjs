import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import {spawnSync} from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
// Public full builds use the pinned source builder, never the active player's mod.
if(!process.argv.includes('--adapter-only') && !process.argv.includes('--allow-unverified-upstream')) {
  const result=spawnSync(process.execPath,[join(here,'prepare-standalone-package.mjs'),...process.argv.slice(2)],{stdio:'inherit'});
  process.exit(result.status ?? 1);
}
const gameRoot = resolve(here, '../..');
const args = new Map();
for (let i = 2; i < process.argv.length; i++) {
  const value = process.argv[i];
  if (value === '--allow-unverified-upstream') args.set('allow', true);
  else if (value === '--adapter-only') args.set('adapterOnly', true);
  else if (value.startsWith('--output=')) args.set('output', resolve(value.slice('--output='.length)));
  else if (value.startsWith('--active-mod=')) args.set('active', resolve(value.slice('--active-mod='.length)));
  else if (value.startsWith('--version=')) args.set('version', value.slice('--version='.length));
}

const output = args.get('output') ?? resolve(here, '../workshop/df-local-zh-complete');
const activeMod = args.get('active') ?? join(process.env.APPDATA ?? '', 'Bay 12 Games', 'Dwarf Fortress', 'mods', 'df-local-zh-complete');
const packageVersion = args.get('version') ?? '0.1.0-dev';
const adapterOnly = Boolean(args.get('adapterOnly'));
const upstreamWorkshopDependencyText = 'DFI18n Workshop 3613958631 與中文資料 Workshop 3635900931';
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(packageVersion)) {
  throw new Error(`Invalid package version: ${packageVersion}`);
}
const status = JSON.parse(await readFile(join(here, 'LICENSE-STATUS.json'), 'utf8'));
if (!adapterOnly && !status.upstreamChineseWorkshopData.redistributionApproved && !args.get('allow')) {
  throw new Error('Upstream Chinese Workshop redistribution is not approved. Use --allow-unverified-upstream only for a private local test package.');
}

let scriptDirectory = join(gameRoot, 'hack', 'scripts');
if (!(await readdir(scriptDirectory)).some(name => name === 'df-local-zh.lua')) {
  scriptDirectory = resolve(here, '../df-local-zh-native/mod/df-local-zh-complete/scripts_modinstalled');
}
const scripts = (await readdir(scriptDirectory))
  .filter(name => /^df-local-zh.*\.lua$/i.test(name) && name !== 'df-local-zh-test.lua');
const brokerFiles = [
  'broker.mjs', 'compile-data.mjs', 'config.json', 'data.mjs', 'description-terms.mjs',
  'dynamic.mjs', 'glossary.json', 'legends-captions.mjs', 'name-dictionary.json', 'reviewed.csv',
  'names.mjs', 'package.json', 'package-lock.json', 'prepare-descriptions.mjs',
  'provider.mjs', 'rich-text.mjs', 'runtime-queue.mjs', 'safety.mjs', 'server.mjs',
  'native-prewarm.mjs', 'status.mjs', 'unit-prewarm.json',
  'Start-Broker.ps1', 'df-broker-launch.dll', 'README.md', 'LICENSE-STATUS.json',
  'validate-workshop-package.mjs',
];
const staticData = [
  'data/descriptions.jsonl', 'data/race-map.json', 'data/prewarmed-unresolved.csv', 'data/prewarmed-raw-states.csv',
  'data/reviewed-raw-names.csv', 'data/prewarmed-reaction-names.csv',
  'data/prewarmed-case-variants.csv',
  'data/fortress-ui.csv',
  'data/fortress-hover.json',
  'data/announcement-rules/index.toml',
  'data/announcement-rules/announcement_date.toml',
];

await rm(output, { recursive: true, force: true });
await mkdir(join(output, 'scripts_modinstalled'), { recursive: true });
await mkdir(join(output, 'broker', 'data'), { recursive: true });
await mkdir(join(output, 'broker', 'data', 'announcement-rules'), { recursive: true });
await mkdir(join(output, 'broker', 'node_modules'), { recursive: true });
if (!adapterOnly) await cp(join(activeMod, 'dfi18n-data'), join(output, 'dfi18n-data'), { recursive: true });
const previewSource = join(here, '../workshop-assets/preview.png');
try {
  await cp(previewSource, join(output, 'preview.png'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
  console.warn(`No preview image found at ${previewSource}; package remains suitable for local testing only.`);
}

for (const script of scripts) await cp(join(scriptDirectory, script), join(output, 'scripts_modinstalled', script));
for (const file of brokerFiles) await cp(join(here, file), join(output, 'broker', file));
try {
  await cp(join(here, 'node_modules'), join(output, 'broker', 'node_modules'), { recursive: true });
} catch (error) {
  if (error.code === 'ENOENT') {
    throw new Error('Broker dependencies are missing. Run npm ci in broker before building the Workshop package.');
  }
  throw error;
}
for (const file of staticData) await cp(join(here, file), join(output, 'broker', file));
await cp(join(here, '../WORKSHOP-PUBLISHING.md'), join(output, 'WORKSHOP-PUBLISHING.md'));
for (const file of ['DFI18N-DATA-ZH-HANS-LICENSE.md', 'ATTRIBUTION.md']) {
  await cp(join(here, '../df-local-zh-native', file), join(output, file));
}

const packageConfig = {
  language: 'zh-Hant',
  releaseMode: adapterOnly ? 'adapter-only' : 'bundled-upstream',
  requiresUpstreamChineseWorkshopData: adapterOnly,
  port: 19753,
  dataDirectory: 'data',
  descriptionInventory: 'data/descriptions.jsonl',
  raceMap: 'data/race-map.json',
  timeoutMs: 25000,
  reviewedDictionary: 'reviewed.csv',
  staticDictionaries: [
    'data/prewarmed-raw-states.csv', 'data/reviewed-raw-names.csv',
    'data/prewarmed-reaction-names.csv', 'data/prewarmed-case-variants.csv',
    'data/fortress-ui.csv',
  ],
  glossaryPath: 'glossary.json',
  rimworldConfig: '',
};
await writeFile(join(output, 'broker', 'config.json'), JSON.stringify(packageConfig, null, 2) + '\n', 'utf8');

const dependencyText = adapterOnly
  ? '需要玩家另外訂閱 DFI18n 與上游中文資料；本包不重新發布上游資料。'
  : '需要 DFHack 與 DFI18n；AI 補譯為可選的本機設定。';
const info = `[ID:df-local-zh-complete]
[NUMERIC_VERSION:1]
[DISPLAYED_VERSION:${packageVersion}]
[EARLIEST_COMPATIBLE_NUMERIC_VERSION:1]
[EARLIEST_COMPATIBLE_DISPLAYED_VERSION:0.1.0-dev]
[AUTHOR:Traditional Chinese Localization contributors]
[NAME:矮人要塞繁體中文化（DFI18n 擴充）]
[DESCRIPTION:繁體中文翻譯資料與動態文字適配器。${dependencyText}]
[STEAM_TITLE:矮人要塞繁體中文化]
[STEAM_DESCRIPTION:繁體中文翻譯資料與 Legends 動態文字適配器。需要 DFHack 53.16-r1.1、DFI18n 0.2.4，以及 ${adapterOnly ? `${upstreamWorkshopDependencyText}；請另外訂閱，本包不包含上游資料。` : '本機測試用中文資料。'} AI 補譯只讀取玩家本機設定，不會把金鑰或存檔放進模組。]
[STEAM_CHANGELOG:${packageVersion}：更新繁體中文資料與動態文字適配器；請查看 README 的相容性與已知限制。]
[STEAM_TAG:dfhack]
[STEAM_TAG:translation]
[STEAM_TAG:chinese]
`;
await writeFile(join(output, 'info.txt'), info, 'utf8');

const readme = `# 矮人要塞繁體中文化\n\n這是 DFHack／DFI18n 的繁體中文資料擴充，包含靜態介面字典、Legends 名稱與動態敘述適配器。\n\n## 依賴\n\n- Dwarf Fortress 53.16\n- DFHack 53.16-r1.1\n- DFI18n 0.2.4\n- ${adapterOnly ? '上游中文資料 Workshop 項目（請玩家自行訂閱；本包不含該資料）' : '本機測試用中文資料'}\n- 動態 AI 補譯需要玩家自行安裝 Node.js，並在本機設定 RimWorld Auto AI Translation Core；模組不包含金鑰。\n\n## 啟用\n\nDFHack 會自動發現本模組的腳本。請在 DFHack 的 \`dfhack.init\` 加入一行 \`df-local-zh\`，重新啟動遊戲後套用繁體中文。\n\n## Workshop 發佈\n\n請先訂閱 DFI18n 與相容的中文資料，再安裝本模組。建置與上傳流程、授權閘門及獨立安裝檢查，請看根目錄的 \`WORKSHOP-PUBLISHING.md\`。\n\n## 隱私與狀態\n\n世界名稱、翻譯快取、未解決文字、AI 設定與日誌會寫入 \`dfhack-config/mods/df-local-zh-complete\`，不會寫回 Workshop 模組。沒有 AI 設定時，已編譯字典仍可使用；首次遇到的動態文字可能維持英文，直到本機翻譯完成。\n\n## 發佈狀態\n\n${adapterOnly ? '這是可供公開發佈的適配器包；上游中文資料由玩家透過 Steam Workshop 另外訂閱。' : '這是開發測試包，不代表遊戲所有畫面已完成零英文驗證。'} 上傳正式版前，仍必須完成獨立安裝、兩個世界、要塞模式、Legends、動態敘述與模組文字驗證。\n`;
await writeFile(join(output, 'README.md'), readme + '\n## 動態報告\n\n公告、戰鬥與醫療報告會在產生時加入本機翻譯佇列，並沿用世界限定的名稱與數字驗證。\n\n## 文字頁\n\n矮人思緒、物品與神器描述、書籍與歷史文字頁會在 textviewer 焦點下遮罩尚未翻譯的英文列，並保留原生輸入與滾動。\n\n包內已附鎖定的 Broker production 依賴；只有在自行重建包且未安裝依賴時，才需要在 broker 目錄執行 `npm ci --omit=optional`。\n', 'utf8');

const forbidden = /(?:[A-Z]:\\Users\\|api[_ -]?key|runtime-(?:requests|responses)|world-names\.json|translations\.jsonl|server\.(?:stdout|stderr)\.log|\.codex)/i;
const absoluteUserPath = /[A-Z]:[\\/]+Users[\\/]/i;
const files = [];
async function walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) await walk(path);
    else files.push(path);
  }
}
await walk(output);
for (const path of files) {
  const rel = relative(output, path).replaceAll('\\', '/');
  if (forbidden.test(rel)) throw new Error(`Private runtime artifact in package: ${rel}`);
  if (rel.endsWith('.json') || rel.endsWith('.txt')) {
    const content = await readFile(path, 'utf8');
    if (forbidden.test(content)) throw new Error(`Private value in package: ${rel}`);
  }
  if (!rel.endsWith('.otf')) {
    const content = await readFile(path, 'utf8');
    if (absoluteUserPath.test(content)) throw new Error(`Absolute user path in package: ${rel}`);
  }
}
const manifest = [];
for (const path of files.sort()) {
  const digest = createHash('sha256').update(await readFile(path)).digest('hex');
  manifest.push({ path: relative(output, path).replaceAll('\\', '/'), sha256: digest });
}
await writeFile(join(output, 'PACKAGE-MANIFEST.json'), JSON.stringify({
  package: 'df-local-zh-complete', version: packageVersion, generatedAt: new Date().toISOString(),
  privateRuntimeExcluded: true, releaseMode: adapterOnly ? 'adapter-only' : 'bundled-upstream',
  upstreamDataBundled: !adapterOnly,
  upstreamRedistributionApproved: Boolean(status.upstreamChineseWorkshopData.redistributionApproved),
  upstreamLicenseMetadata: status.upstreamChineseDataRepositories ?? [], files: manifest,
}, null, 2) + '\n', 'utf8');
console.log(`Prepared ${manifest.length} files at ${output}`);
