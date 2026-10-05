-- Invoked via loadfile(path)(absolute_run_directory). Never saves the world.
local root=assert(...,'Supply run directory')..'/'
local json=require('json')
local function read(name)
    local f=assert(io.open(root..name,'rb'));local data=f:read('*a');f:close()
    return json.decode(data)
end
local expected=read('expected.json')
local result={schema=2,status='running',runId=expected.runId,startedAt=expected.startedAt,
    checks=0,failures={},samples={},fps={},negativeChecks=0}
local function write()
    local f=assert(io.open(root..'live-probe.json','wb'))
    assert(f:write(json.encode(result,{pretty=true})));assert(f:close())
end
local function context()
    local focus=dfhack.gui.getCurFocus()
    if type(focus)=='table' then focus=table.concat(focus,';') end
    local path=dfhack.getSavePath()
    return {worldLoaded=dfhack.isWorldLoaded(),mapLoaded=dfhack.isMapLoaded(),savePath=path,
        world=path and path:gsub('\\','/'):match('([^/]+)$'),
        focus=focus,apiEnabled=reqscript('df-local-zh-settings').effective().apiEnabled,
        paused=df.global.pause_state,tick=dfhack.getTickCount(),render=df.global.enabler.calculated_gfps}
end
local function check(row)
    assert(row.worldLoaded and row.mapLoaded,'World and map must be loaded')
    assert(row.world==expected.world,'Wrong save: '..tostring(row.world))
    assert(row.focus=='dwarfmode' or row.focus:match('^dwarfmode/'),'Not in fortress: '..row.focus)
    assert(row.apiEnabled==false,'AI must be disabled')
end
write() -- Replace old output before any assertion can fail.
local native=reqscript('df-local-zh-core/native')
local original=reqscript('df-local-zh-settings').effective().language
local ok,err=xpcall(function()
    for k,v in pairs(context()) do result[k]=v end
    check(result)
    result.version=reqscript('df-local-zh-core/mod').DISPLAYED_VERSION
    assert(result.version==expected.version,'Unexpected installed version')
    local corpus=read('audit-corpus.json')
    for _,language in ipairs({'zh-Hant','zh-Hans'}) do
        native.set_lang_tag(language)
        for page,entry in pairs(corpus) do
            for _,source in ipairs(entry.sources) do
                if source:match('[A-Za-z]') then
                    local start=os.clock()
                    local translation=native.local_lookup(source)
                    result.samples[#result.samples+1]={page=page,language=language,source=source,
                        translation=translation,first_ms=(os.clock()-start)*1000}
                    result.checks=result.checks+1
                    if not translation then result.failures[#result.failures+1]={page=page,source=source,language=language} end
                end
            end
        end
        assert(native.local_lookup('He is stubborn.  He discovers an unknown moon.')==nil)
        result.negativeChecks=result.negativeChecks+1
    end
end,debug.traceback)
native.set_lang_tag(original)
local function fail(error)
    result.status='failed';result.error=tostring(error);result.finishedAt=os.time();write()
    dfhack.printerr(result.error)
end
if not ok then fail(err);return end
local function sample()
    local passed,reason=xpcall(function()
        local row=context();check(row);result.fps[#result.fps+1]=row
        if #result.fps<6 then write();dfhack.timeout(100,'frames',sample)
        else
            result.status=#result.failures==0 and 'passed' or 'failed'
            result.finishedAt=os.time();write()
            print('OFFLINE_IN_WORLD '..result.status..' '..result.checks)
        end
    end,debug.traceback)
    if not passed then fail(reason) end
end
local scheduled,schedule_error=pcall(dfhack.timeout,100,'frames',sample)
if not scheduled then fail(schedule_error) end
