import { readFile, writeFile } from 'node:fs/promises';
import TOML from '@iarna/toml';
import { validateTranslation } from './safety.mjs';

const [sourcesPath, rulesPath, outputPath] = process.argv.slice(2);
if (!sourcesPath || !rulesPath || !outputPath) {
  throw new Error('Usage: node build-race-map.mjs <race-sources.json> <creatures/name.toml> <race-map.json>');
}

const sources = JSON.parse(await readFile(sourcesPath, 'utf8'));
const data = TOML.parse(await readFile(rulesPath, 'utf8'));
const singular = data.rulesets.find(row => row.name === 'singular')?.rules;
if (!Array.isArray(sources) || !singular) throw new Error('Invalid race sources or creature rules');
const rules = new Map(Object.entries(singular).map(([source, translation]) =>
  [source.toLocaleLowerCase(), translation]));
const overrides = {
  goblin: '哥布林',
  kobold: '狗頭人',
  'forgotten beast': '遺忘巨獸',
  oestocephalus: '歐斯托頭螈',
  'haunt of flame': '火焰幽魂',
  'moon horror': '月之恐獸',
};
const resolved = new Map();
const races = {};
let fromRules = 0;
let fromProvider = 0;

for (const { id, source } of sources) {
  if (typeof id !== 'string' || typeof source !== 'string' || !source) {
    throw new Error('Invalid race source row');
  }
  let translation = resolved.get(source);
  if (!translation) {
    const candidate = overrides[source] ?? rules.get(source.toLocaleLowerCase());
    if (candidate && !/[A-Za-z]/.test(candidate)) {
      translation = validateTranslation(source, candidate);
      fromRules++;
    } else {
      const response = await fetch('http://127.0.0.1:19753/v2/translate', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: source }), signal: AbortSignal.timeout(90000),
      });
      if (!response.ok) throw new Error(`Cannot translate ${source}: HTTP ${response.status}`);
      translation = validateTranslation(source, (await response.json()).translation);
      fromProvider++;
      console.log(JSON.stringify({ source, translation }));
    }
    resolved.set(source, translation);
  }
  races[id] = { source, translation };
}

if (Object.keys(races).length !== sources.length) throw new Error('Duplicate race IDs');
await writeFile(outputPath, JSON.stringify({ schemaVersion: 1, races }), 'utf8');
console.log(JSON.stringify({ total: sources.length, unique: resolved.size, fromRules, fromProvider }));
