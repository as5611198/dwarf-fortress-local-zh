import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import TOML from '@iarna/toml';
import * as OpenCC from 'opencc-js';
import { validateTranslation } from './safety.mjs';

const traditional = OpenCC.Converter({ from: 'cn', to: 'twp' });
const protectedPattern = /\{\{[^{}]*\}\}|\{[^{}]+\}|\[[^\[\]]+\]|<[^>]+>/g;

function convertValue(value) {
  const tokens = [];
  const masked = value.replace(protectedPattern, token => { tokens.push(token); return `\u0001${tokens.length - 1}\u0002`; });
  return traditional(masked).replace(/\u0001(\d+)\u0002/g, (_, index) => tokens[Number(index)]);
}

export function convertCsv(content) {
  // Workshop Chinese data 0.0.15 contains this single malformed CSV field.
  content = content.replace(/^"Add a "Make bed" task",/m, '"Add a ""Make bed"" task",');
  const rows = parse(content, { columns: true, bom: true, skip_empty_lines: true });
  return stringify(rows.map(row => ({ ...row, translation: convertValue(row.translation) })), { header: true, columns: ['text', 'translation', 'tags'] });
}

function convertTree(value) {
  if (typeof value === 'string') return convertValue(value);
  if (Array.isArray(value)) return value.map(convertTree);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, convertTree(child)]));
  return value;
}

export function convertRules(content) {
  return TOML.stringify(convertTree(TOML.parse(content)));
}

export function mergeTraditionalRuleOverride(converted, local) {
  const document = TOML.parse(converted);
  const override = TOML.parse(local);
  if (document.base !== override.base) throw new Error('rule override base mismatch');
  const byName = new Map((document.rulesets ?? []).map(row => [row.name ?? '', row]));
  for (const incoming of override.rulesets ?? []) {
    const name = incoming.name ?? '';
    const current = byName.get(name);
    if (!current) {
      document.rulesets ??= [];
      document.rulesets.push(incoming);
      byName.set(name, incoming);
      continue;
    }
    Object.assign(current, Object.fromEntries(Object.entries(incoming)
      .filter(([key]) => key !== 'rules')));
    current.rules = { ...current.rules, ...incoming.rules };
  }
  return TOML.stringify(document);
}

export function canonicalizeCreatureRules(content) {
  const parsed = TOML.parse(content);
  const terms = {
    singular: { goblin: '哥布林', kobold: '狗頭人' },
    plural: { goblins: '哥布林', kobolds: '狗頭人' },
  };
  for (const ruleset of parsed.rulesets ?? []) {
    for (const [source, translation] of Object.entries(terms[ruleset.name] ?? {})) {
      if (Object.hasOwn(ruleset.rules ?? {}, source)) ruleset.rules[source] = translation;
    }
  }
  return TOML.stringify(parsed);
}

export function reconcilePinnedNames(rows, pins) {
  for (const pin of pins) {
    const previous = [...new Set([...pin.aliases.map(alias => rows.get(alias)?.translation), ...(pin.legacy ?? [])].filter(Boolean))];
    for (const row of rows.values()) {
      if (!pin.aliases.some(alias => row.text.includes(alias))) continue;
      let translation = row.translation;
      for (const old of previous) {
        if (old !== pin.translation) translation = translation.replaceAll(old, pin.translation);
      }
      row.translation = validateTranslation(row.text, translation);
    }
    for (const alias of pin.aliases) rows.set(alias,
      { text: alias, translation: validateTranslation(alias, pin.translation), tags: rows.get(alias)?.tags ?? '' });
  }
}

export function scanRawText(content, mod, file) {
  const output = [];
  const displayTokens = new Set(['NAME', 'ADJ', 'DESCRIPTION', 'DISPLAY_NAME', 'ITEM_NAME', 'ALL_NAMES', 'STATE_NAME', 'STATE_ADJ']);
  let creatureId;
  for (const match of content.matchAll(/\[([^\[\]\r\n]+)\]/g)) {
    const [token, ...values] = match[1].split(':');
    if (token === 'OBJECT') { creatureId = undefined; continue; }
    if (token === 'CREATURE') { creatureId = values[0]; continue; }
    if (!displayTokens.has(token)) continue;
    if (token === 'STATE_NAME' || token === 'STATE_ADJ') values.shift();
    for (const text of values) {
      if (!/\p{Script=Latin}/u.test(text) || /^[A-Z][A-Z_\d]+$/.test(text)) continue;
      output.push({ text, mod, file, token, ...(creatureId ? { creatureId } : {}) });
    }
  }
  return output;
}
