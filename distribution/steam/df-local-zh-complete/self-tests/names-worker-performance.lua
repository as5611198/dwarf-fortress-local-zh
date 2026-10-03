-- Run via DFHack lua -f with the scripts_modinstalled directory as argument.
-- Regression: module resolution must not scale with exported entity count.
local root=assert((...), 'scripts_modinstalled directory required')
local json=require('json')
local unicode_env=setmetatable({},{__index=_G})
assert(loadfile(root..'/df-local-zh-unicode.lua','t',unicode_env))()
local function vector(values)
    local result={}
    for i,value in ipairs(values) do result[i-1]=value end
    return setmetatable(result,{__len=function() return #values end})
end
local figures={}
for i=1,130 do
    figures[i]={id=i,name={first_name='Urist',native='烏里斯特𠀀',english='Urist '..string.char(128)}}
end
local world_data={name={native='測試世界',english='Test world'}}
for _,name in ipairs({'sites','regions','underground_regions','landmasses','mountain_peaks','rivers'}) do
    world_data[name]=vector({})
end
local world={history={figures=vector(figures)},world_data=world_data}
for _,name in ipairs({'entities','artifacts','poetic_forms','musical_forms','dance_forms','written_contents'}) do
    world[name]={all=vector({})}
end
local queue,files,unicode_resolutions={}, {}, 0
local env=setmetatable({
    require=function(name)
        if name=='json' then return {encode=function(value,opts)
            assert(type(value)~='table' or not value.entities or #value.entities<=64,'Whole-world JSON serialization blocked a single frame')
            return json.encode(value,opts)
        end} end
        return require(name)
    end,
    df={global={world=world}},
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return 'fixture/world' end,
        translation={translateName=function(name,english) return english and name.english or name.native end},
        timeout=function(_,unit,fn) assert(unit=='frames');queue[#queue+1]=fn end},
    reqscript=function(name)
        if name=='df-local-zh-unicode' then unicode_resolutions=unicode_resolutions+1;return unicode_env end
        if name=='df-local-zh-core/native' then return {local_export_commit=function(from,to) files[to]=assert(files[from]);files[from]=nil;return true end} end
        assert(name=='df-local-zh-paths',name)
        return {broker_data=function() return 'fixture/data' end}
    end,
    io={open=function(path,mode)
        if mode=='r' then return nil end
        assert(mode=='w')
        files[path]=''
        return {write=function(_,data) files[path]=files[path]..data;return true end,close=function() return true end}
    end},
    print=function() end,
},{__index=_G})
assert(loadfile(root..'/df-local-zh-names-worker.lua','t',env))()
env.start()
local batches=0
while #queue>0 do
    batches=batches+1;assert(batches<10,'Worker must finish bounded fixture')
    table.remove(queue,1)()
end
local registry=json.decode(assert(files['fixture/data/world-names.json']))
local by_id={};for _,row in ipairs(registry.entities) do by_id[row.id]=row end
assert(by_id['figure:1'].nativeName=='烏里斯特𠀀','UTF-8 name must remain intact')
assert(by_id['figure:1'].preferred=='Urist Ç','Legacy CP437 name must still decode')
assert(by_id['figure:130'].nativeName=='烏里斯特𠀀','All batches must export')
assert(batches>1,'Export must remain incremental')
assert(unicode_resolutions<=1,
    'Name export repeatedly resolved the Unicode script: '..unicode_resolutions..' lookups for 130 figures')
print('NAMES_WORKER_PERFORMANCE PASS: 130 figures, UTF-8/CP437 preserved, '..batches..' batches, '..unicode_resolutions..' module lookup')
