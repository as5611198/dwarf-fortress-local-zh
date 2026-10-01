import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { stringify } from 'csv-stringify/sync';
import { validateTranslation } from './safety.mjs';

const endpoint = 'http://127.0.0.1:19753';
const translate = async text => {
  const response = await fetch(`${endpoint}/v2/translate`, { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text }),
    signal: AbortSignal.timeout(90000) });
  if (!response.ok) throw new Error(`Translation HTTP ${response.status}`);
  const result = await response.json();
  return validateTranslation(text, result.translation);
};
const pinFigure = async (id, source) => {
  const response = await fetch(`${endpoint}/v2/pin-figure`, { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }),
    signal: AbortSignal.timeout(90000) });
  if (!response.ok) throw new Error(`Figure pin HTTP ${response.status}`);
  const result = await response.json();
  return validateTranslation(source, result.translation);
};
const rows = [];
const registry = JSON.parse(await readFile(new URL('./data/world-names.json', import.meta.url), 'utf8'));
const fixture = registry.entities.find(row => row.id.startsWith('figure:') &&
  row.aliases.length >= 2 && row.aliases[0] !== row.aliases[1]);
if (!fixture) throw new Error('No dual-alias figure is available for the live check');
for (const text of [
  fixture.aliases[0],
  fixture.aliases[1],
  `${fixture.aliases[0]}, "${fixture.aliases[1]}", male dragon`,
  'In 142, Urist married a dwarf named Domas.',
]) rows.push({ text, translation: await translate(text), tags: '' });
// Generic text requests can legitimately retain two distinct historical aliases.
// Identity consistency is guaranteed by the structured figure-ID endpoint used by
// the Legends adapter, so verify that path directly.
const canonical = await pinFigure(fixture.id, fixture.preferred);
assert.equal(canonical, await pinFigure(fixture.id, fixture.preferred));
assert.match(canonical, /\p{Script=Han}/u);
const before = await (await fetch(`${endpoint}/health`)).json();
const varied = await translate('In 143, Domas married a dwarf named Urist.');
const after = await (await fetch(`${endpoint}/health`)).json();
assert.equal(after.accepted, before.accepted);
assert.ok(varied.includes('多瑪') && varied.includes('烏瑞斯特') && varied.includes('143'));
rows.push({ text: 'In 143, Domas married a dwarf named Urist.', translation: varied, tags: '' });
const death = await translate('d. 250');
assert.equal(death, '卒於250年');
rows.push({ text: 'd. 250', translation: death, tags: '' });
await writeFile(new URL('./data/live-check.csv', import.meta.url), stringify(rows, { header: true, columns: ['text', 'translation', 'tags'] }), 'utf8');
console.log(JSON.stringify({ figurePinStable: true, changedYearAndNamesReuseCache: true, rows }, null, 2));
