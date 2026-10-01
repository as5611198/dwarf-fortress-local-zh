import test from 'node:test';
import assert from 'node:assert/strict';
import { convertCsv, convertRules, scanRawText, reconcilePinnedNames, canonicalizeCreatureRules, mergeTraditionalRuleOverride } from '../data.mjs';
import { parse } from 'csv-parse/sync';
import TOML from '@iarna/toml';

test('converts only CSV translations and keeps multiline source, tags, placeholders', () => {
  const source = 'text,translation,tags\n"A "+" thing","错误日志 {0}","[TEMPLATE:YES]"\n'.replace('"A "+" thing"', '"A ""quoted"" thing"');
  const rows = parse(convertCsv(source), { columns: true });
  assert.equal(rows[0].text, 'A "quoted" thing');
  assert.equal(rows[0].translation, '錯誤日誌 {0}');
  assert.equal(rows[0].tags, '[TEMPLATE:YES]');
});
test('converts TOML rule values while retaining English lookup keys and references', () => {
  const input = 'base="name"\n[[rulesets]]\nname="main"\n[rulesets.rules]\n"The fortress {name}"="要塞 {name}"\n"Error"="错误"\n';
  const parsed = TOML.parse(convertRules(input));
  assert.equal(parsed.rulesets[0].rules['Error'], '錯誤');
  assert.equal(parsed.rulesets[0].rules['The fortress {name}'], '要塞 {name}');
  assert.equal(parsed.base, 'name');
});
test('local TOML overrides retain base references and replace reviewed terms', () => {
  const converted = 'base="day"\n[[rulesets]]\n[rulesets.rules]\n"{month} {%number}"="{%number}年 {month}"\n[[rulesets]]\nname="month"\n[rulesets.rules]\nGranite="花崗岩月"\n[[rulesets]]\nname="season"\n[rulesets.rules]\nspring="春"\n';
  const local = 'base="day"\n[[rulesets]]\nname="season"\n[rulesets.rules]\nspring="春天"\n';
  const merged = TOML.parse(mergeTraditionalRuleOverride(converted, local));
  assert.equal(merged.rulesets[0].rules['{month} {%number}'], '{%number}年 {month}');
  assert.equal(merged.rulesets.find(row => row.name === 'month').rules.Granite, '花崗岩月');
  assert.equal(merged.rulesets.find(row => row.name === 'season').rules.spring, '春天');
  assert.throws(() => mergeTraditionalRuleOverride(converted, 'base="other"\n'), /base mismatch/);
});
test('uses the same creature terms in singular and plural rules', () => {
  const input = 'base="creatures::name"\n[[rulesets]]\nname="singular"\n[rulesets.rules]\ngoblin="妖精"\nkobold="犬蜥人"\n[[rulesets]]\nname="plural"\n[rulesets.rules]\ngoblins="妖精"\nkobolds="犬蜥人"\n';
  const parsed = TOML.parse(canonicalizeCreatureRules(input));
  assert.equal(parsed.rulesets[0].rules.goblin, '哥布林');
  assert.equal(parsed.rulesets[0].rules.kobold, '狗頭人');
  assert.equal(parsed.rulesets[1].rules.goblins, '哥布林');
  assert.equal(parsed.rulesets[1].rules.kobolds, '狗頭人');
});
test('repairs the published tutorial CSV quote defect without retaining outer quotes', () => {
  const rows = parse(convertCsv('text,translation,tags\n"Add a "Make bed" task","添加一个“制作床”的任务",\n'), { columns: true });
  assert.equal(rows[0].text, 'Add a "Make bed" task');
});
test('raw scanner extracts display text, preserves internal tokens and source ownership', () => {
  const input = '[CREATURE:IRON_DWARF]\n[NAME:iron dwarf:iron dwarves:iron dwarven]\n[DESCRIPTION:A dwarf with iron skin.]\n[CREATURE_CLASS:SECRET_ID]\n[STATE_NAME:SOLID:iron]\n[BUILDING:INTERNAL_ID]';
  const found = scanRawText(input, 'mod-x', 'creature.txt');
  assert.deepEqual(found.map(row => row.text), ['iron dwarf', 'iron dwarves', 'iron dwarven', 'A dwarf with iron skin.', 'iron']);
  assert.ok(found.every(row => row.mod === 'mod-x' && row.file === 'creature.txt'));
  assert.deepEqual(found.map(row => row.creatureId), Array(5).fill('IRON_DWARF'));
});

test('compiled history rows use the pinned name without changing unrelated figures', () => {
  const rows = new Map([
    ['Sarvesh Native', { text: 'Sarvesh Native', translation: '薩維石 暖珠', tags: '' }],
    ['Sarvesh Warmthpearls', { text: 'Sarvesh Warmthpearls', translation: '薩維石 暖珠', tags: '' }],
    ['Sarvesh Warmthpearls met Urist.', { text: 'Sarvesh Warmthpearls met Urist.', translation: '薩維石 暖珠遇見烏瑞斯特。', tags: '' }],
    ['Urist met Domas.', { text: 'Urist met Domas.', translation: '烏瑞斯特遇見多瑪。', tags: '' }],
  ]);
  reconcilePinnedNames(rows, [{ aliases: ['Sarvesh Native', 'Sarvesh Warmthpearls'], translation: '薩維石・暖珠' }]);
  assert.equal(rows.get('Sarvesh Native').translation, '薩維石・暖珠');
  assert.equal(rows.get('Sarvesh Warmthpearls met Urist.').translation, '薩維石・暖珠遇見烏瑞斯特。');
  assert.equal(rows.get('Urist met Domas.').translation, '烏瑞斯特遇見多瑪。');
});

test('compiled history rows correct a known older spelling after alias rows were refreshed', () => {
  const rows = new Map([
    ['Sarvesh Warmthpearls', { text: 'Sarvesh Warmthpearls', translation: '薩維石・暖珠', tags: '' }],
    ['Sarvesh Warmthpearls was a dragon.', { text: 'Sarvesh Warmthpearls was a dragon.', translation: '薩維石 暖珠是一條巨龍。', tags: '' }],
  ]);
  reconcilePinnedNames(rows, [{ aliases: ['Sarvesh Warmthpearls'], translation: '薩維石・暖珠',
    legacy: ['薩維石 暖珠'] }]);
  assert.equal(rows.get('Sarvesh Warmthpearls was a dragon.').translation, '薩維石・暖珠是一條巨龍。');
});
