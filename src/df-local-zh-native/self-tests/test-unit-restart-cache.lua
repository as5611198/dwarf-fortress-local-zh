local json=require('json')
local root=dfhack.getDFPath()
local directory='fixture/data/'
local active_world='fixture/world'
local files,dictionary,native_ready,queued={},{},{},{}
local loads,requests=0,0
local source='She enjoys company.'
local translation='她喜歡有人陪伴。'
local name='Doren Ushatesis'
files[directory..'native-prewarm.json']=json.encode({version=1,world=active_world,
    unit={sources={{text=source,translation=translation}},
        names={{text=name,translation='多雷 烏夏特埃錫斯'}},
        fragments={{translation=translation,color=71},{translation='多雷 烏夏特埃錫斯喜歡菊苣。',color=71}}}},
    {pretty=false})
local function restart()
    dictionary,native_ready,queued={},{},{}
    local env=setmetatable({
        dfhack={isWorldLoaded=function() return active_world~=nil end,
            getSavePath=function() return active_world end},
        io={open=function(path,mode)
            if mode=='rb' and not files[path] then return nil end
            if mode=='wb' then files[path]='' end
            local offset=0
            return {seek=function(_,kind,position)
                if kind=='end' then offset=#files[path] else offset=position end
                return offset
            end,read=function() return files[path]:sub(offset+1) end,
            write=function(_,...)
                files[path]=(files[path] or '')..table.concat({...})
                if path==directory..'runtime-requests.jsonl' then requests=requests+1 end
                return true
            end,close=function() return true end}
        end},
        reqscript=function(module)
            if module=='df-local-zh-reviewed-text' then return {translation=function() end} end
            if module=='df-local-zh-creature-names' then return {translation=function(text)
                return ({cat='貓',cats='貓',dog='狗',cow='乳牛',pike='海狼魚'})[text]
            end} end
            if module=='df-local-zh-paths' then return {broker_data=function() return directory:sub(1,-2) end} end
            if module=='df-local-zh-unit-prewarm' then return {remember=function() end,fixed_translation=function() end} end
            if module=='df-local-zh-core/mod' then return {
                sync_translate=function(text) return dictionary[text] end,
                async_translate=function(text) queued[text]=true;return native_ready[text] end}
            end
            assert(module=='df-local-zh-core/native')
            return {load_simple_dict=function(_,path)
                loads=loads+1
                for key,text in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do dictionary[key]=text end
            end}
        end,
    },{__index=_G})
    assert(loadfile(root..'/hack/scripts/df-local-zh-runtime.lua','t',env))()
    return env
end
local function flush_native()
    for key in pairs(queued) do native_ready[key]=dictionary[key] end
end
local runtime=restart()
runtime.poll()
dictionary.cat='貓'
dictionary.cats='貓'
dictionary.dog='狗'
dictionary.cow='乳牛'
dictionary.pike='長槍'
for _,animal in ipairs({'cat','cats','dog','cow'}) do
    assert(runtime.unit_name_translation(animal)==dictionary[animal],
        'Known creature names must synchronously use the native dictionary')
end
assert(not next(queued),'Known creature names must not enqueue native/model work')
assert(runtime.unit_name_translation('pike')=='海狼魚','Creature context must win over weapon homonyms')
assert(loads==1,'Startup must prepare saved display fragments in one dictionary batch')
assert(not next(queued),'Startup must not enqueue every unused saved palette')
assert(runtime.unit_translation(source)==translation,'Known unit prose must be available before a native source request')
assert(runtime.unit_name_translation(name)=='多雷 烏夏特埃錫斯','Restore the same exact full name as the native header')
assert(requests==0,'Restoring translated content must not enqueue AI work')
assert(not runtime.colored_key(translation,string.char(71)),'Unready native aliases must remain hidden')
flush_native()
local before=loads
local key=assert(runtime.colored_key(translation,string.char(71)))
assert(loads==before,'The first cached sheet must reuse its prepared display key')

local later='她喜歡寧靜。'
assert(not runtime.colored_key(later,string.char(71)))
flush_native()
assert(runtime.colored_key(later,string.char(71)))
local response={world=active_world,text='She likes quiet.',translation=later,key='DFLIVE_'..string.rep('0',64)}
files[directory..'runtime-responses.jsonl']=json.encode(response,{pretty=false})..'\n'
runtime.poll()
assert(runtime.unit_translation(response.text)==later)

files[directory..'native-prewarm.json']=nil
files[directory..'runtime-responses.jsonl']=nil
runtime=restart()
runtime.poll()
assert(runtime.unit_translation(source)==translation and runtime.unit_translation(response.text)==later,
    'Both migrated and newly completed unit prose must survive process restart')
assert(runtime.unit_name_translation(name)=='多雷 烏夏特埃錫斯')
before=loads
assert(not runtime.colored_key(translation,string.char(71)))
assert(not runtime.colored_key(later,string.char(71)))
flush_native()
local restored=assert(runtime.colored_key(translation,string.char(71)))
assert(restored==key,'A completed observed palette should retain its persistent native identity')
assert(runtime.colored_key(later,string.char(71)))
assert(loads==before and requests==0,'Reopened cached sheets must not rebuild aliases or queue translations')
assert(not runtime.unit_translation('She enjoys company now.'),'Changed wording must not use the old exact-source result')
assert(requests==1,'Only changed wording should enter the translation queue')
files[directory..'runtime-responses.jsonl']=json.encode({world=active_world,text=source,
    translation='她喜愛有人作伴。',key='DFLIVE_'..string.rep('1',64)},{pretty=false})..'\n'
before=loads
runtime.poll()
assert(loads==before+1,'Response journal replay must use one dictionary batch')
assert(runtime.unit_translation(source)=='她喜愛有人作伴。','A newer completed translation must replace an older saved result')
active_world='fixture/other-world'
runtime.poll()
assert(not runtime.unit_name_translation(name),'Name bindings must not leak into another world')
assert(not runtime.unit_translation(source),'Prose bindings must not leak into another world')
print('PASS restart migration, immediate prose/name restoration, on-demand palette readiness and world/source isolation')
