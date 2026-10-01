import { readFile } from 'node:fs/promises';
import { mentionsTerm } from './safety.mjs';

const compact = value => value.toLowerCase().replace(/[\s-]+/g, '');
const baseName = value => value.replace(/^giant /, '').replace(/ (?:man|woman|men|women)$/, '');

export function buildDescriptionGlossary(rows, races) {
  const canonical = new Map();
  for (const [id, race] of Object.entries(races)) {
    if (/^GIANT_|_(?:MAN|WOMAN)$/.test(id)) continue;
    if (typeof race.source === 'string' && typeof race.translation === 'string') {
      canonical.set(compact(race.source), race.translation);
    }
  }

  const descriptions = new Map();
  for (const row of rows) {
    if (typeof row.text !== 'string') continue;
    const terms = descriptions.get(row.text) ?? {};
    descriptions.set(row.text, terms);
    const race = races[row.creatureId];
    if (!race) continue;
    const species = baseName(race.source);
    const translation = canonical.get(compact(species));
    if (!translation) continue;
    for (const alias of new Set([species, species.replace(/[\s-]+/g, '')])) {
      if (mentionsTerm(row.text, alias)) terms[alias] = translation;
    }
  }
  return descriptions;
}

export async function loadDescriptionGlossary(inventoryPath, raceMapPath) {
  const [inventory, raceMap] = await Promise.all([
    readFile(inventoryPath, 'utf8'), readFile(raceMapPath, 'utf8'),
  ]);
  const rows = inventory.split('\n').filter(Boolean).map(JSON.parse);
  return buildDescriptionGlossary(rows, JSON.parse(raceMap).races);
}
