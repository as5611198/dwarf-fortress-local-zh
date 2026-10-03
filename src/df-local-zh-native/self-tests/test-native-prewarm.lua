-- Fault-injection regression for the native prewarm timer (bulk loading is Rust-owned).
local timer,calls,errors,lookups=nil,0,0,0
local broken=true
local env=setmetatable({
    dfhack={isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
        getSavePath=function() return 'fixture' end,printerr=function() errors=errors+1 end},
    io={open=function() error('The main thread must never open a bulk prewarm export') end},
    reqscript=function(name)
        lookups=lookups+1
        if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture/data' end} end
        if name=='df-local-zh-runtime' then return {language=function() return 'zh-Hant' end} end
        if name=='df-local-zh-status' then return {paused_background=function() return false end} end
        assert(name=='df-local-zh-core/native')
        return {native_prewarm_request=function() calls=calls+1;if broken then error('fixture transient failure') end end}
    end,
    require=function(name)
        if name=='repeat-util' then return {scheduleUnlessAlreadyScheduled=function(_,_,_,fn) timer=fn end,cancel=function() timer=nil end} end
        return require(name)
    end,
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-native-prewarm.lua','t',env))()
broken=false;env.start();assert(timer)
broken=true;timer();assert(errors==1)
broken=false;local before=calls
for _=1,100 do timer() end
assert(calls==before+100,'A failed callback must not strand the timer')
assert(lookups==4,'Script lookup must not scale with timer ticks')
env.stop();assert(not timer)
print('PASS native prewarm recovery, cached modules, and no main-thread bulk IO')
