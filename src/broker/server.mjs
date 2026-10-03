import { createServer } from 'node:http';
import { readFile, appendFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { TranslationBroker } from './broker.mjs';
import { readProviderProfile } from './provider.mjs';
import {createProviderPool} from './provider-pool.mjs';
import { parse } from 'csv-parse/sync';
import { cacheKey, mentionsTerm, validateTranslation, POLICY_VERSION, safeReason } from './safety.mjs';
import { WorldNames } from './names.mjs';
import { RuntimeQueue } from './runtime-queue.mjs';
import { loadDescriptionGlossary } from './description-terms.mjs';
import { translateParagraph } from './rich-text.mjs';
import { NativePrewarmExporter } from './native-prewarm.mjs';
import { StatusBridge } from './status.mjs';
import { SettingsStore, SettingsService,worldKey } from './settings.mjs';
import {SharedOutbox} from './shared-outbox.mjs';
import { simplifyTree } from './language-data.mjs';
import { loadEquipmentTerms } from './equipment-names.mjs';
import {OfficialLibrary} from './official-library.mjs';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const gameClosed=async()=>{
  if(process.platform!=='win32') return false;
  try {const {stdout}=await promisify(execFile)('powershell.exe',['-NoProfile','-Command',"@(Get-Process | Where-Object {$_.ProcessName -eq 'Dwarf Fortress'}).Count"],{windowsHide:true,timeout:5000});return stdout.trim()==='0';}catch{return false;}
};

// Workshop runtime files live in the state root, while DFHack's exported
// world registry lives in its data subdirectory. The development checkout
// keeps both files directly under broker/data.
export function worldNamesPath(directory, stateDirectory) {
  return stateDirectory ? join(directory, 'data', 'world-names.json') :
    join(directory, 'world-names.json');
}

export function runtimeDataPath(directory, stateDirectory) {
  return stateDirectory ? join(directory, 'data') : directory;
}

export function applyStaticDictionaryRows(broker, rows, { literal = false } = {}) {
  const accepted = [];
  for (const row of rows) {
    const conflicts = Object.entries(broker.glossary).some(([name, translation]) =>
      mentionsTerm(row.text, name) && !row.translation.includes(translation));
    if (!conflicts) {
      const translation = validateTranslation(row.text, row.translation);
      broker.cache.set(cacheKey(row.text, broker.language), translation);
      (broker.builtin ??= new Map()).set(row.text, translation);
      if (literal) broker.literalStatic.set(row.text, translation);
      if((row.tags ?? '').includes('[CREATURE:1]')) broker.creatureNames.set(row.text,translation);
      accepted.push(row);
    }
  }
  return accepted;
}

export function staticDictionaryFiles(config, language) {
  const legacy = !config.staticDictionaryLanguage || config.staticDictionaryLanguage === language
    ? [...(config.staticDictionaries ?? []), config.reviewedDictionary] : [];
  const files = new Set([...legacy, ...(config.staticDictionariesByLanguage?.[language] ?? [])].filter(Boolean));
  const reviewedUi = `data/fortress-ui${language === 'zh-Hans' ? '-zh-Hans' : ''}.csv`;
  if (files.delete(reviewedUi)) files.add(reviewedUi);
  const corrections=`data/arena-corrections-${language}.csv`;
  if (files.delete(corrections)) files.add(corrections);
  return [...files];
}

export function createBrokerServer(broker, { auditPath, runtimeQueue, selectBroker, activeBroker } = {}) {
  return createServer(async (req, res) => {
    const respond = (status, payload) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify(payload));
    };
    if (req.url === '/health' && req.method === 'GET') {
      const active=activeBroker ? await activeBroker() : broker;
      return respond(200, { service: 'df-local-zh', policy: POLICY_VERSION, language: active.language, providerConfigured: Boolean(active.provider), cached: active.cache.size, pending: active.pending.size, ...active.stats,
        ...(active.provider?.batchStats ? {providerBatch:{...active.provider.batchStats}} : {}),
        ...(active.provider?.poolStats ? {providerPool:active.provider.poolStats} : {}),
        scheduling:active.scheduling(),official:active.official?.status(active.language),shared:active.shared?.status(),
        ...(runtimeQueue ? { runtime: { ...runtimeQueue.stats, unresolved: runtimeQueue.failures.size,
          queued:runtimeQueue.jobs.size,active:runtimeQueue.activeJobs.size } } : {}) });
    }
    if (!['/v2/translate', '/v2/pin-figure'].includes(req.url) || req.method !== 'POST') {
      return respond(404, { error: 'unknown route' });
    }
    if (req.headers.origin) return respond(403, { error: 'browser requests disabled' });
    let size = 0;
    const chunks = [];
    try {
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 32768) { respond(413, { error: 'request too large' }); req.resume(); return; }
        chunks.push(chunk);
      }
      let payload;
      try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { return respond(400, { error: 'invalid JSON' }); }
      if (payload.language !== undefined && !['zh-Hant', 'zh-Hans'].includes(payload.language)) {
        return respond(400, { error: 'unsupported language' });
      }
      if (payload.world !== undefined && (typeof payload.world !== 'string' || payload.world.length > 1024 || payload.world.includes('\0'))) {
        return respond(400, { error: 'invalid world' });
      }
      if (req.url === '/v2/pin-figure') {
        if (typeof payload.id !== 'string' || !/^figure:\d+$/.test(payload.id)) {
          return respond(400, { error: 'invalid figure ID' });
        }
        if (!broker.pinFigure) return respond(404, { error: 'figure registry unavailable' });
        try {
          const translation = await broker.pinFigure(payload.id);
          return translation ? respond(200, { translation }) : respond(404, { error: 'unknown figure' });
        } catch (error) {
          return respond(503, { error: safeReason(error) });
        }
      }
      if (typeof payload.text !== 'string' || !payload.text.trim() || payload.text.length > 8000) return respond(400, { error: 'invalid text' });
      try {
        const defaultBroker=activeBroker ? await activeBroker() : broker;
        const selected = selectBroker ? await selectBroker(payload.language ?? defaultBroker.language, payload.world ?? '') : broker;
        if (!selected || selected.language !== (payload.language ?? defaultBroker.language)) {
          return respond(503, { error: 'language is unavailable' });
        }
        const translation = await selected.withPriority('foreground',()=>selected.translate(payload.text),
          payload.text,{batch:payload.text.length<=1000});
        respond(200, { translation });
      } catch (error) {
        if (auditPath) await appendFile(auditPath, JSON.stringify({ text: payload.text, reason: safeReason(error), timestamp: new Date().toISOString() }) + '\n', 'utf8').catch(() => {});
        respond(503, { error: safeReason(error) });
      }
    } catch { if (!res.headersSent) respond(400, { error: 'request interrupted' }); }
  });
}

