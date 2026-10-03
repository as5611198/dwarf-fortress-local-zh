local root=dfhack.getDFPath()
local queued, timers, events = {}, {}, {onReport={},eventType={REPORT=1},enableEvent=function() end}
local world='fixture-a'
local reports={}
local count=0
for id=0,39 do reports[id]={id=id,text='Existing report '..id} end
setmetatable(reports,{__len=function() return 40 end})
local failing={}
local attempts=0
local allowed,claimed=true,true
local priorities={}
local published,callbacks,cancelled={}, {},0
local delayed,native_ready=false,true
local native_result
local runtime={on_translation=function(text,callback)
    local entry={callback=callback}
    callbacks[text]=entry
    if not delayed and not failing[text] then entry.callback=nil;callback('公告譯文') end
    return function() entry.callback=nil;cancelled=cancelled+1 end
end,publish_native=function(rows)
    for _,row in ipairs(rows) do published[row.text]=row.translation end
    return true
end,native_ready=function() return native_ready end,
announcement_key=function() return native_ready and 'READY_REPORT_ALIAS' or nil end,
prefetch=function(text,priority)
    attempts=attempts+1
    priorities[#priorities+1]=priority
    if failing[text] then return false end
    queued[#queued+1]=text
    return true
end}
local env=setmetatable({
    df={global={world={status={reports=reports}}},report={find=function(id) return reports[id] end}},
    dfhack={isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
        getSavePath=function() return world end,df2utf=function(text) return text end,
        printerr=error,
        timeout=function(_,mode,fn) assert(mode=='frames'); timers[#timers+1]=fn; return #timers end},
    require=function(name) assert(name=='plugins.eventful'); return events end,
    reqscript=function(name)
        if name=='df-local-zh-runtime' then return runtime end
        if name=='df-local-zh-core/mod' then return {async_translate=function() return native_result end} end
        if name=='df-local-zh-status' then return {
            background_allowed=function() return allowed end,
            claim_background=function(kind) assert(kind=='reports');return claimed end,
            broker=function() return {runtime={backgroundQueued=0}} end,
        } end
        error(name)
    end,
}, {__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-reports.lua','t',env))()
assert(#timers>0,'Loaded reports need a scheduled backfill')
timers[1]()
assert(#queued==4,'Backfill must process at most four reports per granted batch')
timers[2]()
assert(#queued==8,'The next batch must retain the four-report budget')
allowed=false;timers[#timers]()
assert(#queued==8,'Pause must stop report backfill')
allowed=true;claimed=false;timers[#timers]()
assert(#queued==8,'Backfill must respect the shared real-time gate')
claimed=true
for _=1,8 do timers[#timers]() end
assert(#queued==40,'Subsequent bounded batches must finish the existing report backlog')
for _,priority in ipairs(priorities) do assert(priority=='background','Backfill must use the background lane') end
events.onReport.df_local_zh_reports(0)
assert(#queued==40,'Unchanged report must not be duplicated')
reports[0].text='Updated report 0'
events.onReport.df_local_zh_reports(0)
assert(queued[41]=='Updated report 0','Changed report text must be queued again')
assert(priorities[#priorities]=='recent','New report events must use the recent lane')
world='fixture-b'
events.onReport.df_local_zh_reports(0)
assert(#queued==42,'Report IDs must be scoped to each world')
reports[1].text='Retry report 1'
failing[reports[1].text]=true
events.onReport.df_local_zh_reports(1)
failing[reports[1].text]=nil
timers[#timers]()
local found=false
for _,text in ipairs(queued) do if text=='Retry report 1' then found=true end end
assert(found,'A failed event append must be retried by backfill')
timers[#timers]()

reports[2].text='Retry after full scan'
failing[reports[2].text]=true
events.onReport.df_local_zh_reports(2)
failing[reports[2].text]=nil
found=false
for _=1,10 do
    local before_attempts=attempts
    timers[#timers]()
    assert(attempts-before_attempts<=4,'Retry passes must retain bounded batches')
    for _,text in ipairs(queued) do if text=='Retry after full scan' then found=true end end
    if found then break end
end
assert(found,'Backfill must wrap at the end and retry failures on later passes')

delayed=true
reports[3].text='  The miners have completed 12 stairways beneath the fortress.  '
reports[3].color=6;reports[3].bright=true
events.onReport.df_local_zh_reports(3)
local source=reports[3].text
assert(callbacks[source],'Reports must preserve the exact source, including whitespace')
assert(not published[source],'Pending prose must not be declared translated')
native_ready=false
callbacks[source].callback('礦工已完成要塞下方的 12 座樓梯。')
assert(published['[C:6:0:1]'..source]=='[C:6:0:1]礦工已完成要塞下方的 12 座樓梯。',
    'The completion callback must publish the original report color immediately')
local before_attempts=attempts
events.onReport.df_local_zh_reports(3)
assert(attempts>before_attempts,'A staged native color row must remain eligible until ready')
native_ready=true
events.onReport.df_local_zh_reports(3)
before_attempts=attempts
events.onReport.df_local_zh_reports(3)
assert(attempts==before_attempts,'Fully ready prose and color rows must be deduplicated')
reports[3].bright=false
events.onReport.df_local_zh_reports(3)
callbacks[source].callback('礦工已完成要塞下方的 12 座樓梯。')
assert(published['[C:6:0:0]'..source],'Changed report brightness must publish a distinct key')
native_result='Untranslated native fallback'
reports[6].text='[C:7:0:1]The outpost:[C:7:0:0] Seven miners arrived.[B]Strike the earth!'
events.onReport.df_local_zh_reports(6)
assert(callbacks[reports[6].text],'An untranslated native result must still subscribe to Broker completion')
callbacks[reports[6].text].callback('[C:7:0:1]前哨站：[C:7:0:0]七位礦工抵達。[B]開掘大地！')
assert(published[reports[6].text]=='[C:7:0:1]前哨站：[C:7:0:0]七位礦工抵達。[B]開掘大地！',
    'Report completion must preserve embedded color and paragraph tokens')
native_result=nil
reports[4].text='A pending report from the previous world.'
events.onReport.df_local_zh_reports(4)
local stale=callbacks[reports[4].text].callback
world='fixture-c'
events.onReport.df_local_zh_reports(5)
stale('前一世界的公告。')
assert(not published[reports[4].text],'A late callback from another world must not publish')
assert(cancelled>0,'World changes must cancel outstanding subscriptions')

-- Offline providers must not retain one subscription for every historical report.
for id=100,399 do
    reports[id]={id=id,text='Offline report '..id}
    events.onReport.df_local_zh_reports(id)
end
local live=0
for _,entry in pairs(callbacks) do if entry.callback then live=live+1 end end
assert(live<=128,'Offline report subscriptions must stay bounded')
assert(callbacks['Offline report 100'].callback==nil,'Eviction must cancel the old listener')
events.onReport.df_local_zh_reports(100)
assert(callbacks['Offline report 100'].callback,'Deferred reports must be eligible for another pass')

env.stop()
local before=#queued
timers[#timers]()
assert(#queued==before,'Stopped backfill callbacks must be inert')
assert(events.onReport.df_local_zh_reports==nil)
print('PASS reports batching, exact sources, completion callbacks, palette readiness, world isolation and stop')
