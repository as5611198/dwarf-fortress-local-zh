// Independently authored project translations, reviewed for this release.
// CC0-1.0. English keys identify short game UI phrases; no upstream Chinese is read.
export function ownedRows() {
  const rows=[];
  const add=(text,translation,kind='exact')=>rows.push({text,translation,kind,context:'general',origin:'vanilla',source:'project-cc0-20261001',review:'reviewed'});
  const labels={
    'Needs setting':'需要復位','Health':'健康','Overview':'概況','Wounds':'傷口','Treatment':'治療','Equipment':'裝備',
    'Inventory':'物品欄','Personality':'個性','Traits':'特質','Needs':'需求','Preferences':'偏好','Skills':'技能',
    'Thoughts':'想法','Relationships':'關係','Knowledge':'知識','Labor':'勞動','Medical history':'病歷',
    'No wounds':'沒有傷口','No treatment needed':'不需要治療','Diagnosis required':'需要診斷','Needs diagnosis':'需要診斷',
    'Needs surgery':'需要手術','Needs suturing':'需要縫合','Needs dressing':'需要包紮','Needs immobilization':'需要固定',
    'Needs traction':'需要牽引','Needs cleaning':'需要清潔','Needs recovery':'需要休養','Unconscious':'失去意識',
    'Conscious':'有意識','Bleeding':'出血','Dizzy':'頭暈','Nauseous':'噁心','Fever':'發燒','Pain':'疼痛',
    'Swelling':'腫脹','Infection':'感染','Fracture':'骨折','Bruise':'瘀傷','Cut':'割傷','Torn':'撕裂','Broken':'斷裂',
    'Left hand':'左手','Right hand':'右手','Left foot':'左腳','Right foot':'右腳','Head':'頭部','Upper body':'上半身',
    'Lower body':'下半身','Left arm':'左臂','Right arm':'右臂','Left leg':'左腿','Right leg':'右腿',
    'Iron breastplate':'鐵胸甲','Iron helmet':'鐵盔','Iron shield':'鐵盾','Iron pick':'鐵十字鎬','Steel pick':'鋼十字鎬',
    'Steel battle axe':'鋼戰斧','Copper battle axe':'銅戰斧','Leather armor':'皮甲','Leather leggings':'皮護腿',
    'Leather high boot':'皮製高筒靴','Leather low boot':'皮製低筒靴','Copper spear':'銅矛','Iron sword':'鐵劍',
    'Iron gauntlet':'鐵護手','Iron greaves':'鐵脛甲','Clothing':'衣物','Weapons':'武器','Armor':'護甲',
    'will only do assigned tasks':'只會執行指派的工作','Historical figures':'歷史人物','World name':'世界名稱',
    'Clear persistent cache':'清除持久快取','Persistent cache':'持久快取',
  };
  for(const [text,translation] of Object.entries(labels))add(text,translation);
  const reasons={
    'after spending time with people':'與人共度時光','after being away from people':'遠離人群','after drinking':'喝酒',
    'after being kept from alcohol':'沒有酒喝','after meditation':'冥想','after being unable to pray':'無法祈禱',
    'after staying occupied':'保持忙碌','after being unoccupied':'無所事事','after admiring art':'欣賞藝術品',
    'after being unable to admire art':'無法欣賞藝術','after doing something creative':'進行創作',
    'after doing nothing creative':'沒有進行創作','after doing something exciting':'做了令人興奮的事情',
    'after leading an unexciting life':'生活平淡無奇','after learning something':'學到東西','after not learning anything':'沒有學到任何東西',
    'after being with family':'與家人共度時光','after being away from family':'遠離家人','after being with friends':'與朋友共度時光',
    'after being away from friends':'遠離朋友','after being unable to help anybody':'無法幫助任何人',
    'after helping somebody':'幫助別人','after practicing a craft':'練習工藝','after being unable to practice a craft':'無法練習工藝',
    'after practicing a skill':'練習技能','after being unable to practice a skill':'無法練習技能','after a decent meal':'享用像樣的飯菜',
    'after a lack of decent meals':'缺少像樣的飯菜','after being unable to take it easy':'無法放鬆休息',
  };
  const states={
    'unfettered':reason=>`沒有因為${reason}而感到受束縛`,
    'level-headed':reason=>`沒有因為${reason}而失去冷靜`,
    'untroubled':reason=>`沒有因為${reason}而感到困擾`,
    'not distracted':reason=>`沒有因為${reason}而分心`,
    'unfocused':reason=>`因為${reason}而有些心不在焉`,
    'distracted':reason=>`因為${reason}而難以專注`,
    'badly distracted':reason=>`因為${reason}而嚴重分心`,
  };
  for(const [subject,name] of [['He','他'],['She','她']]) {
    for(const [state,translate] of Object.entries(states))for(const [reason,translation] of Object.entries(reasons))
      add(`${subject} is ${state} ${reason}.`,name+translate(translation)+'。');
    for(const [state,translation] of Object.entries({
      'very focused with satisfied needs':'需求已滿足，精神非常集中','quite focused with satisfied needs':'需求已滿足，精神相當集中',
      'somewhat focused with satisfied needs':'需求已滿足，精神有些集中','badly distracted by unmet needs':'因需求未滿足而嚴重分心',
      'distracted by unmet needs':'因需求未滿足而難以專注','unfocused by unmet needs':'因需求未滿足而有些心不在焉',
      'untroubled by unmet needs':'沒有受到未滿足需求的困擾',
    }))add(`Overall, ${subject.toLowerCase()} is ${state}.`,`總體而言，${name}${translation}。`);
  }
  add('{DWARF_NAME} likes chicory.','{DWARF_NAME}喜歡菊苣。','entity');
  add('{DWARF_NAME} likes iron.','{DWARF_NAME}喜歡鐵。','entity');
  add('{DWARF_NAME} likes steel.','{DWARF_NAME}喜歡鋼。','entity');
  add('{DWARF_NAME} likes copper.','{DWARF_NAME}喜歡銅。','entity');
  add('An artery has been opened by the attack!','攻擊導致動脈破裂！');
  add('An artery has been opened by the attack and many nerves have been severed!','攻擊導致動脈破裂，多條神經遭切斷！');
  return rows;
}
