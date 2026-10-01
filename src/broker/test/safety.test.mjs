import test from 'node:test';
import assert from 'node:assert/strict';
import { validateTranslation, cacheKey, mentionsTerm, hasCanonicalNameCounts, hasRuntimeAlias } from '../safety.mjs';

test('display keys are detected inside concatenated native paragraphs without rejecting real L words', () => {
  for (const text of ['L0009Ss________ L0009Su________', '[C:7:0:1]L000123_',
    'prefix DFLIVE_'+'0'.repeat(64), 'L000008', 'P_____']) assert.equal(hasRuntimeAlias(text),true);
  for (const text of ['Laborer','Lithium','Love','Lily','Laborer likes chicory.']) {
    assert.equal(hasRuntimeAlias(text),false);
  }
});

test('fixed terminology is matched as a complete term and required in cached prose', () => {
  assert.equal(mentionsTerm('male elf chaos follower', 'chaos follower'), true);
  assert.equal(mentionsTerm('chaos followership', 'chaos follower'), false);
  assert.equal(hasCanonicalNameCounts('male elf chaos follower', '男性精靈混亂追隨者',
    { 'chaos follower': '混沌追隨者' }), false);
  assert.equal(hasCanonicalNameCounts('male elf chaos follower', '男性精靈混沌追隨者',
    { 'chaos follower': '混沌追隨者' }), true);
});

test('canonical name counts ignore occurrences embedded in longer names', () => {
  const source = 'Bosa Bosaustu, "Bosa Dungeonclean", female goblin';
  const translation = '波薩地牢清潔工，「波薩地牢清潔工」，女性哥布林';
  assert.equal(hasCanonicalNameCounts(source, translation, { Bosa: '波薩' }), true);
  assert.equal(hasCanonicalNameCounts(source, '波薩地牢清潔工，女性哥布林', { Bosa: '波薩' }), false);
});

test('rejects untranslated names and mixed English prose', () => {
  assert.throws(() => validateTranslation('Urist was born.', '烏瑞斯特 was born.'), /English/);
  assert.throws(() => validateTranslation('Urist was born.', 'Urist 出生了。'), /English/);
});

test('documented product and command identifiers survive localized help text only when present in source', () => {
  assert.equal(validateTranslation('Welcome to DFHack!','歡迎使用 DFHack！'),'歡迎使用 DFHack！');
  assert.equal(validateTranslation('Use gui/overlay.','使用 gui/overlay。'),'使用 gui/overlay。');
  assert.equal(validateTranslation('Endgame event 1B','終局事件 1B'),'終局事件 1B');
  assert.throws(()=>validateTranslation('Welcome!','歡迎使用 DFHack！'),/English/);
  assert.throws(()=>validateTranslation('DFHack welcome','DFHack welcome 歡迎'),/English/);
  assert.throws(()=>validateTranslation('Run quickly.','run 快速奔跑。'),/English/);
  assert.equal(validateTranslation('Click the "run" button.','點選「run」按鈕。'),'點選「run」按鈕。');
});
test('does not transliterate an indefinite article as a name', () => {
  assert.throws(() => validateTranslation('An oceanic fish.', '安 海洋魚類。'), /article/);
  assert.throws(() => validateTranslation('An aquatic arthropod.', '安水生節肢動物。'), /article/);
  assert.equal(validateTranslation('An oceanic fish.', '一種海洋魚類。'), '一種海洋魚類。');
});
test('preserves numbers including multiplicity and rejects introduced numbers', () => {
  assert.equal(validateTranslation('In 123, 2 dwarves arrived.', '在 123 年，2 名矮人抵達。'), '在 123 年，2 名矮人抵達。');
  assert.throws(() => validateTranslation('In 123, 2 dwarves arrived.', '在 124 年，2 名矮人抵達。'), /number/);
  assert.throws(() => validateTranslation('2 and 2', '2'), /number/);
  assert.throws(() => validateTranslation('Dwarves arrived.', '7 名矮人抵達。'), /number/);
});
test('preserves placeholders and markup without introducing tokens', () => {
  assert.equal(validateTranslation('[C:4:0:1]Urist has {0} axes.[C:7:0:0]', '[C:4:0:1]烏瑞斯特有 {0} 把斧頭。[C:7:0:0]'), '[C:4:0:1]烏瑞斯特有 {0} 把斧頭。[C:7:0:0]');
  assert.throws(() => validateTranslation('A dwarf.', '矮人 {num1}。'), /token/);
  assert.throws(() => validateTranslation('[C:4:0:1]A dwarf.', '[C:7:0:0]矮人。'), /token/);
});
test('rejects empty output, JSON wrappers, or explanatory filler', () => {
  for (const value of ['', '{"translation":"矮人"}', '```矮人```']) {
    assert.throws(() => validateTranslation('A dwarf.', value));
  }
});
test('cache identity isolates target language and policy version', () => {
  assert.notEqual(cacheKey('A dwarf.', 'zh-Hant'), cacheKey('A dwarf.', 'zh-Hans'));
  assert.notEqual(cacheKey('A dwarf.', 'zh-Hant', '1'), cacheKey('A dwarf.', 'zh-Hant', '2'));
});
