import { createHash } from 'node:crypto';

export const POLICY_VERSION = 'df-zh-3';
export const tokenPattern = /\{\{[^{}\r\n]*\}\}|\{[^{}\r\n]+\}|\[[^\[\]\r\n]+\]|<\/?[A-Za-z][^>\r\n]*>|%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?[a-zA-Z]/g;
const runtimeAlias = /(?:^|[^A-Za-z0-9_])(?:L[A-Za-z0-9]{3}_+|L[A-Za-z0-9]{6}_+|L(?=[A-Za-z0-9]{0,5}\d)[A-Za-z0-9]{6}|P_____|DFLIVE_[0-9a-f]{64})(?=$|[^A-Za-z0-9_])/;
export const hasRuntimeAlias = source => runtimeAlias.test(source);

export function safeReason(error) {
  const message = String(error?.message);
  return /^(residual English|misread English article|format token mismatch|number mismatch|empty translation|missing Chinese|mandatory glossary mismatch|structured or fenced output|excessive translation length|invalid source|incomplete display fragment|translation queue full|no translation provider configured|provider HTTP \d+|provider response invalid|provider timeout|provider connection failed|provider temporarily unavailable)$/.test(message) ? message : 'translation failed';
}
const sorted = values => [...values].sort();
const matches = (value, pattern) => value.match(pattern) ?? [];
// Literal product names, hotkeys and documented commands are not untranslated prose.
const documentedIdentifier=/\b(?:gui\/(?:overlay|launcher|control-panel)|quickstart-guide|DFHack|Windows|ESC|Armok|run|1B|DF|MS)\b/gi;
function proseWithoutIdentifiers(source,output) {
  const available=new Map();
  for(const token of matches(source,documentedIdentifier)) {
    const key=token.toLowerCase();
    if(['run','armok'].includes(key) && !new RegExp('["\'`]'+key+'["\'`]','i').test(source)) continue;
    available.set(key,(available.get(key) ?? 0)+1);
  }
  return output.replace(documentedIdentifier,token=>{
    const key=token.toLowerCase(),count=available.get(key) ?? 0;
    if(!count) return token;
    available.set(key,count-1);return '';
  });
}

function countCompleteTerms(text, term) {
  let count = 0;
  let index = text.indexOf(term);
  while (index !== -1) {
    const before = index ? text[index - 1] : '';
    const after = text[index + term.length] ?? '';
    if (!/[\p{L}\p{N}]/u.test(before) && !/[\p{L}\p{N}]/u.test(after)) count++;
    index = text.indexOf(term, index + term.length);
  }
  return count;
}

export function mentionsTerm(text, term) {
  return countCompleteTerms(text, term) > 0;
}

export function cacheKey(source, language, version = POLICY_VERSION) {
  return createHash('sha256').update(JSON.stringify([version, language, source])).digest('hex');
}

export function hasCanonicalNameCounts(source, translation, glossary) {
  const expected = new Map();
  for (const [alias, value] of Object.entries(glossary)) {
    expected.set(value, (expected.get(value) ?? 0) + countCompleteTerms(source, alias));
  }
  return [...expected].every(([value, count]) => translation.split(value).length - 1 >= count);
}

export function validateTranslation(source, output) {
  if (typeof output !== 'string' || !output.trim()) throw new Error('empty translation');
  const value = output.trim();
  if (/^An [a-z]/.test(source) && /^安/.test(value)) throw new Error('misread English article');
  if (/```/.test(value) || (/^[\[{]/.test(value) && !new RegExp(`^(?:${tokenPattern.source})`).test(value))) {
    throw new Error('structured or fenced output');
  }
  const sourceTokens = sorted(matches(source, tokenPattern));
  const outputTokens = sorted(matches(value, tokenPattern));
  if (JSON.stringify(sourceTokens) !== JSON.stringify(outputTokens)) throw new Error('format token mismatch');
  const plainSource = source.replace(tokenPattern, '');
  const plainOutput = value.replace(tokenPattern, '');
  if (/\p{Script=Latin}/u.test(proseWithoutIdentifiers(plainSource,plainOutput))) throw new Error('residual English');
  if (JSON.stringify(sorted(matches(plainSource, /\d+(?:[.,]\d+)*/g))) !==
      JSON.stringify(sorted(matches(plainOutput, /\d+(?:[.,]\d+)*/g)))) throw new Error('number mismatch');
  if (!/\p{Script=Han}/u.test(plainOutput) && /\p{L}/u.test(plainSource)) throw new Error('missing Chinese');
  if (value.length > Math.max(200, source.length * 4)) throw new Error('excessive translation length');
  return value;
}
