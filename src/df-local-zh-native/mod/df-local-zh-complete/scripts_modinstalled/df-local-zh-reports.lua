--@module=true

-- Reports are created before the announcement/combat panel renders them. Queue
-- each report at that boundary so the existing runtime broker can translate
-- dynamic names, numbers, and formatting before the player opens the log.
local eventful = require('plugins.eventful')
local runtime = reqscript('df-local-zh-runtime')
local mod = reqscript('df-local-zh-core/mod')

local started = false
local active_world
local active_language
local seen = {}
local pending = {}
local backfill_index = 0
local generation = 0
local display_translations,display_records,display_cursors = {},{},{}

local function field(value,name)
    local ok,result=pcall(function() return value[name] end)
    return ok and result or nil
end

local function visit_display(fn,complete)
    local main=field(field(df.global,'game'),'main_interface')
    if not main then return end
    local visited,count={},0
    local function walk(value,depth)
        if not value or depth>18 or not complete and count>=256 then return end
        if tostring(field(value,'_type')):find('shared_ptr',1,true) then
            -- Current Windows DFHack exposes the managed widget as the first pointer word.
            local ptr=df.reinterpret_cast('uint64_t',value).value
            if ptr==0 then return end
            value=df.reinterpret_cast(df.widget,ptr)
        end
        local id=tostring(value)
        if visited[id] then return end
        visited[id]=true;count=count+1
        if type(field(value,'str'))=='string' then fn(value,'str',field(value,'fg'),field(value,'bright')) end
        local children=field(value,'children')
        if children and #children>0 then
            local first
            for index in ipairs(children) do first=index;break end
            -- Rotate bounded scans so long logs are not limited to their first rows.
            local start=complete and 0 or (display_cursors[id] or 0)%#children
            for offset=0,#children-1 do
                if not complete and count>=256 then break end
                local index=(start+offset)%#children
                walk(children[index+first],depth+1)
                if not complete then display_cursors[id]=(index+1)%#children end
            end
        end
    end
    walk(field(field(main,'announcements'),'stack'),0)
    local alert=field(main,'announcement_alert')
    for _,entry in ipairs({
        {field(alert,'alert_text'),field(alert,'scroll_position_alert')},
        {field(alert,'uac_text'),field(alert,'scroll_position_uac')},
        {field(main,'hover_announcement_alert_text'),0},
        {field(main,'hover_announcement_alert_button_text'),0},
    }) do
        local rows=field(entry[1],'text')
        if rows then
            local first=complete and 0 or math.max(0,tonumber(entry[2]) or 0)
            local last=complete and #rows-1 or math.min(#rows-1,first+31)
            for i=first,last do
            local row=rows[i]
            if type(field(row,'value'))=='string' then fn(row,'value',7,false) end
            end
        end
    end
end

local function restore_display()
    visit_display(function(owner,property)
        local old=display_records[tostring(owner)..':'..property]
        if old and owner[property]==old.key then owner[property]=old.source end
    end,true)
    display_records,display_cursors={},{}
end

local function cancel_pending()
    for _,job in pairs(pending) do if job.cancel then job.cancel() end end
    pending = {}
end

local function reset_world()
    local world = dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    local language=runtime.language and runtime.language() or 'zh-Hant'
    if world ~= active_world or language~=active_language then
        restore_display()
        cancel_pending()
        active_world = world
        active_language=language
        seen = {}
        backfill_index = 0
        display_translations={}
    end
    return world
end

function refresh_display()
    if not started or not reset_world() or not dfhack.isMapLoaded() then return end
    visit_display(function(owner,property,fg,bright)
        local id=tostring(owner)..':'..property
        local old=display_records[id]
        local original=owner[property]
        if old and original==old.key then original=old.source
        else display_records[id]=nil end
        local source=dfhack.df2utf(original)
        local translated=display_translations[source]
        if not translated then
            local tag,remainder=source:match('^(%[C:[0-7]:[0-7]:[01]%])(.+)$')
            if tag and display_translations[remainder] then translated=tag..display_translations[remainder] end
        end
        if not translated then return end
        fg=tonumber(fg) or 7
        if fg<0 or fg>7 or fg~=math.floor(fg) then return end
        local key=runtime.announcement_key(translated,string.char(fg+(bright and 64 or 0)))
        if key then owner[property]=key;display_records[id]={source=original,key=key} end
    end)
