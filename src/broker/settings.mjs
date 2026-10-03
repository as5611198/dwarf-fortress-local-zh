import {DEFAULT_TRANSLATION_PROMPT} from './prompts.mjs';
import {readClipboardText} from './clipboard.mjs';
export const DEFAULT_SETTINGS = Object.freeze({
  language: 'zh-Hant', pinyin: true, colorPersistence: true, apiEnabled: true,
  apiProfile: 'legacy', apiProfiles: Object.freeze([]), apiPoolEnabled:false, backgroundTranslation: true, concurrency: 2,
  timeoutMs: 25000, maxRetries: 2, retryBaseMs: 1000,
  translationPrompt: '',
  officialAutoDownload: true,
  sharedContributions: false,
});

const plain = value => value && typeof value === 'object' && !Array.isArray(value);
const profileId = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,48}$/.test(value) &&
  !['__proto__', 'constructor', 'prototype'].includes(value);
const integerFields = { concurrency: [1,32], timeoutMs: [1000,120000], maxRetries: [0,5], retryBaseMs: [100,30000] };

function overrides(value = {}) {
  if (!plain(value)) throw new Error('settings must be an object');
  const result = {};
  for (const [key, input] of Object.entries(value)) {
    if (!Object.hasOwn(DEFAULT_SETTINGS, key)) throw new Error('unknown settings field');
    if (key === 'language') {
      if (!['zh-Hant', 'zh-Hans'].includes(input)) throw new Error('unsupported language');
    } else if (key === 'apiProfile') {
      if (!profileId(input)) throw new Error('invalid API profile ID');
    } else if (key === 'apiProfiles') {
      if(!Array.isArray(input) || input.length>16 || input.some(id=>!profileId(id)) || new Set(input).size!==input.length) throw new Error('invalid API profile list');
    } else if (key === 'translationPrompt') {
      if(typeof input!=='string' || input.length>8192 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(input)) throw new Error('invalid translation prompt');
    } else if (integerFields[key]) {
      const [minimum, maximum] = integerFields[key];
      if (!Number.isSafeInteger(input) || input < minimum || input > maximum) throw new Error(`invalid ${key}`);
    } else if (typeof input !== 'boolean') throw new Error(`invalid ${key}`);
    result[key] = Array.isArray(input) ? [...input] : input;
  }
  if(Object.hasOwn(value,'apiProfiles') && !Object.hasOwn(value,'apiPoolEnabled')) result.apiPoolEnabled=true;
  return result;
}

export function worldKey(path = '') {
  return String(path).replace(/[\\/]+$/, '').split(/[\\/]/).at(-1) ?? '';
}

export function validateSettings(document) {
  if (!plain(document) || document.version !== 1) throw new Error('unsupported settings version');
  if (Object.keys(document).some(key => !['version', 'defaults', 'saves'].includes(key))) throw new Error('unknown settings document field');
  const saves = {};
  if (document.saves !== undefined && !plain(document.saves)) throw new Error('save settings must be an object');
  for (const [id, value] of Object.entries(document.saves ?? {})) {
    if (!id || id.length > 128 || /[\\/\0]/.test(id) || ['__proto__', 'constructor', 'prototype'].includes(id)) {
      throw new Error('invalid save ID');
    }
    saves[id] = overrides(value);
  }
  return { version: 1, defaults: { ...DEFAULT_SETTINGS, ...overrides(document.defaults) }, saves };
}

export function effectiveSettings(document, world) {
  return { ...document.defaults, ...(document.saves[worldKey(world)] ?? {}) };
}

