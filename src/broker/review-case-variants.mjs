import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join, relative, resolve } from 'node:path';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import TOML from '@iarna/toml';
import { validateTranslation } from './safety.mjs';

const [sourceArg, dataArg, outputArg, csvArg] = process.argv.slice(2);
if (!sourceArg || !dataArg || !outputArg) {
  throw new Error('Usage: node review-case-variants.mjs <case-variants.jsonl> <active-dfi18n-data> <output.jsonl> [unique.csv]');
}
const data = resolve(dataArg);
const candidates = new Map();
const add = (key, translation, file) => {
  if (!key || !translation) return;
  const folded = key.toLowerCase();
  const bucket = candidates.get(folded) ?? [];
  bucket.push({ key, translation, file: relative(data, file) });
  candidates.set(folded, bucket);
};
async function files(directory) {
  const found = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...await files(path));
    else if (entry.isFile()) found.push(path);
  }
  return found;
}
for (const file of await files(join(data, 'simple', 'zh-Hant'))) {
  if (!file.endsWith('.csv')) continue;
  for (const row of parse(await readFile(file, 'utf8'), { columns: true, bom: true })) {
    add(row.text, row.translation, file);
  }
}
for (const file of await files(join(data, 'rulesets', 'zh-Hant'))) {
  if (!file.endsWith('.toml')) continue;
  const document = TOML.parse(await readFile(file, 'utf8'));
  for (const ruleset of document.rulesets ?? []) {
    for (const [key, translation] of Object.entries(ruleset.rules ?? {})) {
      if (!/[{}]/.test(key) && typeof translation === 'string') add(key, translation, file);
    }
  }
}
const sources = (await readFile(sourceArg, 'utf8')).trim().split('\n').map(line => JSON.parse(line));
const summary = { uniqueChinese: 0, ambiguous: 0, noChinese: 0 };
const rows = sources.map(source => {
  const matches = (candidates.get(source.text.toLowerCase()) ?? [])
    .filter(row => row.key !== source.text);
  const chinese = [...new Set(matches.map(row => row.translation)
    .filter(value => /\p{Script=Han}/u.test(value) && !/\p{Script=Latin}/u.test(value)))];
  const status = chinese.length === 0 ? 'noChinese'
    : chinese.length === 1 && matches.every(row => row.translation === chinese[0])
      ? 'uniqueChinese' : 'ambiguous';
  summary[status]++;
  return { ...source, status, candidates: matches };
});
await writeFile(outputArg, rows.map(row => JSON.stringify(row)).join('\n') + '\n', 'utf8');
if (csvArg) {
  const unique = rows.filter(row => row.status === 'uniqueChinese').map(row => ({
    text: row.text,
    translation: validateTranslation(row.text, row.candidates[0].translation),
    tags: '',
  }));
  await writeFile(csvArg, stringify(unique, { header: true,
    columns: ['text', 'translation', 'tags'] }), 'utf8');
}
console.log(JSON.stringify({ sources: sources.length, summary, output: resolve(outputArg),
  ambiguousExamples: rows.filter(row => row.status === 'ambiguous').slice(0, 12).map(row => ({
    text: row.text, translations: [...new Set(row.candidates.map(match => match.translation))],
  })) }, null, 2));
