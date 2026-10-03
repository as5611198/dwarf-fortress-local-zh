local root=dfhack.getDFPath()
local json=require('json')
local files,dictionary,native_results={},{},{}
local world='fixture/fortress'
local directory='fixture/broker/data/'
local env=setmetatable({
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return world end},
    reqscript=function(name)
        if name=='df-local-zh-paths' then return {broker_data=function() return directory:sub(1,-2) end} end
        if name=='df-local-zh-core/mod' then return {
            sync_translate=function(key) return dictionary[key] end,
            async_translate=function(key) return native_results[key] end,
        } end
        assert(name=='df-local-zh-core/native')
        return {load_simple_dict=function(_,path)
            for key,value in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do dictionary[key]=value end
        end}
    end,
    io={open=function(path,mode)
        if mode=='rb' and not files[path] then return nil end
        local offset=0
        if mode=='wb' then files[path]='' end
        return {
            seek=function(_,kind,position)
                offset=kind=='end' and #files[path] or position
                return offset
            end,
            lines=function() return ((files[path] or '')..'\n'):gmatch('(.-)\n') end,read=function() return files[path]:sub(offset+1) end,
            write=function(_,...)
                files[path]=(files[path] or '')..table.concat({...})
                return true
            end,
            close=function() return true end,
        }
    end},
},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-runtime.lua','t',env))()
local source='She is not distracted after leading an unexciting life.'
local calls={}
local cancel=env.on_translation(source,function(value) calls[#calls+1]=value end)
assert(type(cancel)=='function' and #calls==0)
local _,status=env.request(source)
assert(status=='queued')
files[directory..'runtime-responses.jsonl']=json.encode({
    world=world,text=source,translation='她沒有因為生活平淡無奇而分心。',
    key='DFLIVE_'..string.rep('0',64),
},{pretty=false})..'\n'
env.poll()
assert(#calls==1 and calls[1]=='她沒有因為生活平淡無奇而分心。',
    'Callback must fire when a verified Broker response enters runtime cache')
env.poll()
assert(#calls==1,'Callback must be one-shot')
env.on_translation(source,function(value) calls[#calls+1]=value end)
assert(#calls==2,'Already cached translation must invoke callback immediately')
local other='A second paragraph that has no response.'
local cancelled=false
local stop=env.on_translation(other,function() cancelled=true end)
stop()
files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
    json.encode({world=world,text=other,translation='第二段。',
        key='DFLIVE_'..string.rep('1',64)},{pretty=false})..'\n'
env.poll()
assert(not cancelled,'Cancelled callback must stay silent')
local native_source='An existing native cached sentence.'
local native_text='已經保存的原生譯文。'
native_results[native_source]=native_text
local native_calls=0
env.on_translation(native_source,function(value)
    assert(value==native_text)
    native_calls=native_calls+1
end)
assert(select(2,env.request(native_source))=='ready')
assert(native_calls==1,'A native cache hit must notify waiting callbacks during the same request')
env.request(native_source)
assert(native_calls==1,'Native cache hit notification must be one-shot')
print('PASS runtime response callback, one-shot, immediate cache hit and cancellation')
