import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp,writeFile,readFile,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { stringify } from 'csv-stringify/sync';
import { nativePrewarmRows,unitDisplayRows,NativePrewarmExporter } from '../native-prewarm.mjs';

const row=(original,translation,extra={})=>({version:'2',fingerprint:'current',source:'local',
  language:'zh-Hant',kind:'plain',rules_first:'false',original,status:'translated',translation,alignment:'left',...extra});

test('unit restart reads a compact export without the bulk native rows',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'df-native-unit-export-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const cachePath=join(dir,'cache.csv'),registryPath=join(dir,'world.json');
  await writeFile(registryPath,JSON.stringify({world:'one',entities:[]}));
  await writeFile(cachePath,stringify([row('She enjoys company.','她喜歡有人陪伴。'),row('Bulk tooltip','大量提示')],{header:true}));
  await new NativePrewarmExporter({cachePath,registryPath,directory:dir}).refresh();
  for(const [file,want] of [['native-prewarm-unit.json','她喜歡有人陪伴。'],['native-prewarm-unit-zh-Hans.json','她喜欢有人陪伴。']]) {
    const compact=JSON.parse(await readFile(join(dir,file),'utf8').catch(e=>{if(e.code==='ENOENT')return '{}';throw e;}));
    assert.equal(compact.world,'one');assert.equal(compact.rows,undefined);
    assert.equal(compact.unit.sources[0].translation,want);
  }
});

test('reviewed local phrases prewarm before any hover and native updates win',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'df-static-native-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const cachePath=join(dir,'cache.csv'),registryPath=join(dir,'world.json');
  await writeFile(registryPath,JSON.stringify({world:'one',entities:[]}));
  await writeFile(cachePath,stringify([row('Clay','黏土')],{header:true}));
  const exporter=new NativePrewarmExporter({cachePath,registryPath,directory:dir,
    staticRows:[{text:'Make wooden bed',translation:'製作木床'},
      {text:'Clay',translation:'泥土'}]});
  await exporter.refresh();
  const data=JSON.parse(await readFile(join(dir,'native-prewarm.json'),'utf8'));
  assert.equal(data.rows.find(row=>row.text==='Make wooden bed')?.translation,'製作木床');
  assert.equal(data.rows.find(row=>row.text==='Clay')?.translation,'黏土');
});
test('reviewed literal correction wins over a stale native cache entry',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'df-literal-native-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const cachePath=join(dir,'cache.csv'),registryPath=join(dir,'world.json');
  await writeFile(registryPath,JSON.stringify({world:'one',entities:[]}));
  await writeFile(cachePath,stringify([row('Color goldenrod items','金菊色物品')],{header:true}));
  const exporter=new NativePrewarmExporter({cachePath,registryPath,directory:dir,
    staticRows:[{text:'Color goldenrod items',translation:'金麒麟黃色物品'}],
    literalRows:[{text:'Color goldenrod items',translation:'金麒麟黃色物品'}]});
  await exporter.refresh();
  const data=JSON.parse(await readFile(join(dir,'native-prewarm.json'),'utf8'));
  assert.equal(data.rows.find(row=>row.text==='Color goldenrod items')?.translation,'金麒麟黃色物品');
});
test('native preload keeps validated concrete text and excludes aliases, unit prose and entity names',()=>{
  const result=nativePrewarmRows([
    row('Rice plants, rice leaves','稻米植株，稻米葉'),
    row('Macadamia tree Sapling','奶油果樹樹苗'),
    row('Old ground','舊地面',{fingerprint:'old'}),
    row('Missing ground','',{status:'missing'}),row('Mixed','Mixed 中文'),
    row('L000123_____','別名'),row('[C:7:0:1]L000123_____','[C:7:0:1]別名'),
    row('{DWARF_NAME} likes chicory.','{DWARF_NAME}喜歡菊苣。'),
    row('Doren Ushatesis','錯誤姓名'),row('She needs company.','她需要陪伴。'),
    row('2 stones','3顆石頭'),row('Damp Stone','潮濕石頭',{language:'zh-Hans'}),
    row('[C:7:0:1]Granite','[C:7:0:1]花崗岩',{kind:'markup'}),
  ],new Set(['Doren Ushatesis']));
  assert.deepEqual(result.map(r=>r.text),['[C:7:0:1]Granite','Macadamia tree Sapling','Rice plants, rice leaves']);
});

