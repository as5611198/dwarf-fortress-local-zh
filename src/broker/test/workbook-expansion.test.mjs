import test from 'node:test';
import assert from 'node:assert/strict';
import { expandWorkbookAlternatives } from '../workbook-expansion.mjs';

test('a finite list produces concrete localized texts, with no slash template in the runtime dictionary',()=>{
  const rows=expandWorkbookAlternatives({text:'when (thirsty/hungry)',translation:'当（口渴/饥饿）时'});
  assert.deepEqual(rows,[{text:'when thirsty',translation:'当口渴时'},
    {text:'when hungry',translation:'当饥饿时'}]);
});
test('unbound placeholders, reordered multi-groups and unequal alternatives remain explicit unresolved templates',()=>{
  for(const row of [{text:'after * dies',translation:'*死亡后'},
    {text:'(interacting/visiting) with a (pet/partner)',translation:'与（宠物/伙伴）（互动/拜访）'},
    {text:'(a/spouse) loss',translation:'配偶失去'}]) assert.equal(expandWorkbookAlternatives(row),null);
});
