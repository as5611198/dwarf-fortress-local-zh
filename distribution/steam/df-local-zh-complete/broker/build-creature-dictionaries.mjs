import { readFile, writeFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import TOML from '@iarna/toml';
import { stringify } from 'csv-stringify/sync';
import { parse } from 'csv-parse/sync';
import { simplify } from './language-data.mjs';

// Creature singular/plural groups are complete labels, unlike grammatical roots.
export async function buildCreatureDictionaries(packageRoot) {
  const broker = join(packageRoot, 'broker');
  const races = JSON.parse(await readFile(join(broker, 'data/race-map.json'), 'utf8'));
  const configPath = join(broker, 'config.json');
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const counts = {};
  const keys = {};
  const fixtures = {};
  for (const language of ['zh-Hant', 'zh-Hans']) {
    const rules = TOML.parse(await readFile(join(packageRoot,
      `dfi18n-data/rulesets/${language}/creatures/name.toml`), 'utf8'));
    const rows = new Map();
    const add = (text, translation) => {
      if (typeof translation !== 'string' || /[{}]/.test(text + translation)) return;
      translation=translation.trim();
      for (const key of new Set([text, text.toLowerCase(), text[0].toUpperCase() + text.slice(1),
        text.replace(/\b[a-z]/g,letter=>letter.toUpperCase())])) {
        rows.set(key, { text: key, translation, tags: '[CREATURE:1][REVIEWED:1]' });
      }
    };
    for (const group of rules.rulesets ?? []) {
      if (!['singular', 'plural'].includes(group.name)) continue;
      for (const [source, translation] of Object.entries(group.rules ?? {})) add(source, translation);
    }
    // Reviewed race labels override rules and cover world-specific creature IDs.
    for (const { source, translation } of Object.values(races.races)) {
      add(source, language === 'zh-Hans' ? simplify(translation) : translation);
    }
    // Keep validated workbook spellings (including gender) for exact source keys.
    const workbook = parse(await readFile(join(broker, `data/community-workbook-${language}.csv`), 'utf8'),
      { columns: true });
    for (const row of workbook) if (rows.has(row.text) && !/ (?:man|men)$/i.test(row.text))
      rows.set(row.text, {...row,translation:row.translation.trim(),tags:'[CREATURE:1][REVIEWED:1]'});
    // Explicit terminology corrections beat imported workbook/model spellings.
    for(const [source,translation] of [['dragon','巨龍'],['dragons','巨龍']])
      add(source,language==='zh-Hans'?simplify(translation):translation);
    for(const [text,row] of rows) {
      if(/ man$| men$/i.test(text) && /\s*男人/.test(row.translation))
        row.translation=row.translation.replace(/\s*男人/g,'人');
    }
    const csv = stringify([...rows.values()].sort((a, b) => a.text.localeCompare(b.text, 'en')),
      { header: true, columns: ['text', 'translation', 'tags'] });
    const file = `data/creature-names-${language}.csv`;
    await writeFile(join(broker, file), csv);
    await writeFile(join(packageRoot, `dfi18n-data/simple/${language}/zzzzzzz-creature-names.csv`), csv);
    await unlink(join(packageRoot, `dfi18n-data/simple/${language}/zzzzz-creature-names.csv`)).catch(error => {
      if (error.code !== 'ENOENT') throw error;
    });
    config.staticDictionariesByLanguage[language] = [...new Set([
      ...(config.staticDictionariesByLanguage[language] ?? []), file])];
    config.literalDictionaries = [...new Set([...(config.literalDictionaries ?? []), file])];
    counts[language] = rows.size;
    fixtures[language] = [...rows.values()];
    for (const row of rows.values()) {
      keys[row.text] ??= {};
      keys[row.text][language] = row.translation;
    }
  }
  await writeFile(configPath, JSON.stringify(config, null, 2) + '\n');
  await writeFile(join(broker, 'data/creature-name-keys.json'), JSON.stringify(keys) + '\n');
  await writeFile(join(packageRoot, 'self-tests/creature-dictionaries.json'), JSON.stringify(fixtures) + '\n');
  return counts;
}
