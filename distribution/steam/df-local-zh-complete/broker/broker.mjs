import { mkdir, readFile, open } from 'node:fs/promises';
import { join } from 'node:path';
import { cacheKey, hasCanonicalNameCounts, validateTranslation, POLICY_VERSION, hasRuntimeAlias } from './safety.mjs';
import { translateEquipmentName } from './equipment-names.mjs';
import { prepareTemplate } from './dynamic.mjs';
import { AsyncLocalStorage } from 'node:async_hooks';
import { simplify } from './language-data.mjs';
import { lookupLiteral } from './literal-lookup.mjs';

const rank = priority => priority === 'background' ? 2 : priority === 'recent' ? 1 : 0;
// DF's native row hook also submits cropped lines while the sheet adapter
// translates the complete paragraph. These observed dangling tails cannot
// carry a complete meaning; leave them in English until that paragraph is ready.
const incompleteNeedsRow = source => /^(?:He|She) is not distracted after being unable to (?:be|pray to)$/.test(
  source.replace(/\[C:[0-7]:[0-7]:[01]\]|\[[PR]\]/g,'').trim());

export class TranslationBroker {
  constructor({ directory, language, provider, concurrency = 2, maxQueue = 64, numericTemplates = true, glossary = {}, gameplayGlossary = {}, descriptionGlossary = new Map() }) {
    this.directory = directory;
    this.language = language;
    this.provider = provider;
    this.concurrency = concurrency;
    this.maxQueue = maxQueue;
    this.numericTemplates = numericTemplates;
    this.glossary = { ...glossary };
    this.gameplayGlossary = { ...gameplayGlossary };
    this.descriptionGlossary = descriptionGlossary;
    this.cache = new Map();
    this.fixed = new Map();
    this.builtin = new Map();
    this.official = null;
    this.literalStatic = new Map();
    this.creatureNames = new Map();
    this.pending = new Map();
    this.waiters = [];
    this.active = 0;
    this.context = new AsyncLocalStorage();
    this.jobs = new Map();
    this.backgroundPaused = false;
    this.writes = Promise.resolve();
    this.stats = { accepted: 0, rejected: 0, cacheHits: 0, recoveredRows: 0, skippedFragments: 0 };
  }
  withPriority(priority, action, source, options = {}) {
    return this.context.run({priority: rank(priority), source, batch: options.batch === true}, action);
  }
  promoteSource(source) {
    for (const job of this.jobs.values()) {
      if (job.origin === source || job.source === source) job.priority = 0;
    }
    this.dispatch();
  }
  scheduling() {
    const result={foregroundActive:0, backgroundActive:0, foregroundQueued:0, backgroundQueued:0,
      backgroundPaused:this.backgroundPaused};
    for (const job of this.jobs.values()) {
      result[(job.priority === 0 ? 'foreground' : 'background') + (job.started ? 'Active' : 'Queued')]++;
    }
    return result;
  }
  dispatch() {
    while (this.active < this.concurrency + 14) {
      const waiting=[...this.jobs.values()].filter(job=>!job.started).sort((a,b)=>a.priority-b.priority);
      const foreground=[...this.jobs.values()].some(job=>job.priority===0);
      const backgroundActive=[...this.jobs.values()].filter(job=>job.started && job.priority>0).length;
      const batchActive=[...this.jobs.values()].filter(job=>job.started && job.batch).length;
      const regularActive=this.active-batchActive;
      const job=waiting.find(job=>
        (job.batch ? batchActive<14 : regularActive<this.concurrency) &&
        (job.priority===0 || (!this.backgroundPaused && !foreground && backgroundActive<1)));
      if (!job) return;
      job.started=true; this.active++; job.resolve();
    }
  }
  async load() {
    await mkdir(this.directory, { recursive: true });
    let content = '';
    try { content = await readFile(join(this.directory, 'translations.jsonl'), 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const converted=[];
    for (const line of content.split('\n').filter(line => line.trim())) {
      try {
        const row = JSON.parse(line);
        if (row.policy !== POLICY_VERSION || !['zh-Hant','zh-Hans'].includes(row.language) ||
            !['exact', 'numeric', 'entity', 'name', 'link', 'phonetic'].includes(row.kind) ||
            row.key !== cacheKey(row.source, row.language, POLICY_VERSION + (row.kind === 'exact' ? '' : ':' + row.kind))) throw new Error('cache identity mismatch');
        const value=validateTranslation(
          row.kind === 'name' || row.kind === 'link' ? row.preferred : row.source,
          row.translation);
        if(row.language===this.language) this.cache.set(row.key,value);
        else if(this.language==='zh-Hans') converted.push([cacheKey(row.source,this.language,
          POLICY_VERSION+(row.kind==='exact' ? '' : ':'+row.kind)),simplify(value)]);
      } catch { this.stats.recoveredRows++; }
    }
    for(const [key,value] of converted) if(!this.cache.has(key)) this.cache.set(key,value);
    // Keep an interrupted trailing write separate from future journal entries.
    if (content && !content.endsWith('\n')) await this.journal('\n');
  }
  async journal(content) {
    const write = this.writes.then(async () => {
      const file = await open(join(this.directory, 'translations.jsonl'), 'a');
      try { await file.writeFile(content, 'utf8'); await file.sync(); }
      finally { await file.close(); }
    });
    this.writes = write.catch(() => {});
    return write;
  }
  async canonicalName(world, id, preferred, fallback, {reuseExact = true} = {}) {
    const source = JSON.stringify([world, id, preferred]);
    const key = cacheKey(source, this.language, POLICY_VERSION + ':name');
    if (this.cache.has(key)) return this.cache.get(key);
    if (this.pending.has(key)) return this.pending.get(key);
    const work = (async () => {
      const exact = reuseExact ? this.cache.get(cacheKey(preferred, this.language)) : undefined;
      const translation = validateTranslation(preferred, exact ?? await fallback());
      await this.journal(JSON.stringify({ key, policy: POLICY_VERSION, kind: 'name', source,
        preferred, language: this.language, translation, timestamp: new Date().toISOString() }) + '\n');
      this.cache.set(key, translation);
      return translation;
    })();
    this.pending.set(key, work);
    try { return await work; }
    finally { this.pending.delete(key); }
  }
  async phoneticName(source, glossary = {}) {
    const key=cacheKey(source,this.language,POLICY_VERSION+':phonetic');
    if (this.cache.has(key)) return this.cache.get(key);
    if (this.pending.has(key)) return this.pending.get(key);
    if (this.pending.size >= this.maxQueue) throw new Error('translation queue full');
    const work=this.process(source,key,'phonetic',{kind:'phonetic-name',glossary});
    this.pending.set(key,work);
    try {return await work;} finally {this.pending.delete(key);}
  }
  async canonicalLink(world, id, preferred, fallback) {
    const source = JSON.stringify([world, id]);
    const key = cacheKey(source, this.language, POLICY_VERSION + ':link');
    if (this.cache.has(key)) return this.cache.get(key);
    if (this.pending.has(key)) return this.pending.get(key);
    const work = (async () => {
      const translation = validateTranslation(preferred, await fallback());
      await this.journal(JSON.stringify({ key, policy: POLICY_VERSION, kind: 'link', source,
        preferred, language: this.language, translation, timestamp: new Date().toISOString() }) + '\n');
      this.cache.set(key, translation);
      return translation;
    })();
    this.pending.set(key, work);
    try { return await work; }
    finally { this.pending.delete(key); }
  }
  peekCached(source) {
    if(this.fixed.has(source)) return this.fixed.get(source);
    const equipment = translateEquipmentName(source,this.equipmentTerms);
    if (equipment) return equipment;
    const literal=lookupLiteral(source,this.literalStatic,this.creatureNames);
    if(literal!==undefined) return literal;
    const known=this.preferred(source);
    if(known!==undefined) return known;
    const cached = this.cache.get(cacheKey(source, this.language));
    if (cached === undefined) return undefined;
    const isDescription = this.descriptionGlossary.has(source);
    const matchingNames = isDescription ? [] : this.matchNames ? this.matchNames(source) : Object.keys(this.glossary);
    if (matchingNames.some(name => !Object.hasOwn(this.glossary, name))) return undefined;
    const glossary = {
      ...this.gameplayGlossary,
      ...Object.fromEntries(matchingNames.map(name => [name, this.glossary[name]])),
      ...(this.descriptionGlossary.get(source) ?? {}),
    };
    return hasCanonicalNameCounts(source, cached, glossary) ? cached : undefined;
  }
  preferred(source) {
    if(this.fixed.has(source)) return this.fixed.get(source);
    const builtin=lookupLiteral(source,this.builtin,this.creatureNames);
    if(builtin!==undefined)return builtin;
    const direct=this.official?.lookup(source,this.language) ?? this.official?.lookup(source,this.language,{kind:'entity'});
    if(direct!==undefined)return direct;
    if(!this.official)return undefined;
    const prepared=prepareTemplate(source,this.glossary,this.numericTemplates);
    const shared=this.official.lookup(prepared.source,this.language,{kind:prepared.kind});
    return shared===undefined ? undefined : prepared.restore(shared);
  }
  async translate(source, { resolveNames = true, glossary: scopedGlossary = {} } = {}) {
    if (typeof source !== 'string' || !source.trim() || source.length > 8000 || hasRuntimeAlias(source)) {
      throw new Error('invalid source');
    }
    if(this.fixed.has(source)) return this.fixed.get(source);
    const equipment = translateEquipmentName(source,this.equipmentTerms);
    if (equipment) { this.stats.cacheHits++; return equipment; }
    if ((this.context.getStore()?.priority ?? 0) === 0) this.promoteSource(source);
    const staticLiteral=lookupLiteral(source,this.literalStatic,this.creatureNames);
    if (staticLiteral!==undefined) {
      this.stats.cacheHits++;
      return staticLiteral;
    }
    const known=this.preferred(source);
    if(known!==undefined) {this.stats.cacheHits++;return known;}
    if (incompleteNeedsRow(source)) {
      this.stats.skippedFragments++;
      throw new Error('incomplete display fragment');
    }
    const isDescription = this.descriptionGlossary.has(source);
    if (resolveNames && this.resolveNames && !isDescription) await this.resolveNames(source);
    const matchingNames = isDescription ? [] : this.matchNames ? this.matchNames(source) : Object.keys(this.glossary);
    const glossary = {
      ...this.gameplayGlossary,
      ...Object.fromEntries(matchingNames.filter(name => Object.hasOwn(this.glossary, name))
        .map(name => [name, this.glossary[name]])),
      ...(this.descriptionGlossary.get(source) ?? {}),
      ...scopedGlossary,
    };
    const directKey = cacheKey(source, this.language);
    if (this.cache.has(directKey)) {
      const cached = this.cache.get(directKey);
      if (hasCanonicalNameCounts(source, cached, glossary)) {
        this.stats.cacheHits++;
        return cached;
      }
    }
    const { source: template, kind, restore, literal } = prepareTemplate(source, glossary, this.numericTemplates);
    if (literal) return restore(literal);
    const key = cacheKey(template, this.language, POLICY_VERSION + (kind === 'exact' ? '' : ':' + kind));
    const shared=this.official?.lookup(template,this.language,{kind});
    if(shared!==undefined) {this.stats.cacheHits++;return restore(shared);}
    if (this.cache.has(key)) { this.stats.cacheHits++; return restore(this.cache.get(key)); }
    if (this.pending.has(key)) {
      const job=this.jobs.get(key);
      if (job) job.priority=Math.min(job.priority,this.context.getStore()?.priority ?? 0);
      this.dispatch();
      return restore(await this.pending.get(key));
    }
    if (this.pending.size >= this.maxQueue) throw new Error('translation queue full');
    const work = this.process(template, key, kind);
    this.pending.set(key, work);
    try { return restore(await work); }
    finally { this.pending.delete(key); }
  }
  async process(source, key, kind, options) {
    const context=this.context.getStore();
    const provider=this.provider;
    const captureShared=this.captureShared;
    await new Promise(resolve=> {
      this.jobs.set(key,{source,origin:context?.source,priority:context?.priority ?? 0,
        batch:context?.batch === true,started:false,resolve});
      this.dispatch();
    });
    try {
      if (!provider) throw new Error('no translation provider configured');
      const translation = validateTranslation(source, await provider(source, this.language,
        {...options, batch:context?.batch === true}));
      await this.journal(JSON.stringify({ key, policy: POLICY_VERSION, kind, source, language: this.language, translation, timestamp: new Date().toISOString() }) + '\n');
      this.cache.set(key, translation);
      this.stats.accepted++;
      // Do not delay the game result for disk, consensus, network or AI review.
      if(captureShared)void Promise.resolve().then(()=>captureShared(source,translation,kind)).catch(()=>{});
      return this.fixed.get(source) ?? this.builtin.get(source) ?? this.official?.lookup(source,this.language,{kind}) ?? translation;
    } catch (error) { this.stats.rejected++; throw error; }
    finally { this.active--; this.jobs.delete(key); this.dispatch(); }
  }
}
