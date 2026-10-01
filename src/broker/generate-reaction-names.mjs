import { readFile, writeFile } from 'node:fs/promises';
import { parse as parseCsv } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import TOML from '@iarna/toml';
import { composeReactionName } from './reaction-names.mjs';
import { validateTranslation } from './safety.mjs';

const [inventoryPath, plantRulesPath, termsPath, outputPath, csvPath] = process.argv.slice(2);
if (!inventoryPath || !plantRulesPath || !termsPath || !outputPath || !csvPath) {
  throw new Error('Usage: node generate-reaction-names.mjs <inventory.jsonl> <plants/name.toml> <reaction-plant-terms.csv> <candidates.jsonl> <translations.csv>');
}
const document = TOML.parse(await readFile(plantRulesPath, 'utf8'));
const plants = new Map(Object.entries(document.rulesets.find(row => row.name === 'singular')?.rules ?? {}));
const extraPlants = parseCsv(await readFile(termsPath, 'utf8'), { columns: true, bom: true });
for (const row of extraPlants) plants.set(row.text, validateTranslation(row.text, row.translation));
const inventory = (await readFile(inventoryPath, 'utf8')).split('\n').filter(Boolean).map(line => JSON.parse(line));
const sources = [...new Set(inventory.filter(row => row.token === 'NAME' &&
  row.mod === 'vanilla_reactions' && /^make .+ dye$/.test(row.text)).map(row => row.text))];
const candidates = [];
const unresolved = [];
for (const text of sources) {
  const composed = composeReactionName(text, plants);
  if (!composed) { unresolved.push(text); continue; }
  candidates.push({ text, translation: validateTranslation(text, composed.translation),
    basis: composed.basis, pattern: composed.pattern });
}
await writeFile(outputPath, candidates.map(row => JSON.stringify(row)).join('\n') + '\n', 'utf8');
await writeFile(csvPath, stringify(candidates.map(({ text, translation }) => ({ text, translation, tags: '' })),
  { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
console.log(JSON.stringify({ sources: sources.length, candidates: candidates.length, unresolved }, null, 2));
