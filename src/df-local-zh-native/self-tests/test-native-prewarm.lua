local world='one'
local clock=100
local manifest={version=1,world='one',revision='first',rows={}}
for i=1,20 do manifest.rows[i]={text='Known tooltip '..i,translation='既有提示'..i,kind='plain'} end
local published,lookups,states={},{},{}
local decodes=0
local runtime={publish_batch=function(rows)
    assert(#rows<=8,'Dictionary load must be bounded')
    for _,row in ipairs(rows) do published[row.text]=row.translation end
    return true
end,native_ready=function(source,text) lookups[#lookups+1]=source;return states[source]==text end}
local env=setmetatable({
    dfhack={isWorldLoaded=function() return world~=nil end,isMapLoaded=function() return true end,
        getSavePath=function() return world end,printerr=error},
    os={time=function() return clock end},
    io={open=function() return {read=function() return manifest.revision end,close=function() end} end},
    require=function(name)
        if name=='json' then return {decode=function() decodes=decodes+1;return manifest end} end
        if name=='repeat-util' then return {scheduleUnlessAlreadyScheduled=function(_,frames,_,fn)
            assert(frames>=20); env_timer=fn
        end,cancel=function() env_timer=nil end} end
        return require(name)
    end,
    reqscript=function(name) assert(name=='df-local-zh-paths');return {broker_data=function() return 'state' end} end,
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-native-prewarm.lua','t',env))()
env.poll(runtime)
local count=0;for _ in pairs(published) do count=count+1 end
assert(count<=8 and count>0,'Known sources must be loaded in bounded batches')
assert(#lookups<=8,'Native readiness probes must share the work budget')
assert(env.status().ready==0,'A dictionary publication alone must not claim render readiness')
for text,translation in pairs(published) do states[text]=translation end
clock=clock+1;env.poll(runtime)
assert(env.status().ready>0,'Successful asynchronous native lookups must be counted separately')
for _=1,12 do clock=clock+1;for text,translation in pairs(published) do states[text]=translation end;env.poll(runtime) end
assert(env.status().ready==20,'All validated cached tooltip sources must eventually be prepared')
assert(decodes==1,'Unchanged manifests must not be parsed on every background tick')
manifest={version=1,world='one',revision='next',rows={{text='A new tooltip',translation='新增提示',kind='plain'}}}
clock=clock+1;env.poll(runtime)
assert(published['A new tooltip']=='新增提示','Newly translated sources must join without restarting')
world='two';published={};clock=clock+1;env.poll(runtime)
assert(next(published)==nil,'Another world must not preload the previous world manifest')
assert(env.status().ready==0,'World switches must discard readiness statistics')
manifest={version=1,world='two',revision='third',rows={{text='Known miss',translation='未命中提示',kind='plain'}}}
clock=clock+1;env.poll(runtime)
for _=1,24 do clock=clock+1;env.poll(runtime) end
assert(env.status().stalled==1,'An existing native miss must be reported instead of reset or infinite retry')
env.start(runtime);assert(env_timer);env.stop();assert(not env_timer)
print('PASS known tooltip batch loading, readiness, new sources, world isolation and retained native misses')
