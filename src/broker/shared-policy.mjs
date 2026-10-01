import {POLICY_VERSION,validateTranslation,hasRuntimeAlias,tokenPattern} from './safety.mjs';

export const CONTRIBUTION_SCHEMA=1;
export const CONSENSUS_DEVICES=3;
export const CONSENSUS_NETWORKS=3;
export const MAX_BATCH=8;
export const MAX_BODY=32768;
const fields=['schema','rules','language','context','kind','origin','text','translation','model','license'];
const secretOrInstruction=/https?:\/\/|(?:sk-|AIza)[A-Za-z0-9_-]{8,}|PRIVATE KEY|api[ _-]?key|password|ignore (?:all |previous |prior )?instructions|system prompt|(?:named|called)\s+[a-z]|\b(?:save|world|region\d+|artifact):/i;
export function safeSharedSource(text,kind='exact') {
  if(typeof text!=='string' || !text.trim() || text.length>8000 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(text) || hasRuntimeAlias(text) ||
    /DFLIVE_|region\d+|\b(?:figure|entity|artifact):\d+|^(?:World|Folder|Portable Folder):|^In \d+,|\b(?:became the|was struck down by)\b/.test(text) ||
    /^(?:He|She) is not distracted after being unable to (?:be|pray to)$/.test(text) ||
    /\blikes\b/.test(text) && !text.includes('{DWARF_NAME}')) return false;
  const tokens=text.match(tokenPattern) ?? [];
  if(tokens.some(token=>token.startsWith('{') && !/^(?:\{DWARF_NAME\}|\{\{DF[NE]\d+\}\})$/.test(token))) return false;
  if(kind==='exact' && tokens.some(token=>token.startsWith('{'))) return false;
  if(kind==='entity' && !tokens.some(token=>/^\{DWARF_NAME\}|\{\{DFE\d+\}\}$/.test(token))) return false;
  if(kind==='numeric' && !tokens.some(token=>/^\{\{DFN\d+\}\}$/.test(token))) return false;
  return true;
}
// Conservative contribution boundary. Reviewed built-in packages may contain
// additional UI forms; arbitrary model text cannot use that broader boundary.
export function shareableText(text,kind='exact') {
  if(!safeSharedSource(text,kind) || text.length>2000 || secretOrInstruction.test(text))return false;
  const plain=text.replace(tokenPattern,'').trim();
  if(!/^[\x20-\x7e]+$/.test(plain) || /[\\/<>@]|\[[^\]]*\]/.test(plain))return false;
  if(!/^(?:He|She|They|It|His|Her|The|A|An|You)\b/.test(plain) &&
    !(kind==='entity' && /^(?:feels|is|has|needs)\b/.test(plain)) &&
    !/^(?:Health|Wounds|Treatment|Equipment|Skills|Traits|Needs|Mood|Melee Combat)$/.test(plain))return false;
  const words=plain.match(/[A-Za-z]+/g) ?? [];
  if(words.slice(1).some(word=>/^[A-Z]/.test(word) && word!=='Combat'))return false;
  if(/\b(?:born|named|called|citizen|world|fortress|artifact|kill(?:ed|s)?|slain)\b/i.test(plain))return false;
  return !/^(?:He|She|They|It)\b/.test(plain) || /[.!?]$/.test(plain);
}
export function validateContribution(row) {
  if(!row || Array.isArray(row) || Object.keys(row).some(key=>!fields.includes(key)) ||
    row.schema!==1 || row.rules!==POLICY_VERSION || !['zh-Hant','zh-Hans'].includes(row.language) ||
    row.context!=='general' || !['exact','entity','numeric'].includes(row.kind) || row.origin!=='vanilla' ||
    row.license!=='CC0-1.0' || typeof row.model!=='string' || !/^[A-Za-z0-9_/.@:+-]{1,100}$/.test(row.model) ||
    !shareableText(row.text,row.kind) || typeof row.translation!=='string' || row.translation.length>4096 ||
    secretOrInstruction.test(row.translation) || secretOrInstruction.test(row.model))throw Error('unsafe contribution');
  return {...row,translation:validateTranslation(row.text,row.translation)};
}
export function contributionIdentity(row) {
  return JSON.stringify([row.rules,row.language,row.context,row.kind,row.origin,row.text]);
}
