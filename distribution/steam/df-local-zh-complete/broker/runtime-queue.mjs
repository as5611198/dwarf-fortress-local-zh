import { createHash } from 'node:crypto';
import { appendFile, readFile, open } from 'node:fs/promises';
import { join } from 'node:path';
import { validateTranslation, safeReason, hasRuntimeAlias } from './safety.mjs';
import { validateParagraph, validateParagraphRequest } from './rich-text.mjs';

const languageOf = row => row.language ?? 'zh-Hant';
const validLanguage = row => ['zh-Hant','zh-Hans'].includes(languageOf(row));
const fileKey = (world, text, figureId, rich = {}) => 'DFLIVE_' + createHash('sha256')
  .update(languageOf(rich)==='zh-Hans' ? 'zh-Hans\0' : '')
  .update(JSON.stringify(rich.kind === 'legends-name' ?
    [world,text,'legends-name-native-v2',rich.entityKind,rich.entityId] :
    rich.kind === 'legends-paragraph' ?
    [world, text, rich.namePolicy === 'native-v2' ? 'legends-paragraph-native-v2' : 'legends-paragraph-v1', rich.subjectId ?? null,
      rich.links.map(link => [link.type, link.id, link.text])] :
    figureId === undefined ? [world, text] :
    [world, text, rich.namePolicy === 'native-v2' ? 'figure-caption-native-v2' : 'figure-caption-v1', figureId])).digest('hex');
const validFigure = row => row.figureId === undefined ||
  (Number.isSafeInteger(row.figureId) && row.figureId >= 0);
const entityKinds = new Set(['site','artifact','book','written_content','region','entity','layer']);
const validEntity = row => row.kind !== 'legends-name' ||
  (row.namePolicy === 'native-v2' && entityKinds.has(row.entityKind) &&
    Number.isSafeInteger(row.entityId) && row.entityId >= 0 && row.figureId === undefined);
const requestFromResponse = row => ({...row, links: row.requestLinks});

export class RuntimeQueue {
  constructor({ directory, translate, currentWorld, maxBatch = 16,
    now = Date.now, retryBaseMs = 20000, retryMaxMs = 300000,
    promote = () => {}, canBackground = () => true, foregroundBusy = () => false,
    accept = () => true, lookupCached = () => undefined,
    isBatchable = () => false, visibleOnly = false,
    limits=()=>({concurrency:2,maxRetries:30,retryBaseMs}) }) {
    this.requests = join(directory, 'runtime-requests.jsonl');
    this.responses = join(directory, 'runtime-responses.jsonl');
    this.failurePath = join(directory, 'runtime-failures.jsonl');
    this.visibilityPath = join(directory, 'runtime-visible.json');
    this.translate = translate;
    this.currentWorld = currentWorld;
    this.maxBatch = maxBatch;
    this.now = now;
    this.retryBaseMs = retryBaseMs;
    this.retryMaxMs = retryMaxMs;
    this.failures = new Map();
    this.stats = { attempted: 0, published: 0, failed: 0, cooldownSkipped: 0, requestBytesRead: 0 };
    this.seen = new Set();
    this.requestOffset = 0;
    this.requestTail = Buffer.alloc(0);
    this.requestIdentity = null;
    this.requestMtimeMs = null;
    this.running = null;
    this.timer = null;
    this.jobs = new Map();
    this.activeJobs = new Map();
    this.ingesting = Promise.resolve();
    this.promote = promote;
    this.canBackground = canBackground;
    this.foregroundBusy = foregroundBusy;
    this.accept = accept;
    this.lookupCached = lookupCached;
    this.isBatchable = isBatchable;
    this.visibleOnly = visibleOnly;
    this.limits=limits;
  }

