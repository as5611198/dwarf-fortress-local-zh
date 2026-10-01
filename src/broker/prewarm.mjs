import { readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import { cacheKey, hasCanonicalNameCounts, mentionsTerm, POLICY_VERSION, validateTranslation } from './safety.mjs';
import { loadDescriptionGlossary } from './description-terms.mjs';

const [input, output, limitArg] = process.argv.slice(2);
if (!input || !output || (limitArg && (!Number.isInteger(Number(limitArg)) || Number(limitArg) < 1))) {
  throw new Error('Usage: node prewarm.mjs <source.jsonl|csv> <supplement.csv> [max-new-sources]');
}
const limit = limitArg ? Number(limitArg) : Infinity;
const raw = await readFile(input, 'utf8');
const items = input.endsWith('.csv') ? parse(raw, { columns: true, bom: true }) : raw.split('\n').filter(Boolean).flatMap(line => {
  try { return [JSON.parse(line)]; } catch { return []; }
});
const sources = [...new Set(items.map(row => row.text ?? row.source).filter(source =>
  typeof source === 'string' && source && !source.includes('{{DF')) )];
const completed = new Map();
try {
  for (const row of parse(await readFile(output, 'utf8'), { columns: true })) {
    try { completed.set(row.text, { ...row, translation: validateTranslation(row.text, row.translation) }); }
    catch { console.log(JSON.stringify({ text: row.text, status: 'refreshing invalid translation' })); }
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }
const fixedGlossary = JSON.parse(await readFile(new URL('./glossary.json', import.meta.url), 'utf8'));
const descriptionGlossary = await loadDescriptionGlossary(
  new URL('./data/descriptions.jsonl', import.meta.url),
  new URL('./data/race-map.json', import.meta.url));
const requiredPins = new Map(sources.map(source => [source, Object.fromEntries(
  Object.entries(fixedGlossary).filter(([term]) => mentionsTerm(source, term)))]));
for (const [source, terms] of descriptionGlossary) {
  if (requiredPins.has(source)) Object.assign(requiredPins.get(source), terms);
}
if (input.endsWith('.jsonl') && items.some(row => Number.isInteger(row.id))) {
  try {
    const directory = dirname(input);
    const registry = JSON.parse(await readFile(join(directory, 'world-names.json'), 'utf8'));
    const entities = new Map(registry.entities.map(row => [row.id, row]));
    const journal = await readFile(join(directory, 'translations.jsonl'), 'utf8');
    const pins = new Map();
    for (const line of journal.split('\n').filter(Boolean)) {
      let row;
      try { row = JSON.parse(line); } catch { continue; }
      if (row.kind !== 'name' || row.policy !== POLICY_VERSION || row.language !== 'zh-Hant' ||
          row.key !== cacheKey(row.source, row.language, POLICY_VERSION + ':name')) continue;
      let world, id, preferred;
      try { [world, id, preferred] = JSON.parse(row.source); } catch { continue; }
      if (world === registry.world && entities.get(id)?.preferred === preferred) pins.set(id, row.translation);
    }
    for (const item of items) {
      if (item.world !== registry.world || !Number.isInteger(item.id)) continue;
      const entity = entities.get('figure:' + item.id);
      const canonical = pins.get('figure:' + item.id);
      if (!entity || !canonical) continue;
      const glossary = Object.fromEntries(entity.aliases.map(alias => [alias, canonical]));
      requiredPins.set(item.text, { ...requiredPins.get(item.text), ...glossary });
    }
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
for (const [source, glossary] of requiredPins) {
  const cached = completed.get(source);
  if (cached && !hasCanonicalNameCounts(source, cached.translation, glossary)) {
    completed.delete(source);
    console.log(JSON.stringify({ text: source, status: 'refreshing inconsistent translation' }));
  }
}
let failed = 0;
let attempted = 0;
for (const source of sources) {
  if (completed.has(source)) continue;
  if (attempted >= limit) break;
  attempted++;
  try {
    const response = await fetch('http://127.0.0.1:19753/v2/translate', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: source }), signal: AbortSignal.timeout(90000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const { translation } = await response.json();
    const accepted = validateTranslation(source, translation);
    if (!hasCanonicalNameCounts(source, accepted, requiredPins.get(source))) {
      throw new Error('inconsistent fixed terminology or name');
    }
    completed.set(source, { text: source, translation: accepted, tags: '' });
    await writeFile(output, stringify([...completed.values()], { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
    console.log(JSON.stringify({ text: source, translation }));
  } catch { failed++; console.log(JSON.stringify({ text: source, status: 'unresolved' })); }
}
console.log(JSON.stringify({ sources: sources.length, completed: completed.size, attempted, failed }));
if (failed) process.exitCode = 1;
