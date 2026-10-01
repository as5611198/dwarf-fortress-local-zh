import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createProvider } from '../provider.mjs';

test('local OpenAI-compatible services work without an API key',async t=>{
  let observed;
  const server=createServer(async(req,res)=>{
    let text='';for await(const chunk of req) text+=chunk;
    observed={url:req.url,authorization:req.headers.authorization,body:JSON.parse(text)};
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({choices:[{message:{content:'{"translation":"矮人抵達了。"}'}}]}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const provider=await createProvider({provider:{kind:'Custom_OpenAI',baseUrl:`http://127.0.0.1:${server.address().port}/v1`,model:'local-fixture',key:''}});
  assert.equal(await provider('A dwarf arrived.','zh-Hant'),'矮人抵達了。');
  assert.equal(observed.url,'/v1/chat/completions');
  assert.equal(observed.authorization,undefined);
  assert.equal(observed.body.model,'local-fixture');
});

test('reads actual RimWorld SettingsBlock wrapper and sends configured OpenAI protocol', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'df-provider-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  let observed;
  const server = createServer(async (req, res) => {
    let body = ''; for await (const c of req) body += c;
    observed = { url: req.url, authorization: req.headers.authorization, body: JSON.parse(body) };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ choices: [{ message: { content: '{"translation":"矮人抵達了。"}' } }] }));
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  t.after(() => new Promise(r => server.close(r)));
  const file = join(dir, 'settings.xml');
  await writeFile(file, `<SettingsBlock><ModSettings><ApiConfigs><li><Provider>Custom_OpenAI</Provider><SelectedModel>fixture-model</SelectedModel><Enabled>True</Enabled><Key>fixture-key</Key><CustomBaseUrl>http://127.0.0.1:${server.address().port}/v1</CustomBaseUrl></li></ApiConfigs></ModSettings></SettingsBlock>`);
  const provider = await createProvider({ rimworldConfig: file });
  assert.equal(await provider('A dwarf arrived.', 'zh-Hant'), '矮人抵達了。');
  assert.equal(observed.url, '/v1/chat/completions');
  assert.equal(observed.authorization, 'Bearer fixture-key');
  assert.equal(observed.body.model, 'fixture-model');
  assert.deepEqual(JSON.parse(observed.body.messages[1].content), { source: 'A dwarf arrived.', mandatoryGlossary: {} });
});

test('starts in offline dictionary mode when no RimWorld profile is enabled', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'df-provider-offline-'));
  const file = join(dir, 'settings.xml');
  await writeFile(file, '<SettingsBlock><ModSettings><ApiConfigs /></ModSettings></SettingsBlock>');
  const provider = await createProvider({ rimworldConfig: file });
  await rm(dir, { recursive: true, force: true });
  assert.equal(provider, null);
});

test('phonetic names use an explicit name prompt without old semantic glossary entries',async t=> {
  let observed;
  const server=createServer(async(req,res)=> {
    let body='';for await(const c of req) body+=c;
    observed=JSON.parse(body);
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({choices:[{message:{content:JSON.stringify({translation:'伊穆斯特 基拉雷布'})}}]}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const provider=await createProvider({glossary:{Imust:'我必須'},provider:{kind:'Custom_OpenAI',model:'fixture',
    baseUrl:`http://127.0.0.1:${server.address().port}/v1`}});
  assert.equal(await provider('Imust Kìrareb','zh-Hant',{kind:'phonetic-name'}),'伊穆斯特 基拉雷布');
  assert.match(observed.messages[0].content,/Never translate these words semantically/);
  assert.deepEqual(JSON.parse(observed.messages[1].content).mandatoryGlossary,{});
});

test('repairs residual English and inconsistent glossary before accepting output', async t => {
  const outputs = ['Urist 抵達了。', '烏里斯特抵達了。', '烏瑞斯特抵達了。'];
  const prompts = [];
  const server = createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    prompts.push(JSON.parse(body).messages[0].content);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ translation: outputs.shift() }) } }] }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const provider = await createProvider({ glossary: { Urist: '烏瑞斯特' }, provider: {
    kind: 'Custom_OpenAI', model: 'fixture', baseUrl: `http://127.0.0.1:${server.address().port}/v1`,
  } });
  assert.equal(await provider('Urist arrived.', 'zh-Hant'), '烏瑞斯特抵達了。');
  assert.equal(prompts.length, 3);
  assert.match(prompts[1], /residual English/);
  assert.match(prompts[2], /mandatory glossary mismatch/);
});
