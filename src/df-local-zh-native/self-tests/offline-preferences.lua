local source=...
local env=setmetatable({dfhack_flags={module=true}},{__index=_G})
assert(loadfile(source..'/df-local-zh-preferences.lua','t',env))()
local s="A𠮷 Smith likes silver and the sound of The Song and Dance."
local masked,bindings=env.mask(s,'A𠮷 Smith',{'The Song and Dance'})
assert(masked=='{DWARF_NAME} likes silver and the sound of {PREF_NAME_1}.')
local translated='{DWARF_NAME}喜歡銀與{PREF_NAME_1}的聲音。'
assert(env.restore(translated,bindings,function() return nil end)=='A𠮷 Smith喜歡銀與「The Song and Dance」的聲音。')
assert(env.restore(translated,bindings,function(name) return name=='A𠮷 Smith' and '史密斯' or '歌與舞' end)=='史密斯喜歡銀與「歌與舞」的聲音。')
for _,bad in ipairs({'{DWARF_NAME}喜歡unknown。','{DWARF_NAME}喜歡{PREF_NAME_2}。','喜歡銀。','{DWARF_NAME}{DWARF_NAME}喜歡銀。'}) do assert(not env.restore(bad,bindings,function()end),bad) end
assert(not env.mask('Other likes silver.','A𠮷 Smith',{}))
assert(not env.mask('A𠮷 Smith likes {PREF_NAME_1}.','A𠮷 Smith',{}))
local poem,poem_bindings=env.mask('A𠮷 Smith likes the words of The Song and Dance.','A𠮷 Smith',{'The Song and Dance'})
assert(poem=='{DWARF_NAME} likes the words of {PREF_NAME_1}.','Poetry names must be masked like music and dance')
assert(env.restore('{DWARF_NAME}喜歡{PREF_NAME_1}的文字。',poem_bindings,function()end)=='A𠮷 Smith喜歡「The Song and Dance」的文字。')
local need,b=env.mask_need('She is distracted after being unable to pray to A𠮷.',{'A𠮷'})
assert(need=='She is distracted after being unable to pray to {DEITY_NAME}.')
assert(env.restore('她因為無法向{DEITY_NAME}祈禱而難以專注。',b,function()end)=='她因為無法向A𠮷祈禱而難以專注。')
assert(not env.mask_need('She is distracted after being unable to pray to A𠮷.',{'Another'}))
assert(not env.mask_need('She is distracted after being unable to pray to A𠮷. unknown',{'A𠮷'}))
assert(not env.mask_need('She is distracted after being unable to pray to {DEITY_NAME}.',{'{DEITY_NAME}'}))
-- Exercise the page adapter too: a literal canonical name must survive the
-- normal renderer's rejection of untranslated English prose.
local function vector(rows)
 local v={};for i,row in ipairs(rows) do v[i-1]=row end
 return setmetatable(v,{__len=function() return #rows end})
end
local raw='A Smith likes silver.'
local box={width=40,line=vector({{text=raw,color=string.rep(string.char(7),#raw)}})}
local sheets={active_id=1,personality_raw_str=vector({{value=raw}}),personality_box=vector({box}),
 unit_knowledge_type=vector({}),unit_knowledge_id=vector({})}
local adapter=setmetatable({df={global={game={main_interface={view_sheets=sheets}}},
 unit={find=function()return {id=1,status={current_soul={preferences={}}}} end}},
 dfhack={isWorldLoaded=function()return true end,isMapLoaded=function()return true end,
 getSavePath=function()return 'test/world' end,df2utf=function(s)return s end,
 units={getVisibleName=function()return {} end},translation={translateName=function()return 'A Smith' end},
 gui={getCurViewscreen=function()return {} end,getFocusStrings=function()return {'ViewSheets/UNIT/Personality/Preferences'} end}},
 reqscript=function(name) if name=='df-local-zh-preferences' then return env end;return {} end,
 require=function(name)if name=='repeat-util' then return {scheduleUnlessAlreadyScheduled=function()end} end;return require(name) end,
},{__index=_G})
assert(loadfile(source..'/df-local-zh-unit-text.lua','t',adapter))()
local rendered,literal_calls=nil,0
local runtime={translation=function(s)assert(s=='{DWARF_NAME} likes silver.');return '{DWARF_NAME}喜歡銀。' end,
 name_translation=function()return nil end,
 colored_key=function(text) assert(not text:match('[A-Za-z]'),'Literal name was sent to prose-only renderer');return 'normal' end,
 literal_colored_key=function(text,color)literal_calls=literal_calls+1;rendered=text;assert(color==string.char(7));return 'L000001___________' end}
adapter.start(runtime);adapter.poll(runtime)
assert(rendered=='A Smith喜歡銀。' and literal_calls==1)
adapter.poll(runtime);assert(literal_calls==1,'Stable page should reuse prepared rows')
assert(sheets.personality_raw_str[0].value==raw,'Never alter source identity')
-- The needs tab must actually reach the typed-name translator even when the
-- original sentence has no dictionary entry (the old precheck blocked it).
local prayer='She is distracted after being unable to pray to A Smith.'
sheets.personality_raw_str[0].value=prayer;box.line[0].text=prayer
box.width=80
adapter.dfhack.gui.getFocusStrings=function()return {'ViewSheets/UNIT/Personality/Needs'}end
adapter.df.unit.find=function()return {id=1,status={current_soul={personality={needs={{deity_id=42}}}}}}end
adapter.df.historical_figure={find=function(id)assert(id==42);return {name={}}end}
runtime.translation=function(s)
 if s=='She is distracted after being unable to pray to {DEITY_NAME}.' then return '她因為無法向{DEITY_NAME}祈禱而難以專注。' end
end
adapter.poll(runtime)
assert(rendered=='她因為無法向A Smith祈禱而難以專注。' and literal_calls==2,'Named needs must use verified identity and literal renderer')
assert(sheets.personality_raw_str[0].value==prayer)
-- DF can display an English surname for a deity even when its native name
-- differs. Both forms must come from the referenced historical figure.
adapter.dfhack.translation.translateName=function(_,english)return english and 'A Pointycrest' or 'A Native' end
sheets.personality_raw_str[0].value='She is distracted after being unable to pray to A Pointycrest.'
box.line[0].text=sheets.personality_raw_str[0].value
adapter.poll(runtime)
assert(rendered=='她因為無法向A Pointycrest祈禱而難以專注。','English deity surname must bind to its real reference')
print('OFFLINE_PREFERENCES PASS: typed slots, literal names, rejection, page renderer, stable polling')
