-- Verify the real DLL worker at the title screen without creating units or combat.
assert(not dfhack.isWorldLoaded(),'Run this verification at the title screen')
local native=reqscript('df-local-zh-core/native')
local paths=reqscript('df-local-zh-paths')
local bridge=reqscript('df-local-zh-native-prewarm')
local runtime=reqscript('df-local-zh-runtime')
local json=require('json')
local original_language=runtime.language()
local directory=paths.broker_data()
local result={version=1,started=os.time(),languages={},errors={}}
local languages={'zh-Hant','zh-Hans'}
local which=0
local done=false
bridge.stop()
local function finish(err)
    if done then return end;done=true
    if err then result.errors[#result.errors+1]=tostring(err) end
    native.native_prewarm_request('','','zh-Hant',0)
    native.native_set_world('')
    native.set_lang_tag(original_language)
    bridge.start()
    result.pass=#result.errors==0
    result.finished=os.time()
    local path=directory..'/native-prewarm-live.json'
    local file=assert(io.open(path,'wb'));file:write(json.encode(result));file:close()
    print(('NATIVE_PREWARM_COMPLETE pass=%s errors=%d; %s'):format(tostring(result.pass),#result.errors,path))
end
local function guarded(fn)
    return function()
        local ok,err=xpcall(fn,debug.traceback)
        if not ok then finish(err) end
    end
end
local next_language
next_language=function()
    which=which+1
    local language=languages[which]
    if not language then return finish() end
    local path=directory..(language=='zh-Hans' and '/native-prewarm-zh-Hans.json' or '/native-prewarm.json')
    local file=assert(io.open(path,'rb'));local data=json.decode(file:read('*a'));file:close()
    assert(data.version==1 and type(data.rows)=='table')
    native.set_lang_tag(language);native.native_set_world(data.world)
    local _,_,before=native.core_cache_metrics()
    local started=dfhack.getTickCount()
    native.native_prewarm_request(path,data.world,language,0)
    local _,_,after_request=native.core_cache_metrics()
    assert(after_request==before,'The request API submitted model work')
    local function wait_ready()
        local status=json.decode(native.native_prewarm_status())
        if status.error then error(status.error) end
        if status.world~=data.world or status.language~=language or status.revision~=data.revision or status.running or status.pending>0 then
            assert(dfhack.getTickCount()-started<10000,'Native preload deadline exceeded')
            dfhack.timeout(1,'frames',guarded(wait_ready));return
        end
        assert(status.loaded==#data.rows and status.ready+status.stalled==#data.rows,'Incomplete native accounting')
        local row={status=status,observed_ready_ms=dfhack.getTickCount()-started,checked=0,exact=0,canonical=0,missing=0,repainted=0,direct_call_submissions_added=0}
        result.languages[language]=row
        local rejected={}
        for _,bad in ipairs(status.stalled_sources or {}) do rejected[bad.source]=true end
        local cursor=1
        local function check_batch()
            for _=1,128 do
                local value=data.rows[cursor]
                if not value then
                    local _,_,after=native.core_cache_metrics();row.concurrent_frame_submissions_added=after-before
                    -- The separate release benchmark isolates the background worker from title redraws.
                    assert(row.missing<=status.stalled,'Unexpected unavailable rows')
                    print(('NATIVE_PREWARM %s loaded=%d ready=%d imported=%d skipped=%d stalled=%d elapsed_ms=%.3f checks=%d submissions=%d'):format(
                        language,status.loaded,status.ready,status.imported,status.skipped,status.stalled,status.elapsed_ms,row.checked,row.direct_call_submissions_added))
                    next_language();return
                end
                cursor=cursor+1;row.checked=row.checked+1
                local _,_,call_before=native.core_cache_metrics()
                local actual=native.cache_lookup(value.text)
                if not actual then
                    row.missing=row.missing+1
                    assert(rejected[value.text],'A valid preloaded row is missing: '..value.text)
                elseif actual==value.translation then
                    row.exact=row.exact+1
                else
                    row.canonical=row.canonical+1
                    assert(row.canonical<=status.canonical+status.stalled,'Unaccounted translation override')
                end
                if actual and row.checked%128==0 then
                    assert(native.async_translate(value.text)==actual,'First repaint did not reuse the known result')
                    row.repainted=row.repainted+1
                end
                local _,_,call_after=native.core_cache_metrics()
                row.direct_call_submissions_added=row.direct_call_submissions_added+call_after-call_before
                assert(call_after==call_before,'A ready cache lookup or repaint submitted model work')
            end
            dfhack.timeout(1,'frames',guarded(check_batch))
        end
        check_batch()
    end
    dfhack.timeout(1,'frames',guarded(wait_ready))
end
dfhack.timeout(2,'frames',guarded(next_language))
