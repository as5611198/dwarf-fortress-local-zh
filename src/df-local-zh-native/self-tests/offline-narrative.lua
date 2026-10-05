local root=(...) or dfhack.getDFPath()..'/hack/scripts'
local env=setmetatable({},{__index=_G})
assert(loadfile(root..'/df-local-zh-offline-narrative.lua','t',env))()
local source='In 125, {{DFL0}} was created by {{DFL1}}'
local links={{id=9,type=3,text='The Silver Door'},{id=19,type=0,text='Urist 𠮷.'}}
local good='125年，{{DFL1}}創造了{{DFL0}}。'
local result=assert(env.translate(source,links,function(s) if s==source then return good end end))
assert(result.translation==good and #result.links==2)
assert(result.links[1].translation=='The Silver Door' and result.links[2].translation=='Urist 𠮷')
assert(links[2].text=='Urist 𠮷.','Original link text must not be mutated')
assert(env.valid('{{DFL0}}',{ {id=19,type=0,text='名。𠮷'} }),
  'UTF-8 punctuation bytes must not be mistaken for locale control characters')
assert(not env.valid('{{DFL0}}',{ {id=math.huge,type=0,text='Name'} }),
  'Native target identity must be finite')
for _,bad in ipairs({'125年，{{DFL0}}。','{{DFL0}}{{DFL0}}{{DFL1}}','{{DFL0}}{{DFL2}}','English {{DFL0}}{{DFL1}}','{{DFL0}}{{DFL1}}[C:evil]'}) do
  assert(env.translate(source,links,function() return bad end)==nil,bad)
end
assert(env.translate(source,{{id=9,type=3,text='bad{slot}'},links[2]},function() return good end)==nil)
assert(env.translate(source,{{id=-1,type=3,text='Name'},links[2]},function() return good end)==nil)
assert(env.translate(source,{},function() return good end)==nil)
assert(env.translate('This is a slab.',{},function() return '這是石板。' end).translation=='這是石板。')
local caption_source='{{DFL0}} attacked {{DFL1}}'
local caption_links={{type=0,id=1,text='the goblin Båx 𠮷'},{type=0,id=2,text='the yeti'}}
local caption_result=assert(env.translate(caption_source,caption_links,function(s)
  if s==caption_source then return '{{DFL0}}攻擊了{{DFL1}}。' end
  if s=='DFL_LEGENDS_RACE:goblin' then return '哥布林' end
  if s=='DFL_LEGENDS_RACE:yeti' then return '雪人' end
end))
assert(caption_result.links[1].translation=='哥布林 Båx 𠮷' and caption_result.links[2].translation=='雪人',
  'Race descriptions inside a figure label must translate while the exact Unicode name remains literal')
assert(caption_links[1].text=='the goblin Båx 𠮷','Caption translation must not change source link labels')
local capital_links={{type=0,id=1,text='The goblin Båx 𠮷'},caption_links[2]}
local capital_result=assert(env.translate(caption_source,capital_links,function(s)
  if s==caption_source then return '{{DFL0}}攻擊了{{DFL1}}。' end
  if s=='DFL_LEGENDS_RACE:goblin' then return '哥布林' end
  if s=='DFL_LEGENDS_RACE:yeti' then return '雪人' end
end))
assert(capital_result.links[1].translation=='哥布林 Båx 𠮷' and capital_links[1].text=='The goblin Båx 𠮷',
  'A sentence-initial native race article must preserve the same typed caption and literal name')
for _,caption in ipairs({'The Goblin Gate','The badger brute The Last Poison','THE goblin Urist'}) do
  local unchanged=assert(env.translate(caption_source,{{type=0,id=1,text=caption},caption_links[2]},function(s)
    if s==caption_source then return '{{DFL0}}攻擊了{{DFL1}}。' end
    if s=='DFL_LEGENDS_RACE:goblin' then return '哥布林' end
    if s=='DFL_LEGENDS_RACE:badger' then return '獾獾' end
  end))
  assert(unchanged.links[1].translation==caption,'Article casing must not certify an unknown race: '..caption)
end
local procedural='the badger brute The Last Poison'
local procedural_result=assert(env.translate(caption_source,
  {{type=0,id=1,text=procedural},caption_links[2]},function(s)
    if s==caption_source then return '{{DFL0}}攻擊了{{DFL1}}。' end
    if s=='DFL_LEGENDS_RACE:badger' then return '獾獾' end
  end))
assert(procedural_result.links[1].translation==procedural,
  'An unknown procedural race must not be partially translated as its shorter animal prefix')
local multiword=assert(env.translate(caption_source,
  {{type=0,id=1,text='the giant grizzly bear 𠮷'},{type=0,id=2,text='the goblin Båx'}},function(s)
    if s==caption_source then return '{{DFL0}}攻擊了{{DFL1}}。' end
    if s=='DFL_LEGENDS_RACE:giant grizzly bear' then return '巨型灰熊' end
    if s=='DFL_LEGENDS_RACE:grizzly bear' then return '灰熊' end
    if s=='DFL_LEGENDS_RACE:goblin' then return '哥布林' end
  end))
assert(multiword.links[1].translation=='巨型灰熊 𠮷' and multiword.links[2].translation=='哥布林 Båx',
  'The complete typed race must still translate before a literal Unicode proper name')
for _,caption in ipairs({'The Goblin Gate','the silver Road','the unknown beast Urist'}) do
  local unchanged=assert(env.translate(caption_source,{{type=0,id=1,text=caption},caption_links[2]},function(s)
    if s==caption_source then return '{{DFL0}}攻擊了{{DFL1}}。' end
    if s=='silver' then return '銀' end
  end))
  assert(unchanged.links[1].translation==caption,'Only typed vanilla races may change a label: '..caption)
end
assert(not env.translate(caption_source,{{type=0,id=1,text='the goblin [bad]'},caption_links[2]},function()
  error('Invalid link markup must reject before any lookup')
end))
local literal_source='{{DFT0}}, only daughter, b. 95'
local literals={{text='Urist 𠮷',color=9}}
local literal_result=assert(env.translate_literal(literal_source,{},literals,function(s)
  assert(s==literal_source);return '{{DFT0}}：獨生女，生於95年。'
end))
assert(literal_result.literals[1].translation=='Urist 𠮷' and #literal_result.links==0)
assert(not env.valid(literal_source,{}),'Local literal tokens must remain forbidden in the request protocol')
for _,bad in ipairs({'{{DFT0}}{{DFT0}}','{{DFT1}}','{{DFT0}} English','{{DFT00}}','{{DFT0}}{{DFL0}}'}) do
  assert(not env.translate_literal(literal_source,{},literals,function() return bad end),bad)
end
local mixed='{{DFT0}} married {{DFL0}}'
local mixed_result=assert(env.translate_literal(mixed,{links[2]},literals,function()
  return '{{DFT0}}與{{DFL0}}結婚。'
end))
assert(mixed_result.literals[1].translation=='Urist 𠮷' and mixed_result.links[1].translation=='Urist 𠮷')
assert(not env.translate_literal(literal_source,{},{{text='bad{token}',color=9}},function() error('must reject before lookup') end))
assert(not env.translate_literal(literal_source,{},{{text=string.char(255),color=9}},function() error('must reject invalid UTF-8') end))
print('OFFLINE_NARRATIVE PASS: link identity, reordering, literal Unicode, atomic rejection')
