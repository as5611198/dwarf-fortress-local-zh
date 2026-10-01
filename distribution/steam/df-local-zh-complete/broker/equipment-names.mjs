import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import TOML from '@iarna/toml';

function literalRows(document, names) {
  return (document.rulesets ?? []).filter(row => names.includes(row.name ?? ''))
    .flatMap(row => Object.entries(row.rules ?? {}))
    .filter(([source, translation]) => /^[a-z][a-z -]*$/.test(source) &&
      typeof translation === 'string' && !translation.includes('{'));
}

export async function loadEquipmentTerms(rulesDirectory) {
  const read = async file => TOML.parse(await readFile(join(rulesDirectory,file),'utf8'));
  const files=(await readdir(join(rulesDirectory,'items'))).filter(file=>file.endsWith('.toml')).sort();
  const [materials, ...items] = await Promise.all([
    read('materials/state.toml'), ...files.map(file=>read('items/'+file)),
  ]);
  const nouns=new Map();
  const materialTerms=new Map(literalRows(materials,['shared::main','adjective']));
  const sizes=new Map();
  for (const document of items) {
    let rows=literalRows(document,['main','default::main','singular::main','plural::main']);
    // Only combine modifiers defined for this item category, e.g. left gauntlet.
    for (const name of ['^chain','^handedness','^length']) {
      const modifiers=literalRows(document,[name]);
      rows=[...rows,...modifiers.flatMap(([source,text])=>rows.map(([noun,translation])=>
        [source.trimEnd()+' '+noun,text+translation]))];
    }
    for (const [source,text] of rows) nouns.set(source,text);
    for (const [source,text] of literalRows(document,['^material'])) materialTerms.set(source.trimEnd(),text);
    for (const [source,text] of literalRows(document,['prefix::maybe_equipment_size'])) sizes.set(source.trimEnd(),text);
  }
  return {
    materials: materialTerms, nouns, sizes,
  };
}

export function translateEquipmentName(source, terms) {
  if (!terms || source.length > 100) return;
  const match = /^(.*?)( \[\d+\])?$/.exec(source);
  let inner=match[1],prefix='',suffix='';
  const count = match[2] ?? '';
  const wrappers=[['XX','XX'],['X','X'],['x','x'],['{','}'],['(',')'],['$','$'],['‼','‼'],
    ['-','-'],['+','+'],['*','*'],['≡','≡'],['☼','☼'],['«','»'],['◄','►']];
  for(let depth=0;depth<9;depth++) {
    const pair=wrappers.find(([left,right])=>inner.length>left.length+right.length &&
      inner.startsWith(left) && inner.endsWith(right));
    if(!pair) break;
    prefix+=pair[0];suffix=pair[1]+suffix;inner=inner.slice(pair[0].length,-pair[1].length);
  }
  if(!/^[A-Za-z][A-Za-z' -]*$/.test(inner)) return;
  let core = inner.toLowerCase(),size='';
  for (const [source,text] of terms.sizes ?? []) {
    if (core.startsWith(source+' ')) { size=text;core=core.slice(source.length+1);break; }
  }
  const wrap=text=>prefix+size+text+suffix+count;
  const bare = terms.nouns.get(core);
  if (bare && (inner.startsWith(core) || count || !['pick','picks'].includes(core))) return wrap(bare);
  for (let space = core.indexOf(' '); space !== -1; space = core.indexOf(' ',space+1)) {
    const material = terms.materials.get(core.slice(0,space));
    const noun = terms.nouns.get(core.slice(space+1));
    if (material && noun) return wrap(material + noun);
  }
}
