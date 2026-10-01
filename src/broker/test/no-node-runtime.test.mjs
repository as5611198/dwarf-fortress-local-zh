import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=process.env.DF_LOCAL_ZH_PACKAGE_TEST_ROOT ?? fileURLToPath(new URL('../../../distribution/steam/df-local-zh-complete/',import.meta.url));
test('Steam network runtime is Rust and requires no installed Node',async()=>{
  assert.ok((await stat(join(root,'broker/df-local-zh-broker.exe')).catch(()=>null))?.isFile(),'missing bundled Rust Broker');
  const manifest=JSON.parse(await readFile(join(root,'PACKAGE-MANIFEST.json'),'utf8'));
  assert.equal(manifest.runtime,'rust');
  assert.equal(manifest.requiresNode,false);
  assert.ok(!manifest.files.some(f=>/node_modules|\.mjs$|Start-Broker\.ps1$/.test(f.path)));
});
