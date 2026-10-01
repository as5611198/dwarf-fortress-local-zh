// Show console diagnostics only. Wrangler event headers may contain operator secrets.
import {spawn} from 'node:child_process';
const child=spawn(process.execPath,['node_modules/wrangler/bin/wrangler.js','tail','--env','staging','--format','json'],{stdio:['ignore','pipe','pipe']});
let buffer='';child.stdout.on('data',chunk=>{buffer+=chunk;for(;;){const start=buffer.indexOf('{');if(start<0){buffer='';return;}buffer=buffer.slice(start);let depth=0,quoted=false,escape=false,end=-1;
 for(let i=0;i<buffer.length;i++){const c=buffer[i];if(quoted){if(escape)escape=false;else if(c==='\\')escape=true;else if(c==='"')quoted=false;}else if(c==='"')quoted=true;else if(c==='{')depth++;else if(c==='}' && --depth===0){end=i+1;break;}}
 if(end<0)return;const raw=buffer.slice(0,end);buffer=buffer.slice(end);try{const event=JSON.parse(raw);for(const log of event.logs??[])for(const message of log.message??[]){try{const value=JSON.parse(message);if(value.service==='df-zh-consensus')console.log(JSON.stringify(value));}catch{}}}catch{}
}});
const timer=setTimeout(()=>child.kill(),55000);child.on('close',()=>clearTimeout(timer));
