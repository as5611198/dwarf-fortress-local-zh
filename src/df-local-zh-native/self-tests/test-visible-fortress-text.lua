local function vector(rows)
    local result={};for i,row in ipairs(rows) do result[i-1]=row end
    return setmetatable(result,{__len=function() return #rows end})
end
local function box(texts)
    local rows={};for _,text in ipairs(texts) do rows[#rows+1]={value=text} end
    return {text=vector(rows)}
end
local now,world,map,focus=1000,'region3',true,'dwarfmode/Default'
local main={current_hover=1,hover_instructions_on=true,
    hover_instruction={[1]=box({'Set digging orders.'}),[2]=box({'Never visited instruction.'})},
    building={current_tool_tip_address=123,current_tool_tip=box({'Build a carpenter workshop.'})},
    hover_compass_stid=-1,hover_compass_text=box({'Old hidden place.'}),
    announcement_alert={open=false,alert_text=box({'Old hidden alert.'})},
    trade={open=false,big_announce=box({'Old hidden trade.'})},
    options={open=false,text=box({'Old hidden options.'}),entering_manual_str='player input'},
    view_sheets={open=false,item_use=vector({'Old item action'})},
    info={open=false,administrators={desc_hover_text=box({'Old noble text.'})},
        justice={interrogation_report_box=box({'Old interrogation.'})}},
}
local calls,logs={},{}
local log_opens=0
local ready=false
local env=setmetatable({
    require=require,
    io={open=function() log_opens=log_opens+1;return {write=function(_,line) logs[#logs+1]=line;return true end,
        close=function() return true end} end},
    reqscript=function(name)
        if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture' end} end
        if name=='df-local-zh-unit-prewarm' then return {fixed_translation=function() end} end
        error(name)
    end,
    df={global={game={main_interface=main}}},
    dfhack={isWorldLoaded=function() return world~=nil end,isMapLoaded=function() return map end,
        getSavePath=function() return world end,getTickCount=function() return now end,df2utf=function(s) return s end,
        gui={getCurViewscreen=function() return {} end,getFocusStrings=function() return {focus} end}},
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-visible-text.lua','t',env))()
local runtime={prefetch=function(source,priority)
    assert(priority=='foreground','Displayed text must promote background translation')
    calls[#calls+1]=source;return ready
end}
env.poll(runtime)
assert(#calls<=2 and calls[1]=='Set digging orders.' and calls[2]=='Build a carpenter workshop.',
    'The real building.current_tool_tip and active hover instruction must be connected')
for _,source in ipairs(calls) do assert(not source:find('hidden') and not source:find('Never visited'),
    'Hidden or unvisited buffers must not be globally pretranslated') end
local before=#calls
env.poll(runtime)
assert(#calls==before,'Foreground work must be throttled in real time')
ready=true;now=now+250;env.poll(runtime)
assert(env.status().ready==2 and main.hover_instruction[1].text[0].value=='Set digging orders.',
    'Ready original native keys must not mutate game sources or leak aliases')
before=#calls;now=now+250;env.poll(runtime)
assert(#calls==before,'Completed original keys must not be republished every frame')
main.hover_instructions_on=false;main.building.current_tool_tip_address=0
main.trade.open=true;main.trade.title='Merchant from the mountain'
main.trade.big_announce=box({'An offer has been made.'})
now=now+250;env.poll(runtime)
assert(calls[#calls]=='An offer has been made.' and calls[#calls-1]=='Merchant from the mountain')
assert(main.options.entering_manual_str=='player input','Input and search fields must remain untouched')
main.trade.open=false;main.view_sheets.open=true
focus='dwarfmode/ViewSheets/ITEM/General'
main.view_sheets.item_use=vector({'Make wooden bolts','L000012___','P_____','中文'})
main.view_sheets.engraving_title='The Quiet Wall'
now=now+250;env.poll(runtime)
for _,source in ipairs(calls) do assert(not source:match('^L000') and source~='P_____',
    'Display aliases must never enter AI or source logs') end
before=#calls;map=false;now=now+250;env.poll(runtime)
assert(#calls==before,'Legends must not run fortress text collection')
map=true;focus='dfhack/lua/status';now=now+250;env.poll(runtime)
assert(#calls==before,'An opaque DFHack screen must not translate covered game buffers')
focus='dwarfmode/Default';world='other-world';now=now+250;env.poll(runtime)
assert(env.status().world=='other-world','Visible progress must be isolated by world')
assert(#logs>0,'Sources, field IDs and readiness must be logged locally')

main.view_sheets.open=false;main.hover_instructions_on=true
main.current_hover=1
main.hover_instruction[1]=box({'L0009Ss_____ L0009Su_____',
    '[C:7:0:1]L0009St_____ [C:7:0:1]L0009Su_____',
    'L000123','L001___ P_____','Laborer','Lithium','Love','Lily'})
local rows=env.collect(main,focus)
assert(#rows==4,'Compound plain/colored aliases and bare aliases must never become translation jobs')
assert(rows[1].field_id=='main_interface.hover_instruction[1].text[4].value',
    'Text logs need exact zero-based row field IDs')
assert(rows[1].type=='hover','The source category must identify its actual UI boundary')

main.hover_instructions_on=false
main.image_creator={open=true,header='Create an image',last_selected_index=-1,
    art_box=box({'Visible art sentence.'}),selected_box=box({'Hidden selection sentence.'}),
    filter='player art filter',number_str='42'}
rows=env.collect(main,focus)
assert(#rows==2,'An unselected art detail buffer must stay excluded')
main.image_creator.last_selected_index=0
rows=env.collect(main,focus)
assert(#rows==3 and rows[3].text=='Hidden selection sentence.','Selected art details should become eligible')
main.image_creator.open=false
main.help={open=true,header='Getting started'}
rows=env.collect(main,focus)
assert(#rows==1 and rows[1].field_id=='help.header','The visible help header should be connected')
main.help.open=false
main.info.open=true;focus='dwarfmode/Info/JUSTICE'
main.info.justice.viewing_interrogation_report=nil
rows=env.collect(main,focus)
assert(#rows==0,'A stale interrogation buffer must not be translated without an active report')
main.info.justice.viewing_interrogation_report={id=1}
main.info.justice.interrogation_report_box=box({'Offscreen report.','Visible report.'})
main.info.justice.scroll_position_interrogation_report=1
rows=env.collect(main,focus)
assert(#rows==1 and rows[1].text=='Visible report.', 'Justice must use its real report scroll position')
assert(main.image_creator.filter=='player art filter' and main.image_creator.number_str=='42',
    'Art filters and numeric input must remain untouched')
main.info.open=false;focus='dwarfmode/Default';main.hover_instructions_on=true

local many={};for i=1,32 do many[i]='New visible log source '..i end
main.hover_instruction[1]=box(many)
local opened=log_opens
now=now+250;env.poll(runtime)
assert(log_opens-opened==1,'A new 32-row viewport must write its text log in one bounded batch')

-- Reaching the tracking limit must not turn every new ready row into repeated work.
ready=true
for i=1,4100 do
    main.hover_instruction[1]=box({'Visible source '..i})
    now=now+250;env.poll(runtime)
end
local state=env.status()
assert(state.tracked<=4096 and state.evicted>0,'Visible dedup state must remain bounded with explicit eviction')
before=#calls;local logged=#logs
for _=1,10 do now=now+250;env.poll(runtime) end
assert(#calls==before and #logs==logged,'New ready sources beyond the limit must still be deduplicated')
assert(state.pending==0 and state.ready<=state.collected,'Ready and progress counts must agree after eviction')

ready=false
main.hover_instruction[1]=box({'A pending foreground sentence.'})
now=now+250;env.poll(runtime);before=#calls
for _=1,8 do now=now+250;env.poll(runtime) end
assert(#calls-before<8,'Pending foreground rows must back off between readiness checks')
local failed=0
runtime.prefetch=function() failed=failed+1;error('fixture source failure') end
main.hover_instruction[1]=box({'A failing foreground sentence.'})
now=now+250;env.poll(runtime)
for _=1,8 do now=now+250;env.poll(runtime) end
assert(failed==1 and env.status().errors==1,'An error must not be retried or logged every frame')
runtime.prefetch=function() return true end
now=now+5000;env.poll(runtime)
assert(env.status().errors==0,'Successful completion must remove the current unresolved error')
world='capacity-boundary';ready=true
runtime.prefetch=function() return true end
for i=1,4096 do
    main.hover_instruction[1]=box({'Boundary source '..i})
    now=now+250;env.poll(runtime)
end
main.hover_instruction[1]=box({'Boundary source 1','A new boundary source.'})
now=now+250
local safe,err=pcall(env.poll,runtime)
assert(safe,'Eviction must not discard a row in the active viewport: '..tostring(err))
assert(env.status().pending==0 and env.status().tracked==4096 and env.status().errors==0)
main.hover_instructions_on=false
env.df.look_info_type={[0]='Item',[1]='Floor',[2]='Unit',[3]='Building'}
local mouse={x=10,y=20,z=3}
env.dfhack.gui.getMousePos=function() return mouse end
env.df.global.ui_look_list=vector({
    {type=1,pos={x=10,y=20,z=3},display_str='Smooth granite floor'},
    {type=0,pos={x=10,y=20,z=3},display_str='A silver war hammer'},
    {type=2,pos={x=10,y=20,z=3},display_str='Ur Randomname, Miner'},
    {type=3,pos={x=11,y=20,z=3},display_str='Stale offscreen workshop'},
    {type=0,pos={x=10,y=20,z=3},display_str='L000123___'},
})
rows=env.collect(main,focus)
assert(#rows==2 and rows[1].field_id=='ui_look_list[0].display_str' and
    rows[2].type=='map-hover:Item','Active map hover must use exact lookinfost display strings')
assert(env.df.global.ui_look_list[0].display_str=='Smooth granite floor',
    'Map tooltip source must remain unchanged')
mouse=nil
assert(#env.collect(main,focus)==0,'A stale map look list must be ignored when the mouse leaves the map')
mouse={x=10,y=20,z=3}
assert(#env.collect(main,'dwarfmode/ViewSheets/ITEM/General')==0,
    'Map hover must not collect tooltip buffers behind another panel')
print('PASS active real buffers, foreground priority, throttle, hidden exclusion, original preservation and world isolation')
