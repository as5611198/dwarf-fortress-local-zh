local source=...
local function vector(rows)
 local v={};for i,row in ipairs(rows) do v[i-1]=row end
 return setmetatable(v,{__len=function()return #rows end})
end
local raw='[C:7:0:0]He felt [C:3:0:1]fondness [C:7:0:0]talking with a friend.'
local translated='[C:7:0:0]他因[C:7:0:0]與朋友交談而感到[C:3:0:1]親近[C:7:0:0]。'
local box={width=70,line=vector({{text='He felt fondness talking with a friend.',color=string.rep(string.char(7),38)}})}
local sheets={active_id=1,raw_thought_str=vector({{value=raw}}),thought_box=vector({box}),unit_knowledge_type=vector({}),unit_knowledge_id=vector({})}
local adapter=setmetatable({df={global={game={main_interface={view_sheets=sheets}}},unit={find=function()return nil end}},
 dfhack={isWorldLoaded=function()return true end,isMapLoaded=function()return true end,getSavePath=function()return 'test/world' end,
 df2utf=function(s)assert(not s:find('親近',1,true),'UTF-8 translation must not be decoded as CP437');return s end,
 gui={getCurViewscreen=function()return {} end,getFocusStrings=function()return {'ViewSheets/UNIT/Thoughts/Current'}end}},
 reqscript=function()return {}end,require=function(name)if name=='repeat-util' then return {scheduleUnlessAlreadyScheduled=function()end}end;return require(name)end},{__index=_G})
assert(loadfile(source..'/df-local-zh-unit-text.lua','t',adapter))()
local calls,rendered=0,nil
local runtime={translation=function(s)calls=calls+1;if s==raw then return translated end end,
 colored_key=function()error('Thought must preserve its semantic color spans')end,
 announcement_key=function(text)rendered=text;return 'color_alias' end}
adapter.start(runtime);adapter.poll(runtime)
assert(rendered and rendered:find('[C:3:0:1]親近',1,true),'Emotion color was lost')
assert(box.line[0].text=='color_alias')
local before=calls;adapter.poll(runtime);assert(calls==before,'Stable page should not retranslate')
assert(sheets.raw_thought_str[0].value==raw)
print('OFFLINE_THOUGHTS PASS: full composition, semantic palette, UTF8 and stable polling')
