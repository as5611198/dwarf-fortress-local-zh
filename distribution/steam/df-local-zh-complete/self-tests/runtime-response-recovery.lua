local root=assert((...), 'scripts directory required')
local json=require('json')
local files,dictionary={},{}
local broken=true
local errors=0
local world='fixture/world'
local env=setmetatable({
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return world end,
        printerr=function() errors=errors+1 end},
    reqscript=function(name)
        if name=='df-local-zh-status' then return {broker=function() return {runtime={retryGeneration='fixture'}} end} end
        if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture' end} end
        if name=='df-local-zh-core/mod' then return {sync_translate=function(key) return dictionary[key] end} end
        assert(name=='df-local-zh-core/native',name)
        return {load_simple_dict=function(_,path)
            if broken then error('fixture dictionary unavailable') end
            for key,value in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do dictionary[key]=value end
        end}
    end,
    io={open=function(path,mode)
        if mode=='rb' and not files[path] then return nil end
        local offset=0
        if mode=='wb' then files[path]='' end
        return {seek=function(_,kind,n) offset=kind=='end' and #files[path] or n;return offset end,
            lines=function() return ((files[path] or '')..'\n'):gmatch('(.-)\n') end,read=function(_,limit) return files[path]:sub(offset+1,type(limit)=='number' and offset+limit or nil) end,
            write=function(_,text) files[path]=(files[path] or '')..text;return true end,close=function() return true end}
    end},
},{__index=_G})
assert(loadfile(root..'/df-local-zh-runtime.lua','t',env))()
env.poll()
local source='One completed sentence.'
local key='DFLIVE_'..string.rep('a',64)
files['fixture/runtime-responses.jsonl']=json.encode({world=world,text=source,translation='已完成的一句。',key=key},{pretty=false})..'\n'
local delivered=0
env.on_translation(source,function(text) assert(text=='已完成的一句。');delivered=delivered+1 end)
env.poll()
assert(delivered==0)
broken=false
env.poll()
assert(delivered==1,'A failed dictionary load must not consume and permanently lose a completed response')
assert(errors>0,'A failed response load must be observable')
env.poll()
assert(delivered==1,'Successful retry must deliver once')
files['fixture/runtime-failures.jsonl']=json.encode({world=world,text='A permanently rejected sentence.',reason='format token mismatch',terminal=true,retryGeneration='fixture'},{pretty=false})..'\n'
env.poll()
local value,status,reason=env.request('A permanently rejected sentence.')
assert(not value and status=='failed' and reason=='format token mismatch','Terminal errors must stop pretending to collect text')
print('RUNTIME_RESPONSE_RECOVERY PASS')
