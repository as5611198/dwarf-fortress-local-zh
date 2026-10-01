-- Automated fortress translation checks. Run with: df-local-zh-test
local json=require('json')
local root=dfhack.getDFPath()
local paths=reqscript('df-local-zh-paths')
local package_root=paths.source()
local fixture_root=package_root..'/self-tests'
local original_loadfile=loadfile
local fixtures={
    'test-paths-performance.lua',
    'test-startup-events.lua',
    'test-runtime-language.lua',
    'test-pinyin-routing.lua',
    'test-settings-ui.lua',
    'test-runtime-callback.lua',
    'test-runtime-queue-io.lua',
    'test-runtime-rich.lua',
    'test-runtime-poll-cost.lua',
    'test-unit-sheet-text.lua',
    'test-unit-prewarm.lua',
    'test-unit-restart-cache.lua',
    'test-cache-immediate.lua',
    'test-display-color-persistence.lua',
    'test-text-viewer-color.lua',
    'test-runtime-rebind.lua',
    'test-hover-text.lua',
    'test-native-prewarm-bridge.lua',
    'test-visible-fortress-text.lua',
    'test-fortress-text-audit.lua',
    'test-fortress-sources.lua',
    'test-fortress-reports.lua',
    'test-announcement-display.lua',
    'test-fortress-ui.lua',
    'test-status-ui.lua',
    'test-work-name-registry.lua',
    'test-chinese-search.lua',
}
local results={version=1,mode='fortress',started=os.time(),checks={},
    world=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil}
local log_path=paths.broker_data()..'/fortress-auto-test-'..results.started..'.json'
local finished=false
local cancel_watch
local deadline_timer
local function finish()
    if finished then return end
    finished=true
    if cancel_watch then cancel_watch() end
    if deadline_timer then dfhack.timeout_active(deadline_timer,nil);deadline_timer=nil end
    results.finished=os.time()
    results.passed=0
    results.failed=0
    for _,row in ipairs(results.checks) do
        if row.status=='PASS' then results.passed=results.passed+1
        elseif row.status=='FAIL' then results.failed=results.failed+1 end
    end
    local file,err=io.open(log_path,'wb')
    if file then file:write(json.encode(results,{pretty=true}));file:close()
    else dfhack.printerr('df-local-zh-test log: '..tostring(err)) end
    print(('df-local-zh-test COMPLETE %d PASS, %d FAIL; %s'):format(
        results.passed,results.failed,log_path))
end
local function check(name,ok,detail)
    local row={name=name,status=ok==nil and 'SKIP' or (ok and 'PASS' or 'FAIL'),
        detail=tostring(detail or '')}
    results.checks[#results.checks+1]=row
    print(('df-local-zh-test %s %s: %s'):format(row.status,name,row.detail))
end
local fixture_failures=0
for _,name in ipairs(fixtures) do
    local sandbox=setmetatable({dfhack=setmetatable({getDFPath=function() return root end},
        {__index=dfhack})},
        {__index=_G})
    sandbox._G=sandbox
    sandbox.loadfile=function(path,mode,env)
        local script=path:match('/hack/scripts/([^/]+%.lua)$')
        if script then path=package_root..'/scripts_modinstalled/'..script end
        if path==root..'/_localization-work/runtime-rebind.lua' then
            path=fixture_root..'/runtime-rebind.lua'
        end
        return original_loadfile(path,mode,env or sandbox)
    end
    local path=fixture_root..'/'..name
    local ok,err=xpcall(function() assert(original_loadfile(path,'t',sandbox))() end,debug.traceback)
    check(name,ok,ok and 'fixture assertions passed' or err)
    if not ok then fixture_failures=fixture_failures+1 end
end
if fixture_failures>0 then finish();return end
if not dfhack.isMapLoaded() then
    check('live Broker and native color',nil,'fortress map not loaded')
    finish()
    return
end

local runtime=reqscript('df-local-zh-runtime')
if not runtime.on_translation then
    local script=assert(dfhack.findScript('df-local-zh-runtime'))
    assert(loadfile(script,'t',runtime))()
    runtime.adopt_running()
end
local source='In the early spring of 39, the dwarf Rovod Toolstrokes became obsessed with her own mortality and sought to extend her life by any means having ambitions for which death was only a small obstacle.'
local expected='在 39 年初春，矮人羅沃德·工具擊開始執著於自己終將死亡的命運，並不擇手段地尋求延長壽命；對她的野心而言，死亡只是個小障礙。'
local color=string.char(7)
local function color_ready(translated,attempt)
    if finished then return end
    local length=utf8.len(translated)
    if not length then
        check('native color keys',false,'Broker response is not valid UTF-8')
        finish()
        return
    end
    local mod=reqscript('df-local-zh-core/mod')
    local tag='[C:7:0:0]'
    local ready=true
    local fragments=0
    for first=1,length,24 do
        local begin=utf8.offset(translated,first)
        local ending=utf8.offset(translated,math.min(first+24,length+1)) or #translated+1
        local fragment=translated:sub(begin,ending-1)
        local key=runtime.colored_key(fragment,color)
        fragments=fragments+1
        if not key or mod.sync_translate(tag..key)~=tag..fragment then ready=false end
    end
    if ready then
        check('native color keys',true,'palette=7 fragments='..fragments)
        finish()
    elseif attempt<120 then
        dfhack.timeout(1,'frames',function() color_ready(translated,attempt+1) end)
    else
        check('native color keys',false,'native renderer did not accept all fragments within 120 frames')
        finish()
    end
end
cancel_watch=runtime.on_translation(source,function(translated)
    local valid=translated==expected and not translated:match('[A-Za-z]')
    check('Broker long prose callback',valid,translated)
    if valid then color_ready(translated,1) else finish() end
end)
if finished then return end
local _,status,err=runtime.request(source,nil,nil,'background')
if status~='queued' and status~='pending' and status~='ready' then
    check('Broker request',false,tostring(status)..' '..tostring(err))
    finish()
    return
end
check('Broker request',true,status)
deadline_timer=dfhack.timeout(1800,'frames',function()
    if not finished then
        check('Broker long prose callback',false,'no accepted response within 1800 frames')
        finish()
    end
end)
