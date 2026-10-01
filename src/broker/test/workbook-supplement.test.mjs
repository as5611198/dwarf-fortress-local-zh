import test from 'node:test';
import assert from 'node:assert/strict';
import { planSupplement } from '../workbook-supplement.mjs';

const candidate = (text, translation, sheet = '界面UI元素') => ({ text, translation, sheet, row: 3, columns: 'A:B' });

test('workbook supplement converts Chinese and retains established keys and identity rules', () => {
  const plan = planSupplement([candidate('New label', '新标签'), candidate('IRON', '铁'),
    candidate('Name Root', '名称词根')], new Set(['iron', 'Name Root']));
  assert.deepEqual(plan.rows.map(row => row.text), ['IRON', 'New label']);
  assert.equal(plan.decisions.filter(row => row.reason === 'existing key retained').length, 1);
});

test('English identity values cannot hide available workbook translations', () => {
  const existing=new Map([['Abated','Abated'],['Name','Name'],['Iron','鐵']]);
  const plan=planSupplement([candidate('Abated','减轻的'),candidate('Name','名称'),
    candidate('Iron','铁'),candidate('IRON','铁')],existing);
  assert.deepEqual(plan.rows.map(row=>row.text),['Abated','IRON','Name']);
  assert.equal(plan.rows.find(row=>row.text==='Name').translation,'名稱');
});

test('a generic label and grammatical uses keep independent reviewed meanings', () => {
  const plan=planSupplement([candidate('Name','名称'),candidate('Name','名字','拼接-名词'),
    candidate('Name','命名','动词')],new Map());
  assert.deepEqual(plan.rows,[{text:'Name',translation:'名稱',tags:''}]);
  assert.equal(plan.decisions.filter(row=>row.reason==='contextual meaning retained').length,2);
});

test('draft templates, source typos and gender mismatches are not static entries', () => {
  const plan = planSupplement([candidate('Option {%number}', '选项 {%number}'),
    candidate('after (eating/drinking)', '在（吃饭/喝水）后'),
    candidate('Paraceratheriun', '巨犀'), candidate('region5', '区域5'),
    candidate('Drepanopterus man', '女镰翅鲎人')], new Set());
  assert.equal(plan.rows.length, 0);
  assert.equal(plan.decisions.length, 5);
});

test('fully specified creature descriptions are safe exact-only entries without a contextual pattern',()=>{
  const plan=planSupplement([candidate('A unique creature.','一种独特生物。','动物介绍')],new Map());
  assert.deepEqual(plan.rows,[{text:'A unique creature.',translation:'一種獨特生物。',tags:''}]);
});

test('conflicts and duplicate rows have deterministic decisions with source locations', () => {
  const plan = planSupplement([candidate('New label', '新标签'), candidate('New label', '新的标签'),
    candidate('Other label', '其他标签'), candidate('Other label', '其他标签')], new Set());
  assert.deepEqual(plan.rows.map(row => row.text), ['Other label']);
  assert.equal(plan.decisions.filter(row => row.reason === 'conflicting translations').length, 2);
  assert.equal(plan.decisions.filter(row => row.reason === 'duplicate row').length, 1);
  assert.ok(plan.decisions.every(row => row.row === 3 && row.columns === 'A:B'));
});

test('format, numbers and pinned terminology must be valid after conversion or review', () => {
  const plan = planSupplement([candidate('Color goldenrod items', '金菊色物品'),
    candidate('10 items', '11个物品'), candidate('Safe items', '安全物品')], new Set(),
  { goldenrod: '金麒麟黃' });
  assert.deepEqual(plan.rows.map(row => row.text), ['Safe items']);
  assert.ok(plan.decisions.some(row => row.reason === 'pinned terminology mismatch'));
  assert.ok(plan.decisions.some(row => row.reason === 'number mismatch'));
});

test('Simplified entries reuse the workbook text exactly and use their own existing keys', () => {
  const input = [candidate('New label', '新标签'), candidate('Iron items', '铁制品')];
  const hant = planSupplement(input, new Set(['Iron items']));
  const hans = planSupplement(input, new Set(), {}, {}, { language: 'zh-Hans' });
  assert.deepEqual(hant.rows.map(row => row.text), ['New label']);
  assert.deepEqual(hans.rows, [
    { text: 'Iron items', translation: '铁制品', tags: '' },
    { text: 'New label', translation: '新标签', tags: '' },
  ]);
  assert.equal(input[0].translation, '新标签');
});

test('reviewed corrections select the requested language without changing the workbook source', () => {
  const input = [candidate('Charge', '蓄力')];
  const corrections = { Charge: { 'zh-Hant': '衝鋒', 'zh-Hans': '冲锋' } };
  assert.equal(planSupplement(input, new Set(), {}, corrections).rows[0].translation, '衝鋒');
  assert.equal(planSupplement(input, new Set(), {}, corrections,
    { language: 'zh-Hans' }).rows[0].translation, '冲锋');
  assert.equal(input[0].translation, '蓄力');
});

test('mistyped table descriptions and mismatched woman translations are excluded', () => {
  const input = [candidate('À table object must be made.', '必须先制作桌子。'),
    candidate('Drepanopterus woman', '男镰翅鲎人')];
  assert.equal(planSupplement(input, new Set(), {}, {}, { language: 'zh-Hans' }).rows.length, 0);
});