export function validateProfiles(document) {
  if (!plain(document) || document.version !== 1 || !plain(document.profiles)) throw new Error('invalid API profiles document');
  const profiles = {};
  for (const [id, input] of Object.entries(document.profiles)) {
    if (!profileId(id) || !plain(input)) throw new Error('invalid API profile');
    if (Object.keys(input).some(key => !['label','enabled','kind','baseUrl','model','key','inheritLegacy','concurrency'].includes(key))) {
      throw new Error('unknown API profile field');
    }
    const profile = { label: id, enabled: true, kind: 'Custom_OpenAI', baseUrl: '', model: '', key: '',
      inheritLegacy: false, concurrency: 2, ...input };
    if(!Number.isSafeInteger(profile.concurrency) || profile.concurrency<1 || profile.concurrency>16) throw new Error('invalid API concurrency');
    for (const [field, limit] of Object.entries({ label: 80, kind: 40, baseUrl: 2048, model: 200, key: 8192 })) {
      if (typeof profile[field] !== 'string' || profile[field].length > limit || /[\x00-\x1f]/.test(profile[field])) {
        throw new Error(`invalid API ${field}`);
      }
    }
    if (typeof profile.enabled !== 'boolean' || typeof profile.inheritLegacy !== 'boolean') throw new Error('invalid API profile flags');
    if (profile.baseUrl) {
      const url = new URL(profile.baseUrl);
      if (url.username || url.password || url.search || url.hash ||
        url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname))) {
        throw new Error('API URL requires HTTPS or loopback without URL credentials');
      }
    }
    if (profile.enabled && !profile.inheritLegacy && (!profile.baseUrl || !profile.model)) throw new Error('API URL/model missing');
    profiles[id] = profile;
  }
  return { version: 1, profiles };
}

export function publicProfile(profile) {
  if (!profile) return { enabled: false, hasKey: false };
  return { label: profile.label, enabled: profile.enabled, kind: profile.kind,
    baseUrl: profile.baseUrl, model: profile.model, concurrency:profile.concurrency, hasKey: Boolean(profile.key) };
}
import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { watch } from 'node:fs';
import { createProvider } from './provider.mjs';


export async function atomicJson(path, value) {
  const temporary=path+`.${process.pid}.tmp`;
  await writeFile(temporary, JSON.stringify(value)+'\n', {encoding:'utf8',mode:0o600});
  await rename(temporary,path);
}

