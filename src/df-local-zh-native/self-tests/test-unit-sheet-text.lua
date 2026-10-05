local root = dfhack.getDFPath()
local function vector(rows)
    local result={}
    for i,row in ipairs(rows) do result[i-1]=row end
    return setmetatable(result,{__len=function() return #rows end})
end
local raw='[P][C:7:0:0]She is not distracted after leading an unexciting life.'
local lines=vector({{text='She is not distracted after leading an unexciting',color=string.rep('G',49)},
    {text='life.',color='GGGGG'}})
local box={line=lines,width=53}
local sheets={personality_raw_str=vector({{value=raw}}),personality_box=vector({box}),
    unit_knowledge_type=vector({14,15,16,17,0}),unit_knowledge_id=vector({1,2,3,4,5}),
    scroll_position_unit_skill=0}
local focus='dwarfmode/ViewSheets/UNIT/Personality/Needs'
local works={[1]='The Fuchsia Silkinesses',[2]='The Blue Song',[3]='The Quiet Dance'}
local preference_env=setmetatable({},{__index=_G})
assert(loadfile(dfhack.findScript('df-local-zh-preferences'),'t',preference_env))()
local env=setmetatable({
    reqscript=function(name)
        if name=='df-local-zh-preferences' then return preference_env end
        assert(name=='df-local-zh-nickname-display');return {poll=function() end}
    end,
    require=function(name)
        assert(name=='repeat-util')
        return {scheduleUnlessAlreadyScheduled=function() end,cancel=function() end}
    end,
    df={global={game={main_interface={view_sheets=sheets}}},
        view_sheet_unit_knowledge_type={[14]='POETIC_FORM',[15]='MUSICAL_FORM',[16]='DANCE_FORM',[17]='WRITTEN_CONTENT'},
        poetic_form={find=function(id) return {name=works[id]} end},
        musical_form={find=function(id) return {name=works[id]} end},
        dance_form={find=function(id) return {name=works[id]} end},
        written_content={find=function() return {title='A Treatise on Stone'} end}},
    dfhack={isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
        getSavePath=function() return 'fixture/world' end,df2utf=function(s) return s end,
        gui={getCurViewscreen=function() return {} end,getFocusStrings=function() return {focus} end},
        translation={translateName=function(name) return name end}},
},{__index=_G})
local translations={['She is not distracted after leading an unexciting life.']='她沒有因為生活平淡無奇而分心。',
    ['The Fuchsia Silkinesses']='紫紅絲滑',['The Blue Song']='藍色之歌',
    ['The Quiet Dance']='靜謐之舞',['A Treatise on Stone']='石材論述'}
local alias_text,requested,published={},{},{}
local runtime={translation=function(source)
    requested[source]=true
    return translations[source]
end,colored_key=function(text,color)
    assert(type(color)=='string' and #color==1,'Colored rows must carry their native palette byte')
    local key='L'..string.format('%06d',#alias_text+1)
    alias_text[#alias_text+1]=text
    alias_text[key]=text
    return key
end,publish=function(source,text) published[source]=text; return true end}
assert(loadfile((...) or dfhack.findScript('df-local-zh-unit-text'),'t',env))()
-- Exercise the production initialization path while keeping timers isolated.
runtime.literal_colored_key=runtime.colored_key
env.start(runtime)
env.poll(runtime)
assert(requested['She is not distracted after leading an unexciting life.'],
    'The hook must translate the full paragraph before native line splitting')
assert(alias_text[lines[0].text]=='她沒有因為生活平淡無奇而分心。' and lines[1].text=='',
    'Chinese must replace the wrapped paragraph without leaving English tails')
assert(sheets.personality_raw_str[0].value==raw,'Raw source prose must remain unchanged')
local first_key=lines[0].text
env.poll(runtime)
assert(lines[0].text==first_key,'Repeated polling must not recapture aliases as prose')
box.width=16
env.poll(runtime)
assert(#lines[0].text<=16 and #lines[1].text<=16,'Resizing must keep every alias inside its row')
assert(alias_text[lines[0].text]..alias_text[lines[1].text]=='她沒有因為生活平淡無奇而分心。',
    'Resizing must reflow the complete translation without truncating it')
focus='dwarfmode/Default'
env.poll(runtime)
assert(lines[0].text=='She is not distracted after leading an unexciting' and lines[1].text=='life.',
    'Leaving a sheet must restore only its display buffer')
focus='dwarfmode/ViewSheets/UNIT/Skills/Knowledge'
env.poll(runtime)
for title,translation in pairs(translations) do
    if title~='She is not distracted after leading an unexciting life.' then
        assert(published[title]==translation,'Knowledge title must be published for native render: '..title)
    end
end
assert(works[1]=='The Fuchsia Silkinesses','World form names must not be mutated')
focus='dwarfmode/ViewSheets/UNIT/Personality/Preferences'
sheets.active_id=12
env.df.unit={find=function(id) assert(id==12); return {sex=0,name='Doren Ushatesis',status={}} end}
env.dfhack.units={getVisibleName=function(unit) return unit.name end}
sheets.personality_raw_str=vector({{value='[C:7:0:1]Doren Ushatesis likes chicory.'}})
lines=vector({{text='Doren Ushatesis likes chicory.',color=string.rep('G',29)}})
sheets.personality_box=vector({{line=lines,width=53}})
translations['Doren Ushatesis']='多倫·地下小跑'
runtime.name_translation=function(source)
    assert(source=='Doren Ushatesis')
    return '多雷 烏夏特埃錫斯'
end
translations['{DWARF_NAME} likes chicory.']='{DWARF_NAME}喜歡菊苣。'
env.poll(runtime)
assert(requested['{DWARF_NAME} likes chicory.'] and not requested['Doren Ushatesis likes chicory.'],
    'Preferences must request a shared name-token template without sending the full name')
assert(alias_text[lines[0].text]=='多雷 烏夏特埃錫斯喜歡菊苣。',
    'The preference subject must keep the same name as the unit header')
local current_unit={sex=1,name='Feb Amemdakost',status={}}
sheets.active_id=13
env.df.unit.find=function(id) assert(id==13); return current_unit end
runtime.name_translation=function(source) assert(source=='Feb Amemdakost'); return '費布 埃梅姆達科斯' end
sheets.personality_raw_str=vector({{value='Feb Amemdakost likes chicory.'}})
lines=vector({{text='Feb Amemdakost likes chicory.',color=string.rep('G',29)}})
sheets.personality_box=vector({{line=lines,width=53}})
env.poll(runtime)
assert(alias_text[lines[0].text]=='費布 埃梅姆達科斯喜歡菊苣。',
    'Another unit must reuse the same template with its own name even without changing focus')
translations['{DWARF_NAME} likes chicory.']='喜歡菊苣。'
lines[0].text='Feb Amemdakost likes chicory.'
env.poll(runtime)
assert(lines[0].text=='Feb Amemdakost likes chicory.','A missing name token must not be displayed')
translations['{DWARF_NAME} likes chicory.']='{DWARF_NAME}{DWARF_NAME}喜歡菊苣。'
env.poll(runtime)
assert(lines[0].text=='Feb Amemdakost likes chicory.','A duplicated name token must not be displayed')
focus='dwarfmode/ViewSheets/UNIT/Personality/Needs'
local need_a={line=vector({{text='She needs company.',color='GGGGGGGGGGGGGGGGGG'}}),width=53}
local need_b={line=vector({{text='She needs excitement.',color='GGGGGGGGGGGGGGGGGGGGG'}}),width=53}
sheets.personality_raw_str=vector({{value='She needs company.'},{value='She needs excitement.'}})
sheets.personality_box=vector({need_a,need_b})
translations['She needs company.']='她需要陪伴。'
env.poll(runtime)
assert(alias_text[need_a.line[0].text]=='她需要陪伴。' and need_b.line[0].text=='She needs excitement.',
    'Ready Needs paragraphs must appear without waiting for an unrelated model request')
local ready_need_key=need_a.line[0].text
translations['She needs excitement.']='她需要刺激。'
env.poll(runtime)
assert(alias_text[need_a.line[0].text]=='她需要陪伴。' and alias_text[need_b.line[0].text]=='她需要刺激。',
    'Pending Needs paragraphs must render when their own translation is ready')
assert(need_a.line[0].text==ready_need_key,'Completing another paragraph must not replace an already displayed alias')
focus='dwarfmode/Default'; env.poll(runtime)
focus='dwarfmode/ViewSheets/UNIT/Personality/Needs'
local dense_sources,dense_boxes={},{}
for i=1,8 do
    local text='She needs company '..i..'.'
    translations[text]='她需要陪伴'..i..'。'
    dense_sources[#dense_sources+1]={value=text}
    dense_boxes[#dense_boxes+1]={line=vector({{text=text,color=string.rep('G',#text)}}),width=53}
    dense_sources[#dense_sources+1]={value=''}
    dense_boxes[#dense_boxes+1]={line=vector({{text='',color=''}}),width=53}
end
sheets.personality_raw_str=vector(dense_sources); sheets.personality_box=vector(dense_boxes)
env.poll(runtime)
for i=1,8 do
    assert(alias_text[dense_boxes[i*2-1].line[0].text]=='她需要陪伴'..i..'。',
        'Eight cached Needs must render in one pass without empty rows consuming the budget')
end
print('PASS unit sheet full paragraphs, alias stability, buffer restoration and four knowledge title types')

focus='dwarfmode/Default'; env.poll(runtime)
focus='dwarfmode/ViewSheets/UNIT/Personality/Preferences'
translations['{DWARF_NAME} likes chicory.']='{DWARF_NAME}喜歡菊苣。'
lines=vector({{text='Feb Amemdakost likes chicory.',color='G'..string.rep(string.char(2),28)}})
sheets.personality_raw_str=vector({{value='Feb Amemdakost likes chicory.'}})
sheets.personality_box=vector({{line=lines,width=53}})
env.poll(runtime)
assert(lines[0].color==string.rep('G',#lines[0].text),
    'Published single-color aliases must not retain unrelated source color transitions')

focus='dwarfmode/Default'; env.poll(runtime)
focus='dwarfmode/ViewSheets/UNIT/Personality/Needs'
sheets.personality_raw_str=vector({{value='She needs company.'},{value='She needs excitement.'}})
need_a={line=vector({{text='She needs company.',color=string.rep('G',18)}}),width=53}
need_b={line=vector({{text='She needs excitement.',color=string.rep('G',21)}}),width=53}
sheets.personality_box=vector({need_a,need_b})
local original_colored=runtime.colored_key
runtime.colored_key=function(text,color)
    if text=='她需要刺激。' then return nil end
    return original_colored(text,color)
end
env.poll(runtime)
assert(alias_text[need_a.line[0].text]=='她需要陪伴。' and need_b.line[0].text=='She needs excitement.',
    'An unavailable palette must only delay its own paragraph')
runtime.colored_key=original_colored
env.poll(runtime)
assert(alias_text[need_a.line[0].text]=='她需要陪伴。' and alias_text[need_b.line[0].text]=='她需要刺激。')
print('PASS uniform alias palettes and independent Needs paragraph readiness')

focus='dwarfmode/Default';env.poll(runtime)
for _,pair in ipairs({{'raw_thought_str','thought_box','Thoughts'},
    {'thoughts_raw_memory_str','thoughts_memory_box','Thoughts/Memories'},
    {'unit_health_raw_str','unit_health_box','Health'},
    {'skill_description_raw_str','skill_description_box','Skills'},
    {'kill_description_raw_str','kill_description_box','Military/Kills'}}) do
    focus='dwarfmode/ViewSheets/UNIT/'..pair[3]
    local source='A visible '..pair[3]..' description.'
    translations[source]='這是一段說明。'
    local display={line=vector({{text=source,color=string.rep('G',#source)}}),width=53}
    sheets[pair[1]]=vector({{value=source}});sheets[pair[2]]=vector({display})
    env.poll(runtime)
    assert(alias_text[display.line[0].text]=='這是一段說明。','Missing display adapter: '..pair[1])
    assert(sheets[pair[1]][0].value==source,'Raw source changed: '..pair[1])
    focus='dwarfmode/Default';env.poll(runtime)
    assert(display.line[0].text==source,'Display must restore on leaving '..pair[3])
end
focus='dwarfmode/ViewSheets/ITEM/Description'
sheets.raw_description='This is a silver hammer.'
sheets.description_width=53
sheets.description={text=vector({{value='This is a silver hammer.'}})}
translations[sheets.raw_description]='這是一把銀製戰錘。'
env.poll(runtime)
assert(alias_text[sheets.description.text[0].value]=='這是一把銀製戰錘。',
    'Item/building/unit descriptions need the curses text adapter')
focus='dwarfmode/Default';env.poll(runtime)
assert(sheets.description.text[0].value==sheets.raw_description,'Description display must restore')
print('PASS thoughts, memories, health, skills, kills and description adapters')

-- The game rebuilds curses description rows before drawing. A periodic alias
-- writer makes fragment translations alternate with the full paragraph.
focus='dwarfmode/Default';env.poll(runtime)
focus='dwarfmode/ViewSheets/ITEM/Description'
sheets.raw_description='This is a silver hammer. It is spattered with blood.'
sheets.description_width=30
local original_rows={'This is a silver hammer. ','It is spattered with blood.'}
sheets.description={text=vector({{value=original_rows[1]},{value=original_rows[2]}})}
translations[sheets.raw_description]='這是一把銀製戰錘。它沾滿血跡。'
env.df.sizeof=function(row)
    return 32,row==sheets.description.text[0] and 1001 or 1002
end
local bindings
runtime.display_rows=function(rows) bindings=rows;return true end
for frame=1,20 do
    for i=0,1 do sheets.description.text[i].value=original_rows[i+1] end
    env.poll(runtime)
    assert(sheets.description.text[0].value==original_rows[1] and
        sheets.description.text[1].value==original_rows[2],
        'Native description binding must not race the game by rewriting wrapped rows')
    assert(bindings and #bindings==2 and bindings[1].address==1001 and
        bindings[1].source==original_rows[1] and bindings[2].source==original_rows[2])
    assert(bindings[1].translation..bindings[2].translation==translations[sheets.raw_description],
        'Every rebuilt frame must use the same complete paragraph translation')
end
-- DF resets the width to zero while rebuilding the same paragraph. Do not
-- publish an empty binding batch between two valid-width frames.
sheets.description_width=0
env.poll(runtime)
assert(bindings and #bindings==2 and bindings[1].width==30,
    'Transient zero width must retain the proven layout for unchanged source rows')
assert(bindings[1].translation..bindings[2].translation==translations[sheets.raw_description])
sheets.raw_description='Another item description.'
sheets.description.text[0].value='Another item description.'
translations[sheets.raw_description]='另一物品。'
env.poll(runtime)
assert(#bindings==0,'A zero-width new item must never inherit the previous item layout')
focus='dwarfmode/Default';env.poll(runtime)
assert(#bindings==0,'Leaving the sheet must clear native description bindings')
runtime.display_rows=nil
print('PASS rebuilt item descriptions retain one native paragraph rendering')

-- Native item sheets retain the previous item's scroll offset, even when the
-- next item has only one row. A valid binding cannot draw an offscreen row.
focus='dwarfmode/Default';env.poll(runtime)
focus='dwarfmode/DWARF_ARENA/Default|dwarfmode/ViewSheets/ITEM'
sheets.active_id=11
sheets.raw_description='A long corpse description.'
sheets.description_width=54
local corpse_rows={}
for i=1,28 do corpse_rows[i]={value='Corpse row '..i} end
sheets.description={text=vector(corpse_rows)}
translations[sheets.raw_description]=string.rep('屍體說明。',60)
env.poll(runtime)
sheets.scroll_position_description=7
env.poll(runtime)
assert(sheets.scroll_position_description==7,'Polling the same item must preserve user scrolling')
for _,item in ipairs({{id=3,source='This is a silver shield.',text='這是一面銀盾。'},
    {id=0,source='This is a silver war hammer.',text='這是一把銀製戰錘。'}}) do
    sheets.active_id=item.id
    sheets.raw_description=item.source
    sheets.description={text=vector({{value=item.source}})}
    translations[item.source]=item.text
    sheets.scroll_position_description=7
    env.poll(runtime)
    assert(sheets.scroll_position_description==0,
        'Switching from a scrolled corpse must show the first row of '..item.source)
end
print('PASS corpse-to-equipment switching resets stale description scroll without resetting same-item scrolling')
