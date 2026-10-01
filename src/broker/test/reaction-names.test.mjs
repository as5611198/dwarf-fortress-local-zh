import test from 'node:test';
import assert from 'node:assert/strict';
import { composeReactionName } from '../reaction-names.mjs';

const plants = new Map([
  ['acacia', '刺槐'],
  ['apple tree', '蘋果樹'],
  ['bilberry', '越橘'],
  ['coffee tree', '咖啡樹'],
  ['mangrove', '紅樹'],
  ['alder', '榿樹'],
  ['onion', '洋蔥'],
  ['rice', '稻'],
  ['chestnut', '板栗樹'],
]);

test('dye reaction names reuse plant names and preserve the source part', () => {
  assert.equal(composeReactionName('make acacia bark dye', plants)?.translation, '製作刺槐樹皮染料');
  assert.equal(composeReactionName('make apple leaf dye', plants)?.translation, '製作蘋果葉染料');
  assert.equal(composeReactionName('make coffee bean dye', plants)?.translation, '製作咖啡豆染料');
  assert.equal(composeReactionName('make mangrove leaf dye', plants)?.translation, '製作紅樹葉染料');
  assert.equal(composeReactionName('make alder cone dye', plants)?.translation, '製作榿樹球果染料');
  assert.equal(composeReactionName('make onion skin dye', plants)?.translation, '製作洋蔥皮染料');
  assert.equal(composeReactionName('make rice husk dye', plants)?.translation, '製作稻殼染料');
  assert.equal(composeReactionName('make chestnut hull dye', plants)?.translation, '製作板栗外殼染料');
  assert.equal(composeReactionName('make bilberry dye', plants)?.translation, '製作越橘染料');
  assert.equal(composeReactionName('make unknown leaf dye', plants), null);
});
