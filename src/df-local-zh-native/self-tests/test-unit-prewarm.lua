local world='world-one'
local manifest={version=1,fixed={
    {text='She is unfocused after spending time with people.',translation='她因為與人共度時光而有些心不在焉。'},
    {text='He is not distracted after leading an unexciting life.',translation='他沒有因為生活平淡無奇而分心。'},
},templates={{world=world,text='{DWARF_NAME} likes chicory.'},
    {world='other-world',text='{DWARF_NAME} likes other music.'}}}
local timers={}
local calls={}
local saved=''
local env=setmetatable({
    require=function(name)
        if name=='json' then return {decode=function() return manifest end,encode=function(row) return row.text..'\n' end} end
        if name=='repeat-util' then return {scheduleUnlessAlreadyScheduled=function(name,frames,unit,fn)
            assert(frames>=20 and unit=='frames'); timers[name]=fn
        end,cancel=function(name) timers[name]=nil end} end
        return require(name)
    end,
    io={open=function(_,mode)
        return {read=function() return '{}' end,close=function() end,
            write=function(_,text) saved=saved..text;return true end}
    end},
    reqscript=function(name) assert(name=='df-local-zh-paths'); return {
        broker_data=function() return 'state' end,broker_source=function() return 'assets' end,
    } end,
    dfhack={isWorldLoaded=function() return world~=nil end,isMapLoaded=function() return true end,
        getSavePath=function() return world end,printerr=error},
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-unit-prewarm.lua','t',env))()
local runtime={translation=function(source) calls[#calls+1]=source end,
    colored_key=function() error('Unvisited fixed Needs must not generate every display/color combination') end}
assert(env.fixed_translation(manifest.fixed[1].text)==manifest.fixed[1].translation,
    'Fixed Needs must be available before any background tick or player visit')
assert(not env.fixed_translation('She is distracted after spending time with people.'),
    'Changed source must not inherit a stale exact-source translation')
assert(env.status().fixed_loaded==2,'The status must count translations already in memory')
env.start(runtime)
local tick=assert(timers['df-local-zh-unit-prewarm'])
tick()
assert(#calls<=8,'Background work must have a fixed per-tick budget')
assert(calls[1]=='{DWARF_NAME} likes chicory.','Known templates must precede the bulk fixed background work')
for _,source in ipairs(calls) do
    assert(not env.fixed_translation(source),'Fixed Needs must never be sent to AI')
end
for _,source in ipairs(calls) do assert(not source:find('other music',1,true),'Other world templates must not be queued') end
assert(env.remember('{DWARF_NAME} likes wood opal.'))
assert(not env.remember('{DWARF_NAME} likes wood opal.'),'Known source entries must deduplicate')
assert(not env.remember('Doren likes wood opal.'),'Remember only masked preference templates')
tick()
assert(saved:find('wood opal',1,true),'New template sources must survive restart')
world='world-two';calls={};tick()
for _,source in ipairs(calls) do assert(not source:find('chicory',1,true),'World changes must discard previous template bindings') end
env.stop()
assert(not timers['df-local-zh-unit-prewarm'])
print('PASS fixed lookup before opening sheets, bounded prewarm, source revisions, persistence and world isolation')
