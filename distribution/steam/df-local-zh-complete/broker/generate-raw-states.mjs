import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parse as parseCsv } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import TOML from '@iarna/toml';
import { composeRawState, selectRawStateSources } from './raw-states.mjs';
import { validateTranslation } from './safety.mjs';

const [inventoryPath, dataPath, reviewedPath, termsPath, outputPath, csvPath] = process.argv.slice(2);
if (!inventoryPath || !dataPath || !reviewedPath || !termsPath || !outputPath || !csvPath) {
  throw new Error('Usage: node generate-raw-states.mjs <inventory.jsonl> <dfi18n-data> <reviewed.csv> <raw-state-terms.csv> <candidates.jsonl> <translations.csv>');
}

async function rules(file) {
  const document = TOML.parse(await readFile(file, 'utf8'));
  return new Map(Object.entries(document.rulesets.find(row => row.name === 'singular')?.rules ?? {}));
}
async function ruleKeys(path) {
  const keys = new Set();
  async function scan(directory) {
    for (const item of await readdir(directory, { withFileTypes: true })) {
      const full = join(directory, item.name);
      if (item.isDirectory()) await scan(full);
      else if (item.isFile() && item.name.endsWith('.toml')) {
        const document = TOML.parse(await readFile(full, 'utf8'));
        for (const ruleset of document.rulesets ?? []) {
          for (const key of Object.keys(ruleset.rules ?? {})) keys.add(key);
        }
      }
    }
  }
  await scan(path);
  return keys;
}
const root = join(dataPath, 'rulesets', 'zh-Hant');
const [creatures, plants, existingRules, reviewedRows, termRows] = await Promise.all([
  rules(join(root, 'creatures', 'name.toml')),
  rules(join(root, 'plants', 'name.toml')),
  ruleKeys(root),
  readFile(reviewedPath, 'utf8').then(value => parseCsv(value, { columns: true, bom: true })),
  readFile(termsPath, 'utf8').then(value => parseCsv(value, { columns: true, bom: true })),
]);
const reviewed = new Map([...reviewedRows, ...termRows].map(row => [row.text, row.translation]));
const rows = selectRawStateSources((await readFile(inventoryPath, 'utf8')).split('\n')
  .filter(Boolean).map(line => JSON.parse(line)), existingRules);
const candidates = [];
for (const row of rows) {
  const composed = composeRawState(row.text, { creatures, plants, reviewed });
  if (!composed) continue;
  candidates.push({ text: row.text, translation: validateTranslation(row.text, composed.translation),
    basis: composed.basis, pattern: composed.pattern, mods: row.mods });
}
await writeFile(outputPath, candidates.map(row => JSON.stringify(row)).join('\n') + '\n', 'utf8');
await writeFile(csvPath, stringify(candidates.map(({ text, translation }) => ({ text, translation, tags: '' })),
  { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
const patterns = Object.groupBy(candidates, row => row.pattern);
console.log(JSON.stringify({ stateSources: rows.length, candidates: candidates.length,
  byPattern: Object.fromEntries(Object.entries(patterns).map(([name, matches]) => [name, matches.length])),
  examples: candidates.slice(0, 12), output: outputPath, csv: csvPath }, null, 2));
