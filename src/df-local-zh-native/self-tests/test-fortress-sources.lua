local root=dfhack.getDFPath()
local function vector(rows)
    local v={};for i,row in ipairs(rows) do v[i-1]=row end
    return setmetatable(v,{__len=function() return #rows end})
end
local collected,published={},{}
local timers={}
local map,allowed=true,true
local book={title='A Local Stone Book'}
local music={name='A Citizen Song'}
local poem={name='A Learned Poem'}
local pages_type,artifact_type={},{}
local env=setmetatable({
    require=function(name)
        if name=='json' then return require('json') end
        if name=='repeat-util' then return {
            scheduleUnlessAlreadyScheduled=function(id,_,_,fn) timers[id]=timers[id] or fn end,
            cancel=function(id) timers[id]=nil end,
        } end
        error(name)
    end,
    io={open=function() return {write=function() return true end,close=function() return true end} end},
    reqscript=function(name)
        if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture' end} end
        if name=='df-local-zh-status' then return {background_allowed=function() return allowed end,
            broker=function() return {runtime={backgroundQueued=0}} end} end
        if name=='df-local-zh-unit-prewarm' then return {fixed_translation=function(source)
            if source=='A Fixed Need.' then return '固定需求。' end
        end} end
        if name=='df-local-zh-visible-text' then return {poll=function() end,status=function() return {} end} end
        error(name)
    end,
    df={itemimprovement_pagesst=pages_type,itemimprovement_writingst={},general_ref_is_artifactst=artifact_type,
        unitpref_type={[1]='LikeMusicalForm'},
        written_content={find=function(id) return id==11 and book end},
        musical_form={find=function(id) return id==12 and music end},
        poetic_form={find=function(id) return id==13 and poem end},dance_form={find=function() end},
        artifact_record={find=function(id) return id==14 and {name='A Local Artifact'} end},
        global={world={units={active=vector({{id=1,status={current_soul={
            preferences=vector({{type=1,musical_form_id=12}}),performance_skills={
                poetic_forms=vector({{id=13}}),musical_forms=vector({}),dance_forms=vector({})}}}}})},
        items={all=vector({{id=999}}),other={IN_PLAY=vector({{id=2,
            improvements=vector({{_type=pages_type,contents=vector({11})}}),
            general_refs=vector({{_type=artifact_type,artifact_id=14}})}})}},
        buildings={all=vector({{id=3}})},raws={plants={all=vector({{name='oak',
            material=vector({{state_name=vector({'oak wood'})}})}})}},
        written_contents={all=vector({{title='A Remote Book'}})},
        musical_forms={all=vector({{name='A Remote Song'}})}}}},
    dfhack={isWorldLoaded=function() return true end,isMapLoaded=function() return map end,
        getSavePath=function() return 'fortress' end,df2utf=function(v) return v end,printerr=error,
        units={isCitizen=function() return true end,getProfessionName=function() return 'Miner' end,
            getRaceReadableName=function() return 'dwarf' end},
        items={getReadableDescription=function(i) return i.id==999 and 'remote item' or 'silver war hammer' end,
            getDescription=function() return 'silver war hammer' end},
        translation={translateName=function(name) return name end},
        buildings={getName=function() return 'Carpenters workshop' end},gui={}},
},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-prefetch.lua','t',env))()
local runtime={prefetch=function(text) collected[text]=true;return true end,
    translation=function(text) published[text]=true end}
for _=1,30 do env.poll(runtime) end
assert(collected['silver war hammer'] and collected['Carpenters workshop'] and
    collected['Miner'] and collected['A Local Stone Book'],'Actual local books must survive an absent getBookTitle API')
assert(collected['A Citizen Song'] and collected['A Learned Poem'] and collected['A Local Artifact'],
    'Only works referenced by local citizens and items should prewarm')
assert(not collected['A Remote Book'] and not collected['A Remote Song'] and
    not collected['oak wood'] and not collected['remote item'],
    'Remote world works, all-world items and unrelated raws must remain on demand')
local before=env.status().collected
allowed=false
env.df.global.world.items.other.IN_PLAY[0]={id=4}
env.dfhack.items.getReadableDescription=function() return 'new item' end
env.poll(runtime)
assert(not collected['new item'] and env.status().collected==before,'Pause must stop background collection')
allowed=true;map=false
for _=1,10 do env.poll(runtime) end
assert(not collected['new item'],'Legends must never start fortress AI prefetch')
map=true
env.observe('A Remote Book','display','fixture.knowledge')
env.observe('A Fixed Need.','display','fixture.needs')
for _=1,10 do env.poll(runtime) end
assert(collected['A Remote Book'],'Narrowing prewarm must preserve observed on-demand text')
assert(not collected['A Fixed Need.'],'Observed fixed Needs must not enter the Broker queue again')
for i=1,200 do env.observe('Unseen observed text '..i,'tooltip','fixture.tooltip') end
assert(env.status().pending<=128,'Observed rows must not overrun the background queue limit')
env.start({prefetch=function() error('Stale runtime callback after hot reload') end})
env.start(runtime)
timers['df-local-zh-prefetch']()
print('PASS local references, remote exclusion, observed text, pause and fortress-only collection')
