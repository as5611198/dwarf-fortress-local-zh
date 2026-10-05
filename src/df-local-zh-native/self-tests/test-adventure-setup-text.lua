-- Native setup text is split before addst; bind complete translated paragraphs.
local function vector(rows)
    local result={}
    for i,row in ipairs(rows) do result[i-1]=row end
    return setmetatable(result,{__len=function() return #rows end})
end
local address=100
local function box(rows)
    local values={}
    for _,text in ipairs(rows) do address=address+1; values[#values+1]={value=text,address=address} end
    return {text=vector(values)}
end
local original={'Difficulty only ','affects ','starting skills ','and equipment.'}
local screen={_type='setupadventure',mode=0,destiny_desc=vector({box({}),box({}),box({})}),difficulty_desc=box(original)}
local world='fixture/world'
local bindings,requests={},{}
local source='Difficulty only affects starting skills and equipment.'
local translated='難度只影響初始技能與裝備。'
local runtime={display_rows=function(rows) bindings=rows end,translation=function(s)
    requests[#requests+1]=s
    if s==source then return translated end
end}
local env=setmetatable({
    df={viewscreen_setupadventurest='setupadventure',sizeof=function(row) return 32,row.address end,
        global={game={main_interface={view_sheets={}}}}},
    dfhack={isWorldLoaded=function() return world~=nil end,isMapLoaded=function() return false end,
        getSavePath=function() return world end,df2utf=function(s) return s end,
        gui={getCurViewscreen=function() return screen end,getFocusStrings=function() return {'setupadventure'} end}},
},{__index=_G})
assert(loadfile((...) or dfhack.findScript('df-local-zh-unit-text'),'t',env))()
env.poll(runtime)
assert(#requests==1 and requests[1]==source,'Request the whole setup explanation, never its wrapped fragments')
assert(#bindings==4,'All native rows including blank Chinese tails need bindings')
local parts={}
for i,row in ipairs(bindings) do
    parts[i]=row.translation
    assert(row.source==original[i] and row.address==screen.difficulty_desc.text[i-1].address)
    assert(utf8.len(row.translation)*2<=row.width,'Do not overflow the native box')
    assert(screen.difficulty_desc.text[i-1].value==original[i],'Never mutate native source strings')
end
assert(table.concat(parts)==translated,'Preserve complete UTF-8 Chinese without truncation')
-- Reallocation/narrowing refreshes scalar address bindings; no retained pointers.
screen.difficulty_desc=box({'Difficulty ','only affects ','starting ','skills and ','equipment.'})
env.poll(runtime)
assert(#bindings==5 and bindings[1].address==screen.difficulty_desc.text[0].address)
parts={};for i,row in ipairs(bindings) do parts[i]=row.translation end
assert(table.concat(parts)==translated)
screen.difficulty_desc=box({'Difficulty only unknown prose.'})
env.poll(runtime);assert(#bindings==0,'Unknown complete paragraphs preserve original display')
screen.difficulty_desc=box(original);screen.mode=1
env.poll(runtime);assert(#bindings==0,'Clear bindings on leaving destiny selection')
screen.mode=0;screen._type='other'
env.poll(runtime);assert(#bindings==0,'Do not infer a screen from field names alone')
screen._type='setupadventure';screen.difficulty_desc=box({string.rep('x',257)})
local count=#requests;env.poll(runtime);assert(#bindings==0 and #requests==count,'Bound input row size')
local rows={};for i=1,33 do rows[i]='Difficulty only ' end
screen.difficulty_desc=box(rows);env.poll(runtime);assert(#bindings==0 and #requests==count,'Bound input row count')
screen.difficulty_desc=box(original);world=nil
env.poll(runtime);assert(#bindings==0,'Clear bindings when the world unloads')
-- A failed scheduled poll must clear stale native bindings and report the error.
local background=setmetatable({df=env.df,dfhack=env.dfhack},{__index=_G})
assert(loadfile(dfhack.findScript('df-local-zh-adventure-background'),'t',background))()
env.reqscript=function(name) assert(name=='df-local-zh-adventure-background');return background end
local identity_reads=0
env.df.world_site={find=function(id)
    identity_reads=identity_reads+1
    return id==1 and {name='Fixturetown',entity_links=vector({})} or nil
end}
env.dfhack.translation={translateName=function(name) return name end}
local background_rows={'You are a miner in Fixturetown, a human hamlet, and ', 'you have never strayed far from home.'}
local sheet={sub_mode=9,start_site_id=1,background_start_squad_epp_id=-1,background_text=box(background_rows)}
screen.mode=5;screen.csheet=vector({sheet});screen.active_sheet_index=0;world='fixture/world'
local normal_translation=runtime.translation
runtime.translation=function(s)
    requests[#requests+1]=s
    if s=='miner' then return '礦工' end
    if s=='human hamlet' then return '人類村落' end
    if s=='You are a {ADV_JOB} in {ADV_SITE}, a {ADV_SITE_KIND}, and you have never strayed far from home.' then
        return '你是{ADV_SITE}（{ADV_SITE_KIND}）的{ADV_JOB}，從未遠離家鄉。'
    end
end
env.poll(runtime)
assert(#bindings==2,'Character background needs complete native row bindings')
for _,row in ipairs(bindings) do assert(row.verified_name_literals==true,'Native bridge must explicitly preserve verified background names') end
parts={};for i,row in ipairs(bindings) do parts[i]=row.translation;assert(sheet.background_text.text[i-1].value==background_rows[i]) end
assert(table.concat(parts)=='你是Fixturetown（人類村落）的礦工，從未遠離家鄉。')
env.poll(runtime);assert(identity_reads==1,'Cache world reference resolution until the source or identity changes')
sheet.start_site_id=2;env.poll(runtime);assert(#bindings==0,'A different site cannot reuse the old verified identity')
sheet.start_site_id=1;sheet.sub_mode=6;env.poll(runtime);assert(#bindings==0,'Clear background bindings outside the background tab')
screen.active_sheet_index=10000;sheet.sub_mode=9;env.poll(runtime);assert(#bindings==0,'Bound selected sheet access')
screen.active_sheet_index=0;sheet.sub_mode=7
sheet.appearance_text=box({'His hair is wavy.  His skin is brown.', ' ', 'A short, sturdy creature fond of drink and industry.'})
runtime.translation=function(s)
    if s=='His hair is wavy.  His skin is brown.' then return '他的頭髮呈波浪狀。他的皮膚呈棕色。' end
    if s=='A short, sturdy creature fond of drink and industry.' then return '一種矮小而結實的生物，喜愛飲酒與勞作。' end
    if s=='He dreams of making a great discovery.' then return '他夢想做出偉大的發現。' end
end
env.poll(runtime)
assert(#bindings==2,'Appearance paragraphs translate independently around native blank rows')
for _,row in ipairs(bindings) do assert(not row.verified_name_literals,'Ordinary prose must retain the no-English completeness guard') end
assert(bindings[1].address==sheet.appearance_text.text[0].address and bindings[2].address==sheet.appearance_text.text[2].address)
sheet.sub_mode=8;sheet.personal_values_text=box({'He dreams of making a great discovery.'})
sheet.personality_text=box({'Unknown trait paragraph.'});sheet.civ_values_text=box({})
env.poll(runtime);assert(#bindings==1 and bindings[1].address==sheet.personal_values_text.text[0].address,'Keep native palette boundaries and unknown trait prose')
runtime.translation=normal_translation;screen.mode=0
local scheduled,errors
env.reqscript=function() return {poll=function() end} end
env.require=function(name)
    assert(name=='repeat-util')
    return {scheduleUnlessAlreadyScheduled=function(_,_,_,callback) scheduled=callback end}
end
env.dfhack.printerr=function(err) errors=err end
world='fixture/world';env.start(runtime);scheduled();assert(#bindings==4)
env.dfhack.df2utf=function() error('fixture decode failure') end
scheduled();assert(#bindings==0 and errors:find('fixture decode failure',1,true),'Clear and report scheduled errors')
print('PASS adventure setup whole paragraphs, UTF-8, resize, scope and bounds')
