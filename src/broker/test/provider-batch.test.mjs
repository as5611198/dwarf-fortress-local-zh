import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createProvider } from '../provider.mjs';

async function fixture(handler) {
  const server = createServer(async (req, res) => {
    let content = '';
    for await (const chunk of req) content += chunk;
    const input = JSON.parse(JSON.parse(content).messages[1].content);
    const output = await handler(input.items ? input : {items: [{id: 'single', text: input.source}]});
    const response = input.items ? output : {translation: output.translations?.[0]?.translation ?? '中文'};
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({choices: [{message: {content: JSON.stringify(response)}}]}));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {server, provider: await createProvider({provider: {kind: 'Custom_OpenAI', model: 'fixture',
    baseUrl: `http://127.0.0.1:${server.address().port}/v1`}})};
}

test('Legends batches twelve short entries into bounded physical requests', async t => {
  const sizes = [];
  const {server, provider} = await fixture(input => {
    sizes.push(input.items.length);
    return {translations: input.items.map(item => ({id: item.id, translation: `中文${item.text.match(/\d+/)[0]}`}))};
  });
  t.after(() => new Promise(resolve => server.close(resolve)));
  const outputs = await Promise.all(Array.from({length: 12}, (_, n) =>
    provider(`Entry ${n}`, 'zh-Hant', {batch: true})));
  assert.deepEqual(outputs, Array.from({length: 12}, (_, n) => `中文${n}`));
  assert.deepEqual(sizes.sort((a,b) => a-b), [2,10]);
  assert.equal(provider.batchStats.items, 12);
  assert.equal(provider.batchStats.requests, 2);
});

test('batch accepts valid entries while rejecting an invalid translation', async t => {
  const {server, provider} = await fixture(input => ({translations: input.items.map(item => ({
    id: item.id, translation: item.text === 'Bad 2' ? 'English' : `中文${item.text.match(/\d+/)[0]}`,
  }))}));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const results = await Promise.allSettled(['Good 1','Bad 2','Good 3'].map(text =>
    provider(text, 'zh-Hant', {batch: true})));
  assert.deepEqual(results.map(row => row.status), ['fulfilled','rejected','fulfilled']);
  assert.equal(results[0].value, '中文1');
  assert.match(results[1].reason.message, /residual English/);
  assert.equal(results[2].value, '中文3');
});

test('batch rejects duplicate response IDs instead of assigning wrong names', async t => {
  const {server, provider} = await fixture(input => ({translations: input.items.map(item => ({
    id: input.items[0].id, translation: '中文',
  }))}));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const results = await Promise.allSettled(['Native A','Native B'].map(text =>
    provider(text, 'zh-Hant', {batch: true, kind: 'phonetic-name'})));
  assert.deepEqual(results.map(row => row.status), ['rejected','rejected']);
  assert.ok(results.every(row => row.reason.message === 'provider response invalid'));
});

test('single and batched calls share a three-connection HTTP limit', async t => {
  let active = 0, peak = 0;
  const {server, provider} = await fixture(async input => {
    active++; peak = Math.max(peak, active);
    await new Promise(resolve => setTimeout(resolve, 35));
    active--;
    return {translations: input.items.map(item => ({id:item.id,
      translation:`中文${item.text.match(/\d+/)?.[0] ?? ''}`}))};
  });
  t.after(() => new Promise(resolve => server.close(resolve)));
  const calls = Array.from({length:5},(_,i)=>provider(`Single ${i}`,'zh-Hant'));
  calls.push(...Array.from({length:12},(_,i)=>provider(`Batch ${i}`,'zh-Hant',{batch:true})));
  await Promise.all(calls);
  assert.ok(peak <= 3, `observed ${peak} concurrent requests`);
});

test('batch input character cap splits long entries', async t => {
  const sizes=[];
  const {server, provider}=await fixture(input=>{
    sizes.push(input.items.length);
    return {translations:input.items.map(item=>({id:item.id,translation:'中文'}))};
  });
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  await Promise.all(Array.from({length:3},(_,i)=>
    provider(`Text ${String.fromCharCode(65+i)} ${'x'.repeat(4500)}`,'zh-Hant',{batch:true})));
  assert.deepEqual(sizes.sort(),[1,1,1]);
});
