local n=reqscript('df-local-zh-core/native')
local runtime=reqscript('df-local-zh-runtime')
assert(reqscript('df-local-zh-settings').effective().apiEnabled==false)
assert(reqscript('df-local-zh-core/mod').DISPLAYED_VERSION=='0.5.11')
assert(n.local_lookup('{{DFL0}} married @1.')==nil)
local source='In 125, {{DFL0}} was created by {{DFL1}}'
assert(n.local_lookup(source)=='125年，{{DFL1}}創造了{{DFL0}}。')
assert(n.local_lookup('In 25, {{DFL0}} was created in {{DFL1}} by {{DFL2}}')=='25年，{{DFL2}}在{{DFL1}}創造了{{DFL0}}。')
local result,status=runtime.paragraph_lookup(source,{{id=1,type=3,text='The Silver Door'},{id=2,type=0,text='Urist 𠮷.'}})
assert(status=='ready' and result.translation=='125年，{{DFL1}}創造了{{DFL0}}。')
assert(result.links[2].translation=='Urist 𠮷')
assert(n.local_lookup('This is an iron battle axe. It is decorated with silver.'))
assert(n.local_lookup('This is an iron battle axe. It is encrusted with diamonds.')=='這是鐵戰斧。 它鑲嵌著鑽石。')
assert(n.local_lookup('On the item is an image of diamonds in diamond.')=='物品上有以鑽石製成的菱形圖像。')
assert(n.local_lookup('This is an iron battle axe. Unknown sentence.')==nil)
local fallback,state=runtime.paragraph_lookup('{{DFL0}} performed an unknown ritual.',{{id=2,type=0,text='Urist'}})
assert(state=='ready' and fallback.translation=='{{DFL0}} performed an unknown ritual.')
local art='On the item is an image of {{DFL0}} and dwarves in cat bone. {{DFL1}} is surrounded by the dwarves. The artwork relates to the election of {{DFL2}} to the position of mayor of {{DFL3}} in 1.'
local expected='物品上有以家貓骨頭製成的{{DFL0}}與矮人圖像。 {{DFL1}}被矮人包圍著。 這件藝術品描繪了{{DFL2}}於1年當選為{{DFL3}}市長的事件。'
assert(n.local_lookup(art)==expected)
local art_result,art_status=runtime.paragraph_lookup(art,{
 {id=1415,type=0,text='Urist 𠮷 the dwarf'},
 {id=1415,type=0,text='Urist 𠮷'},
 {id=1415,type=0,text='the dwarf Urist 𠮷'},
 {id=1007,type=6,text='The Held Gorge'},
})
assert(art_status=='ready' and art_result.translation==expected)
assert(art_result.links[1].translation=='Urist 𠮷 the dwarf')
assert(art_result.links[4].translation=='The Held Gorge')
assert(n.local_lookup(art..' Unknown sentence.')==nil)
assert(n.local_lookup('In 161, {{DFL0}} was stored in {{DFL1}} in {{DFL2}}')=='161年，{{DFL0}}被存放於{{DFL2}}的{{DFL1}}。')
print('ARTWORK_NATIVE PASS: 0.5.11 AI=false, linked artwork, literal identities, history, atomic fallback')

local loot='In the late spring of 88, {{DFL0}} was looted from {{DFL1}} by {{DFL2}} after defeating {{DFL3}}'
assert(n.local_lookup(loot)=='88年暮春，{{DFL2}}擊敗{{DFL3}}後，從{{DFL1}}掠走了{{DFL0}}。')
assert(n.local_lookup('{{DFL0}} b. 82 d. 157')=='{{DFL0}}：生於82年，卒於157年。')
assert(n.local_lookup('{{DFL0}} d. 233, two kills')=='{{DFL0}}：卒於233年，擊殺2次。')
assert(n.local_lookup('{{DFL0}} third eldest daughter, b. 4 d. 82')=='{{DFL0}}：第三女，生於4年，卒於82年。')
local loot_result,loot_status=runtime.paragraph_lookup(loot,{{id=11,type=0,text='Artifact'},{id=12,type=0,text='Fortress'},{id=13,type=0,text='Urist'},{id=14,type=0,text='Goblin'}})
assert(loot_status=='ready' and loot_result.translation=='88年暮春，{{DFL2}}擊敗{{DFL3}}後，從{{DFL1}}掠走了{{DFL0}}。')
assert(loot_result.links[1].translation=='Artifact' and loot_result.links[4].translation=='Goblin')
print('BIOGRAPHY_NATIVE PASS: offline looting, lifespan, kills, ordinal and heading')
