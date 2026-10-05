-- All world/native objects are mocked. Reproduces the observed [B] health box.
local function vector(rows)
    local out={};for i,row in ipairs(rows) do out[i-1]=row end
    return setmetatable(out,{__len=function() return #rows end})
end
local raw='A short, sturdy creature fond of drink and industry.[B][C:2:0:0]She is rarely sick, [C:4:0:0]but she is flimsy and very quick to tire.  [B][C:7:0:1]Her hair is unknown.  '
local originals={'A short, sturdy creature fond of drink and industry.','',
    'She is rarely sick, but she is flimsy and very quick','to tire.','','Her hair is unknown.'}
local function make_box()
    local rows={}
    for i,text in ipairs(originals) do rows[i]={text=text,color=string.rep(string.char(i==3 and 2 or i==4 and 4 or 7),#text)} end
    return {width=53,line=vector(rows)}
end
local box=make_box()
local sheets={active_id=10,unit_health_raw_str=vector({{value=raw}}),unit_health_box=vector({box}),
    unit_knowledge_type=vector({}),unit_knowledge_id=vector({})}
local focus='dwarfmode/ViewSheets/UNIT/Health/Description'
local env=setmetatable({df={unit={find=function() return nil end},global={game={main_interface={view_sheets=sheets}}}},dfhack={
    isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
    getSavePath=function() return 'fixture/world' end,df2utf=function(s) return s end,
    gui={getCurViewscreen=function() return {} end,getFocusStrings=function() return {focus} end},
}},{__index=_G})
local ability='[C:2:0:0]She is rarely sick, [C:4:0:0]but she is flimsy and very quick to tire.'
local translations={
    [originals[1]]='一種矮小而結實的生物，喜愛飲酒與勞作。',
    [ability]='[C:2:0:0]她很少生病，[C:4:0:0]但她體質脆弱且十分容易疲勞。',
}
local aliases,seen={},{}
local pending=true
local function alias(text,color)
    if pending and text:find('體質',1,true) then return nil end
    local plain=text:gsub('%[C:%d+:%d+:%d+%]','')
    local key='L'..string.format('%06d',#aliases+1)..string.rep('_',math.max(0,utf8.len(plain)*2-7))
    aliases[#aliases+1]=key;aliases[key]={text=text,color=color};return key
end
local runtime={translation=function(s) seen[s]=true;return translations[s] end,
    colored_key=alias,announcement_key=alias}
assert(loadfile((...) or dfhack.findScript('df-local-zh-unit-text'),'t',env))()
env.poll(runtime)
assert(aliases[box.line[0].text] and aliases[box.line[0].text].text==translations[originals[1]],
    'A known first paragraph must translate without waiting for unknown appearance prose')
assert(seen[ability],'Physical ability must be queried with its complete semantic palette')
assert(box.line[2].text==originals[3] and box.line[3].text==originals[4],
    'Pending rich aliases must keep the whole ability paragraph intact')
assert(box.line[5].text==originals[6],'An unknown paragraph must remain English')
pending=false;env.poll(runtime)
local rich=assert(aliases[box.line[2].text]).text
assert(rich==translations[ability] and box.line[3].text=='','Physical colors and Chinese must survive reflow')
assert(box.line[1].text=='' and box.line[4].text=='','Native blank paragraph separators must remain intact')
local key=box.line[2].text;local requests=#aliases
env.poll(runtime)
assert(box.line[2].text==key and #aliases==requests,'Stable health polling must reuse existing aliases')
assert(sheets.unit_health_raw_str[0].value==raw,'Health source must never be changed')
focus='dwarfmode/Default';env.poll(runtime)
for i,text in ipairs(originals) do assert(box.line[i-1].text==text,'Exit must restore every original row') end

-- A layout mismatch must never write translated text into another paragraph.
focus='dwarfmode/ViewSheets/UNIT/Health/Description'
box=make_box();box.line[2].text='A different physical description.';sheets.unit_health_box=vector({box})
env.poll(runtime)
assert(box.line[0].text==originals[1] and box.line[2].text=='A different physical description.',
    'Mismatched source/layout must fail without mutating the display')
focus='dwarfmode/Default';env.poll(runtime)

-- The native game can rebuild rows without changing the page or unit.
focus='dwarfmode/ViewSheets/UNIT/Health/Description';box=make_box();sheets.unit_health_box=vector({box})
env.poll(runtime)
box.line[2].text=originals[3];box.line[2].color=string.rep(string.char(2),#originals[3])
env.poll(runtime)
assert(aliases[box.line[2].text] and box.line[3].text=='','A partially rebuilt paragraph must recover')
focus='dwarfmode/Default';env.poll(runtime)
for i,text in ipairs(originals) do assert(box.line[i-1].text==text,'Partial rebuild must not capture aliases as original rows') end
-- The first palette can be inherited from the native row instead of an explicit tag.
focus='dwarfmode/ViewSheets/UNIT/Health/Description';box=make_box();sheets.unit_health_box=vector({box})
local inherited=ability:gsub('^%[C:2:0:0%]','')
translations[inherited]=translations[ability]:gsub('^%[C:2:0:0%]','')
sheets.unit_health_raw_str[0].value=raw:gsub('%[C:2:0:0%]','')
env.poll(runtime)
assert(aliases[box.line[2].text].text==translations[ability],'An inherited green palette must not become gray')
-- A narrower box must restore first, then fit the whole paragraph or leave it original.
box.width=10;env.poll(runtime)
assert(box.line[2].text==originals[3] and box.line[3].text==originals[4],'Resize must not retain overflowing aliases')
box.width=53;env.poll(runtime)
assert(aliases[box.line[2].text].text==translations[ability],'Widening must recover the translated paragraph')
focus='dwarfmode/Default';env.poll(runtime)
for i,text in ipairs(originals) do assert(box.line[i-1].text==text,'Resize exit must restore original rows') end

-- Unknown raw markup is not safe to strip or silently ignore.
focus='dwarfmode/ViewSheets/UNIT/Health/Description';box=make_box();sheets.unit_health_box=vector({box})
sheets.unit_health_raw_str[0].value=raw..'[UNKNOWN]'
env.poll(runtime)
for i,text in ipairs(originals) do assert(box.line[i-1].text==text,'Invalid markup must fail without display writes') end
focus='dwarfmode/Default';env.poll(runtime)

-- Adventure omits the physical-ability paragraph, leaving consecutive [B]
-- separators. Empty prose is layout, not an unsupported appearance clause.
focus='dungeonmode/ViewSheets/UNIT/Health/Description'
local appearance='Her hair is curly.  Her skin is pale chestnut.'
local empty_raw=originals[1]..'[B][B][C:7:0:1]'..appearance..'  '
local empty_rows={originals[1],'','',appearance}
local native_rows={}
for i,text in ipairs(empty_rows) do native_rows[i]={text=text,color=string.rep(string.char(i==4 and 71 or 7),#text)} end
box={width=53,line=vector(native_rows)}
sheets.unit_health_box=vector({box});sheets.unit_health_raw_str[0].value=empty_raw
translations[appearance]='她的頭髮捲曲。她的皮膚呈淡栗色。'
env.poll(runtime)
assert(aliases[box.line[0].text] and aliases[box.line[3].text],
    'An omitted ability paragraph must not block the supported race and appearance paragraphs')
assert(aliases[box.line[3].text].text==translations[appearance] and box.line[3].color:byte(1)==71,
    'Appearance must remain complete with the inherited bright palette')
assert(box.line[1].text=='' and box.line[2].text=='','Preserve both native blank rows')
local empty_key=box.line[3].text;local before=#aliases
env.poll(runtime)
assert(box.line[3].text==empty_key and #aliases==before,'Consecutive separators must retain the layout cache')
assert(sheets.unit_health_raw_str[0].value==empty_raw,'Never write back into the raw health source')
focus='dungeonmode/Default';env.poll(runtime)
for i,text in ipairs(empty_rows) do assert(box.line[i-1].text==text,'Adventure exit must restore all original rows') end
print('PASS health paragraphs: independent readiness, inherited palette, atomic aliases, empty paragraphs, layout guards, rebuild, resize, restore')
