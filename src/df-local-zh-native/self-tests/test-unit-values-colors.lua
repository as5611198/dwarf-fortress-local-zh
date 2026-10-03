-- Run via dfhack-run lua "assert(loadfile(TEST)) (SOURCE)"; all game state is mocked.
local source_path=(...) or dfhack.findScript('df-local-zh-unit-text')
local function vector(rows)
    local out={};for i,row in ipairs(rows) do out[i-1]=row end
    return setmetatable(out,{__len=function() return #rows end})
end
local raw='[P][C:7:0:0]He values family.  [C:3:0:1]He personally respects power.  [C:6:0:1]He dreams of mastering a skill.  '
local originals={'He values family. He personally','respects power. He dreams of','mastering a skill.',''}
local lines={};for _,text in ipairs(originals) do lines[#lines+1]={text=text,color=string.rep(string.char(7),#text)} end
local box={width=22,line=vector(lines)}
local sheets={personality_raw_str=vector({{value=raw}}),personality_box=vector({box}),
    unit_knowledge_type=vector({}),unit_knowledge_id=vector({})}
local focus='dwarfmode/ViewSheets/UNIT/Personality/Values'
local env=setmetatable({df={global={game={main_interface={view_sheets=sheets}}}},dfhack={
    isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
    getSavePath=function() return 'test/world' end,df2utf=function(s) return s end,
    gui={getCurViewscreen=function() return {} end,getFocusStrings=function() return {focus} end},
}},{__index=_G})
local translations={['He values family.']='他重視家庭。',
    ['He personally respects power.']='他個人尊重權力。',
    ['He dreams of mastering a skill.']='他夢想精通𠀀技能。'}
local seen,aliases={},{}
local alias_pending=false
local pending='He dreams of mastering a skill.'
local runtime={translation=function(s)
    seen[s]=true
    if s==pending then return nil end
    return translations[s]
end,colored_key=function() error('Mixed-color prose must not use a flat-color alias') end,
announcement_key=function(text,color)
    if alias_pending then return nil end
    local plain=text:gsub('%[C:%d+:%d+:%d+%]','')
    local key='L'..string.format('%06d',#aliases+1)..string.rep('_',math.max(0,utf8.len(plain)*2-7))
    aliases[#aliases+1]=key;aliases[key]={text=text,color=color}
    return key
end}
assert(loadfile(source_path,'t',env))()
env.poll(runtime)
assert(seen['He values family.'] and seen['He personally respects power.'] and seen[pending],
    'Request complete color spans, not the flattened paragraph that loses semantic color boundaries')
assert(box.line[0].text==originals[1],'Pending spans must leave the entire original display intact')
pending=nil;alias_pending=true;env.poll(runtime)
assert(box.line[0].text==originals[1],'Pending native rich-text aliases must not blank the paragraph')
alias_pending=false;env.poll(runtime)
local function rendered()
    local chars,colors={},{}
    for j=0,#box.line-1 do
        local row=box.line[j]
        if row.text~='' then
            local a=assert(aliases[row.text],'Every replacement row must use a verified rich-text alias')
            assert(#row.text<=box.width,'Alias must fit native row width')
            local rest,color=a.text,nil
            while #rest>0 do
                local token=rest:match('^(%[C:%d+:%d+:%d+%])')
                if token then color=token;rest=rest:sub(#token+1)
                else
                    local ending=utf8.offset(rest,2) or #rest+1
                    chars[#chars+1]=rest:sub(1,ending-1);colors[#colors+1]=color
                    rest=rest:sub(ending)
                end
            end
        end
    end
    return chars,colors
end
local function check()
    local chars,colors=rendered()
    local expected=translations['He values family.']..translations['He personally respects power.']..translations['He dreams of mastering a skill.']
    assert(table.concat(chars)==expected,'Wrapping must preserve all Chinese including supplementary Unicode')
    for i=1,#chars do
        assert(colors[i]==(i<=6 and '[C:7:0:0]' or i<=14 and '[C:3:0:1]' or '[C:6:0:1]'),
            'Color must follow the translated semantic span across line boundaries')
    end
end
check()
local key=box.line[0].text;env.poll(runtime)
assert(box.line[0].text==key,'Stable polling must not retranslate or rewrite rows')
box.width=16;env.poll(runtime);check()
focus='dwarfmode/Default';env.poll(runtime)
for j=0,#box.line-1 do
    assert(box.line[j].text==originals[j+1],'Leaving the page must restore original text')
    assert(box.line[j].color==string.rep(string.char(7),#originals[j+1]),'Leaving the page must restore original colors')
end
assert(sheets.personality_raw_str[0].value==raw,'Raw source and world data must remain untouched')
print('PASS values: semantic colors, atomic readiness, UTF-8 wrapping, resize, stable polling, restore')