end

local function report_source(id)
    local report = df.report.find(id)
    if not report or type(report.text) ~= 'string' then return end
    local ok,text = pcall(dfhack.df2utf,report.text)
    if not ok or type(text) ~= 'string' or not text:match('[A-Za-z]') then return end
    local color = tonumber(report.color) or 7
    if color < 0 or color > 7 or color ~= math.floor(color) then return end
    local tag = ('[C:%d:0:%d]'):format(color,report.bright and 1 or 0)
    return text,tag,text..'\0'..tag
end

local function valid_translation(text)
    if type(text) ~= 'string' then return false end
    local plain = text:gsub('%[C:%d+:%d+:%d+%]',''):gsub('%[[BPR]%]','')
    return plain:match('[\128-\255]') and not plain:match('[A-Za-z{}]')
end

local function publish_report(id,job)
    if not started or not reset_world() or not dfhack.isMapLoaded() or
            active_world ~= job.world or pending[id] ~= job then return end
    local _,_,signature = report_source(id)
    if signature ~= job.signature then return end
    local translated = job.translation
    if not valid_translation(translated) then return end
    local colored_source,colored_text = job.tag..job.text,job.tag..translated
    if not job.published then
        job.published = runtime.publish_native({
            {text=job.text,translation=translated},
            {text=colored_source,translation=colored_text},
        })
    end
    if job.published then
        display_translations[job.text]=translated
        refresh_display()
    end
    local color,bright=job.tag:match('%[C:(%d+):0:(%d+)%]')
    local key=job.published and runtime.announcement_key(translated,string.char(tonumber(color)+tonumber(bright)*64))
    if key then
        seen[id] = job.signature
        pending[id] = nil
        if job.cancel then job.cancel() end
    end
end

local function queue_report(id,priority)
    if not reset_world() or not dfhack.isMapLoaded() then return end
    local text,tag,signature = report_source(id)
    if not text or seen[id] == signature then return end
    local job = pending[id]
    if not job or job.signature ~= signature then
        if job and job.cancel then job.cancel() end
        job = {text=text,tag=tag,signature=signature,world=active_world}
        pending[id] = job
    end
    runtime.prefetch(text,priority or 'recent')
    if not job.translation then
        local native_text = mod.async_translate(text)
        if valid_translation(native_text) then job.translation = native_text end
    end
    if not job.translation and not job.cancel then
        -- Broker completion publishes the original palette key at once. The
        -- bounded backfill also retries native readiness and failed requests.
        job.cancel = runtime.on_translation(text,function(translated)
            job.translation = translated
            publish_report(id,job)
        end)
    end
    publish_report(id,job)
end

local function backfill()
    if not reset_world() or not dfhack.isMapLoaded() then return end
    local ok,status=pcall(reqscript,'df-local-zh-status')
    if ok then
        if not status.background_allowed() then return end
        if status.claim_background and not status.claim_background('reports') then return end
        local b=status.broker();local r=b and b.runtime or {}
        if (r.backgroundQueued or 0)+(b and b.backgroundQueued or 0)>24 then return end
    end
    local reports = df.global.world.status.reports
    if backfill_index >= #reports then backfill_index = 0 end
    local stop = math.min(#reports, backfill_index + 4)
    while backfill_index < stop do
        local report = reports[backfill_index]
        if report then queue_report(report.id,'background') end
        backfill_index = backfill_index + 1
    end
end

function start()
    if started then return end
    started = true
    eventful.enableEvent(eventful.eventType.REPORT, 1)
    eventful.onReport.df_local_zh_reports = queue_report
    generation = generation + 1
    local current_generation = generation
    local function tick()
        if not started or current_generation ~= generation then return end
        local ok, err = pcall(backfill)
        if not ok then dfhack.printerr('df-local-zh-reports: ' .. tostring(err)) end
        local shown,show_err=pcall(refresh_display)
        if not shown then dfhack.printerr('df-local-zh-reports display: '..tostring(show_err)) end
        dfhack.timeout(20, 'frames', tick)
    end
    dfhack.timeout(1, 'frames', tick)
end

function stop()
    restore_display()
    eventful.onReport.df_local_zh_reports = nil
    started = false
    generation = generation + 1
    active_world = nil
    cancel_pending()
    seen = {}
    backfill_index = 0
    display_translations={}
end

start()

