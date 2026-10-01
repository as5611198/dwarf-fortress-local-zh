--@module=true
local json=require('json')
local paths=reqscript('df-local-zh-paths')
local defaults={language='zh-Hant',pinyin=true,colorPersistence=true,apiEnabled=true,
    apiProfile='legacy',apiProfiles={},apiPoolEnabled=false,backgroundTranslation=true,concurrency=2,timeoutMs=25000,
    maxRetries=2,retryBaseMs=1000,translationPrompt='',officialAutoDownload=true,sharedContributions=false}
local snapshot,applied,sequence,pending=nil,nil,0,nil

local function read(name)
    local file=io.open(paths.state()..'/'..name,'rb')
    if not file then return end
    local text=file:read('*a');file:close()
    local ok,value=pcall(json.decode,text)
    return ok and type(value)=='table' and value or nil
end
local function copy(value)
    local result={};for key,item in pairs(value or {}) do result[key]=item end;return result
end
local function write(name,value)
    local path=paths.state()..'/'..name
    local file=assert(io.open(path..'.tmp','wb'))
    assert(file:write(json.encode(value,{pretty=false})));assert(file:close())
    os.remove(path);assert(os.rename(path..'.tmp',path))
end
function world()
    return dfhack.isWorldLoaded() and dfhack.getSavePath() or ''
end
function world_key(value) return (value or ''):gsub('\\','/'):gsub('/+$',''):match('[^/]+$') or '' end
function reload()
    snapshot=read('settings-public.json')
    if not snapshot or snapshot.version~=1 or type(snapshot.document)~='table' then
        snapshot={version=1,document=read('settings.json') or {version=1,defaults=copy(defaults),saves={}},
            profiles={legacy={label='Existing API',enabled=false,hasKey=false}}}
    end
    return snapshot
end
function get_snapshot() return snapshot or reload() end
function effective(scope)
    local doc=get_snapshot().document
    local value=copy(defaults)
    for key,item in pairs(doc.defaults or {}) do value[key]=item end
    if scope~='global' then
        for key,item in pairs((doc.saves or {})[world_key(world())] or {}) do value[key]=item end
    end
    return value
end
function apply_native()
    local value=effective()
    local signature=json.encode({world=world(),settings=value},{pretty=false})
    if signature==applied then return value end
    local native=reqscript('df-local-zh-core/native')
    local runtime=reqscript('df-local-zh-runtime')
    if runtime.language()~=value.language then
        local ok,unit=pcall(reqscript,'df-local-zh-unit-text')
        if ok and unit.language_changed then unit.language_changed() end
    end
    native.native_set_world(world())
    native.set_lang_tag(value.language)
    native.search_pinyin_enable(value.pinyin and 1 or 0)
    reqscript('df-local-zh-search').configure(value)
    if native.color_persistence_set then native.color_persistence_set(value.colorPersistence and 1 or 0) end
    if native.broker_timeout_set then native.broker_timeout_set(value.timeoutMs) end
    if native.translation_concurrency_set then native.translation_concurrency_set(value.concurrency) end
    if value.apiEnabled then native.cloud_enable() else native.cloud_disable() end
    runtime.set_language(value.language,value.colorPersistence)
    runtime.configure(value)
    write('active-context.json',{version=1,world=world(),language=value.language})
    applied=signature
    return value
end
function is_pending() return pending~=nil end
local official_cached,official_tick=nil,0
function official_status(language)
    local tick=dfhack.getTickCount()
    if not official_cached or tick-official_tick>500 or official_cached.language~=language then
        official_cached=read('official/status-'..language..'.json') or {language=language,phase='idle',entries=0}
        official_tick=tick
    end
    return official_cached
end
local shared_cached,shared_tick=nil,0
function shared_status()
    local tick=dfhack.getTickCount()
    if not shared_cached or tick-shared_tick>500 then
        shared_cached=read('shared/status.json') or {phase='idle',pending=0,sent=0}
        shared_tick=tick
    end
    return shared_cached
end
function submit(request,callback)
    if pending then return false,'設定作業進行中' end
    sequence=sequence+1
    request=copy(request)
    request.id='lua-'..os.time()..'-'..sequence..'-'..tostring(dfhack.getTickCount())
    request.world=request.world or world()
    local path=paths.state()..'/settings-request.json'
    local file=io.open(path..'.tmp','wb')
    if not file then return false,'無法寫入設定' end
    local ok,written=pcall(file.write,file,json.encode(request,{pretty=false}))
    local closed,result=pcall(file.close,file)
    if not ok or not written or not closed or not result then return false,'無法寫入設定' end
    os.remove(path)
    if not os.rename(path..'.tmp',path) then return false,'無法提交設定' end
    pending={id=request.id,callback=callback,deadline=dfhack.getTickCount()+(request.action=='test' and 7000 or 5000)}
    local function receive()
        if not pending then return end
        local response=read('settings-response.json')
        if response and response.id==pending.id then
            local job=pending;pending=nil
            if response.ok and response.snapshot then reload();apply_native() end
            if job.callback then job.callback(response) end
            return
        end
        if dfhack.getTickCount()>=pending.deadline then
            local job=pending;pending=nil
            if job.callback then job.callback({ok=false,error='設定服務沒有回應'}) end
            return
        end
        dfhack.timeout(1,'frames',receive)
    end
    dfhack.timeout(1,'frames',receive)
    return true
end