  async load() {
    let content = '';
    try { content = await readFile(this.responses, 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    for (const line of content.split('\n')) {
      if (!line) continue;
      try {
        const row = JSON.parse(line);
        const request = requestFromResponse(row);
        if (validLanguage(row) && validFigure(row) && validEntity(row) &&
            row.key === fileKey(row.world, row.text, row.figureId, request)) {
          if (row.kind === 'legends-paragraph') validateParagraph(request, row);
          else validateTranslation(row.text, row.translation);
          this.seen.add(row.key);
        }
      } catch { /* Ignore interrupted or invalid response records. */ }
    }
    if (content && !content.endsWith('\n')) await appendFile(this.responses, '\n', 'utf8');
    let failures = '';
    try { failures = await readFile(this.failurePath, 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    for (const line of failures.split('\n').filter(Boolean)) {
      try {
        const row = JSON.parse(line);
        if (typeof row.world !== 'string' || typeof row.text !== 'string' ||
            !validLanguage(row) || !validFigure(row) || !validEntity(row) ||
            row.key !== fileKey(row.world, row.text, row.figureId, row) ||
            !Number.isSafeInteger(row.attempts) || row.attempts < 0 ||
            !Number.isFinite(row.retryAt) || row.retryAt < 0) continue;
        if (!row.attempts || this.seen.has(row.key)) this.failures.delete(row.key);
        else this.failures.set(row.key, row);
      } catch { /* A partial failure record must not prevent startup. */ }
    }
    if (failures && !failures.endsWith('\n')) await appendFile(this.failurePath, '\n', 'utf8');
  }

  async recordFailure(row) {
    const file = await open(this.failurePath, 'a');
    try { await file.writeFile(JSON.stringify(row) + '\n', 'utf8'); await file.sync(); }
    finally { await file.close(); }
  }

  async drain() {
    await this.ingest();
    let count=0;
    while (count < this.maxBatch) {
      this.dispatch();
      if (!this.activeJobs.size) return;
      await Promise.race([...this.activeJobs.values()].map(job=>job.work));
      count++;
    }
  }

  ingest() {
    const work=this.ingesting.then(()=>this.readRequests());
    this.ingesting=work.catch(()=>{});
    return work;
  }

  async readNewRequestLines() {
    let file;
    try { file = await open(this.requests, 'r'); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      this.requestOffset = 0;
      this.requestTail = Buffer.alloc(0);
      this.requestIdentity = null;
      this.requestMtimeMs = null;
      return [];
    }
    try {
      const state = await file.stat();
      const identity = `${state.dev}:${state.ino}`;
      if ((this.requestIdentity && this.requestIdentity !== identity) ||
          state.size < this.requestOffset ||
          (state.size === this.requestOffset && this.requestMtimeMs !== null &&
            state.mtimeMs !== this.requestMtimeMs)) {
        this.requestOffset = 0;
        this.requestTail = Buffer.alloc(0);
      }
      this.requestIdentity = identity;
      this.requestMtimeMs = state.mtimeMs;
      if (state.size === this.requestOffset) return [];
      const chunks = [];
      let position = this.requestOffset;
      while (position < state.size) {
        const chunk = Buffer.allocUnsafe(Math.min(65536, state.size - position));
        const { bytesRead } = await file.read(chunk, 0, chunk.length, position);
        if (!bytesRead) break;
        chunks.push(chunk.subarray(0, bytesRead));
        position += bytesRead;
      }
      this.stats.requestBytesRead += position - this.requestOffset;
      this.requestOffset = position;
      const content = Buffer.concat([this.requestTail, ...chunks]);
      const end = content.lastIndexOf(10);
      if (end < 0) { this.requestTail = content; return []; }
      this.requestTail = Buffer.from(content.subarray(end + 1));
      return content.subarray(0, end).toString('utf8').split('\n');
    } finally { await file.close(); }
  }

  async readRequests() {
    let visible = new Set();
    if (this.visibleOnly) {
      try {
        const row=JSON.parse(await readFile(this.visibilityPath,'utf8'));
        if (row.world===await this.currentWorld() && Array.isArray(row.ids) && row.ids.length<=256) {
          visible=new Set(row.ids.filter(id=>typeof id==='string' && id.length<=8000));
        }
      } catch { /* A missing or interrupted visibility file means no AI prefetch. */ }
      for (const [key,row] of this.jobs) {
        if (this.isBatchable(row) && !visible.has(row.visibilityId)) this.jobs.delete(key);
      }
    }
    const lines = await this.readNewRequestLines();
    for (let index = 0; index < lines.length; index++) {
      let row;
      try { row = JSON.parse(lines[index]); }
      catch { continue; }
      if (typeof row.world !== 'string' || !row.world ||
          typeof row.text !== 'string' || !row.text.trim() || row.text.length > 8000 ||
          hasRuntimeAlias(row.text) || !validLanguage(row) || !validFigure(row)) continue;
      if (row.kind !== undefined && !['legends-paragraph','legends-name'].includes(row.kind)) continue;
      if (!validEntity(row)) continue;
      if (this.visibleOnly && this.isBatchable(row) && !visible.has(row.visibilityId)) continue;
      if (!this.accept(row)) continue;
      if (row.kind === 'legends-paragraph') {
        try { validateParagraphRequest(row); } catch { continue; }
      }
      const world = await this.currentWorld();
      if (world !== row.world) continue;
      const key = fileKey(row.world, row.text, row.figureId, row);
      if (this.seen.has(key)) continue;
      if (row.kind === undefined && row.figureId === undefined && !this.activeJobs.has(key)) {
        let cached;
        try { cached = await this.lookupCached(row.text, row); }
        catch { /* An unavailable cache still leaves the normal translation path. */ }
        if (cached !== undefined) {
          try {
            await this.publish(key, row, cached);
            this.jobs.delete(key);
            continue;
          } catch { /* An invalid cache entry must not suppress translation. */ }
        }
      }
      row.priority=['foreground','recent','background'].includes(row.priority) ? row.priority : 'recent';
      const existing=this.jobs.get(key) ?? this.activeJobs.get(key)?.row;
      if (existing) {
        if (row.priority==='foreground') { existing.priority='foreground'; this.promote(row.text); }
        continue;
      }
      const previous = this.failures.get(key);
      if(previous && previous.attempts>this.limits(row).maxRetries) continue;
      if (previous && this.now() < previous.retryAt) {
        this.stats.cooldownSkipped++;
        continue;
      }
      this.jobs.set(key,row);
    }
  }

  dispatch() {
    while (this.activeJobs.size < 16) {
      const entries=[...this.jobs].sort((a,b)=>
        ({foreground:0,recent:1,background:2}[a[1].priority])-({foreground:0,recent:1,background:2}[b[1].priority]));
      const foreground=this.foregroundBusy() || [...this.activeJobs.values()].some(job=>job.row.priority==='foreground') ||
        entries.some(([,row])=>row.priority==='foreground');
      const background=[...this.activeJobs.values()].some(job=>job.row.priority!=='foreground');
      const batchActive=[...this.activeJobs.values()].filter(job=>this.isBatchable(job.row)).length;
      const regularActive=this.activeJobs.size-batchActive;
      const entry=entries.find(([,row])=>
        (this.isBatchable(row) ? batchActive<14 : regularActive<this.limits(row).concurrency) &&
        (row.priority==='foreground' || (!this.backgroundPaused && !foreground && !background && this.canBackground(row))));
      if (!entry) return;
      const [key,row]=entry;
      this.jobs.delete(key);
      const work=this.processRow(key,row).catch(()=>{}).finally(()=> {this.activeJobs.delete(key);});
      this.activeJobs.set(key,{row,work});
    }
  }

  async processRow(key,row) {
      if (await this.currentWorld() !== row.world) return;
      const previous=this.failures.get(key);
      this.stats.attempted++;
      try {
        const result = await this.translate(row.text, row);
        await this.publish(key,row,result);
      } catch (error) {
        const attempts = Math.min(31, (previous?.attempts ?? 0) + 1);
        const failure = { key, world: row.world, language:languageOf(row), text: row.text, figureId: row.figureId, attempts,
          ...(row.namePolicy ? {namePolicy:row.namePolicy} : {}),
          ...(row.kind === 'legends-name' ? {kind:row.kind,entityKind:row.entityKind,
            entityId:row.entityId} : {}),
          ...(row.kind === 'legends-paragraph' ? {kind: row.kind, subjectId: row.subjectId, links: row.links} : {}),
          retryAt: this.now() + Math.min(this.retryMaxMs, this.limits(row).retryBaseMs * 2 ** (attempts - 1)),
          reason: safeReason(error) };
        this.failures.set(key, failure);
        this.stats.failed++;
        await this.recordFailure(failure);
      }
  }

  async publish(key,row,result) {
    const payload = row.kind === 'legends-paragraph' ? {
      ...validateParagraph(row, result), kind: row.kind,
      subjectId: row.subjectId, requestLinks: row.links,
    } : {translation: validateTranslation(row.text, result)};
    if (await this.currentWorld() !== row.world) return;
    await appendFile(this.responses,
      JSON.stringify({ key, world: row.world, language:languageOf(row), text: row.text, figureId: row.figureId,
      ...(row.namePolicy ? {namePolicy:row.namePolicy} : {}),
      ...(row.kind === 'legends-name' ? {kind:row.kind,entityKind:row.entityKind,
        entityId:row.entityId} : {}), ...payload }) + '\n', 'utf8');
    this.seen.add(key);
    this.stats.published++;
    this.failures.delete(key);
  }

  start(intervalMs = 500) {
    if (this.timer) return;
    this.timer = setInterval(() => { void this.ingest().then(()=>this.dispatch()).catch(() => {}); }, intervalMs);
    void this.drain().catch(() => {});
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}
