import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildSimplified } from '../build-language-data.mjs';

test('rebuilding Simplified data does not duplicate literal dictionary paths', async t => {
  const root = await mkdtemp(join(tmpdir(), 'df-language-build-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const path of ['dfi18n-data/simple/zh-Hant', 'dfi18n-data/rulesets/zh-Hant',
    'broker/data/announcement-rules']) await mkdir(join(root, path), { recursive: true });
  const dictionary = 'data/fortress-ui.csv';
  await writeFile(join(root, 'broker', dictionary), 'text,translation,tags\nGeneral,常規,\n');
  await writeFile(join(root, 'broker/config.json'), JSON.stringify({
    staticDictionaries: [dictionary], reviewedDictionary: dictionary,
    literalDictionaries: [dictionary], staticDictionariesByLanguage: { 'zh-Hans': [] },
  }));

  await buildSimplified(root);
  const first = await readFile(join(root, 'broker/config.json'), 'utf8');
  await buildSimplified(root);
  const second = await readFile(join(root, 'broker/config.json'), 'utf8');
  assert.equal(second, first);
});
