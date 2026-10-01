--@module=true

local json=require('json')
local paths=reqscript('df-local-zh-paths')
local manifest, fixed, learned, fixed_loaded
local active_world, active_language, templates, seen, done, template_cursor

local function read(path)
    local file=io.open(path,'rb')
    if not file then return nil end
    local text=file:read('*a'); file:close()
    return text
end

local function valid_template(row)
    return type(row)=='table' and type(row.world)=='string' and type(row.text)=='string' and
        #row.text<=8000 and row.text:sub(1,19)=='{DWARF_NAME} likes ' and
        select(2,row.text:gsub('{DWARF_NAME}',''))==1
end

local function load()
    if manifest then return end
    local content=read(paths.broker_source()..'/unit-prewarm.json')
    local ok,value=pcall(json.decode,content or '')
    manifest=ok and type(value)=='table' and value.version==1 and value or {fixed={},templates={}}
    fixed,learned,fixed_loaded={},{},0
    for _,row in ipairs(manifest.fixed or {}) do
        if type(row.text)=='string' and type(row.translation)=='string' and
                not row.translation:match('[A-Za-z{}]') then
            if not fixed[row.text] then fixed_loaded=fixed_loaded+1 end
            fixed[row.text]=row.translation
        end
    end
    for _,row in ipairs(manifest.templates or {}) do
        if valid_template(row) then learned[#learned+1]=row end
    end
    for _,name in ipairs({'unit-prewarm-sources.jsonl','runtime-requests.jsonl'}) do
        for line in (read(paths.broker_data()..'/'..name) or ''):gmatch('(.-)\n') do
            local decoded,row=pcall(json.decode,line)
            if decoded and valid_template(row) then learned[#learned+1]=row end
        end
    end
end

local function world()
    return dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
end

local function context()
    load()
    local current=world()
    local ok,runtime=pcall(reqscript,'df-local-zh-runtime')
    local language=ok and runtime.language and runtime.language() or 'zh-Hant'
    if current==active_world and language==active_language and templates then return current end
    active_world=current
    active_language=language
    templates,seen,done,template_cursor={},{},{},1
    for _,row in ipairs(learned) do
        if row.world==current and not seen[row.text] then
            seen[row.text]=true; templates[#templates+1]=row.text
        end
    end
    return current
end

function fixed_translation(source)
    load()
    return fixed[source]
end

function remember(source)
    local current=context()
    local row={world=current,text=source}
    if not current or not valid_template(row) or seen[source] then return false end
    local file=io.open(paths.broker_data()..'/unit-prewarm-sources.jsonl','ab')
    if not file then return false end
    local ok,result=pcall(file.write,file,json.encode(row,{pretty=false})..'\n')
    file:close()
    if not ok or not result then return false end
    seen[source]=true; templates[#templates+1]=source; learned[#learned+1]=row
    return true
end

function poll(runtime)
    if not context() or not dfhack.isMapLoaded() then return end
    local ok,status=pcall(reqscript,'df-local-zh-status')
    if ok and status.paused_background() then return end
    if ok and status.claim_background and not status.claim_background('unit') then return end
    for _=1,math.min(4,#templates) do
        if template_cursor>#templates then template_cursor=1 end
        local source=templates[template_cursor]
        if not done[source] then
            local translated=runtime.translation(source)
            if type(translated)=='string' and select(2,translated:gsub('{DWARF_NAME}',''))==1 and
                    not translated:gsub('{DWARF_NAME}',''):match('[A-Za-z]') then done[source]=true end
        end
        template_cursor=template_cursor+1
    end
    -- Fixed prose is already in memory. Runtime restores observed color/width
    -- fragments at world load; unseen display combinations are prepared on demand.
end

function status()
    context()
    local ready=0
    for _ in pairs(done) do ready=ready+1 end
    return {fixed=#(manifest.fixed or {}),fixed_loaded=fixed_loaded,
        templates=#templates,templates_ready=ready,display_policy='observed-only',world=active_world}
end

function start(runtime)
    context()
    runtime_bridge=runtime
    require('repeat-util').scheduleUnlessAlreadyScheduled('df-local-zh-unit-prewarm',20,'frames',function()
        local ok,err=pcall(poll,runtime_bridge)
        if not ok then dfhack.printerr('df-local-zh-unit-prewarm: '..tostring(err)) end
    end)
end

function stop()
    require('repeat-util').cancel('df-local-zh-unit-prewarm')
end