export class SettingsStore {
  constructor(directory) {
    this.directory=directory;
    this.document=validateSettings({version:1});
    this.profiles=validateProfiles({version:1,profiles:{legacy:{enabled:false}}});
    this.writes=Promise.resolve();
  }
  async load(legacy) {
    await mkdir(this.directory,{recursive:true});
    let existingSettings=false;
    try { this.document=validateSettings(JSON.parse(await readFile(join(this.directory,'settings.json'),'utf8')));existingSettings=true; }
    catch(error) { if(error.code!=='ENOENT') throw new Error('invalid local settings file'); }
    try { this.profiles=validateProfiles(JSON.parse(await readFile(join(this.directory,'api-profiles.private.json'),'utf8'))); }
    catch(error) {
      if(error.code!=='ENOENT') throw new Error('invalid private API profiles file');
      const {keyEnv,...legacyFields}=legacy ?? {};
      this.profiles=validateProfiles({version:1,profiles:{legacy:legacy ? {
        label:'Existing API',enabled:true,...legacyFields,
        key:keyEnv ? process.env[keyEnv] ?? '' : legacy.key ?? '',
      } : {label:'Existing API',enabled:false}}});
      await atomicJson(join(this.directory,'api-profiles.private.json'),this.profiles);
    }
    // New defaults are merged in memory. A service restart must preserve private settings bytes.
    if(!existingSettings) await atomicJson(join(this.directory,'settings.json'),this.document);
    await this.publish();
  }
  effective(world='') { return effectiveSettings(this.document,world); }
  snapshot(world='') {
    return {version:1,document:this.document,effective:this.effective(world),
      promptDefaults:{translation:DEFAULT_TRANSLATION_PROMPT},
      world:worldKey(world),profiles:Object.fromEntries(Object.entries(this.profiles.profiles)
        .map(([id,profile])=>[id,publicProfile(profile)]))};
  }
  draftProfile(update) {
    if(!plain(update) || !profileId(update.id)) throw new Error('invalid API profile ID');
    const {id,clearKey,...fields}=update;
    const previous=this.profiles.profiles[id] ?? {label:id,enabled:false};
    if(clearKey!==undefined && typeof clearKey!=='boolean') throw new Error('invalid clear key flag');
    if(clearKey) fields.key='';
    const profile=validateProfiles({version:1,profiles:{[id]:{...previous,...fields,inheritLegacy:false}}}).profiles[id];
    return {id,profile};
  }
  apply(change) {
    const work=this.writes.then(()=>this.update(change));
    this.writes=work.catch(()=>{});return work;
  }
  async update({scope,world='',settings={},profile,profiles:updates=[],deleteProfiles=[],reset=false}) {
    if(!['save','global'].includes(scope)) throw new Error('invalid settings scope');
    const save=worldKey(world);
    if(scope==='save' && !save) throw new Error('save settings require a loaded world');
    const document=structuredClone(this.document),profiles=structuredClone(this.profiles);
    if(!Array.isArray(deleteProfiles) || deleteProfiles.length>16 ||
      deleteProfiles.some(id=>!profileId(id) || !Object.hasOwn(profiles.profiles,id)) ||
      new Set(deleteProfiles).size!==deleteProfiles.length) throw new Error('invalid profile deletions');
    const deleted=new Set(deleteProfiles);
    if(!Array.isArray(updates) || updates.length>16) throw new Error('invalid profile updates');
    for(const update of [...updates,...(profile ? [profile] : [])]) {
      if(deleted.has(update?.id)) throw new Error('cannot update a deleted profile');
      const draft=this.draftProfile(update);profiles.profiles[draft.id]=draft.profile;
    }
    const values=overrides(settings);
    if(scope==='global') document.defaults={...document.defaults,...values};
    else if(reset) {
      if(Object.keys(values).length) document.saves[save]=values;
      else delete document.saves[save];
    }
    else document.saves[save]={...(document.saves[save] ?? {}),...values};
    const transitional=structuredClone(profiles);
    for(const id of deleted) delete profiles.profiles[id];
    const fallback=Object.keys(profiles.profiles).sort()[0] ?? 'legacy';
    const previouslyEmpty=Object.keys(this.profiles.profiles).length===0;
    if(deleted.size || previouslyEmpty) {
      const selected=row=>row.apiPoolEnabled ? row.apiProfiles : [row.apiProfile];
      const before=structuredClone(document);
      for(const row of [document.defaults,...Object.values(document.saves)]) {
        if(deleted.has(row.apiProfile) || previouslyEmpty && row.apiProfile==='legacy' &&
          !Object.hasOwn(profiles.profiles,'legacy')) row.apiProfile=fallback;
        if(row.apiProfiles) row.apiProfiles=row.apiProfiles.filter(id=>!deleted.has(id));
      }
      const desiredDefault=selected(before.defaults).filter(id=>!deleted.has(id));
      if(JSON.stringify(selected(document.defaults))!==JSON.stringify(desiredDefault)) {
        document.defaults.apiPoolEnabled=true;document.defaults.apiProfiles=desiredDefault;
      }
      for(const [id,row] of Object.entries(document.saves)) {
        const desired=selected(effectiveSettings(before,id)).filter(id=>!deleted.has(id));
        if(JSON.stringify(selected(effectiveSettings(document,id)))!==JSON.stringify(desired)) {
          row.apiPoolEnabled=true;row.apiProfiles=desired;
        }
      }
    }
    const validated=validateSettings(document);
    const references=[validated.defaults,...Object.values(validated.saves)];
    for(const row of references) {
      if(row.apiProfile && !Object.hasOwn(profiles.profiles,row.apiProfile) &&
        !(row.apiProfile==='legacy' && Object.keys(profiles.profiles).length===0)) throw new Error('unknown API profile');
      for(const id of row.apiProfiles ?? []) if(!Object.hasOwn(profiles.profiles,id)) throw new Error('unknown API profile');
    }
    // Secrets are saved before profile references; an interrupted update can
    // leave an unused profile, but cannot leave a dangling reference.
    // Publish new profiles first, remove references next, and only then erase
    // deleted credentials. An interruption cannot leave dangling references.
    await atomicJson(join(this.directory,'api-profiles.private.json'),deleted.size ? transitional : profiles);
    await atomicJson(join(this.directory,'settings.json'),validated);
    if(deleted.size) await atomicJson(join(this.directory,'api-profiles.private.json'),profiles);
    this.document=validated;this.profiles=profiles;await this.publish();
    return this.snapshot(world);
  }
  async disableOfficialDownload() {
    const document=structuredClone(this.document);
    document.defaults.officialAutoDownload=false;
    for(const row of Object.values(document.saves))delete row.officialAutoDownload;
    await atomicJson(join(this.directory,'settings.json'),document);
    this.document=document;await this.publish();
  }
  async publish() { await atomicJson(join(this.directory,'settings-public.json'),this.snapshot()); }
}

