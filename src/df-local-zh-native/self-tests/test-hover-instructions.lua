-- Complete native tooltip rows must translate atomically without changing DF strings.
local function vector(rows)
    local result={}
    for i,row in ipairs(rows) do result[i-1]=row end
    return setmetatable(result,{__len=function() return #rows end})
end
local original={'Default attack is a ','strike without charging ','or wrestling.'}
local box={text=vector({{value=original[1],address=5011},{value=original[2],address=5012},{value=original[3],address=5013}})}
local m={view_sheets={},hover_instructions_on=true,current_hover=501,last_displayed_hover_inst=501,
    hover_instruction=vector({box})}
-- The actual array index is 501; mirror its fixed native size.
m.hover_instruction=setmetatable({[501]=box},{__len=function() return 622 end})
local loaded,map,focus=true,true,'dungeonmode/CombatPreferences'
local env=setmetatable({df={global={game={main_interface=m}},sizeof=function(row) return 32,row.address end},
    dfhack={isWorldLoaded=function() return loaded end,isMapLoaded=function() return map end,
        getSavePath=function() return 'fixture/world' end,df2utf=function(s) return s end,
        gui={getCurViewscreen=function() return {} end,getFocusStrings=function() return {focus} end}}},
    {__index=_G})
local full='Default attack is a strike without charging or wrestling.'
local translated='預設攻擊為一般打擊，不使用衝撞或摔角。'
local translations={[full]=translated,['Unknown fragment ']='假譯文',['or wrestling.']='假片段'}
local requested,bindings={},nil
local runtime={translation=function(source) requested[#requested+1]=source;return translations[source] end,
    display_rows=function(rows) bindings=rows;return true end,
    colored_key=function() error('Tooltip must use native bindings, never mutate aliases') end}
assert(loadfile(dfhack.findScript('df-local-zh-unit-text'),'t',env))()
env.poll(runtime)
assert(bindings and #bindings==3,'A displayed complete tooltip must publish all three native rows')
assert(#requested==1 and requested[1]==full,'Wrapped tooltip must request the complete source once')
assert(bindings[1].translation..bindings[2].translation..bindings[3].translation==translated,
    'Complete translation must reflow without English tails or missing characters')
for i=0,2 do
    assert(box.text[i].value==original[i+1],'Native source strings must remain byte-for-byte unchanged')
    assert(bindings[i+1].source==original[i+1] and bindings[i+1].address==5011+i)
    assert(utf8.len(bindings[i+1].translation)*2<=bindings[i+1].width,'Chinese must fit each native row')
end
-- Native strings can be reallocated between polls; only fresh addresses are published.
for i=0,2 do box.text[i]={value=original[i+1],address=6011+i} end
env.poll(runtime)
assert(bindings[1].address==6011 and bindings[3].address==6013)
m.hover_instructions_on=false;env.poll(runtime)
assert(#bindings==0,'Hiding the tooltip must clear every tooltip binding')
m.hover_instructions_on=true;m.last_displayed_hover_inst=500;env.poll(runtime)
assert(#bindings==0,'A stale last-displayed tooltip must not be rebound')
m.last_displayed_hover_inst=501
box.text=vector({{value='Unknown fragment ',address=7011},{value='or wrestling.',address=7012}})
requested={};env.poll(runtime)
assert(#bindings==0 and #requested==1 and requested[1]=='Unknown fragment or wrestling.',
    'Known arbitrary fragments must never translate part of an unknown tooltip')
box.text=vector({{value=full,address=8011}})
translations[full]=string.rep('漢',100);env.poll(runtime)
assert(#bindings==0,'An oversized translation must fall back atomically')
translations[full]='𠮷'..translated;env.poll(runtime)
assert(#bindings==1 and bindings[1].translation=='𠮷'..translated,'Supplementary characters must remain intact')
-- At 24 cells the old fixed slicing put the final stop on a line by itself.
box.text=vector({{value='Choose default attack ',address=8101},{value='according to opponent.',address=8102}})
translations['Choose default attack according to opponent.']='依對手選擇預設攻擊方式。'
env.poll(runtime)
assert(#bindings==2 and bindings[2].translation~='。' and bindings[2].translation:sub(1,3)~='。',
    'Tooltip wrapping must keep closing punctuation with a preceding character')
assert(bindings[1].translation..bindings[2].translation=='依對手選擇預設攻擊方式。')
translations['Choose default attack according to opponent.']='甲乙丙丁戊己庚辛壬癸（子丑。'
env.poll(runtime)
assert(bindings[1].translation:sub(-3)~='（','Opening brackets must stay with the following character')
assert(bindings[1].translation..bindings[2].translation=='甲乙丙丁戊己庚辛壬癸（子丑。')
-- An impossible punctuation run may not publish a partial paragraph.
translations['Choose default attack according to opponent.']=string.rep('。',15)
env.poll(runtime);assert(#bindings==0,'An unbreakable punctuation run must keep native fallback')
for _,bad in ipairs({'bad\0source','bad\nsource','[KEY:SELECT] source',string.rep('a',257)}) do
    box.text=vector({{value=bad,address=9001}});requested={};env.poll(runtime)
    assert(#bindings==0 and #requested==0,'Unsupported controls, markup and bounds must keep native fallback')
end
local many={};for i=1,33 do many[i]={value='row ',address=10000+i} end
box.text=vector(many);requested={};env.poll(runtime)
assert(#bindings==0 and #requested==0,'Tooltip row count must be bounded before translation')
box.text=vector({{value=full,address=8011}});translations[full]=translated
for _,index in ipairs({-1,622,1.5}) do
    m.current_hover=index;m.last_displayed_hover_inst=index;env.poll(runtime)
    assert(#bindings==0,'Invalid native array indices must clear bindings without dereferencing')
end
m.current_hover=501;m.last_displayed_hover_inst=501
loaded=false;env.poll(runtime);assert(#bindings==0,'Unloading the world must clear bindings')
loaded=true;map=false;env.poll(runtime);assert(#bindings==0,'Leaving map rendering must clear bindings')
print('PASS complete visible hover instructions, atomic fallback, UTF-8 fit and transition clearing')