export async function start(configPath = join(dirname(fileURLToPath(import.meta.url)), 'config.json'), stateDirectory) {
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const configDirectory = dirname(configPath);
  const staticDirectory = resolve(configDirectory, config.staticDataDirectory ?? '.');
  const requestedState = stateDirectory ?? process.env.DF_LOCAL_ZH_STATE_DIRECTORY;
  if (requestedState) config.dataDirectory = requestedState;
  if (!config.rimworldConfig && process.env.DF_LOCAL_ZH_RIMWORLD_CONFIG) {
    config.rimworldConfig = process.env.DF_LOCAL_ZH_RIMWORLD_CONFIG;
  }
  const directory = resolve(configDirectory, config.dataDirectory ?? 'data');
  const runtimeDirectory = runtimeDataPath(directory, requestedState);
  const settingsStore=new SettingsStore(directory);
  settingsStore.document.defaults.language=config.language ?? 'zh-Hant';
  await settingsStore.load(await readProviderProfile(config));
  let settingsService;
  const shared=new SharedOutbox({directory,isEnabled:scope=>settingsStore.effective(scope).sharedContributions===true,
    statusScope:()=>worldKey(settingsService?.currentWorld ?? '')});
  await shared.load();
  const official=new OfficialLibrary({directory,canActivate:gameClosed});
  await official.load(); // Local verification only. Startup never waits for a network request.
  const descriptionGlossary = config.descriptionInventory && config.raceMap
    ? await loadDescriptionGlossary(resolve(staticDirectory, config.descriptionInventory),
      resolve(staticDirectory, config.raceMap)) : new Map();
  let dictionary = {};
  try { dictionary = JSON.parse(await readFile(join(staticDirectory, 'name-dictionary.json'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const raceMap = config.raceMap ? JSON.parse(await readFile(
    resolve(staticDirectory, config.raceMap), 'utf8')) : { races: {} };
  const originalRaces = Object.fromEntries(Object.values(raceMap.races)
    .map(row => [row.source, row.translation]));
  const contexts=new Map();
  const activeWorld=()=>settingsService?.currentWorld ?? names.world ?? '';
  const configure=async(context,world='')=>{
    const settings=settingsStore.effective(world);
    const ids=settings.apiPoolEnabled ? settings.apiProfiles : [settings.apiProfile];
    const profiles=ids.map(id=>({id,profile:settingsStore.profiles.profiles[id] && {
      ...settingsStore.profiles.profiles[id],
      // Existing single-API installations used the total setting as their limit.
      ...(!settings.apiPoolEnabled ? {concurrency:settings.concurrency} : {}),
    }}));
    const signature=JSON.stringify([settings,profiles,worldKey(world)]);
    if(signature===context.settingsSignature) return context.broker;
    const previous=context.configuring ?? Promise.resolve();
    const work=previous.catch(()=>{}).then(async()=>{
      if(signature===context.settingsSignature) return context.broker;
      const broker=context.broker;
      const modelClaims=[...new Set(profiles.filter(row=>row.profile?.enabled).map(row=>row.profile.model))];
      const model=modelClaims.length===1 && /^[A-Za-z0-9_/.@:+-]{1,100}$/.test(modelClaims[0]) ? modelClaims[0] : 'configured-provider-pool';
      const scope=worldKey(world);
      broker.captureShared=settings.sharedContributions ? (text,translation,kind)=>shared.capture({schema:1,rules:POLICY_VERSION,
        language:broker.language,context:'general',kind,origin:'vanilla',text,translation,model,license:'CC0-1.0'},scope) : undefined;
      broker.concurrency=settings.concurrency;
      broker.configuredBackgroundPaused=!settings.backgroundTranslation;
      broker.backgroundPaused=broker.configuredBackgroundPaused;
      broker.provider=settings.apiEnabled ? await createProviderPool({
        profiles,glossary:{...broker.glossary,...broker.gameplayGlossary},concurrency:settings.concurrency,
        translationPrompt:settings.translationPrompt,
        timeoutMs:settings.timeoutMs,maxRetries:settings.maxRetries,retryBaseMs:settings.retryBaseMs,
      }) : null;
      context.settingsSignature=signature;broker.dispatch();return broker;
    });
    context.configuring=work;
    return work;
  };
  async function contextFor(language) {
    if(!['zh-Hant','zh-Hans'].includes(language)) throw new Error('unsupported language');
    if(contexts.has(language)) return contexts.get(language);
    const building=(async()=>{
      const convert=value=>language==='zh-Hans' ? simplifyTree(value) : value;
      const glossaryPath=config.glossaryPathsByLanguage?.[language] ?? config.glossaryPath;
      const glossary=glossaryPath ? convert(JSON.parse(await readFile(resolve(staticDirectory,glossaryPath),'utf8'))) : convert(config.glossary ?? {});
      const gameplayGlossary=config.gameplayGlossaryPath ? convert(JSON.parse(await readFile(resolve(staticDirectory,config.gameplayGlossaryPath),'utf8'))) : {};
      const broker=new TranslationBroker({directory,language,glossary,gameplayGlossary,
        descriptionGlossary:new Map([...descriptionGlossary].map(([key,value])=>[key,convert(value)]))});
      broker.official=official;
      broker.shared=shared;
      try {
        const pins=JSON.parse(await readFile(join(directory,`fixed-${language}.json`),'utf8'));
        for(const [text,value] of Object.entries(pins)) broker.fixed.set(text,validateTranslation(text,value));
      }catch(error){if(error.code!=='ENOENT') throw new Error('invalid fixed translation file');}
      if(config.equipmentRulesDirectory) broker.equipmentTerms=await loadEquipmentTerms(resolve(
        staticDirectory,config.equipmentRulesDirectory,language));
      await broker.load();
      const names=new WorldNames(worldNamesPath(directory,requestedState),convert(dictionary));
      const races=convert(originalRaces);
      broker.resolveNames=source=>names.resolve(source,broker);
      broker.matchNames=source=>names.match(source);
      broker.pinFigure=id=>names.pinFigure(id,broker);
      const staticRows=[{text:'will only do assigned tasks',translation:convert('只會執行指派的工作')}],literalRows=[];
      for(const file of staticDictionaryFiles(config,language)) {
        const rows=parse(await readFile(resolve(staticDirectory,file),'utf8'),{columns:true,skip_empty_lines:true,bom:true});
        const literal=['data/community-reviewed.csv','data/fortress-ui.csv',...(config.literalDictionaries ?? [])].includes(file);
        const accepted=applyStaticDictionaryRows(broker,rows,{literal});staticRows.push(...accepted);
        if(literal) literalRows.push(...accepted);
      }
      const context={broker,names,races,staticRows,literalRows};await configure(context);
      return context;
    })();
    contexts.set(language,building);
    try {return await building;} catch(error) {contexts.delete(language);throw error;}
  }
  const selectBroker=async(language,world)=>{
    if(world && settingsService?.currentWorld!==undefined && world!==settingsService.currentWorld) {
      throw new Error('translation world changed');
    }
    return configure(await contextFor(language),world);
  };
  const initial=await contextFor(settingsStore.effective('').language);
  const {broker,names}=initial;
  const runtimeQueue = new RuntimeQueue({ directory: runtimeDirectory,
    lookupCached:async(source,row)=>{
      const context=await contextFor(row.language ?? 'zh-Hant');
      await context.names.refresh(context.broker);
      return context.broker.peekCached(source);
    },
    translate: async(source,row)=>{
      const context=await contextFor(row.language ?? 'zh-Hant');
      const selected=await configure(context,row.world);
      return selected.withPriority(row.priority,()=>row.kind==='legends-paragraph' ?
        translateParagraph(row,context.names,selected) : row.kind==='legends-name' ?
        context.names.translateListName(row,selected) : row.figureId===undefined ?
        selected.translate(source) : context.names.translateCaption(row,selected,context.races),source,
        {batch:row.kind==='legends-paragraph' || row.kind==='legends-name' || row.figureId!==undefined || source.length<=1000});
    },
    isBatchable:row=>row.kind==='legends-paragraph' || row.kind==='legends-name' || row.figureId!==undefined || row.text.length<=1000,
    visibleOnly:true,
    promote:source=>broker.promoteSource(source),
    canBackground:row=>settingsStore.effective(row.world).backgroundTranslation && settingsStore.effective(row.world).apiEnabled,
    limits:row=>settingsStore.effective(row.world),
    accept:row=>(row.figureId===undefined && !['legends-paragraph','legends-name'].includes(row.kind)) ||
      row.namePolicy==='native-v2',
    foregroundBusy:()=> {const s=broker.scheduling();return s.foregroundActive+s.foregroundQueued>0;},
    currentWorld: async () => { await names.refresh(broker); return activeWorld(); },
  });
  await runtimeQueue.load();
  const activeBroker=async()=>{
    await names.refresh(broker);
    const world=activeWorld();
    return selectBroker(settingsStore.effective(world).language,world);
  };
  const server = createBrokerServer(broker, { auditPath: join(runtimeDirectory, 'unresolved.jsonl'), runtimeQueue,selectBroker,activeBroker });
  const port = config.port ?? 19753;
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
  const statusBridge=new StatusBridge(runtimeDirectory,broker,runtimeQueue,activeWorld);
  const updateSettings=async()=>{
    await names.refresh(broker);
    for(const value of contexts.values()) await configure(await value,activeWorld());
    const active=await contextFor(settingsStore.effective(activeWorld()).language);
    statusBridge.broker=active.broker;
    runtimeQueue.backgroundPaused=!settingsStore.effective(activeWorld()).backgroundTranslation;
    await statusBridge.publish();
    official.checkAuto?.();
    shared.consentChanged();
    await shared.publish(worldKey(activeWorld()));
  };
  settingsService=new SettingsService(settingsStore,{onApply:updateSettings,onSync:language=>{void official.sync(language).catch(()=>{});},onClearShared:()=>shared.clear(),onClearOfficial:()=>official.clear()});
  await settingsService.refreshContext();
  settingsService.start();
  official.start(()=>settingsStore.effective(activeWorld()));
  shared.start();server.on('close',()=>shared.stop());
  server.on('close',()=>official.stop());
  statusBridge.beforePublish=async()=>{statusBridge.broker=await activeBroker();};
  await statusBridge.publish();
  runtimeQueue.start();
  statusBridge.start();
  server.on('close',()=>statusBridge.stop());
  server.on('close',()=>settingsService.stop());
  if(process.env.DF_LOCAL_ZH_GAME_ROOT) {
    const nativePrewarm=new NativePrewarmExporter({
      cachePath:join(process.env.DF_LOCAL_ZH_GAME_ROOT,'dfi18n-data','cache','translation-cache.csv'),
      registryPath:worldNamesPath(directory,requestedState),directory:runtimeDirectory,
      staticRows:initial.staticRows,literalRows:initial.literalRows,
    });
    nativePrewarm.start();
    server.on('close',()=>nativePrewarm.stop());
  }
  server.on('close', () => runtimeQueue.stop());
  console.log(`DF translation broker: http://127.0.0.1:${port}; language=${broker.language}; cache=${broker.cache.size}; provider=${Boolean(broker.provider)}`);
  return { server, broker, runtimeQueue, statusBridge,settingsStore,settingsService,selectBroker };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  start(process.argv[2], process.argv[3]).catch(() => { console.error('Broker startup failed. Check local configuration and port availability.'); process.exitCode = 1; });
}
