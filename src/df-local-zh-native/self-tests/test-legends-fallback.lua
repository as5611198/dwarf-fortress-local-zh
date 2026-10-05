local world='fixture/one'
local width=80
local rows={
    {str='Urist',px=0,py=0,link_index=0,red=0,green=128,blue=255},
    {str='McTest',px=6,py=0,link_index=0,red=0,green=128,blue=255},
    {str='(mayor)',px=13,py=0,link_index=-1,red=255,green=255,blue=255},
}
local function words_for(values)
    local words=setmetatable({},{__len=function() return #values end})
    for i,row in ipairs(values) do words[i-1]=row end
    return words
end
local page={mode=1,index=20,header='Original header',text_box={word=words_for(rows)}}
local vs={active_page_index=2,page={[2]=page},histfigs={[20]=7}}
local env=setmetatable({
    df={legends_mode_type={HFS=1},viewscreen_legendsst={is_instance=function(_,v) return v==vs end}},
    dfhack={df2utf=function(s) return s end,isWorldLoaded=function() return true end,
        getSavePath=function() return world end,gui={getCurViewscreen=function() return vs end},
        screen={getWindowSize=function() return width,50 end}},
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-legends.lua','t',env))()
local translation
local runtime={short_lookup=function(source)
    if source=='Urist McTest' then return translation end
end,pending_key=function() return 'P_____' end}
local function tick() for _=1,20 do env.poll(runtime) end end
tick()
assert(rows[1].str=='Urist' and rows[2].str=='McTest' and rows[3].str=='(mayor)',
    'Unavailable legacy translations must retain the original readable name and role')
translation='L000001_______'
tick()
assert(rows[1].str==translation and rows[2].str=='','A completed translation must still replace the name')
assert(rows[1].link_index==0 and rows[1].blue==255,'Replacement must preserve native link and color')
translation=nil
tick()
assert(rows[1].str=='Urist' and rows[2].str=='McTest' and rows[2].px==6,
    'Losing a translation after a setting change must restore every original word and coordinate')
translation=string.rep('L',100)
tick()
assert(rows[1].str=='Urist' and rows[2].str=='McTest','An oversized translation must fall back to source')
translation='L000002'
tick()
assert(rows[1].str==translation)
page.scroll_position_text=0;page.text_box.max_y=10
page.text_box.link={[0]={type=0,id=7}}
env.df.global={enabler={renderer={dispx=8,dispy=12}}}
local rich=setmetatable({},{__index=env})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-narrative.lua','t',rich))()
runtime.restore_legends=env.restore_native
local captured=assert(rich.view(runtime))
assert(captured.paragraphs[1].request_links[1].text=='Urist McTest',
    'Rich reader capture must see the real link label, not a legacy alias')
assert(rows[1].str=='Urist' and rows[2].str=='McTest' and rows[3].px==13,
    'Switching to the rich reader must restore native text before paragraph capture')
-- Native regeneration can reuse the same detail object and word count.
rows[1].str='Other';rows[2].str='Person'
translation=nil
tick()
assert(rows[1].str=='Other' and rows[2].str=='Person','Stale snapshots must never overwrite a rebuilt page')
world='fixture/two'
tick()
assert(rows[1].str=='Other' and rows[2].str=='Person','Changing worlds must not reuse another world snapshot')
print('PASS Legends original fallback, restoration, width, identity, color and world isolation')
