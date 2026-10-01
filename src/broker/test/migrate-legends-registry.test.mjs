import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const script=fileURLToPath(new URL('../migrate-legends-registry.mjs',import.meta.url));

test('migration verifies live native aliases and preserves registry content',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'df-registry-migrate-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const registry=join(dir,'world.json'),audit=join(dir,'audit.json');
  const original={world:'region1',entities:[
    {id:'site:1',aliases:['Kacufensast','Dripscarred'],preferred:'Dripscarred'},
    {id:'artifact:2',aliases:['Ithbi','The Sword'],preferred:'The Sword'},
    {id:'figure:3',aliases:['Imust','I Must'],preferred:'I Must',nativeName:'Imust'},
    {id:'written_content:4',aliases:['The Book'],preferred:'The Book'},
  ]};
  await writeFile(registry,JSON.stringify(original));
  await writeFile(audit,JSON.stringify({world:'region1',samples:[
    {id:'site:1',native:'Kacufensast'},
    {id:'artifact:2',native:'Ithbi'},
  ]}));
  const run=(...args)=>execFileSync(process.execPath,[script,registry,audit,...args],{encoding:'utf8'});
  assert.match(run(),/"updated":2/);
  assert.deepEqual(JSON.parse(await readFile(registry,'utf8')),original,'dry run must not write');
  assert.match(run('--apply'),/"updated":2/);
  const result=JSON.parse(await readFile(registry,'utf8'));
  assert.equal(result.entities[0].nativeName,'Kacufensast');
  assert.equal(result.entities[1].nativeName,'Ithbi');
  assert.deepEqual(result.entities.map(({nativeName,...row})=>row),
    original.entities.map(({nativeName,...row})=>row));
  assert.equal(result.entities[2].nativeName,'Imust');
  assert.equal(result.entities[3].nativeName,undefined);
  assert.deepEqual(JSON.parse(await readFile(registry+'.before-native-list','utf8')),original);
  await writeFile(audit,JSON.stringify({world:'region1',samples:[{id:'site:1',native:'Wrong'}]}));
  assert.throws(()=>run(),/alias mismatch/);
});
