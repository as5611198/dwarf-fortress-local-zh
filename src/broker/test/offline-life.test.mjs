import test from 'node:test';
import assert from 'node:assert/strict';
import {lifeRows} from '../build-offline-life.mjs';

test('offline life includes missing needs, both genders, quotes and events without save names',()=>{
  const rows=lifeRows(),dict=new Map(rows.map(r=>[r.text,r]));
  assert.equal(dict.get('He is not distracted after a lack of introspection.')?.translation,'他沒有因為缺少自省而分心。');
  assert.equal(dict.get('She is badly distracted after a lack of introspection.')?.translation,'她因為缺少自省而嚴重分心。');
  assert.equal(dict.get('Some migrants have arrived.')?.translation,'有移民抵達了。');
  assert.equal(dict.get('"Try to focus on the practical side of the matter."')?.translation,'「試著專注於事情實際的一面。」');
  assert.ok(dict.get('DFL_EMOTION:fondness')?.tags.includes('[PROSE:emotion]'));
  assert.ok(dict.get('DFL_REASON:talking with a friend')?.tags.includes('[PROSE:reason]'));
  assert.equal(dict.get('DFL_PREF_REASON:spots')?.translation,'斑點');
  assert.equal(dict.get('DFL_PREF_REASON:chestnuts')?.translation,'栗子');
  assert.equal(dict.get('DFL_PREF_REASON:wine')?.translation,'釀成的酒');
  assert.equal(dict.get('DFL_PREF_SUBJECT:ash')?.translation,'白蠟樹');
  assert.equal(dict.get('DFL_PREF_REASON:giant second foredigit claws')?.translation,'前肢第二指的巨爪');
  assert.ok(!dict.has('spots') && !dict.has('length'),'Preference reasons must not override generic UI terms');
  assert.equal(dict.get('I once wandered the wilds.')?.translation,'我曾在荒野漫遊。');
  assert.ok(!dict.has('it is enough to'),'Unexpanded dialogue fragments are not complete sentences');
  assert.ok(!dict.has('content') && !dict.has('free'),'Contextual emotion terms must not override unrelated UI words');
  assert.equal(rows.length,dict.size);
  const counts={};
  for (const row of rows) {
    assert.ok(Buffer.byteLength(row.text)<=4096 && Buffer.byteLength(row.translation)<=4096);
    assert.doesNotMatch(row.text+row.translation,/Istrath|Racon|Tobul/);
    assert.doesNotMatch(row.translation.replaceAll('{DEITY_NAME}',''),/[A-Za-z{}]/);
    counts[row.tags]=(counts[row.tags]??0)+1;
  }
  assert.ok(Object.values(counts).every(n=>n<16384));
});
