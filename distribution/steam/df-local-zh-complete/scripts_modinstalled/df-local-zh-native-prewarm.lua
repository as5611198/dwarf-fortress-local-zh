--@module=true
-- The DLL owns file I/O, validation and bulk publication on its own worker.
local json=require('json')
local native=reqscript('df-local-zh-core/native')
local paths=reqscript('df-local-zh-paths')

function poll()
    local world=dfhack.isWorldLoaded() and dfhack.isMapLoaded() and dfhack.getSavePath() or ''
    local runtime=reqscript('df-local-zh-runtime')
    local language=runtime.language()
    local paused=reqscript('df-local-zh-status').paused_background()
    local filename=language=='zh-Hans' and '/native-prewarm-zh-Hans.json' or '/native-prewarm.json'
    native.native_prewarm_request(paths.broker_data()..filename,world,language,paused and 1 or 0)
end

function status()
    return json.decode(native.native_prewarm_status())
end

function start()
    poll()
    require('repeat-util').scheduleUnlessAlreadyScheduled('df-local-zh-native-prewarm',20,'frames',function()
        local ok,err=pcall(poll)
        if not ok then dfhack.printerr('df-local-zh-native-prewarm: '..tostring(err)) end
    end)
end

function stop()
    require('repeat-util').cancel('df-local-zh-native-prewarm')
    native.native_prewarm_request('', '', 'zh-Hant', 0)
end
