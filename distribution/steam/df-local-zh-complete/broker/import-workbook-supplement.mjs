import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import TOML from '@iarna/toml';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import * as OpenCC from 'opencc-js';
import { planSupplement,normalizeSource } from './workbook-supplement.mjs';
import { expandWorkbookAlternatives } from './workbook-expansion.mjs';

const brokerRoot = dirname(fileURLToPath(import.meta.url));
const [workbookPath, installedPath] = process.argv.slice(2);
if (!workbookPath || !installedPath) throw new Error('Usage: import-workbook-supplement.mjs <source.xlsx> <installed-mod> [--apply]');
const auditRoot = resolve(brokerRoot, '../text-audit');
const extracted = JSON.parse(await readFile(join(auditRoot, 'community-workbook-extracted.json'), 'utf8'));
const hash = createHash('sha256').update(await readFile(workbookPath)).digest('hex');
if (hash !== extracted.sha256) throw new Error('Workbook changed; extract and review the new source before importing');
const keysByLanguage = { 'zh-Hant': new Map(), 'zh-Hans': new Map() };
function remember(keys,source,translation) {
  if(typeof translation!=='string' || !/\p{Script=Han}/u.test(translation)) return;
  if(!keys.has(source)) keys.set(source,[]);
  keys.get(source).push(translation);
}
async function collect(directory, keys) {
  let entries;
  try { entries = await readdir(directory, { withFileTypes: true }); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) await collect(path, keys);
    else if (entry.name.endsWith('.csv') && !/community-workbook|creature-names/.test(entry.name)) {
      for (const row of parse(await readFile(path, 'utf8'), { columns: true, bom: true, skip_empty_lines: true })) {
        if (row.text) remember(keys,row.text,row.translation);
      }
    } else if (entry.name.endsWith('.toml')) {
      const document = TOML.parse(await readFile(path, 'utf8'));
      for (const ruleset of document.rulesets ?? []) for (const [key,value] of Object.entries(ruleset.rules ?? {})) remember(keys,key,value);
    }
  }
}
const names = JSON.parse(await readFile(join(installedPath, 'broker/name-dictionary.json'), 'utf8'));
const glossary = JSON.parse(await readFile(join(brokerRoot, 'glossary.json'), 'utf8'));
const corrections = JSON.parse(await readFile(join(brokerRoot, 'data/community-workbook-corrections.json'), 'utf8'));
const toSimplified = OpenCC.Converter({ from: 'tw', to: 'cn' });
for (const row of parse(await readFile(join(brokerRoot, 'data/community-reviewed.csv'), 'utf8'), { columns: true })) {
  corrections[row.text] = { ...corrections[row.text], 'zh-Hans': toSimplified(row.translation) };
}
const simplifiedGlossary = Object.fromEntries(Object.entries(glossary).map(([key, value]) => [key, toSimplified(value)]));
const summary = { source: basename(workbookPath), sha256: hash, candidates: extracted.candidates.length,
  aiCalls: 0, languages: {} };
const plans = {};
for (const [language, keys] of Object.entries(keysByLanguage)) {
  for (const type of ['simple', 'rulesets']) await collect(join(installedPath, 'dfi18n-data', type, language), keys);
  // Phonetic name roots belong to contextual name composition, not literal UI dictionaries.
  const plan = planSupplement(extracted.candidates, keys, language === 'zh-Hans' ? simplifiedGlossary : glossary,
    corrections, { language, protectedKeys: new Set(Object.keys(names)) });
  const normalizedKnown=new Map([...keys.keys()].map(key=>[normalizeSource(key),key]));
  for(const decision of plan.decisions.filter(row=>row.reason==='source transcription error')) {
    const corrected=decision.text.replaceAll('Paraceratheriun','Paraceratherium')
      .replaceAll('fight. and manage','fight, and manage').replaceAll('froml','from')
      .replaceAll('Uisit','Visit').replaceAll('Serue','Serve').replaceAll('À table','A table')
      .replaceAll('Horizontal axles the transfer power on same elevation',
        'Horizontal axles transfer power on the same elevation');
    const known=normalizedKnown.get(normalizeSource(corrected));
    if(known) {decision.correctedSource=known;decision.reason='corrected source already translated';}
  }
  plan.expansions=[];
  for(const decision of plan.decisions.filter(row=>row.reason==='dynamic template or alternatives')) {
    const expanded=expandWorkbookAlternatives({text:decision.text,translation:decision.translation});
    if(!expanded) continue;
    const converted=planSupplement(expanded.map(row=>({...row,sheet:decision.sheet,row:decision.row,
      columns:decision.columns})),new Map(),language==='zh-Hans' ? simplifiedGlossary : glossary,corrections,{language});
    if(converted.rows.length!==expanded.length) continue;
    const bySource=new Map(plan.rows.map(row=>[row.text,row]));
    for(const row of converted.rows) if(!bySource.has(row.text)) {
      plan.rows.push(row);plan.decisions.push({...decision,...row,status:'imported',reason:'expanded alternative',
        originalTemplate:decision.text,targetTranslation:row.translation,
        corrected:language==='zh-Hans' && row.translation!==expanded.find(value=>value.text===row.text).translation});
    }
    plan.expansions.push({template:decision.text,sources:converted.rows.map(row=>row.text)});
    decision.reason='expanded alternatives';
  }
  // Rebuilding against an already installed base must not delete prior imports.
  const previous=parse(await readFile(join(brokerRoot,`data/community-workbook-${language}.csv`),'utf8'),{columns:true});
  const planned=new Set(plan.rows.map(row=>row.text));
  for(const row of previous) {
    if(planned.has(row.text)) continue;
    const decision=plan.decisions.find(candidate=>candidate.text===row.text &&
      candidate.targetTranslation===row.translation) ?? plan.decisions.find(candidate=>candidate.text===row.text);
    if(!decision) throw new Error(`Previous workbook entry lost its provenance: ${row.text}`);
    decision.status='imported';decision.reason='previous supplement retained';
    decision.targetTranslation=row.translation;
    decision.corrected=language==='zh-Hans' && row.translation!==decision.translation.trim();
    plan.rows.push(row);planned.add(row.text);
  }
  plan.rows.sort((a,b)=>a.text.localeCompare(b.text,'en'));
  const counts = {};
  for (const row of plan.decisions) counts[row.reason] = (counts[row.reason] ?? 0) + 1;
  const imported = plan.decisions.filter(row => row.status === 'imported');
  summary.languages[language] = { existingKeys: keys.size, imported: plan.rows.length,
    originalTextReused: imported.filter(row => row.targetTranslation === row.translation).length,
    corrected: imported.filter(row => row.corrected).length, decisions: counts,
    sheets: Object.fromEntries([...new Set(plan.decisions.map(row => row.sheet))].map(sheet =>
      [sheet, imported.filter(row => row.sheet === sheet).length])) };
  plans[language] = plan;
  if (process.argv.includes('--apply')) await writeFile(join(brokerRoot, `data/community-workbook-${language}.csv`),
    stringify(plan.rows, { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
}
if (process.argv.includes('--apply')) await writeFile(join(brokerRoot, 'glossary-zh-Hans.json'),
  JSON.stringify(simplifiedGlossary, null, 2) + '\n');
await writeFile(join(auditRoot, 'community-supplement-import.json'), JSON.stringify({ ...summary, plans }, null, 2) + '\n');
console.log(JSON.stringify(summary, null, 2));
