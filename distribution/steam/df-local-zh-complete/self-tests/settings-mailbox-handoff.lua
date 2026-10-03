-- Deterministic two-phase mailbox test. No player files or settings are touched.
local source=...
local json=require('json')
local files,timers,tick={},{},0
local env=setmetatable({dfhack_flags={module=true},
    reqscript=function(name) assert(name=='df-local-zh-paths');return {state=function() return 'fixture' end} end,
    dfhack={isWorldLoaded=function() return false end,getTickCount=function() return tick end,
        timeout=function(_,_,fn) timers[#timers+1]=fn end},
    os=setmetatable({remove=function(path) files[path]=nil;return true end,
        rename=function(a,b) files[b]=files[a];files[a]=nil;return true end},{__index=os}),
    io={open=function(path,mode)
        if mode=='rb' then
            if not files[path] then return end
            return {read=function() return files[path] end,close=function() return true end}
        end
        return {write=function(_,value) files[path]=value;return true end,close=function() return true end}
    end}},{__index=_G})
assert(loadfile(source..'/df-local-zh-settings.lua','t',env))()
local completed=0
assert(env.submit({action='official-sync'},function(response)
    assert(response.ok);completed=completed+1
    assert(env.submit({action='official-sync'}))
end))
local request=json.decode(files['fixture/settings-request.json'])
files['fixture/settings-response.json']=json.encode({id=request.id,ok=true})
table.remove(timers,1)()
assert(env.is_pending() and completed==0,'Reply must not release the mailbox before acknowledgement')
assert(not env.submit({action='official-sync'}),'A new request must not race with previous cleanup')
files['fixture/settings-request.json']=json.encode({version=1,processed=request.id})
table.remove(timers,1)()
assert(completed==1 and env.is_pending())
local next_request=json.decode(files['fixture/settings-request.json'])
assert(next_request.id~=request.id and next_request.action=='official-sync')
-- A missing acknowledgement must still end with a bounded failure.
files['fixture/settings-response.json']=json.encode({id=next_request.id,ok=true})
tick=6000;table.remove(timers,1)()
assert(not env.is_pending(),'Missing acknowledgement must time out, not remain pending')
print('SETTINGS_MAILBOX_HANDOFF PASS: response-before-ack, callback resubmit, bounded timeout')