export class SettingsService {
  constructor(store,{onApply=async()=>{},onSync=()=>{},onClearShared=async()=>{},onClearOfficial=async()=>{throw Error("official library unavailable");},readClipboard=readClipboardText}={}) {
    this.onSync=onSync;
    this.onClearShared=onClearShared;this.onClearOfficial=onClearOfficial;
    this.readClipboard=readClipboard;
    this.store=store;this.onApply=onApply;this.lastId=null;this.work=Promise.resolve();
  }
  async handle(request) {
    if(!plain(request) || typeof request.id!=='string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(request.id)) {
      throw new Error('invalid settings request');
    }
    const result={version:1,id:request.id,ok:false};
    try {
      if(request.action==='official-sync') {
        if(!['zh-Hant','zh-Hans'].includes(request.language)) throw new Error('invalid language');
        this.onSync(request.language);
        // Acknowledgement only; do not return a settings snapshot or disturb drafts.
      } else if(request.action==='official-clear') {
        await this.store.disableOfficialDownload();
        await this.onClearOfficial();
        result.snapshot=this.store.snapshot(request.world);result.restartRequired=true;
        await this.onApply();
      } else if(request.action==='shared-clear') {
        await this.onClearShared();
      } else if(request.action==='clipboard') {
        const text=await this.readClipboard();
        result.text=overrides({translationPrompt:text}).translationPrompt;
      } else if(request.action==='save') {
        result.snapshot=await this.store.apply(request);
        await this.onApply();
      } else if(request.action==='test') {
        const draft=request.profile ? this.store.draftProfile(request.profile).profile :
          this.store.profiles.profiles[this.store.effective(request.world).apiProfile];
        if(!draft?.enabled) throw new Error('API disabled');
        const provider=await createProvider({provider:draft,timeoutMs:5000,maxRetries:0,concurrency:1});
        if(!provider) throw new Error('API unconfigured');
        await provider('Connection test.',this.store.effective(request.world).language);
      } else throw new Error('unknown settings action');
      result.ok=true;
    } catch(error) {
      result.error=/^provider HTTP \d{3}$/.test(error.message) ? error.message :
        /^provider timeout$/.test(error.message) ? '連線逾時' :
        /^API (disabled|unconfigured)$/.test(error.message) ? 'API 尚未啟用或設定' : '設定無效或連線失敗';
    }
    return result;
  }
  process() {
    const work=this.work.then(async()=>{
      let request;
      try {
        const data=await readFile(join(this.store.directory,'settings-request.json'),'utf8');
        if(data.length>32768) return;
        request=JSON.parse(data);
      } catch {return;}
      if(!request.id || request.id===this.lastId) return;
      const result=await this.handle(request);
      this.lastId=request.id;
      await atomicJson(join(this.store.directory,'settings-request.json'),{version:1,processed:request.id});
      await atomicJson(join(this.store.directory,'settings-response.json'),result);
      this.onComplete?.(result);
    });
    this.work=work.catch(()=>{});return work;
  }
  start() {
    if(this.watcher) return;
    this.watcher=watch(this.store.directory,(_,file)=>{
      if(String(file)==='settings-request.json') void this.process().catch(()=>{});
      if(String(file)==='active-context.json') void this.refreshContext().catch(()=>{});
    });
    this.watcher.on('error',()=>{});
    void this.process().catch(()=>{});
  }
  async refreshContext() {
    let row;
    try {row=JSON.parse(await readFile(join(this.store.directory,'active-context.json'),'utf8'));} catch {return;}
    if(row.version!==1 || typeof row.world!=='string' || row.world.length>1024 ||
        !['zh-Hant','zh-Hans'].includes(row.language)) return;
    if(row.world===this.currentWorld && row.language===this.currentLanguage) return;
    this.currentWorld=row.world;this.currentLanguage=row.language;
    await this.onApply();
  }
  stop() {this.watcher?.close();this.watcher=null;}
}
