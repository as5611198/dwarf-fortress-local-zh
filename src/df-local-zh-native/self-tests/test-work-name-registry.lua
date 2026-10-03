local root=dfhack.getDFPath()
local function vector(rows)
    local v={}
    for i,row in ipairs(rows) do v[i-1]=row end
    return setmetatable(v,{__len=function() return #rows end})
end
local files,timers={},{}
local world={history={figures=vector({{id=1,name={first_name='Urist',text='Urist'}}})},
    world_data={name={text='The World'}},entities={all=vector({})},artifacts={all=vector({})},
    poetic_forms={all=vector({{id=52,name={text='The Fuchsia Silkinesses'}}})},
    musical_forms={all=vector({{id=87,name={text='The Fuchsia Wisp'}}})},
    dance_forms={all=vector({{id=6,name={text='The Quiet Dance'}}})},
    written_contents={all=vector({{id=8,title='A Treatise on Stone'}})}}
local env=setmetatable({
    df={global={world=world}},
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return 'fixture/world' end,
        df2utf=function(s) return s end,translation={translateName=function(n) return n.text end},
        timeout=function(_,_,fn) timers[#timers+1]=fn end},
    io={open=function(path,mode)
        if mode=='r' then return nil end
        files[path]=''
        return {write=function(_,content) files[path]=files[path]..content; return true end,close=function() return true end}
    end},
    reqscript=function(name)
        if name=='df-local-zh-unicode' then return {decode=function(s) return s end} end
        if name=='df-local-zh-core/native' then return {local_export_commit=function(from,to) files[to]=files[from];files[from]=nil;return true end} end
        assert(name=='df-local-zh-paths'); return {broker_data=function() return 'fixture' end}
    end,
},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-names-worker.lua','t',env))()
env.start()
local index=1
while index<=#timers do timers[index](); index=index+1; assert(index<20) end
local registry=require('json').decode(assert(files['fixture/world-names.json']))
local figure
for _,entity in ipairs(registry.entities) do if entity.id=='figure:1' then figure=entity end end
assert(figure and figure.nativeName=='Urist','Figure export must preserve the constructed-language full name')
local entities={}
for _,entity in ipairs(registry.entities) do entities[entity.id]=entity.preferred end
assert(entities['poetic_form:52']=='The Fuchsia Silkinesses','Poetic work identity must reach the registry')
assert(entities['musical_form:87']=='The Fuchsia Wisp','Musical work identity must reach the registry')
assert(entities['dance_form:6']=='The Quiet Dance','Dance work identity must reach the registry')
assert(entities['written_content:8']=='A Treatise on Stone','Written titles must reach the registry')
assert(world.poetic_forms.all[0].name.text=='The Fuchsia Silkinesses','Export must not mutate world names')
print('PASS generated work registry types, IDs, titles and unchanged world names')
