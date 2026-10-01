import { readFile, writeFile } from 'node:fs/promises';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: node prepare-descriptions.mjs <mod-inventory.jsonl> <descriptions.jsonl>');
const content = await readFile(input, 'utf8');
const seen = new Set();
const rows = [];
for (const line of content.split('\n')) {
  if (!line) continue;
  const row = JSON.parse(line);
  if (row.token !== 'DESCRIPTION' || typeof row.text !== 'string' || seen.has(row.text)) continue;
  seen.add(row.text);
  rows.push(row);
}
await writeFile(output, rows.map(row => JSON.stringify(row)).join('\n') + '\n', 'utf8');
console.log(JSON.stringify({ descriptions: rows.length, mods: [...new Set(rows.map(row => row.mod))], output }));
