local json = require('json')
local root = dfhack.getDFPath()
local failures = {}

local function check(condition, message)
    if not condition then failures[#failures+1] = message end
end

local function fixture(mode)
    local state = {mode=mode, content='', opens=0, closes=0, world='fixture/region1',
        now=100, dictionary={}, lookups=0,sync_sources={},rotation=nil}
    local env = setmetatable({
        dfhack={isWorldLoaded=function() return state.world ~= nil end,
            getSavePath=function() return state.world end},
        os={time=function() return state.now end},
        io={open=function(path, access)
            if access == 'rb' and state.rotation and path:match('journal%-rotation%.json$') then
                return {
                    read=function() return json.encode(state.rotation) end,
                    close=function() state.closes=state.closes+1;return true end,
                }
            end
            if access == 'rb' then return nil end
            state.opens = state.opens + 1
            if state.mode == 'open' then return nil, 'fixture open failure' end
            return {
                write=function(_, ...)
                    local content = table.concat({...})
                    if state.mode == 'write' or state.mode == 'write-throw' then
                        state.content = state.content .. content:sub(1, 12)
                        if state.mode == 'write-throw' then error('fixture write failure') end
                        return nil, 'fixture write failure'
                    end
                    state.content = state.content .. content
                    return true
                end,
                close=function()
                    state.closes = state.closes + 1
                    if state.mode == 'close-throw' then error('fixture close failure') end
                    if state.mode == 'close' then return nil, 'fixture close failure' end
                    return true
                end,
            }
        end},
        reqscript=function(name)
            if name=='df-local-zh-offline-narrative' then
                local helper=setmetatable({},{__index=_G})
                assert(loadfile(root..'/hack/scripts/df-local-zh-offline-narrative.lua','t',helper))()
                return helper
            end
            if name == 'df-local-zh-paths' then
                return {broker_data=function() return 'fixture/broker/data' end}
            end
            if name == 'df-local-zh-core/mod' then
                return {sync_translate=function(source)
                    state.sync_sources[#state.sync_sources+1]=source
                    return state.dictionary[source]
                end,
                    async_translate=function(source)
                    state.lookups = state.lookups + 1
                    return state.dictionary[source]
                end}
            end
            assert(name == 'df-local-zh-core/native')
            return {load_simple_dict=function()
                for key,value in state.content:gmatch('"([^"]+)","([^"]+)"') do
                    state.dictionary[key]=value
                end
            end}
        end,
    }, {__index=_G})
    assert(loadfile(root..'/hack/scripts/df-local-zh-runtime.lua', 't', env))()
    return env, state
end

for _, kind in ipairs({'plain', 'paragraph'}) do
    for _, mode in ipairs({'open', 'write', 'close', 'write-throw', 'close-throw'}) do
        local env, state = fixture(mode)
        local source = kind=='paragraph' and '{{DFL0}} has an unknown report.' or 'A report that must survive a queue failure.'
        local links = {{type=0, id=7, text='Urist'}}
        local function request()
            if kind == 'plain' then return env.request(source) end
            return env.paragraph_lookup(source, links, 7)
        end
        local ok, value, status = pcall(request)
        local label = kind .. '/' .. mode .. ': '
        check(ok and value == nil and status == 'failed', label .. 'failed IO must be reported')
        check(mode == 'open' or state.closes == 1, label .. 'opened files must be closed')
        state.mode = nil
        ok, value, status = pcall(request)
        check(ok and value == nil and status == 'queued' and state.opens == 2,
            label .. 'a failed append must retry immediately without pending suppression')
        local last
        for line in state.content:gmatch('([^\n]+)\n') do last = line end
        local decoded, row = pcall(json.decode, last or '')
        check(decoded and type(row) == 'table' and row.text == source,
            label .. 'partial failed writes must not corrupt the next request')
        local before = state.opens
        ok, value, status = pcall(request)
        check(ok and value == nil and status == 'pending' and state.opens == before,
            label .. 'accepted requests must retain pending deduplication')
    end
end

local env, state = fixture()
local disabled_env,disabled_state=fixture()
local _,queued=disabled_env.request('An untranslated identity',7)
check(queued=='queued','Identity request must first enter the queue')
local before_disable=disabled_state.opens
disabled_env.configure({apiEnabled=false})
local _,disabled=disabled_env.request('An untranslated identity',7)
check(disabled=='disabled','Disabling AI must supersede an existing pending request immediately')
local _,lookup_state=disabled_env.lookup('An untranslated identity',7)
check(lookup_state=='disabled','Lookup must preserve the disabled request status')
local _,short_state=disabled_env.short_lookup('An untranslated identity',true,nil,nil,7)
check(short_state=='disabled','Short lookup must preserve status for display fallback')
check(disabled_env.pending_key('pending')==nil and disabled_state.opens==before_disable,
    'AI-off pending display must not load a placeholder dictionary or write files')
disabled_env.configure({apiEnabled=true})
for _,status in ipairs({'disabled','failed','invalid','unavailable','rendering','ready'}) do
    check(disabled_env.pending_key(status)==nil and disabled_state.opens==before_disable,
        status..' must not be represented as an AI translation in progress')
end
local live_env,live_state=fixture()
local _,live_status=live_env.short_lookup('New identity',true,nil,nil,8)
check(live_status=='queued','Short lookup must propagate an accepted request status')
local pending_key=live_env.pending_key(live_status)
check(type(pending_key)=='string' and live_state.dictionary[pending_key]=='翻譯中',
    'A real accepted AI request may still display its translated pending label')
local _,repeat_status=live_env.short_lookup('New identity',true,nil,nil,8)
check(repeat_status=='pending','Short lookup must preserve request deduplication status')
local cold_env,cold_state=fixture()
local cold_source=string.rep('He has not seen this particular long description. ',12)
local _,cold_status=cold_env.request(cold_source)
check(cold_status=='queued' and cold_state.lookups==0 and #cold_state.sync_sources==0,
    'Cold long prose must enter the Broker without starting native rule work')
cold_state.now=101
cold_env.request(cold_source)
check(cold_state.lookups==0 and cold_state.opens==1,
    'Pending long prose must not restart native work on the next second')
local _,alias_status=cold_env.request('L0009Ss________ L0009Su________ L0009St________')
check(alias_status=='invalid' and cold_state.opens==1,
    'Joined display aliases must never become a prose translation job')
local priority_env, priority_state=fixture()
priority_env.request('Shared background text',nil,nil,'background')
check(#priority_state.sync_sources==0,'Unknown background text must never run the blocking native translator')
local last
for line in priority_state.content:gmatch('([^\n]+)\n') do last=line end
check(json.decode(last).priority=='background','Prefetch requests must enter the background lane')
priority_env.request('Shared background text')
for line in priority_state.content:gmatch('([^\n]+)\n') do last=line end
check(priority_state.opens==2 and json.decode(last).priority=='foreground',
    'Opening a pending background source must promote it immediately')
priority_env.request('Shared background text')
check(priority_state.opens==2,'Foreground promotion must not append on every frame')
local value, status = env.request('')
check(value == nil and status == 'invalid' and state.opens == 0,
    'invalid text must not enter the queue')
state.world = nil
value, status = env.request('No loaded world')
check(value == nil and status == 'invalid' and state.opens == 0,
    'unloaded worlds must not enter the queue')

local runtime, queue = fixture()
local report_publications={}
runtime.prefetch=function(text,priority)
    local key=runtime.request(text,nil,nil,priority)
    if key then report_publications[text]=true end
    return key~=nil
end
runtime.publish_batch=function(rows)
    for _,row in ipairs(rows) do
        queue.dictionary[row.text]=row.translation
        report_publications[row.text]=true
    end
    return true
end
runtime.publish_native=runtime.publish_batch
runtime.announcement_key=function() return 'READY_REPORT_ALIAS' end
local report = {id=0, text='Awaited translation'}
local reports = setmetatable({[0]=report}, {__len=function() return 1 end})
local timers = {}
local events = {onReport={}, eventType={REPORT=1}, enableEvent=function() end}
local report_env = setmetatable({
    df={global={world={status={reports=reports}}}, report={find=function() return report end}},
    dfhack={isWorldLoaded=function() return true end, isMapLoaded=function() return true end,
        getSavePath=function() return queue.world end, df2utf=function(text) return text end,
        timeout=function(_, _, fn) timers[#timers+1]=fn end},
    require=function(name) assert(name == 'plugins.eventful'); return events end,
    reqscript=function(name)
        if name=='df-local-zh-core/mod' then return runtime.reqscript(name) end
        if name=='df-local-zh-status' then return {background_allowed=function() return true end,broker=function() return {} end} end
        assert(name == 'df-local-zh-runtime'); return runtime
    end,
}, {__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-reports.lua', 't', report_env))()
timers[#timers]()
check(queue.opens == 1, 'report backfill must submit the first request')
timers[#timers]()
check(queue.opens == 1, 'pending report scans must not append duplicates')
queue.now = 121
timers[#timers]()
check(queue.opens == 2, 'unresolved reports must retry after the runtime timeout')
queue.dictionary[report.text] = '\230\138\181\233\129\148'
runtime.request(report.text) -- Simulate a foreground native result becoming available.
check(report_publications[report.text], 'A native cache hit must publish waiting reports in the same request')
queue.now = 142
timers[#timers]()
local lookups = queue.lookups
timers[#timers]()
check(queue.opens == 2 and queue.lookups == lookups,
    'ready reports must stop retrying without changing their source text')
check(report_publications[report.text] and report.text=='Awaited translation',
    'Report readiness must publish the original display key without changing report memory')
report_env.stop()

local prefetch_env,prefetch_state=fixture()
prefetch_env.request('Initialize world',nil,nil,'background')
prefetch_state.dictionary.KnownAlias='已完成翻譯'
prefetch_env.request=function() return 'KnownAlias' end
prefetch_env.publish_batch=function(rows)
    prefetch_state.dictionary[rows[1].text]=rows[1].translation
    return true
end
prefetch_env.native_ready=function() return true end
check(prefetch_env.prefetch('Previously unseen source'),'Completed background results should publish original keys')
check(prefetch_state.sync_sources[1]=='KnownAlias' and #prefetch_state.sync_sources==1,
    'Prefetch must publish before any original-source lookup can trigger expensive native rules')
prefetch_state.dictionary.KnownAlias='[C:7:0:1]公告[B]第二段[C:7:0:0]'
check(prefetch_env.prefetch('[C:7:0:1]An announcement[B]A second paragraph[C:7:0:0]'),
    'Broker report markup must be accepted without treating color tokens as residual English')

local existing_env,existing_state=fixture()
existing_state.dictionary.Planter='播種者'
check(existing_env.prefetch('Planter') and existing_state.opens==0,
    'Already translated short native text must finish without a Broker request')
existing_state.dictionary['Known break marker']='第一段[B]第二段'
check(existing_env.prefetch('Known break marker') and existing_state.opens==0,
    'A translated native paragraph break must not be mistaken for English')
local long_existing=string.rep('A known item description. ',9)
existing_state.dictionary[long_existing]='原生既有中文'
existing_state.dictionary.BrokerAlias='另一種中文譯法'
existing_env.request=function() return 'BrokerAlias' end
existing_env.publish_batch=function() return false end
check(existing_env.prefetch(long_existing) and existing_state.lookups==3,
    'A different existing Chinese display must finish long-source prewarm after Broker publication fails')

assert(#failures == 0, table.concat(failures, '\n'))
print('PASS runtime queue IO failures, partial writes, deduplication, report timeout retry and ready completion')
