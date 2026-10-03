--@module=true
-- Opt-in, bounded, local-only residual sampling. Never dispatches translations.
local json=require('json')
local repeatutil=require('repeat-util')
local paths=reqscript('df-local-zh-paths')
local audit=reqscript('df-local-zh-audit')
local seen,count={},0
local watch_name='df-local-zh-local-residuals'
local max_rows,max_bytes=8192,5*1024*1024
function select_rows(sample,registry,capacity)
    local result={};registry=registry or seen;capacity=capacity or max_rows-count
    for _,row in ipairs(sample.strings or {}) do
        if #result>=capacity then break end
        if row.classification=='latin_residual' and type(row.text)=='string' and #row.text<=4096 then
            local key=table.concat({sample.summary.world or '',sample.summary.screen_type or '',
                table.concat(sample.summary.focus or {},'/'),row.field_id or '',row.text},'\0')
            if not registry[key] then registry[key]=true;result[#result+1]=row end
        end
    end
    return result
end
function once()
    -- Skip custom dialogs and title/settings screens, including API-key drafts.
    if not dfhack.isWorldLoaded() or dfhack.gui.getCurViewscreen()~=dfhack.gui.getDFViewscreen() then return 0 end
    local screen=dfhack.gui.getDFViewscreen()
    if not (df.viewscreen_dwarfmodest:is_instance(screen) or df.viewscreen_dungeonmodest:is_instance(screen) or
            df.viewscreen_adventure_logst:is_instance(screen) or df.viewscreen_legendsst:is_instance(screen)) then return 0 end
    if count>=max_rows then return 0 end
    local root=paths.state()..'/local-diagnostics'
    assert(dfhack.filesystem.mkdir_recursive(root),'Cannot create local diagnostics directory')
    local path=root..'/residuals.jsonl'
    local existing=io.open(path,'rb');local bytes=existing and existing:seek('end') or 0
    if existing then existing:close() end
    if bytes>=max_bytes then return 0 end
    local sample=audit.scan()
    if df.viewscreen_adventure_logst:is_instance(screen) then
        for index,row in ipairs(reqscript('df-local-zh-adventure').collect(screen)) do
            sample.strings[#sample.strings+1]={field_id='adventure.journal['..index..']',
                category='adventure_'..row.category,text=row.source,classification=audit.classify(row.source)}
        end
    end
    local rows=select_rows(sample)
    local file=assert(io.open(path,'ab'));local written=0
    for _,row in ipairs(rows) do
        local line=json.encode({world=sample.summary.world,screen=sample.summary.screen_type,
            focus=sample.summary.focus,field_id=row.field_id,category=row.category,text=row.text})..'\n'
        if bytes+#line>max_bytes then break end
        assert(file:write(line));bytes=bytes+#line;written=written+1
    end
    assert(file:close());count=count+#rows
    return written
end
function refresh()
    local native=reqscript('df-local-zh-core/native')
    local root=paths.broker_source()..'/data/'
    local failures={}
    for _,lang in ipairs({'zh-Hant','zh-Hans'}) do
        local suffix=lang=='zh-Hant' and '' or '-zh-Hans'
        local ok,err=native.load_simple_dict(lang,root..'fortress-ui'..suffix..'.csv')
        if not ok then failures[#failures+1]=tostring(err) end
        ok,err=native.load_translation_rulesets(lang,root..'announcement-rules'..suffix)
        if not ok then failures[#failures+1]=tostring(err) end
    end
    native.local_rules_refresh()
    -- Each loader validates into a candidate before replacing that dictionary.
    -- No core reset, DLL replacement, uploads, or runtime-cache file writes.
    return #failures==0,failures
end
function stop() repeatutil.cancel(watch_name) end
function watch() stop();repeatutil.scheduleEvery(watch_name,600,'frames',function()
    local ok,err=pcall(once);if not ok then stop();dfhack.printerr('Local residual sampler stopped: '..tostring(err)) end
end) end
if not dfhack_flags.module then
    local command=({...})[1] or 'once'
    if command=='once' then print('LOCAL_RESIDUALS '..once())
    elseif command=='watch' then watch();print('Local sampler enabled; 8192 rows / 5 MiB cap')
    elseif command=='stop' then stop()
    elseif command=='refresh' then local ok,errors=refresh();if not ok then qerror(table.concat(errors,'\n')) end;print('Local dictionaries refreshed')
    else qerror('Usage: df-local-zh-local-diagnostics [once|watch|stop|refresh]') end
end
