import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {personalityRows} from '../build-offline-personality.mjs';

test('complete current quotes preserve punctuation, sentence boundaries and existing reviewed wording',()=>{
  const quotes={
    'Yes, I want more.  Is that so bad?':'沒錯，我還想要更多。這有那麼糟嗎？',
    "I'm feel like I'm about to snap.":'我覺得自己快要崩潰了。',
    'Who cares what they think?':'誰在乎他們怎麼想？',
    'That isn\'t funny.':'那可不好笑。',
  };
  const dict=new Map(personalityRows({sentences:[],values:[]},{},{},{},{},{},quotes)
    .map(r=>[r.text,r.translation]));
  assert.equal(dict.get('"Yes, I want more.  Is that so bad?"'),'「沒錯，我還想要更多。這有那麼糟嗎？」');
  assert.equal(dict.get('"I\'m feel like I\'m about to snap."'),'「我覺得自己快要崩潰了。」');
  assert.equal(dict.get('"Who cares what they think?"'),'「誰在乎他們怎麼想？」');
  assert.equal(dict.get('"That isn\'t funny."'),'「那一點也不好笑。」','Prior hand-reviewed wording wins');
  assert.equal(dict.has('"Yes, I want more. Is that so bad?"'),false,'Exact spacing remains part of the key');
  assert.equal(dict.has('"Yes, I want more.  Is that so bad? Unknown tail."'),false);
  assert.throws(()=>personalityRows({sentences:[],values:[]},{},{},{},{},{},{'Did you hear the one about the ':'未完成片段'}),/complete quote/);
});

test('expanded predicates and conflict tails preserve pronouns without inventing world names',()=>{
  const rows=personalityRows({sentences:[],values:[]},{traits:{'is very stubborn':'十分固執'},values:{'values decorum, dignity and proper behavior':'重視禮儀、尊嚴與合宜舉止'}},{'a very good sense of the position of {his} own body':'很好的身體位置感知'},{heads:{'is troubled by this since':'對此感到困擾，因為'},reasons:{'values harmony':'重視和諧'},standalone:{}});
  const dict=new Map(rows.map(r=>[r.text,r]));
  assert.equal(dict.get('She is very stubborn.')?.translation,'她十分固執。');
  assert.equal(dict.get('a very good sense of the position of her own body')?.translation,'很好的身體位置感知');
  assert.equal(dict.get('though she is troubled by this since she values harmony.')?.translation,'但她對此感到困擾，因為她重視和諧。');
});

test('reviewed offline prose generates complete pronouns without private world names', async()=>{
  const data=JSON.parse(await readFile(new URL('../offline-personality.json',import.meta.url),'utf8'));
  const rows=personalityRows(data);
  const dict=new Map(rows.map(row=>[row.text,row]));
  for (const [he,his,zh] of [['He','his','他'],['She','her','她'],['It','its','牠']]) {
    assert.equal(dict.get(`${he} dreams of raising a family.`).translation,`${zh}夢想建立家庭。`);
    assert.ok(dict.has(`${he} is pleased by ${his} own appearance and talents.`));
  }
  assert.equal(rows.length,new Set(rows.map(row=>row.text)).size);
  for (const row of rows) {
    assert.doesNotMatch(row.text+row.translation,/[{}]/);
    assert.doesNotMatch(row.translation,/[A-Za-z]/);
    assert.match(row.tags,/\[REVIEWED:1\]/);
  }
  assert.throws(()=>personalityRows({sentences:[['{unknown}','壞資料']],values:[]}),/Unresolved/);
});

test('all authored personality inputs fit bounded indexes and translate both genders',async()=>{
  const names=['offline-personality','offline-personality-extra','offline-abilities','offline-conflicts','offline-preference-terms','offline-mannerisms','offline-current-quotes'];
  const inputs=await Promise.all(names.map(async n=>JSON.parse(await readFile(new URL(`../${n}.json`,import.meta.url),'utf8'))));
  const rows=personalityRows(...inputs),counts={};
  for(const row of rows) {
    assert.doesNotMatch(row.text+row.translation,/[{}]/);
    assert.doesNotMatch(row.translation,/[A-Za-z]/);
    assert.ok(Buffer.byteLength(row.text)<=4096 && Buffer.byteLength(row.translation)<=4096);
    counts[row.tags]=(counts[row.tags]??0)+1;
  }
  assert.ok(Object.values(counts).every(n=>n<16384));
  assert.ok(rows.some(r=>r.text==='She exhales slowly and deliberately when she starts getting bored.'));
});

test('observed rigid anger mannerism composes all pronouns with its trait paragraph',async()=>{
  const data=JSON.parse(await readFile(new URL('../offline-personality.json',import.meta.url),'utf8'));
  const mannerisms=JSON.parse(await readFile(new URL('../offline-mannerisms.json',import.meta.url),'utf8'));
  const dict=new Map(personalityRows(data,{},{},{},{},mannerisms).map(r=>[r.text,r.translation]));
  for(const [he,lower,zh] of [['He','he','他'],['She','she','她'],['It','it','牠']]) {
    assert.equal(dict.get(`${he} becomes very rigid when ${lower}'s angry.`),`${zh}生氣時會變得十分僵硬。`);
  }
  assert.equal(dict.get("She becomes very rigid whenever she's angry."),'她生氣時會變得十分僵硬。');
  assert.equal(dict.has("She becomes very rigid when she's mildly upset."),false,'Unreviewed conditions stay unsupported');
});
