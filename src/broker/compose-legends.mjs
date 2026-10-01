import { readFile, writeFile } from 'node:fs/promises';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import { composeCaption, indexPinnedFigures } from './legends-captions.mjs';
import { validateTranslation } from './safety.mjs';

const limitArg = process.argv[2];
if (limitArg && (!Number.isInteger(Number(limitArg)) || Number(limitArg) < 1)) {
  throw new Error('Usage: node compose-legends.mjs [max-new-captions]');
}
const limit = limitArg ? Number(limitArg) : Infinity;
const data = new URL('./data/', import.meta.url);
const output = new URL('composed-legends.csv', data);
const registry = JSON.parse(await readFile(new URL('world-names.json', data), 'utf8'));
const raceMap = JSON.parse(await readFile(new URL('race-map.json', data), 'utf8'));
const races = Object.fromEntries(Object.values(raceMap.races).map(row => [row.source, row.translation]));
const entities = new Map(registry.entities.map(row => [row.id, row]));
const captions = new Map();
for (const line of (await readFile(new URL('captured-legends.jsonl', data), 'utf8')).split('\n').filter(Boolean)) {
  const caption = JSON.parse(line);
  if (caption.world !== registry.world) throw new Error('captured Legends world changed');
  if (captions.has(caption.id) && captions.get(caption.id).text !== caption.text) {
    throw new Error(`conflicting caption for figure:${caption.id}`);
  }
  captions.set(caption.id, caption);
}
const completed = new Map();
try {
  for (const row of parse(await readFile(output, 'utf8'), { columns: true, bom: true, skip_empty_lines: true })) {
    completed.set(row.text, { text: row.text, translation: validateTranslation(row.text, row.translation), tags: '' });
  }
} catch (error) { if (error.code !== 'ENOENT') throw error; }

async function pins() {
  return indexPinnedFigures(await readFile(new URL('translations.jsonl', data), 'utf8'),
    registry.world, registry.entities);
}
let pinned = await pins();
let attempted = 0, failed = 0;
for (const caption of captions.values()) {
  const entity = entities.get(`figure:${caption.id}`);
  if (!entity) throw new Error(`missing figure:${caption.id}`);
  let canonical = pinned.get(entity.id);
  if (canonical && completed.get(caption.text)?.translation === composeCaption(caption, entity, canonical, races)) continue;
  if (attempted >= limit) break;
  attempted++;
  try {
    if (!canonical) {
      const response = await fetch('http://127.0.0.1:19753/v2/pin-figure', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: entity.id }), signal: AbortSignal.timeout(90000),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const result = await response.json();
      pinned = await pins();
      canonical = pinned.get(entity.id);
      if (!canonical || canonical !== result.translation) throw new Error('figure name was not pinned');
    }
    const translation = composeCaption(caption, entity, canonical, races);
    completed.set(caption.text, { text: caption.text, translation, tags: '' });
    await writeFile(output, stringify([...completed.values()], {
      header: true, columns: ['text', 'translation', 'tags'],
    }), 'utf8');
    if (attempted % 25 === 0) console.log(JSON.stringify({ attempted, completed: completed.size, failed }));
  } catch (error) {
    failed++;
    console.log(JSON.stringify({ id: caption.id, error: String(error.message) }));
  }
}
console.log(JSON.stringify({ sources: captions.size, completed: completed.size, attempted, failed }));
if (failed) process.exitCode = 1;