test('latest source result wins and an invalid update cannot resurrect an older translation',()=>{
  assert.deepEqual(nativePrewarmRows([row('Clay','泥土'),row('Clay','黏土')],new Set()),
    [{text:'Clay',translation:'黏土',kind:'plain'}]);
  assert.deepEqual(nativePrewarmRows([row('Clay','泥土'),row('Clay','',{status:'missing'})],new Set()),[]);
  assert.equal(nativePrewarmRows([row('Centered title','置中標題',{alignment:'center'})])[0].alignment,'center');
});

test('unit restart preparation restores known prose, exact names and completed colored fragments',()=>{
  const result=unitDisplayRows([
    row('She enjoys company.','她喜歡有人陪伴。'),
    row('Doren Ushatesis','多雷 烏夏特埃錫斯'),
    row('Doren Ushatesis likes chicory.','多倫喜歡菊苣。'),
    row('[C:7:0:1]L000123_____','[C:7:0:1]她喜歡有人陪伴。',{kind:'markup'}),
    row('[C:7:0:1]L000124_____','[C:7:0:1]她喜歡有人陪伴。',{kind:'markup'}),
    row('[C:7:0:1]L000125_____','[C:7:0:1]Old 中文',{kind:'markup'}),
    row('[C:2:0:0]L000126_____','[C:7:0:1]錯誤顏色',{kind:'markup'}),
    row('He enjoys company.','他喜歡有人陪伴。',{fingerprint:'old'}),
    row('She needs company.','她需要陪伴。'),
    row('She needs company.','',{status:'missing'}),
  ],new Set(['Doren Ushatesis']));
  assert.deepEqual(result,{
    sources:[{text:'She enjoys company.',translation:'她喜歡有人陪伴。'}],
    names:[{text:'Doren Ushatesis',translation:'多雷 烏夏特埃錫斯'}],
    fragments:[{translation:'她喜歡有人陪伴。',color:71,key:'L000124_____'}],
  });
});

test('plain native color records retain their completed display alias across restart',()=>{
  const result=unitDisplayRows([
    row('[C:3:2:1]L000321___','[C:3:2:1]已有譯文'),
    row('[C:3:2:1]L000322___','[C:3:2:1]English 中文'),
  ]);
  assert.deepEqual(result.fragments,[{translation:'已有譯文',color:83,key:'L000321___'}]);
});

test('export refreshes new translations, isolates world revisions and ignores interrupted files',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'df-native-prewarm-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const cachePath=join(dir,'cache.csv'),registryPath=join(dir,'world.json');
  const writeCache=rows=>writeFile(cachePath,stringify(rows,{header:true}));
  await writeFile(registryPath,JSON.stringify({world:'one',entities:[]}));
  await writeCache([row('Clay','黏土')]);
  const exporter=new NativePrewarmExporter({cachePath,registryPath,directory:dir});
  assert.equal((await exporter.refresh()).rows,1);
  const first=JSON.parse(await readFile(join(dir,'native-prewarm.json'),'utf8'));
  await writeCache([row('Clay','黏土'),row('Sand','沙土')]);
  assert.equal((await exporter.refresh()).rows,2);
  const second=JSON.parse(await readFile(join(dir,'native-prewarm.json'),'utf8'));
  assert.notEqual(second.revision,first.revision);
  await writeFile(cachePath,'version,fingerprint\n"unfinished');
  await assert.rejects(exporter.refresh());
  assert.deepEqual(JSON.parse(await readFile(join(dir,'native-prewarm.json'),'utf8')),second);
  await writeCache([row('Clay','黏土')]);
  await writeFile(registryPath,JSON.stringify({world:'two',entities:[]}));
  await exporter.refresh();
  const third=JSON.parse(await readFile(join(dir,'native-prewarm.json'),'utf8'));
  assert.equal(third.world,'two');assert.notEqual(third.revision,first.revision);
});
