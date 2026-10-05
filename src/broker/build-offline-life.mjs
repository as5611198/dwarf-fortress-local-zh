import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {stringify} from 'csv-stringify/sync';
import {simplify} from './language-data.mjs';

// Independently reviewed clauses, never harvested from a player's learned cache.
const needs={
  'being away from people':'遠離人群','spending time with people':'與人共度時光',
  'being unoccupied':'無所事事','staying occupied':'保持忙碌',
  'doing nothing creative':'沒有進行創作','doing something creative':'進行創作',
  'leading an unexciting life':'生活平淡無奇','doing something exciting':'做了令人興奮的事情',
  'being unable to acquire something':'無法獲得某些東西','a satisfying acquisition':'獲得滿意的物品',
  'being kept from alcohol':'沒有酒喝','drinking':'喝酒',
  'a lack of decent meals':'缺少像樣的飯菜','a good meal':'享用美食',
  'being unable to fight':'無法戰鬥','fighting':'戰鬥',
  'a lack of trouble-making':'沒能製造麻煩','causing trouble':'製造麻煩',
  'being unable to argue':'無法與人爭論','arguing':'與人爭論',
  'being unable to be extravagant':'無法奢侈揮霍','being extravagant':'奢侈揮霍',
  'not learning anything':'沒有學到任何東西','learning something':'學到新知',
  'being unable to help anybody':'無法幫助任何人','helping somebody':'幫助他人',
  'a lack of abstract thinking':'缺少抽象思考','thinking abstractly':'進行抽象思考',
  'being unable to make merry':'無法盡情娛樂','making merry':'盡情娛樂',
  'being unable to admire art':'無法欣賞藝術','admiring art':'欣賞藝術',
  'being unable to practice a craft':'無法練習工藝','practicing a craft':'練習工藝',
  'being away from family':'遠離家人','being with family':'與家人共度時光',
  'being away from friends':'遠離朋友','being with friends':'與朋友共度時光',
  'a lack of introspection':'缺少自省','introspection':'自省',
  'being unable to practice a martial art':'無法練習武術','practicing a martial art':'練習武術',
  'being unable to practice a skill':'無法練習技能','practicing a skill':'練習技能',
  'being unable to take it easy':'無法放鬆休息','taking it easy':'放鬆休息',
  'being unable to pray to {DEITY_NAME}':'無法向{DEITY_NAME}祈禱',
  'communing with {DEITY_NAME}':'與{DEITY_NAME}靈性交流',
};
const states={
  'unfettered':['沒有因為','而感到受束縛'], 'level-headed':['沒有因為','而失去冷靜'],
  'untroubled':['沒有因為','而感到困擾'], 'not distracted':['沒有因為','而分心'],
  'unfocused':['因為','而有些心不在焉'], 'distracted':['因為','而難以專注'],
  'badly distracted':['因為','而嚴重分心'],
};
const overall={
  'very focused with satisfied needs':'需求已滿足，精神非常集中',
  'quite focused with satisfied needs':'需求已滿足，精神相當集中',
  'somewhat focused with satisfied needs':'需求已滿足，精神有些集中',
  'badly distracted by unmet needs':'因需求未滿足而嚴重分心',
  'distracted by unmet needs':'因需求未滿足而難以專注',
  'unfocused by unmet needs':'因需求未滿足而有些心不在焉',
  'untroubled by unmet needs':'沒有受到未滿足需求的困擾',
};
const emotions={
  adoration:'崇拜',admiration:'欽佩',affection:'喜愛',aroused:'興奮',caring:'關切',empathy:'共鳴',
  enraptured:'陶醉',fondness:'親近',gratitude:'感激',lustful:'慾火中燒',love:'愛意',passionate:'熱情',
  pleasure:'愉悅',proud:'自豪',repentant:'懊悔',sympathy:'同情',tenderness:'溫柔',amused:'好笑',
  blissful:'無比幸福',content:'滿足',delighted:'欣喜',elated:'興高采烈',enjoyment:'愉快',euphoric:'狂喜',
  expectant:'期待',free:'自由',gaiety:'歡快',happy:'開心',hope:'希望',jovial:'快活',joy:'喜悅',
  relieved:'如釋重負',satisfied:'滿意',triumph:'得意',optimistic:'樂觀',astonished:'驚訝',awe:'敬畏',
  excited:'興奮',eager:'渴望',exhilarated:'振奮',interested:'興致盎然',wonder:'驚歎',accepting:'釋然',
  ambivalent:'矛盾','grim satisfaction':'冷酷的滿足',suspicious:'懷疑',aggravated:'惱火',agitated:'焦躁',
  annoyed:'煩惱',anxious:'焦慮',bitter:'苦澀',bored:'無聊',confused:'困惑',contemptuous:'輕蔑',
  dejected:'沮喪',disappointed:'失望',disillusioned:'幻滅',dislike:'厭惡',embarrassed:'尷尬',
  exasperated:'惱怒',frustrated:'挫敗',gloomy:'陰鬱',glum:'鬱悶',grouchy:'煩躁',guilty:'內疚',
  indignant:'憤慨',insulted:'受辱',irritated:'惱火',isolated:'孤立無援',lonely:'孤獨',regretful:'後悔',
  resentful:'怨恨',restless:'坐立不安','self-pity':'自憐',shaken:'心神不寧',shame:'羞愧',
  uneasy:'不安',unhappy:'不快',afraid:'害怕',anger:'憤怒',angry:'憤怒',anguish:'痛苦',
  despair:'絕望',disgust:'噁心',distress:'苦惱',dread:'恐懼',fear:'害怕',fright:'驚恐',grief:'悲痛',
  horrified:'驚駭',horror:'恐怖',humiliated:'屈辱',loathing:'憎惡',misery:'悲苦',mortified:'羞憤',
  nervous:'緊張',outraged:'震怒',panic:'恐慌',rage:'暴怒',sad:'傷心',sadness:'悲傷',
  shock:'震驚',shocked:'震驚',terrified:'恐懼萬分',vengeful:'復仇的渴望',worried:'擔憂',
};
const reasons={
  'talking with the spouse':'與配偶交談','talking with mother':'與母親交談','talking with father':'與父親交談',
  'talking with a lover':'與愛人交談','talking with a friend':'與朋友交談','talking with a sibling':'與兄弟姐妹交談',
  'talking with a child':'與孩子交談','talking with somebody':'與他人交談','talking with an acquaintance':'與熟人交談',
  'after a bath':'洗澡','after a soapy bath':'用肥皂洗澡','being near to a waterfall':'靠近瀑布',
  'after retching on a miasma':'被瘴氣熏得乾嘔','after choking on smoke underground':'在地下被煙嗆到',
  'after choking on dust underground':'在地下被灰塵嗆到','at the lack of chairs':'沒有椅子可坐',
  'eating at a crowded table':'在擁擠的餐桌旁進食','at the lack of dining tables':'沒有餐桌可用',
  'after having a drink without using a goblet, cup or mug':'沒有用杯子喝酒',
  'after watching a performance':'觀看表演','after talking to a pillar of society':'與社會棟梁交談',
  'interacting with a pet':'與寵物互動','visiting with a pet':'探望寵物',
  'interacting with a animal training partner':'與受訓動物夥伴互動','visiting with a animal training partner':'探望受訓動物夥伴',
  'when forced to talk to somebody annoying':'被迫與討厭的人交談',
  'after bringing somebody to rest in bed':'將他人帶到床上休息','after giving somebody food':'給他人食物',
  'after giving somebody water':'給他人飲水','after making a friend':'交到朋友','making a friend':'交到朋友',
  'after getting into an argument':'與人爭吵','after forming a grudge':'與人結怨','after adopting a new pet':'收養新寵物',
  'at being separated from a loved one':'與摯愛分離','at being separated from loved ones':'與摯愛們分離',
  'at work':'工作','after producing a masterwork':'製作出傑作','after creating an artifact':'製作出神器',
  'after suffering the travesty of art defacement':'藝術品遭到破壞','after felling a tree':'砍倒樹木',
  'after putting a piece on display':'展示作品','to be wearing old clothing':'穿著舊衣服',
  'to be wearing tattered clothing':'穿著破爛衣服','to have clothes rot off':'衣服腐爛脫落',
  'to be uncovered':'衣不蔽體','to have no shirt':'沒有上衣穿','to have no shoes':'沒有鞋穿',
  'after becoming a parent':'成為父母','after gaining a sibling':'多了一位兄弟姐妹',
  'after gaining siblings':'多了兄弟姐妹','while getting married':'結婚','after a miscarriage':'流產',
  "after spouse's miscarriage":'配偶流產','to be elected':'當選','to be re-elected':'連任',
  'after entering the nobility':'晉升貴族','after receiving a higher rank of nobility':'爵位提升',
  'after being released from confinement':'獲釋','after being confined':'遭到監禁',
  'after being beaten':'遭到毆打','after being beaten with a hammer':'遭到錘擊',
  'after being rescued':'獲救','after being able to rest and recuperate':'能夠休養',
  'after receiving food':'獲得食物','after receiving water':'獲得飲水','after being attacked':'遭到攻擊',
  'after being attacked by the dead':'遭到死者攻擊','after suffering a minor injury':'受了輕傷',
  'after suffering a major injury':'受了重傷','being near to a conflict':'靠近衝突現場',
  'while in conflict':'身處衝突','when joining an existing conflict':'加入衝突',
  'while killing somebody':'殺死他人','after a sparring session':'進行對練','during long patrol duty':'長時間巡邏',
  'when caught in the rain':'淋雨','when caught in a snow storm':'遇上暴風雪',
  'at being out in the sunshine again':'再次沐浴陽光','after being nauseated by the sun':'因陽光而反胃',
  'due to inebriation':'醉酒','while performing':'表演','performing':'表演',
  'after experiencing trauma':'遭遇創傷','experiencing trauma':'遭遇創傷','after a satisfying acquisition':'獲得滿意的物品',
  'after sleeping uneasily due to noise':'因噪音而睡不安穩','after being disturbed during sleep by loud noises':'睡眠被巨大噪音打斷',
  'after loud noises made it impossible to sleep':'被噪音吵得無法入睡','after sleeping without a proper room':'沒有適當的房間睡覺',
  'after being forced to eat vermin to survive':'被迫吃害蟲求生','drinking nasty water':'喝了難喝的水',
  'drinking the same old booze':'反覆喝同一種酒','eating the same old food':'反覆吃同一種食物',
};
const preferenceReasons={
  'chestnuts':'栗子','wine':'釀成的酒','stinging tail':'帶螫針的尾巴','agility':'敏捷的身手',
  'tooth whorl':'螺旋狀齒列','parenting':'育幼行為','pods':'莢果','gray leaves':'灰色葉片',
  'scuttling':'快速爬行的姿態','tail club':'尾錘','ferocious jaws':'凶猛的顎部','length':'長度',
  'blossoms':'花朵','coldness to the touch':'冰冷的觸感','beer':'啤酒','spots':'斑點','dome':'圓隆的頭頂',
  'snouts':'吻部','sails':'背帆','thorns':'尖刺','edible roots':'可食用的根','grain':'穀粒',
  'giant second foredigit claws':'前肢第二指的巨爪','flatness':'扁平的形態','waxy berries':'帶蠟質的漿果',
  'small trunk':'短小的鼻子','sad appearance':'哀傷的外表','three horns':'三隻角',
  'nut-filled pots':'裝滿堅果的壺狀果實','menacing spikes':'駭人的尖刺','seeds':'種子','wings':'翅膀',
  'affinity for land':'偏好陸地的習性','amazing arms':'驚人的前肢','armored carapace':'堅固的甲殼',
  'autumn coloration':'秋季的色彩','back plates':'背板','backward-curving tusks':'向後彎曲的獠牙',
  'beaks':'喙','bold head sclerites':'醒目的頭部硬片','branch shedding':'自行脫落的枝條',
  'broad heads':'寬闊的頭部','buds and berries':'芽與漿果','bulbs':'鱗莖','buttresses':'板根',
  'catkins':'柔荑花序','cloves':'蒜瓣','cones':'毬果','crest':'冠飾','curving trunk':'彎曲的鼻子',
  'delicious shoots':'美味的嫩芽','disturbing size':'令人不安的體型','double carapace':'雙層甲殼',
  'edible nuts':'可食用的堅果','edible tubers':'可食用的塊莖','elongated snout':'細長的吻部',
  'extra eyes':'額外的眼睛','eye horns':'眼部的角','feathers':'羽毛','feathery leaves':'羽毛般的葉片',
  'ferocious bite':'凶猛的咬擊','fibrous stems':'富含纖維的莖','fine grain':'細緻的紋理',
  'flippers':'鰭肢','flowers':'花朵','fluffy catkins':'毛茸茸的柔荑花序','flying keys':'飛旋的翅果',
  'forked horns':'分叉的角','fragrant fruit':'芳香的果實','frontal appendages':'前方的附肢',
  'fruit':'果實','fruit and nuts':'果實與堅果','fuzzy projections':'毛茸茸的突起',
  'giant claws':'巨大的爪子','gigantic eye teeth':'巨大的犬齒','gloomy appeal':'陰鬱的魅力',
  'graceful flight':'優雅的飛行姿態','graceful movement':'優雅的動作','grasping proboscis':'可抓握的長鼻',
  'hairy heads':'毛茸茸的頭部','hanging leaves':'垂掛的葉片','head crests':'頭冠','inner light':'體內的光芒',
  'jawed proboscis':'帶顎的長吻','jaws':'顎部','leaf coloration':'葉片的色彩','leaves':'葉片',
  'lens-shaped seeds':'透鏡狀的種子','lively nature':'活潑的天性','living shadows':'活生生的陰影',
  'lobopods':'葉足','long tongues':'長舌','loose inflorescences':'疏鬆的花序','magnificence':'壯麗的姿態',
  'needles':'針葉','nuts':'堅果','oil-giving fruit':'能榨油的果實','popped kernels':'爆開的穀粒',
  'precise lines':'整齊的線條','precise thorns':'排列整齊的刺','raining spores':'如雨飄落的孢子',
  'roots':'根','round heads':'圓頭','round shape':'圓潤的外形','rounded tops':'圓潤的頂部',
  'sail':'背帆','scything claws':'鐮刀般的爪子','short arms':'短小的前肢','shovel-like lower tusks':'鏟狀的下獠牙',
  'shrouded history':'神祕的歷史','sickening appearance':'令人作嘔的外表','silver bark':'銀色樹皮',
  'single claws':'單爪','slithering':'蜿蜒爬行的姿態','smelly catkins':'氣味強烈的柔荑花序',
  'soothing color':'令人舒心的色彩','soothing fragrance':'令人放鬆的香氣','spiny pods':'帶刺的莢果',
  'sprouts':'嫩芽','stalks':'莖稈','stiff, triangular leaves':'堅挺的三角形葉片','stout bodies':'粗壯的身軀',
  'stout shape':'粗壯的外形','striking color':'醒目的色彩','stunning color':'驚豔的色彩',
  'sweeping stalks':'舒展的莖稈','sweet-smelling flowers':'芬芳的花朵','tail spikes':'尾刺',
  'taste':'滋味','terrifying beaks':'駭人的喙','thumb spikes':'拇指上的尖刺','tilted walk':'傾斜的步態',
  'tiny arms':'細小的前肢','tiny leaves':'細小的葉片','tubers':'塊莖','twisting shape':'扭曲的外形',
  'twisting stalks':'扭曲的莖稈','two teeth':'兩顆牙齒','useful stems':'實用的莖',
  'vivid red color':'鮮豔的紅色','wedge-shaped heads':'楔形的頭部','wicked thorns':'兇險的尖刺',
  'wingspan':'翼展','yummy cherries':'美味的櫻桃','yummy hearts':'美味的菜心',
};
const events={
  'I once wandered the wilds.':'我曾在荒野漫遊。',
  'Once it was my calling to rescue lost children.':'我曾以拯救迷途的孩子為使命。',
  'In the past, I hunted great beasts.':'過去，我曾獵捕巨獸。',
  'I once sought great treasures.':'我曾尋找珍貴的寶藏。',
  'In the past, I sought fortune and glory by offering my skill at arms.':'過去，我曾憑藉武藝為人效力，追求財富與榮耀。',
  'I am a soldier.':'我是士兵。','I am a guard.':'我是守衛。',
  'Hellooo!':'哈囉！','Prepare to die!':'準備受死吧！',
  'Who dares to enter my house?  I curse you!':'誰敢闖進我的屋子？我詛咒你！',
  'A baby!  How adorable!':'是個嬰兒！真可愛！','Look at you!':'瞧瞧你！',
  "Don't start any trouble.":'別惹麻煩。',"I'm pleased to hear that.":'聽到這件事我很高興。',
  "I'm proud of you.":'我以你為榮。',"I'm thrilled to hear that.":'聽到這件事我興奮極了。',
  'wonderful!':'太棒了！','fantastic!':'太好了！','very good.':'很好。',
  'that is good news.':'那是個好消息。','that is wonderful news.':'那真是個絕佳的消息。',
  'that is a good turn of affairs.':'事情有了好的轉變。','this is encouraging.':'這令人鼓舞。',
  'Some migrants have arrived.':'有移民抵達了。',
  'Some migrants have arrived, despite the danger.':'儘管有危險，仍有移民抵達了。',
  'Some migrants have arrived at this unhappy place.':'有移民抵達這個不快樂的地方了。',
  'Some migrants have arrived at this miserable place.':'有移民抵達這個悲慘的地方了。',
  'Migrants were too nervous to make the journey this season.':'移民因為太過不安，本季沒有啟程。',
  'Migrants were too wary to make the journey this season.':'移民因為心懷戒備，本季沒有啟程。',
  'Migrants refused to journey to such a dangerous fortress this season.':'移民拒絕在本季前往如此危險的要塞。',
  'The enemy have come and are preparing to lay siege.  They seek a parley!':'敵人已抵達，正準備圍城。他們要求談判！',
  'The enemy have come and are laying siege to the fortress.':'敵人已抵達，正在圍攻要塞。',
  'An ambush!  Curse them!':'有埋伏！該死的傢伙！',
  'An ambush!  Drive them out!':'有埋伏！把他們趕出去！',
  'An ambush!  Skulking vermin!':'有埋伏！鬼鬼祟祟的害蟲！',
  'An ambush!  Curse all friends of nature!':'有埋伏！詛咒所有自然之友！',
  'Spring has arrived!':'春天到了！', 'Autumn has come.':'秋天到了。',
  'Spring has arrived on the calendar.':'依照曆法，春天到了。',
  'Summer has arrived on the calendar.':'依照曆法，夏天到了。',
  'Autumn has arrived on the calendar.':'依照曆法，秋天到了。',
  'Winter has arrived on the calendar.':'依照曆法，冬天到了。',
  'This is an example urgent alert!  These are very important.  Ignore them at your peril.':'這是緊急警報的範例！這些警報非常重要，忽略它們可能會帶來危險。',
  '"Try to focus on the practical side of the matter."':'「試著專注於事情實際的一面。」',
  '"I have trouble controlling my temper."':'「我很難控制自己的脾氣。」',
};
export function lifeRows() {
  const rows=new Map();
  const add=(text,translation,kind='sentence')=>{
    if(rows.has(text) && rows.get(text).translation!==translation) throw new Error(`Conflicting life clause: ${text}`);
    rows.set(text,{text,translation,tags:`[REVIEWED:1][PROSE:${kind}]`});
  };
  for(const [he,zh] of [['He','他'],['She','她'],['It','牠']]) {
    for(const [state,[prefix,suffix]] of Object.entries(states))
      for(const [reason,target] of Object.entries(needs)) add(`${he} is ${state} after ${reason}.`,`${zh}${prefix}${target}${suffix}。`);
    for(const [state,target] of Object.entries(overall)) add(`Overall, ${he.toLowerCase()} is ${state}.`,`總體而言，${zh}${target}。`);
  }
  // Do not change an unrelated UI label like "content" or "free" globally.
  for(const [source,target] of Object.entries(emotions)) add(`DFL_EMOTION:${source}`,target,'emotion');
  for(const [source,target] of Object.entries(reasons)) add(`DFL_REASON:${source}`,target,'reason');
  for(const [source,target] of Object.entries(preferenceReasons)) add(`DFL_PREF_REASON:${source}`,target,'preference-reason');
  for(const [source,target] of Object.entries({ash:'白蠟樹',eggplant:'茄子'}))
    add(`DFL_PREF_SUBJECT:${source}`,target,'preference-subject');
  for(const [source,target] of Object.entries(events)) add(source,target);
  for(const [direction,d] of Object.entries({northern:'北方',southern:'南方',eastern:'東方',western:'西方',northeastern:'東北方',northwestern:'西北方',southeastern:'東南方',southwestern:'西南方'}))
    for(const [terrain,t] of Object.entries({swamps:'沼澤',marshes:'濕地',river:'河流',lake:'湖泊',ocean:'海洋',sea:'海域'}))
      add(`There is nothing to catch in the ${direction} ${terrain}.`,`${d}${t}沒有可捕捉的魚。`);
  return [...rows.values()];
}
export async function buildOfflineLife(output) {
  const rows=lifeRows();
  for(const language of ['zh-Hant','zh-Hans']) {
    const localized=rows.map(row=>({...row,translation:language==='zh-Hans'?simplify(row.translation):row.translation}));
    await writeFile(join(output,'dfi18n-data/simple',language,'zzzzzzzzzz-offline-life.csv'),stringify(localized,{header:true,columns:['text','translation','tags']}));
  }
  return rows.length;
}
