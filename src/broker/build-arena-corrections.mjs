import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {stringify} from 'csv-stringify/sync';
import {simplify} from './language-data.mjs';
import TOML from '@iarna/toml';

// Finite game clauses: enumerate all combinations so even long reports remain
// synchronous dictionary hits rather than entering the bounded model queue.
export async function buildArenaCorrections(root) {
  const rows=new Map();
  const add=(text,translation)=>rows.set(text,{text,translation,tags:'[REVIEWED:1]'});
  for(const term of ['eye tooth','eye teeth']) for(const side of ['','left ','right ']) {
    const source=side+term, translation=(side==='left '?'左':side==='right '?'右':'')+'犬齒';
    for(const key of [source,source[0].toUpperCase()+source.slice(1)]) add(key,translation);
  }
  for(const key of ['dragon','Dragon','dragons','Dragons']) {
    add(key,'巨龍');rows.get(key).tags+='[CREATURE:1]';
  }
  for(const key of ['Needs setting','.Needs setting']) add(key,key.startsWith('.')?'.需要復位':'需要復位');
  // A timber title has item wrappers. Bare chestnut remains a color rule;
  // overriding that bare word would corrupt hair, skin and dye descriptions.
  add('(chestnut)','(栗木)');
  // These exact recipe labels name world-generated instruments/components.
  // Keep their names as names, using the existing Dwarven name dictionary.
  for(const [source,text] of [
    ['Make etnàr melody pipe','製作「埃特納」旋律管'],
    ['Make tenshed stand','製作「滕謝德」支架'],
    ['Make tenshed hammers','製作「滕謝德」鼓槌'],
    ['Make er mallets','製作「爾」敲槌'],
    ['Make desis','製作「德錫斯」木管樂器'],
  ]) add(source,text);
  const seeds=TOML.parse(await readFile(join(root,'dfi18n-data/rulesets/zh-Hant/plants/seed.toml'),'utf8'));
  const gameplayTerms={};
  for(const rule of seeds.rulesets ?? []) for(const [source,text] of Object.entries(rule.rules ?? {})) {
    if(!/^[a-z][a-z -]*$/.test(source) || typeof text!=='string' || text.includes('{')) continue;
    gameplayTerms[source]=text;
    add(source,text);
    for(const [left,right] of [['(',')'],['{','}']]) add(left+source+right,left+text+right);
  }
  Object.assign(gameplayTerms,{'plump helmet':'肉盔菇','plump helmets':'肉盔菇','plump helmet spawn':'肉盔菇菌種'});
  for(const [source,text] of Object.entries(gameplayTerms).filter(([source])=>source.startsWith('plump helmet'))) add(source,text);
  const bag='plump helmet spawn Bag (alpaca wool)',bagText='肉盔菇菌種袋（羊駝毛）';
  add(bag,bagText);add('('+bag+')','('+bagText+')');
  // This exact clipped title was observed for the inspected alpaca-wool bag.
  // Shorter prefixes cannot identify its material and must not expand to it.
  add('(plump helmet spawn Bag (alpaca wo...','('+bagText+')');
  const description='This is a '+bag+'.  It is made from alpaca wool cloth.';
  for(const tail of ['','  ']) add(description+tail,'這是一個肉盔菇菌種袋（羊駝毛）。它由羊駝毛布料製成。');
  const clauses=[['many nerves have been severed','多條神經遭切斷'],
    ['a ligament has been torn','韌帶遭撕裂'],['a tendon has been torn','肌腱遭撕裂']];
  for(let mask=0;mask<8;mask++) {
    const extras=clauses.filter((_,i)=>mask&(1<<i));
    let source='An artery has been opened by the attack';
    if(extras.length===1) source+=' and '+extras[0][0];
    if(extras.length>1) source+=', '+extras.slice(0,-1).map(c=>c[0]).join(', ')+' and '+extras.at(-1)[0];
    add(source+'!','攻擊導致動脈破裂'+(extras.length?'，'+extras.map(c=>c[1]).join('、'):'')+'！');
  }
  const configPath=join(root,'broker/config.json');
  const config=JSON.parse(await readFile(configPath,'utf8'));
  config.gameplayGlossaryPath='data/gameplay-glossary.json';
  await writeFile(join(root,'broker/data/gameplay-glossary.json'),JSON.stringify(gameplayTerms)+'\n');
  const fixtures={};
  for(const language of ['zh-Hant','zh-Hans']) {
    fixtures[language]=[...rows.values()].map(row=>({...row,translation:language==='zh-Hans'?simplify(row.translation):row.translation}));
    const csv=stringify(fixtures[language],{header:true,columns:['text','translation','tags']});
    const file=`data/arena-corrections-${language}.csv`;
    // Broker treats {...} as a protected format token. Its literal lookup
    // already unwraps item quality braces, so register their bare terms there.
    const brokerRows=fixtures[language].filter(row=>!/^\{[a-z -]+\}$/.test(row.text));
    await writeFile(join(root,'broker',file),stringify(brokerRows,{header:true,columns:['text','translation','tags']}));
    await writeFile(join(root,`dfi18n-data/simple/${language}/zzzzzzzz-arena-corrections.csv`),csv);
    config.staticDictionariesByLanguage[language]=[...new Set([...(config.staticDictionariesByLanguage[language]??[]),file])];
    config.literalDictionaries=[...new Set([...(config.literalDictionaries??[]),file])];
  }
  await writeFile(configPath,JSON.stringify(config,null,2)+'\n');
  const keys=Object.fromEntries([...rows.values()].map(row=>[row.text,{'zh-Hant':row.translation,'zh-Hans':simplify(row.translation)}]));
  await writeFile(join(root,'broker/data/reviewed-text-keys.json'),JSON.stringify(keys)+'\n');
  await writeFile(join(root,'self-tests/arena-corrections.json'),JSON.stringify(fixtures)+'\n');
  return Object.fromEntries(Object.entries(fixtures).map(([lang,values])=>[lang,values.length]));
}
