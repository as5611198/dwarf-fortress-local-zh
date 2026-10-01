import TOML from '@iarna/toml';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function fixedNeeds(plainText, psychologyText) {
  const plain=TOML.parse(plainText).rulesets;
  const psychology=TOML.parse(psychologyText).rulesets;
  const rules=name=>plain.find(row=>row.name===name)?.rules ?? {};
  const reasons={...psychology.find(row=>row.name==='things::after').rules,...rules('reason')};
  const result=new Map();
  for(const [pattern,translation] of Object.entries(plain[0].rules)) {
    const subjects=pattern.includes('{lower_subject}') ? rules('lower_subject') : rules('subject');
    for(const [subject,name] of Object.entries(subjects)) {
      const source=pattern.replace('{subject}',subject).replace('{lower_subject}',subject);
      const target=translation.replace('{subject}',name).replace('{lower_subject}',name);
      if(!source.includes('{reason}')) {result.set(source,target);continue;}
      for(const [reason,text] of Object.entries(reasons)) {
        if(reason==='after communing with' || /[{}]/.test(text)) continue;
        const clean=text.replace(/^在/,'').replace(/之後$|後$/,'').replace(/^因/,'');
        result.set(source.replace('{reason}',reason),target.replace('{reason}',clean));
      }
    }
  }
  const overall={
    'very focused with satisfied needs':'需求已滿足，精神非常集中',
    'quite focused with satisfied needs':'需求已滿足，精神相當集中',
    'somewhat focused with satisfied needs':'需求已滿足，精神有些集中',
    'badly distracted by unmet needs':'因需求未滿足而嚴重分心',
    'distracted by unmet needs':'因需求未滿足而難以專注',
    'unfocused by unmet needs':'因需求未滿足而有些心不在焉',
    'untroubled by unmet needs':'沒有受到未滿足需求的困擾',
  };
  for(const [subject,name] of Object.entries(rules('lower_subject'))) {
    for(const [state,text] of Object.entries(overall))
      result.set(`Overall, ${subject} is ${state}.`,`總體而言，${name}${text}。`);
  }
  return [...result].map(([text,translation])=>({text,translation}));
}

export function fixedThoughts() {
  return Object.entries({
    '"An artisan, their materials and the tools to shape them!"':'「工匠、材料，還有塑造材料的工具！」',
    '"Everyone should broaden their horizons.  Any work beyond learning the basics is just a waste."':'「每個人都應該開闊自己的視野。任何超出基礎學習範圍的工作都只是浪費。」',
    '"Everything\'s alright."':'「一切都還好。」',
    '"Everything\'s fine."':'「一切都好。」',
    '"I could do without all of those creatures and that tangled greenery."':'「沒有那些生物和雜亂的草木也挺好。」',
    '"I do admire a clever trap."':'「我確實欣賞巧妙的陷阱。」',
    '"I finished up some work.  I am very satisfied."':'「我完成了一些工作，感到非常滿意。」',
    '"I\'m doing alright."':'「我過得還不錯。」',
    '"I\'m doing well."':'「我過得很好。」',
    '"I\'m well."':'「我很好。」',
    '"I\'ve been alright."':'「我最近過得還不錯。」',
    '"I\'ve been well."':'「我最近過得很好。」',
    '"In life, you should work hard.  Then work harder."':'「人生在世，應該努力工作，然後更加努力。」',
    '"It won\'t turn out well."':'「這不會有好結果。」',
    '"One must always be loyal to their cause and the ones they serve."':'「人必須始終忠於自己的志業與效忠的對象。」',
    '"That isn\'t funny."':'「那一點也不好笑。」',
    '"The best way to get what you want out of life is to work for it."':'「想從人生中得到什麼，最好的方法就是為之努力。」',
    '"Why must they be so violent?"':'「他們為什麼非得這麼暴力？」',
  }).map(([text,translation])=>({text,translation}));
}

export function knownPreferences(content) {
  const rows=new Map();
  for(const line of content.split('\n')) {
    let row;
    try {row=JSON.parse(line);} catch {continue;}
    if(typeof row.world!=='string' || !row.world || typeof row.text!=='string' ||
      row.text.length>8000 || !row.text.startsWith('{DWARF_NAME} likes ') ||
      (row.text.match(/\{DWARF_NAME\}/g) ?? []).length!==1) continue;
    rows.set(JSON.stringify([row.world,row.text]),{world:row.world,text:row.text});
  }
  return [...rows.values()];
}

export async function buildUnitPrewarm(rulesDirectory,requestsPath,output) {
  const [plain,psychology,requests]=await Promise.all([
    readFile(resolve(rulesDirectory,'plain_needs.toml'),'utf8'),
    readFile(resolve(rulesDirectory,'psychology/needs.toml'),'utf8'),
    readFile(requestsPath,'utf8').catch(error=>{if(error.code==='ENOENT') return '';throw error;}),
  ]);
  const manifest={version:1,fixed:[...fixedNeeds(plain,psychology),...fixedThoughts()],
    templates:knownPreferences(requests)};
  await writeFile(output,JSON.stringify(manifest)+'\n','utf8');
  return {fixed:manifest.fixed.length,templates:manifest.templates.length};
}

if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  const args=process.argv.slice(2);
  if(args.length!==3) throw new Error('Usage: node unit-prewarm.mjs <rules-directory> <runtime-requests.jsonl> <output.json>');
  console.log(JSON.stringify(await buildUnitPrewarm(...args)));
}
