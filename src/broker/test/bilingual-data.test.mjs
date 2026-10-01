import test from 'node:test';
import assert from 'node:assert/strict';
import * as data from '../workbook-supplement.mjs';
import * as language from '../language-data.mjs';

test('generated Simplified rules retain source keys, tags and structural placeholders', () => {
  const source={base:'tiles',rulesets:[{name:'main',rules:{
    '{::materials} up/down stairway':'[C:6:0:1]{::materials}上下樓梯[B]',
    'Fighting':'戰鬥',
  }}]};
  assert.deepEqual(language.simplifyTree(source),{base:'tiles',rulesets:[{name:'main',rules:{
    '{::materials} up/down stairway':'[C:6:0:1]{::materials}上下楼梯[B]',Fighting:'战斗',
  }}]});
});
