import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { TranslationBroker } from '../broker.mjs';
import { WorldNames } from '../names.mjs';
import { translateParagraph, validateParagraph } from '../rich-text.mjs';

test('rich prose uses target IDs for shared short names and preserves every link', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-rich-prose-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({world: 'region1', entities: [
    {id: 'figure:20', preferred: 'Vadane Wildmists', aliases: ['Vadane Native', 'Vadane Wildmists'], shortAliases: ['Vadane']},
    {id: 'figure:21', preferred: 'Vadane Other', aliases: ['Vadane Other'], shortAliases: ['Vadane']},
    {id: 'site:7', preferred: 'The Home', aliases: ['The Home']},
  ]}));
  const broker = new TranslationBroker({directory, language: 'zh-Hant',
    glossary: {'Vadane Wildmists': '荒霧瓦丹', 'Vadane Other': '另一位瓦丹', 'The Home': '家園', Vadane: '錯誤簡稱'},
    provider: async source => {
      assert.equal(source, '{{DFE0}} met {{DFL0}} in {{DFL1}} in {{DFN0}}.');
      return '{{DFE0}}於{{DFN0}}年在{{DFL1}}遇見{{DFL0}}。';
    }});
  await broker.load();
  const names = new WorldNames(path);
  broker.resolveNames = text => names.resolve(text, broker);
  broker.matchNames = text => names.match(text);
  const request = {kind: 'legends-paragraph', world: 'region1', subjectId: 20,
    text: 'Vadane met {{DFL0}} in {{DFL1}} in 12.',
    links: [{type: 0, id: 21, text: 'Vadane'}, {type: 1, id: 7, text: 'The Home'}]};
  const result = await translateParagraph(request, names, broker);
  assert.equal(result.translation, '荒霧瓦丹於12年在{{DFL1}}遇見{{DFL0}}。');
  assert.deepEqual(result.links, [{translation: '另一位瓦丹'}, {translation: '家園'}]);
  assert.equal(broker.glossary.Vadane, '錯誤簡稱', 'A subject-scoped name must not leak to other figures');
  assert.deepEqual(validateParagraph(request, result), result);
  await assert.rejects(translateParagraph({...request, world: 'region2'}, names, broker), /world/);
  await assert.rejects(translateParagraph({...request, links: [{type: 0, id: 21, text: 'Another figure'}, request.links[1]]}, names, broker), /identity/);
});

test('link-only paragraphs keep their tokens without calling the provider', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-rich-link-only-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({world: 'region1', entities: [
    {id: 'site:7', preferred: 'The Home', aliases: ['The Home']},
  ]}));
  const broker = new TranslationBroker({directory, language: 'zh-Hant',
    glossary: {'The Home': '家園'},
    provider: () => { throw new Error('link-only text must not call the provider'); },
  });
  await broker.load();
  const names = new WorldNames(path);
  const request = {kind: 'legends-paragraph', world: 'region1',
    text: '{{DFL0}}', links: [{type: 1, id: 7, text: 'The Home'}]};
  const result = await translateParagraph(request, names, broker);
  assert.deepEqual(result, {translation: '{{DFL0}}', links: [{translation: '家園'}]});
  await assert.rejects(translateParagraph({...request,
    links: [{type: 1, id: 7, text: 'Laborer'}]}, names, broker), /identity mismatch/);
  assert.deepEqual(validateParagraph(request, result), result);
});

test('rendered link aliases resolve through their target identity', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-rich-rendered-link-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({world: 'region1', entities: [
    {id: 'site:7', preferred: 'The Home', aliases: ['The Home']},
  ]}));
  const broker = new TranslationBroker({directory, language: 'zh-Hant',
    glossary: {'The Home': '家園'},
    provider: () => { throw new Error('rendered aliases must not call the provider'); },
  });
  await broker.load();
  const names = new WorldNames(path);
  const request = {kind: 'legends-paragraph', world: 'region1',
    text: '{{DFL0}}', links: [{type: 1, id: 7, text: 'L0001mC_'}]};
  const result = await translateParagraph(request, names, broker);
  assert.deepEqual(result, {translation: '{{DFL0}}', links: [{translation: '家園'}]});
});

test('unknown link IDs keep one canonical name across changing display aliases', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-rich-unknown-link-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'world.json');
  await writeFile(path, JSON.stringify({world: 'region1', entities: []}));
  const calls = [];
  const broker = new TranslationBroker({directory, language: 'zh-Hant',
    provider: async source => {
      calls.push(source);
      assert.equal(source, 'The Secretive Horns.');
      return '秘密之角。';
    },
  });
  await broker.load();
  const names = new WorldNames(path);
  const makeRequest = text => ({kind: 'legends-paragraph', world: 'region1',
    text: '{{DFL0}}', links: [{type: 4, id: 678, text}]});
  const first = await translateParagraph(makeRequest('The Secretive Horns.'), names, broker);
  const second = await translateParagraph(makeRequest('Secretive Horns'), names, broker);
  assert.deepEqual(first, {translation: '{{DFL0}}', links: [{translation: '秘密之角。'}]});
  assert.deepEqual(second, first);
  assert.deepEqual(calls, ['The Secretive Horns.']);
  const rendered = await translateParagraph(makeRequest('L0001mC_'), names, broker);
  assert.deepEqual(rendered, first);
  const restarted = new TranslationBroker({directory, language: 'zh-Hant',
    provider: () => { throw new Error('a pinned link must survive broker restart'); },
  });
  await restarted.load();
  const afterRestart = await translateParagraph(makeRequest('A Secretive Horns alias'),
    new WorldNames(path), restarted);
  assert.deepEqual(afterRestart, first);
});

test('rich paragraph validation rejects changed or duplicated targets and English linked text', () => {
  const request = {kind: 'legends-paragraph', world: 'fixture', text: '{{DFL0}} arrived in 12.',
    links: [{type: 0, id: 20, text: 'Vadane'}]};
  assert.throws(() => validateParagraph(request, {translation: '{{DFL0}}於12年抵達。', links: []}), /links/);
  assert.throws(() => validateParagraph(request, {translation: '{{DFL0}}於12年抵達。', links: [{translation: 'Vadane'}]}), /English/);
  assert.throws(() => validateParagraph(request, {translation: '{{DFL1}}於12年抵達。', links: [{translation: '瓦丹'}]}), /token/);
  assert.throws(() => validateParagraph({...request, text: '{{DFL0}} {{DFL0}} arrived in 12.'},
    {translation: '{{DFL0}}{{DFL0}}於12年抵達。', links: [{translation: '瓦丹'}]}), /link/);
});
