import { readFile, writeFile, rename } from 'node:fs/promises';
import { join } from 'node:path';

export class StatusBridge {
  constructor(directory, broker, queue, world) {
    Object.assign(this,{directory,broker,queue,world});
    this.running=null;
  }
  async publish() {
    if (this.running) return this.running;
    this.running=this.update();
    try {return await this.running;} finally {this.running=null;}
  }
  async update() {
    if(this.beforePublish) await this.beforePublish();
    try {
      const controls=JSON.parse(await readFile(join(this.directory,'translation-controls.json'),'utf8'));
      if (controls.version===1 && typeof controls.backgroundPaused==='boolean') {
        this.broker.backgroundPaused=controls.backgroundPaused || this.broker.configuredBackgroundPaused===true;
        this.queue.backgroundPaused=this.broker.backgroundPaused;
      }
    } catch { /* Retain the last valid control on partial or absent writes. */ }
    this.broker.dispatch();
    const world=this.world();
    const pending=[...this.queue.jobs.values()].filter(row=>row.world===world);
    const active=[...this.queue.activeJobs.values()].map(job=>job.row).filter(row=>row.world===world);
    const scheduling=this.broker.scheduling();
    const data={version:1,timestamp:Date.now(),world,
      language:this.broker.language,
      providerConfigured:Boolean(this.broker.provider),cached:this.broker.cache.size,
      ...scheduling,providerQueued:scheduling.foregroundQueued+scheduling.backgroundQueued,
      providerActive:scheduling.foregroundActive+scheduling.backgroundActive,
      runtime:{...this.queue.stats,
        unresolved:[...this.queue.failures.values()].filter(row=>row.world===world).length,
        retainedFailures:this.queue.failures.size,
        foregroundQueued:pending.filter(row=>row.priority==='foreground').length,
        backgroundQueued:pending.filter(row=>row.priority!=='foreground').length,
        foregroundActive:active.filter(row=>row.priority==='foreground').length,
        backgroundActive:active.filter(row=>row.priority!=='foreground').length}};
    const path=join(this.directory,'broker-status.json');
    await writeFile(path+'.tmp',JSON.stringify(data),'utf8');
    await rename(path+'.tmp',path);
    return data;
  }
  start() {
    if(this.timer) return;
    this.timer=setInterval(()=>void this.publish().catch(()=>{}),1000);
    void this.publish().catch(()=>{});
  }
  stop() {clearInterval(this.timer);this.timer=null;}
}
