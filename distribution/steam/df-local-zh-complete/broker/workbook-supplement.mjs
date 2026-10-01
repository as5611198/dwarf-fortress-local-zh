import { convertCsv } from './data.mjs';
import { parse } from 'csv-parse/sync';
import { stringify } from 'csv-stringify/sync';
import { validateTranslation, hasCanonicalNameCounts, mentionsTerm, safeReason } from './safety.mjs';

export const normalizeSource = text => text.replace(/\s+/g, ' ').trim().toLowerCase();

export function planSupplement(candidates, existing, glossary = {}, corrections = {}, { language = 'zh-Hant', protectedKeys = new Set() } = {}) {
  if (!['zh-Hant', 'zh-Hans'].includes(language)) throw new Error('Unsupported workbook language');
  const converted = language === 'zh-Hans' ? candidates : parse(convertCsv(stringify(candidates.map(row => ({
    text: row.text, translation: row.translation, tags: '',
  })), { header: true })), { columns: true });
  const known = existing instanceof Map ? new Set([...existing].filter(([,values]) =>
    [values].flat().some(value => typeof value==='string' && /\p{Script=Han}/u.test(value))).map(([key])=>key)) : existing;
  const decisions = [];
  const groups = new Map();
  candidates.forEach((candidate, index) => {
    const correction = corrections[candidate.text];
    const reviewed = typeof correction === 'string' ? (language === 'zh-Hant' ? correction : undefined) : correction?.[language];
    const row = { ...candidate, language, targetTranslation: reviewed ?? converted[index].translation,
      corrected: reviewed !== undefined };
    let reason;
    if (known.has(row.text) || protectedKeys.has(row.text)) reason = 'existing key retained';
    else if (correction?.exclude) reason = correction.exclude;
    else if (/[{}\[\]*]/.test(row.text) || /\([^)]*\/[^)]*\)/.test(row.text)) reason = 'dynamic template or alternatives';
    else if (row.text==='xth') reason = 'ordinal template';
    else if (/^region\d+$/i.test(row.text)) reason = 'save identifier';
    else if (/Paraceratheriun|\bfroml\b|\bUisit\b|\bSerue\b|Horizontal axles the transfer|À table|fight\. and manage/.test(row.text)) reason = 'source transcription error';
    else if (/\b(?:man|men)\b/.test(row.text) && /[女雌]/.test(row.targetTranslation) ||
             /\b(?:woman|women)\b/.test(row.text) && /[男雄]/.test(row.targetTranslation)) reason = 'gender mismatch';
    else {
      try {
        row.targetTranslation = validateTranslation(row.text, row.targetTranslation);
        const terms = Object.fromEntries(Object.entries(glossary).filter(([term]) => mentionsTerm(row.text, term)));
        if (!hasCanonicalNameCounts(row.text, row.targetTranslation, terms)) reason = 'pinned terminology mismatch';
      } catch (error) { reason = safeReason(error); }
    }
    if (reason) decisions.push({ ...row, status: 'retained', reason });
    else {
      const key = normalizeSource(row.text);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(row);
    }
  });
  const rows = [];
  for (const group of groups.values()) {
    const variants = new Set(group.map(row => row.targetTranslation));
    const semanticSheets=['界面UI元素','各种UI文本','名词','拼接-名词','动词','拼接-形容词','形容词'];
    const meanings=new Set(group.map(row=>row.sheet));
    const ranked=meanings.size>1 ? group.filter(row=>semanticSheets.includes(row.sheet))
      .sort((a,b)=>semanticSheets.indexOf(a.sheet)-semanticSheets.indexOf(b.sheet)) : [];
    const selected=ranked[0];
    if (variants.size > 1 && !selected) {
      decisions.push(...group.map(row => ({ ...row, status: 'retained', reason: 'conflicting translations' })));
      continue;
    }
    const sources = new Set();
    for (const row of group) {
      if (variants.size>1 && row.targetTranslation!==selected.targetTranslation) {
        decisions.push({...row,status:'retained',reason:'contextual meaning retained'});
        continue;
      }
      if (sources.has(row.text)) {
        decisions.push({ ...row, status: 'retained', reason: 'duplicate row' });
      } else {
        sources.add(row.text);
        rows.push({ text: row.text, translation: row.targetTranslation, tags: '' });
        decisions.push({ ...row, status: 'imported', reason: 'fixed supplement' });
      }
    }
  }
  rows.sort((a, b) => a.text.localeCompare(b.text, 'en'));
  return { rows, decisions };
}
