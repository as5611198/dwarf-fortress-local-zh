import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parse as parseCsv } from 'csv-parse/sync';
import TOML from '@iarna/toml';

const [inventoryPath, dataPath, outputPath, tokenFilter, outputStatus = 'unmapped'] = process.argv.slice(2);
if (!inventoryPath || !dataPath) {
  throw new Error('Usage: node audit-raw-coverage.mjs <inventory.jsonl> <dfi18n-data> [output.jsonl] [token] [status]');
}
if (!['csv', 'rules', 'caseVariant', 'unmapped'].includes(outputStatus)) {
  throw new Error(`invalid output status: ${outputStatus}`);
}

async function files(path) {
  const result = [];
  for (const item of await readdir(path, { withFileTypes: true })) {
    const full = join(path, item.name);
    if (item.isDirectory()) result.push(...await files(full));
    else if (item.isFile()) result.push(full);
  }
  return result;
}

const csvKeys = new Set();
const ruleKeys = new Set();
for (const file of await files(dataPath)) {
  if (file.endsWith('.csv') && file.includes(`${join('simple', 'zh-Hant')}`)) {
    for (const row of parseCsv(await readFile(file, 'utf8'), { columns: true, bom: true })) {
      if (row.text) csvKeys.add(row.text);
    }
  } else if (file.endsWith('.toml') && file.includes(`${join('rulesets', 'zh-Hant')}`)) {
    const document = TOML.parse(await readFile(file, 'utf8'));
    for (const ruleset of document.rulesets ?? []) {
      for (const key of Object.keys(ruleset.rules ?? {})) {
        if (!/[{}]/.test(key)) ruleKeys.add(key);
      }
    }
  }
}

const inventory = (await readFile(inventoryPath, 'utf8')).split('\n')
  .filter(Boolean).map(line => JSON.parse(line));
const unique = new Map();
for (const row of inventory) {
  const prior = unique.get(row.text);
  if (prior) {
    if (!prior.tokens.includes(row.token)) prior.tokens.push(row.token);
    if (!prior.mods.includes(row.mod)) prior.mods.push(row.mod);
  } else {
    unique.set(row.text, { text: row.text, tokens: [row.token], mods: [row.mod] });
  }
}

const caseKeys = new Set([...csvKeys, ...ruleKeys].map(key => key.toLowerCase()));
const emptyCounts = () => ({ csv: 0, rules: 0, caseVariant: 0, unmapped: 0 });
const totals = emptyCounts();
const byToken = {};
const selected = [];
for (const row of unique.values()) {
  const status = csvKeys.has(row.text) ? 'csv' : ruleKeys.has(row.text) ? 'rules'
    : caseKeys.has(row.text.toLowerCase()) ? 'caseVariant' : 'unmapped';
  totals[status]++;
  for (const token of row.tokens) {
    const counts = byToken[token] ??= emptyCounts();
    counts[status]++;
  }
  if (status === outputStatus && (!tokenFilter || row.tokens.includes(tokenFilter))) selected.push(row);
}
if (outputPath) {
  await writeFile(outputPath, selected.map(row => JSON.stringify(row)).join('\n') + '\n', 'utf8');
}
console.log(JSON.stringify({ unique: unique.size, totals, byToken,
  outputStatus, outputCount: selected.length, examples: selected.slice(0, 24), output: outputPath ?? null }, null, 2));
