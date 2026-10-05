import test from 'node:test';
import assert from 'node:assert/strict';
import {appearanceRows} from '../build-offline-appearance.mjs';

test('resident appearance preserves medium length and eye spacing across colors',()=>{
  const dict=new Map(appearanceRows({cobalt:'鈷藍色',copper:'銅色'}).map(r=>[r.text.replace('DFL_APPEARANCE:',''),r.translation]));
  assert.equal(dict.get('subject:medium-length sideburns'),'中等長度的鬢角');
  assert.equal(dict.get('subject:medium-length moustache'),'中等長度的髭鬚');
  assert.equal(dict.get('predicate:ears:very splayed out'),'大幅向外張開');
  assert.equal(dict.get('subject:slightly wide-set narrow cobalt eyes'),'間距略寬且狹長的鈷藍色眼睛');
  assert.equal(dict.get('subject:slightly wide-set narrow copper eyes'),'間距略寬且狹長的銅色眼睛');
  assert.ok(!dict.has('subject:slightly wide-set narrow unknown eyes'));
});

test('independent adventure appearance terms compose across reviewed colors',()=>{
  const rows=appearanceRows({copper:'銅色',ochre:'赭色'});
  const dict=new Map(rows.map(r=>[r.text.replace('DFL_APPEARANCE:',''),r.translation]));
  for(const [source,target] of [
    ['subject:sunken narrow copper eyes','深陷狹長的銅色眼睛'],
    ['subject:sunken narrow ochre eyes','深陷狹長的赭色眼睛'],
    ['predicate:eyes:incredibly close-set','間距極為狹窄'],
    ['subject:somewhat tall ears','略高的耳朵'],
    ['predicate:ears:fuse-lobed','耳垂貼連'],
    ['subject:quite dense hair','相當濃密的頭髮'],
    ['predicate:hair:arranged in double braids','編成雙辮'],
    ['self:average in size','體型中等'],
    ['subject:somewhat short head','略短的頭部'],
    ['predicate:head:somewhat narrow','略顯狹窄'],
    ['predicate:eyelashes:short','很短'],
  ]) assert.equal(dict.get(source),target,source);
  assert.ok(!dict.has('subject:sunken narrow unknown eyes'));
  assert.ok(!dict.has('predicate:ears:arranged in double braids'));
});

test('appearance terms are body-specific, bounded and preserve observed modifiers',()=>{
  const rows=appearanceRows({cobalt:'鈷藍色','burnt sienna':'焦赭色',brown:'棕色',aquamarine:'海藍寶石色'});
  const dict=new Map(rows.map(r=>[r.text.replace('DFL_APPEARANCE:',''),r.translation]));
  assert.equal(dict.get('subject:very long hair'),'長長的頭髮');
  assert.equal(dict.get('subject:very long beard'),'長長的鬍鬚');
  assert.equal(dict.get('subject:very long sideburns'),'長長的鬢角');
  assert.equal(dict.get('subject:very long moustache'),'長長的髭鬚');
  assert.equal(dict.get('predicate:hair:tied in a pony tail'),'束成馬尾');
  assert.equal(dict.get('subject:nearly fuse-lobed ears'),'耳垂幾乎貼連的耳朵');
  assert.equal(dict.get('subject:slightly close-set aquamarine eyes'),'間距略窄的海藍寶石色眼睛');
  assert.equal(dict.get('predicate:eyes:slightly rounded'),'略呈圓形');
  assert.equal(dict.get('has:a scratchy voice'),'聲音粗啞');
  assert.equal(dict.get('predicate:hair:neatly combed'),'梳理得很整齊');
  assert.equal(dict.get('predicate:teeth:tangled'),'交錯不齊');
  assert.equal(dict.get('predicate:nose bridge:convex'),'向外凸起');
  assert.equal(dict.get('subject:cobalt eyes'),'鈷藍色眼睛');
  assert.equal(dict.get('predicate:eyes:sunken'),'深陷');
  assert.equal(dict.get('has:very low cheekbones'),'顴骨很低');
  assert.equal(dict.get('subject:somewhat narrow ears'),'略窄的耳朵');
  assert.equal(dict.get('predicate:ears:splayed out'),'向外張開');
  assert.equal(dict.get('predicate:head:broad'),'寬闊');
  assert.equal(dict.get('predicate:nose:somewhat narrow'),'略窄');
  assert.equal(dict.get('predicate:hair:burnt sienna'),'呈焦赭色');
  assert.equal(dict.get('predicate:skin:brown'),'呈棕色');
  assert.ok(!dict.has('predicate:eyes:neatly combed'));
  assert.ok(!dict.has('predicate:teeth:brown'));
  assert.ok(!dict.has('subject:mysterious hair'));
  assert.equal(rows.length,dict.size);
  assert.ok(rows.length<16384);
  for(const row of rows) {
    assert.equal(row.tags,'[REVIEWED:1][PROSE:appearance]');
    assert.doesNotMatch(row.translation,/[A-Za-z{}]/);
    assert.ok(Buffer.byteLength(row.text)<=4096 && Buffer.byteLength(row.translation)<=4096);
  }
});
