local world,language,paused='one','zh-Hant',false
local requests={}
local native={native_prewarm_request=function(path,current,lang,pause)
    requests[#requests+1]={path=path,world=current,language=lang,paused=pause}
end,native_prewarm_status=function()
    return require('json').encode({world=world,language=language,loaded=10000,ready=10000,pending=0,queued=0,stalled=0})
end}
local timer
local env=setmetatable({
    io={open=function() error('Bulk prewarm files must be read by the DLL, not Lua') end},
    dfhack={isWorldLoaded=function() return world~=nil end,isMapLoaded=function() return true end,
        getSavePath=function() return world end,printerr=error},
    reqscript=function(name)
        if name=='df-local-zh-core/native' then return native end
        if name=='df-local-zh-runtime' then return {language=function() return language end} end
        if name=='df-local-zh-paths' then return {broker_data=function() return 'state' end} end
        assert(name=='df-local-zh-status');return {paused_background=function() return paused end,
            claim_background=function() error('Local import must not wait for the model scheduler') end}
    end,
    require=function(name)
        if name=='repeat-util' then return {cancel=function() timer=nil end,
            scheduleUnlessAlreadyScheduled=function(_,_,_,fn) timer=fn end} end
        return require(name)
    end,
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-native-prewarm.lua','t',env))()
env.poll()
assert(requests[1] and requests[1].world=='one','The native worker must receive the current world')
assert(env.status().ready==10000,'Progress must come from the native snapshot')
language='zh-Hans';env.poll()
assert(requests[#requests].path=='state/native-prewarm-zh-Hans.json')
paused=true;env.poll();assert(requests[#requests].paused==1,'User pause must reach the native worker')
world=nil;env.poll();assert(requests[#requests].world=='','Unloading a world must cancel native publication')
env.start();assert(timer);env.stop();assert(not timer)
print('PASS native prewarm bridge, no bulk Lua I/O, no model gating, language and cancellation')
