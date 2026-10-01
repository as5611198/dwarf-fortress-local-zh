import { readdir, mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { join, resolve, dirname } from 'node:path';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import { canonicalizeCreatureRules, convertCsv, convertRules, mergeTraditionalRuleOverride, reconcilePinnedNames } from './data.mjs';
import { validateTranslation, hasCanonicalNameCounts, mentionsTerm, cacheKey, POLICY_VERSION } from './safety.mjs';

const [baseArg, localArg, outputArg] = process.argv.slice(2);
if (!baseArg || !localArg || !outputArg) throw new Error('Usage: node compile-data.mjs <companion-data> <native-local-data> <output-mod>');
const base = resolve(baseArg), local = resolve(localArg), output = resolve(outputArg);
const data = join(output, 'dfi18n-data');
const glossary = JSON.parse(await readFile(new URL('./glossary.json', import.meta.url), 'utf8'));
let csvRows = 0, rules = 0;
async function listFiles(path, prefix = '') {
  const found = [];
  for (const item of await readdir(path, { withFileTypes: true })) {
    const relative = join(prefix, item.name);
    if (item.isDirectory()) found.push(...await listFiles(join(path, item.name), relative));
    else if (item.isFile()) found.push(relative);
  }
  return found;
}
for (const [source, type] of [[join(base, 'simple', 'zh-Hans'), 'simple'], [join(local, 'simple', 'zh-Hans'), 'simple'], [join(base, 'rulesets', 'zh-Hans'), 'rulesets'], [join(local, 'rulesets', 'zh-Hans'), 'rulesets']]) {
  let files;
  try { files = await listFiles(source); } catch (e) { if (e.code === 'ENOENT') continue; throw e; }
  const target = join(data, type, 'zh-Hant');
  await mkdir(target, { recursive: true });
  for (const file of files) {
    await mkdir(dirname(join(target, file)), { recursive: true });
    if (type === 'simple' && file.endsWith('.csv')) {
      const converted = convertCsv(await readFile(join(source, file), 'utf8'));
      csvRows += parse(converted, { columns: true }).length;
      await writeFile(join(target, file), converted, 'utf8');
    } else if (type === 'rulesets' && file.endsWith('.toml')) {
      await writeFile(join(target, file), convertRules(await readFile(join(source, file), 'utf8')), 'utf8');
      rules++;
    }
  }
}
const traditionalOverrides = join(local, 'rulesets', 'zh-Hant');
try {
  for (const file of await listFiles(traditionalOverrides)) {
    if (!file.endsWith('.toml')) continue;
    const target = join(data, 'rulesets', 'zh-Hant', file);
    const override = await readFile(join(traditionalOverrides, file), 'utf8');
    try {
      await writeFile(target, mergeTraditionalRuleOverride(await readFile(target, 'utf8'), override), 'utf8');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, override, 'utf8');
    }
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }
const traditionalSimpleOverrides = join(local, 'simple', 'zh-Hant');
try {
  for (const file of await listFiles(traditionalSimpleOverrides)) {
    if (!file.endsWith('.csv')) continue;
    const target = join(data, 'simple', 'zh-Hant', file);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, await readFile(join(traditionalSimpleOverrides, file), 'utf8'), 'utf8');
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }
const creatureRulesPath = join(data, 'rulesets', 'zh-Hant', 'creatures', 'name.toml');
await writeFile(creatureRulesPath, canonicalizeCreatureRules(await readFile(creatureRulesPath, 'utf8')), 'utf8');
const reviewed = parse(await readFile(new URL('./reviewed.csv', import.meta.url), 'utf8'), { columns: true });
const corrections = parse(await readFile(new URL('./corrections.csv', import.meta.url), 'utf8'), { columns: true });
let community = [];
try { community = parse(await readFile(new URL('./data/community-reviewed.csv', import.meta.url), 'utf8'), { columns: true }); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const greed = { Greed: '貪欲', Avarice: '貪婪', Jealousy: '嫉妒', Cupidity: '貪財', Gluttony: '貪食' };
const work = { Toil: '勞苦', Diligence: '勤勉', Exertion: '奮力', Tenacity: '堅韌', Resourcefulness: '機智', Determination: '決心', Mettle: '勇氣', Dynamism: '活力', Industry: '勤奮', Enterprise: '進取', Labor: '勞動', Perseverance: '毅力' };
for (const [a, zhA] of Object.entries(greed)) {
  for (const [b, zhB] of Object.entries(work)) corrections.push({ text: `Histories of ${a} and ${b}`, translation: `${zhA}與${zhB}的歷史`, tags: '[ALIGNMENT:CENTER]' });
}
await writeFile(join(data, 'simple', 'zh-Hant', 'zzz-local-reviewed.csv'), stringify([...reviewed, ...corrections, ...community], { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
await copyFile(new URL('./data/fortress-ui.csv', import.meta.url),
  join(data, 'simple', 'zh-Hant', 'zzzzz-fortress-ui.csv'));
const workbookRows = {};
for (const language of ['zh-Hant', 'zh-Hans']) {
  try {
    const path = new URL(`./data/community-workbook-${language}.csv`, import.meta.url);
    workbookRows[language] = parse(await readFile(path, 'utf8'), { columns: true }).length;
    await mkdir(join(data, 'simple', language), { recursive: true });
    await copyFile(path, join(data, 'simple', language, 'zzzzzz-community-workbook.csv'));
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
await mkdir(join(output,'broker','data'),{recursive:true});
await copyFile(new URL('./data/fortress-hover.json',import.meta.url),join(output,'broker','data','fortress-hover.json'));
const indexPath=join(data,'rulesets','zh-Hant','index.toml');
await writeFile(indexPath,mergeTraditionalRuleOverride(await readFile(indexPath,'utf8'),
  await readFile(new URL('./data/announcement-rules/index.toml',import.meta.url),'utf8')),'utf8');
await copyFile(new URL('./data/announcement-rules/announcement_date.toml',import.meta.url),
  join(data,'rulesets','zh-Hant','announcement_date.toml'));
await mkdir(join(data, 'fonts', 'zh-Hant'), { recursive: true });
for (const font of await readdir(join(base, 'fonts', 'zh-Hans'))) {
  await copyFile(join(base, 'fonts', 'zh-Hans', font), join(data, 'fonts', 'zh-Hant', font));
}
await writeFile(join(data, 'dfi18n.txt'), '[FONT:fonts]\n[DATA:simple:simple]\n[DATA:rulesets:rulesets]\n', 'utf8');
await writeFile(join(output, 'info.txt'), '[ID:df-local-zh-complete]\n[NUMERIC_VERSION:1]\n[DISPLAYED_VERSION:0.1.0]\n[AUTHOR:Local]\n[NAME:Local Traditional Chinese]\n[DESCRIPTION:Supplementary Chinese dictionaries and translation broker integration.]\n', 'utf8');
const TOML = (await import('@iarna/toml')).default;
const nameRules = TOML.parse(await readFile(join(data, 'rulesets', 'zh-Hant', 'dwarf_language', 'none.toml'), 'utf8'));
const names = {};
for (const row of nameRules.rulesets ?? []) {
  for (const [key, value] of Object.entries(row.rules ?? {})) {
    if (!/[{}]/.test(key) && typeof value === 'string' && !/\p{Script=Latin}/u.test(value)) names[key] = value;
  }
}
const fixedNames = Object.fromEntries(Object.entries(glossary).filter(([name]) => Object.hasOwn(names, name)));
for (const row of nameRules.rulesets) {
  for (const [name, translation] of Object.entries(fixedNames)) {
    if (Object.hasOwn(row.rules ?? {}, name)) row.rules[name] = translation;
  }
}
Object.assign(names, fixedNames);
await writeFile(join(data, 'rulesets', 'zh-Hant', 'dwarf_language', 'none.toml'), TOML.stringify(nameRules), 'utf8');
await writeFile(new URL('./name-dictionary.json', import.meta.url), JSON.stringify(names), 'utf8');
let prewarmed = [];
for (const filename of ['prewarmed.csv', 'prewarmed-unresolved.csv', 'prewarmed-legends.csv', 'prewarmed-descriptions.csv', 'prewarmed-raw-states.csv', 'reviewed-raw-names.csv', 'prewarmed-reaction-names.csv', 'prewarmed-case-variants.csv', 'live-check.csv', 'composed-legends.csv']) {
  try { prewarmed.push(...parse(await readFile(new URL('./data/' + filename, import.meta.url), 'utf8'), { columns: true })); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
const fixed = new Map(prewarmed.map(row => [row.text, { ...row, translation: validateTranslation(row.text, row.translation) }]));
const pinnedAliases = new Set();
for (const [text, translation] of Object.entries(glossary)) fixed.set(text, { text, translation: validateTranslation(text, translation), tags: '' });
try {
  const registry = JSON.parse(await readFile(new URL('./data/world-names.json', import.meta.url), 'utf8'));
  const variants = JSON.parse(await readFile(new URL('./canonical-name-variants.json', import.meta.url), 'utf8'));
  const entities = new Map(registry.entities.map(row => [row.id, row]));
  const pins = new Map();
  const journal = await readFile(new URL('./data/translations.jsonl', import.meta.url), 'utf8');
  for (const line of journal.split('\n').filter(Boolean)) {
    let row;
    try { row = JSON.parse(line); } catch { continue; }
    if (row.kind !== 'name' || row.policy !== POLICY_VERSION || row.language !== 'zh-Hant' ||
        row.key !== cacheKey(row.source, row.language, POLICY_VERSION + ':name')) continue;
    let world, id, preferred;
    try { [world, id, preferred] = JSON.parse(row.source); } catch { continue; }
    const entity = entities.get(id);
    if (world !== registry.world || entity?.preferred !== preferred) continue;
    pins.set(id, { aliases: entity.aliases, translation: validateTranslation(preferred, row.translation),
      legacy: variants[preferred] ?? [] });
  }
  try {
    const captions = await readFile(new URL('./data/captured-legends.jsonl', import.meta.url), 'utf8');
    for (const line of captions.split('\n').filter(Boolean)) {
      let caption;
      try { caption = JSON.parse(line); } catch { continue; }
      if (caption.world !== registry.world || !Number.isInteger(caption.id)) continue;
      const pin = pins.get('figure:' + caption.id);
      const row = fixed.get(caption.text);
      if (pin && row && !hasCanonicalNameCounts(caption.text, row.translation,
        Object.fromEntries(pin.aliases.map(alias => [alias, pin.translation])))) {
        throw new Error(`inconsistent captured Legends caption for figure:${caption.id}`);
      }
    }
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  for (const pin of pins.values()) for (const alias of pin.aliases) pinnedAliases.add(alias);
  reconcilePinnedNames(fixed, pins.values());
} catch (error) { if (error.code !== 'ENOENT') throw error; }
for (const row of fixed.values()) {
  if (pinnedAliases.has(row.text)) continue;
  const terms = Object.fromEntries(Object.entries(glossary).filter(([term]) => mentionsTerm(row.text, term)));
  if (!hasCanonicalNameCounts(row.text, row.translation, terms)) {
    throw new Error(`inconsistent fixed terminology in ${row.text}`);
  }
}
await writeFile(join(data, 'simple', 'zh-Hant', 'zzzz-local-canonical.csv'), stringify([...fixed.values()], { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
console.log(JSON.stringify({ output, csvRows, reviewed: reviewed.length, corrections: corrections.length, community: community.length, workbookRows, rules }));
