import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, readdir, mkdtemp, rm, stat, cp, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL, fileURLToPath} from 'node:url';
import {parse} from 'csv-parse/sync';
import TOML from '@iarna/toml';
import {spawnSync} from 'node:child_process';

const packageRoot = process.env.DF_LOCAL_ZH_PACKAGE_TEST_ROOT ?? fileURLToPath(new URL('../../../distribution/steam/df-local-zh-complete/', import.meta.url));

test('one Workshop package supplies both languages and its own core without upstream subscriptions', async () => {
  const manifest = JSON.parse(await readFile(join(packageRoot, 'PACKAGE-MANIFEST.json'), 'utf8'));
  assert.equal(manifest.releaseMode, 'standalone-bilingual');
  assert.equal(manifest.requiresOriginalEngine, false);
  assert.equal(manifest.requiresOriginalDataSubscription, false);
  assert.deepEqual(manifest.languages, ['zh-Hant', 'zh-Hans']);
  assert.equal(manifest.upstreamRedistributionApproved, true);
  for (const name of ['libs/df_local_zh_core.dll', ...(manifest.runtime==='rust'?['broker/df-local-zh-broker.exe']:['broker/server.mjs','broker/runtime-queue.mjs']),
    'scripts_modinstalled/df-local-zh-core/native.lua', 'scripts_modinstalled/df-local-zh-core/mod.lua']) {
    assert.ok((await stat(join(packageRoot, name))).isFile(), name);
  }
  const config = JSON.parse(await readFile(join(packageRoot, 'broker/config.json'), 'utf8'));
  assert.equal(config.requiresUpstreamChineseWorkshopData, false);
  const info = await readFile(join(packageRoot, 'info.txt'), 'utf8');
  assert.doesNotMatch(info, /3613958631|3635900931/);
  const helpers = await readFile(join(packageRoot, 'scripts_modinstalled/df-local-zh-core/helpers.lua'), 'utf8');
  assert.match(helpers, /MOD_SOURCE_PATH \.\. 'dfi18n-data'/);
  for (const language of manifest.languages) {
    assert.ok((await readdir(join(packageRoot, 'dfi18n-data/simple', language))).length > 0);
    assert.ok((await readdir(join(packageRoot, 'dfi18n-data/fonts', language))).some(name => name.endsWith('.otf')));
    TOML.parse(await readFile(join(packageRoot, 'dfi18n-data/rulesets', language, 'index.toml'), 'utf8'));
  }
});

test('release validator refuses a self-consistent manifest missing the owned core', async () => {
  const directory=await mkdtemp(join(tmpdir(),'df-package-validator-'));
  try {
    await cp(packageRoot,directory,{recursive:true});
    await rm(join(directory,'libs/df_local_zh_core.dll'));
    const manifest=JSON.parse(await readFile(join(directory,'PACKAGE-MANIFEST.json'),'utf8'));
    manifest.files=manifest.files.filter(row=>row.path!=='libs/df_local_zh_core.dll');
    await writeFile(join(directory,'PACKAGE-MANIFEST.json'),JSON.stringify(manifest));
    const result=spawnSync(process.execPath,[fileURLToPath(new URL('../validate-workshop-package.mjs',import.meta.url)),directory],{encoding:'utf8'});
    assert.equal(result.status,1);
    assert.match(result.stderr,/missing standalone runtime file: libs\/df_local_zh_core.dll/);
  } finally {await rm(directory,{recursive:true,force:true});}
});

test('clean state and offline restart translate both languages with zero AI calls and preserve corrections', async () => {
  const {TranslationBroker} = await import('../broker.mjs');
  const {applyStaticDictionaryRows, staticDictionaryFiles} = await import('../server.mjs');
  const config = JSON.parse(await readFile(join(packageRoot, 'broker/config.json'), 'utf8'));
  const state = await mkdtemp(join(tmpdir(), 'df-single-package-'));
  let aiCalls = 0;
  try {
    for (const language of ['zh-Hant', 'zh-Hans']) for (let restart=0; restart<2; restart++) {
      const broker = new TranslationBroker({directory: join(state, language), language,
        provider: async () => { aiCalls++; throw new Error('No API or network'); }});
      await broker.load();
      const files = staticDictionaryFiles(config, language);
      assert.ok(files.length > 0);
      for (const file of files) {
        const rows = parse(await readFile(join(packageRoot, 'broker', file), 'utf8'), {columns:true, bom:true, skip_empty_lines:true});
        applyStaticDictionaryRows(broker, rows, {literal: config.literalDictionaries.includes(file)});
      }
      const source = 'Change to standard dig mode.';
      assert.equal(await broker.translate(source), language === 'zh-Hant' ? '切換至一般挖掘模式。' : '切换至一般挖掘模式。');
      broker.fixed.set(source, language === 'zh-Hant' ? '自訂挖掘修正。' : '自订挖掘修正。');
      assert.equal(await broker.translate(source), language === 'zh-Hant' ? '自訂挖掘修正。' : '自订挖掘修正。');
      await broker.writes;
    }
    assert.equal(aiCalls, 0);
  } finally { await rm(state, {recursive:true, force:true}); }
});
