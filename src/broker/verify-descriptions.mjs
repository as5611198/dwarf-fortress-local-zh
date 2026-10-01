import { readFile } from 'node:fs/promises';
import { parse } from 'csv-parse/sync';
import { loadDescriptionGlossary } from './description-terms.mjs';
import { hasCanonicalNameCounts, validateTranslation } from './safety.mjs';

const [inventoryPath, csvPath, raceMapPath] = process.argv.slice(2);
if (!inventoryPath || !csvPath || !raceMapPath) {
  throw new Error('Usage: node verify-descriptions.mjs <descriptions.jsonl> <translations.csv> <race-map.json>');
}
const sources = new Set((await readFile(inventoryPath, 'utf8')).split('\n')
  .filter(Boolean).map(line => JSON.parse(line).text));
const rows = parse(await readFile(csvPath, 'utf8'), { columns: true, bom: true });
const terms = await loadDescriptionGlossary(inventoryPath, raceMapPath);
const translated = new Set();
let canonical = 0;
for (const row of rows) {
  if (!sources.has(row.text) || translated.has(row.text)) {
    throw new Error(`unexpected or duplicate description: ${row.text}`);
  }
  const value = validateTranslation(row.text, row.translation);
  const required = terms.get(row.text) ?? {};
  if (!hasCanonicalNameCounts(row.text, value, required)) {
    throw new Error(`inconsistent creature name: ${row.text}`);
  }
  if (Object.keys(required).length) canonical++;
  translated.add(row.text);
}
if (translated.size !== sources.size) {
  throw new Error(`missing descriptions: ${sources.size - translated.size}`);
}
console.log(JSON.stringify({ sources: sources.size, translated: translated.size, canonical }));
