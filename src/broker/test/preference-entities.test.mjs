import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TranslationBroker } from '../broker.mjs';

test('preference entities are protected inside a complete sentence and restored without Latin residue', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'df-preferences-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const glossary = JSON.parse(await readFile(new URL('../glossary.json', import.meta.url), 'utf8'));
  const source = 'She likes tetrahedrite, wood opal, goldenrod, giant sponges and chicory.';
  const broker = new TranslationBroker({ directory, language: 'zh-Hant', glossary,
    provider: async template => {
      assert.equal(template, 'She likes {{DFE0}}, {{DFE1}}, {{DFE2}}, {{DFE3}} and {{DFE4}}.');
      return '她喜歡{{DFE0}}、{{DFE1}}、{{DFE2}}、{{DFE3}}和{{DFE4}}。';
    } });
  await broker.load();
  assert.equal(await broker.translate(source), '她喜歡黝銅礦、木歐泊、金麒麟黃、巨型海綿和菊苣。');
});
