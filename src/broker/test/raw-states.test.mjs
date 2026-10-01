import test from 'node:test';
import assert from 'node:assert/strict';
import { composeRawState, selectRawStateSources } from '../raw-states.mjs';

const terms = {
  creatures: new Map([
    ['bark scorpion', '樹皮蠍'],
    ['donkey', '驢'],
  ]),
  plants: new Map([['carambola tree', '楊桃樹']]),
  reviewed: new Map([['dwarven', '矮人']]),
};

test('raw material states reuse the same creature name through temperature changes', () => {
  assert.equal(composeRawState('bark scorpion venom', terms)?.translation, '樹皮蠍毒液');
  assert.equal(composeRawState('frozen bark scorpion venom', terms)?.translation, '冰凍樹皮蠍毒液');
  assert.equal(composeRawState('boiling bark scorpion venom', terms)?.translation, '沸騰樹皮蠍毒液');
});

test('raw dairy and wood names compose only from known base terms', () => {
  assert.equal(composeRawState("donkey's milk", terms)?.translation, '驢奶');
  assert.equal(composeRawState('donkey cheese powder', terms)?.translation, '驢乳酪粉');
  assert.equal(composeRawState('melted donkey cheese', terms)?.translation, '融化的驢乳酪');
  assert.equal(composeRawState('dwarven milk', terms)?.translation, '矮人奶');
  assert.equal(composeRawState('carambola wood', terms)?.translation, '楊桃木材');
  assert.equal(composeRawState('unknown beast venom', terms), null);
  assert.equal(composeRawState('unknown tree wood', terms), null);
});

test('state source selection is stable after translations are deployed', () => {
  const rows = [
    { text: 'donkey cheese', token: 'STATE_NAME', mod: 'vanilla_creatures' },
    { text: 'donkey cheese', token: 'STATE_ADJ', mod: 'vanilla_creatures' },
    { text: 'donkey cheese', tokens: ['STATE_NAME', 'STATE_ADJ'], mods: ['vanilla_creatures'] },
    { text: 'donkey', token: 'NAME', mod: 'vanilla_creatures' },
  ];
  assert.deepEqual(selectRawStateSources(rows), [
    { text: 'donkey cheese', mods: ['vanilla_creatures'] },
  ]);
});

test('state generation leaves sources already owned by a TOML rule alone', () => {
  const rows = [
    { text: 'blood', token: 'STATE_NAME', mod: 'vanilla_materials' },
    { text: 'frozen blood', token: 'STATE_NAME', mod: 'vanilla_materials' },
  ];
  assert.deepEqual(selectRawStateSources(rows, new Set(['Blood'])), [
    { text: 'frozen blood', mods: ['vanilla_materials'] },
  ]);
});

test('reviewed base materials keep one translation across state variants', () => {
  const context = { ...terms, reviewed: new Map([
    ['blood', '血液'],
    ['octopus ink', '章魚墨汁'],
  ]) };
  assert.equal(composeRawState('blood', context)?.translation, '血液');
  assert.equal(composeRawState('frozen blood', context)?.translation, '冰凍血液');
  assert.equal(composeRawState('boiling octopus ink', context)?.translation, '沸騰章魚墨汁');
  assert.equal(composeRawState('unknown fluid', context), null);
});

test('existing creature rules can supply a differently capitalized animal name', () => {
  const context = { ...terms, creatures: new Map([['Miohippus', '漸新馬']]) };
  assert.equal(composeRawState('miohippus cheese', context)?.translation, '漸新馬乳酪');
  assert.equal(composeRawState("frozen miohippus's milk", context)?.translation, '冰凍漸新馬奶');
});
