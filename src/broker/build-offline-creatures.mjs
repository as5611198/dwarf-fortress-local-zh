import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {parse} from 'csv-parse/sync';
import {stringify} from 'csv-stringify/sync';
import {simplify} from './language-data.mjs';

// Build-time only. Each accepted paragraph becomes one exact dictionary row;
// neither the render hook nor the Broker runs this grammar at runtime.
export function translateDescription(source,terms,grammar) {
  const clean=source.trim();
  if (!clean || /[\r\n\[\]{}]/.test(clean)) return;
  if (grammar.paragraphs && Object.hasOwn(grammar.paragraphs,source)) return grammar.paragraphs[source];
  const sentences=clean.replace(/\.$/,'').split(/\.\s+/);
  const translated=[];
  for (const sentence of sentences) {
    if (Object.hasOwn(grammar.sentences,sentence)) {
      translated.push(grammar.sentences[sentence]);continue;
    }
    const shape=/^(?:A|An) (.+?) (?:in the form of|in the shape of|the shape of|taking the shape of|with the shape of) (?:a|an) (.+)$/.exec(sentence);
    if (shape && Object.hasOwn(grammar.forms,shape[1]) && terms.has(shape[2])) {
      translated.push(`一隻外形如${terms.get(shape[2])}的${grammar.forms[shape[1]]}`);continue;
    }
    const person=/^(?:A|An) (?:(.+?) )?person with the (.+?) of (?:a|an) (.+)$/.exec(sentence);
    if (person && Object.hasOwn(grammar.personAdjectives,person[1] ?? '') &&
        Object.hasOwn(grammar.bodyParts,person[2]) && terms.has(person[3])) {
      const adjective=grammar.personAdjectives[person[1] ?? ''];
      translated.push(`一名${adjective?adjective+'、':''}具有${terms.get(person[3])}${grammar.bodyParts[person[2]]}的人形生物`);continue;
    }
    return; // One unknown clause keeps the complete original available.
  }
  return translated.join('。')+'。';
}

export async function buildOfflineCreatures(output) {
  const inventory=JSON.parse(await readFile(new URL('./offline-creature-sources.json',import.meta.url),'utf8'));
  const grammar=JSON.parse(await readFile(new URL('./offline-creature-grammar.json',import.meta.url),'utf8'));
  const literals=JSON.parse(await readFile(new URL('./offline-creature-literals.json',import.meta.url),'utf8'));
  const wildlife=JSON.parse(await readFile(new URL('./offline-creature-wildlife.json',import.meta.url),'utf8'));
  const small=JSON.parse(await readFile(new URL('./offline-creature-small.json',import.meta.url),'utf8'));
  grammar.sentences={...grammar.sentences,...literals,...wildlife,...small};
  grammar.paragraphs=JSON.parse(await readFile(new URL('./offline-creature-paragraphs.json',import.meta.url),'utf8'));
  const counts={};
  for (const language of ['zh-Hant','zh-Hans']) {
    const names=parse(await readFile(join(output,`dfi18n-data/simple/${language}/zzzzzzz-creature-names.csv`),'utf8'),{columns:true});
    const terms=new Map(names.map(row=>[row.text,row.translation]));
    const rows=[];
    for (const text of inventory.descriptions) {
      let translation=translateDescription(text,terms,grammar);
      if (!translation) continue;
      if (language==='zh-Hans') translation=simplify(translation);
      if (/[A-Za-z{}\[\]]/.test(translation)) throw new Error(`Invalid offline creature output: ${text}`);
      rows.push({text,translation,tags:'[REVIEWED:1]'});
    }
    const descriptionCount=rows.length;
    // A typed namespace prevents a figure's descriptive race prefix from being
    // mistaken for an arbitrary term or a part of its generated proper name.
    for (const text of new Set(inventory.creatureLabels)) {
      const translation=terms.get(text);
      if (!translation || /[A-Za-z{}\[\]\ufffd\r\n]/.test(translation)) continue;
      rows.push({text:'DFL_LEGENDS_RACE:'+text,translation,tags:'[REVIEWED:1]'});
    }
    await writeFile(join(output,`dfi18n-data/simple/${language}/zzzzzzzzzzz-offline-creatures.csv`),
      stringify(rows,{header:true,columns:['text','translation','tags']}));
    counts[language]=rows.length;
    counts[language+'Descriptions']=descriptionCount;
    counts[language+'LegendsRaces']=rows.length-descriptionCount;
  }
  return counts;
}
