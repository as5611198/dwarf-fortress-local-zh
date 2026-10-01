--@module=true
local json=require('json')
local paths=reqscript('df-local-zh-paths')
local cached,last_read,paused=nil,nil,false
local cached_snapshot,snapshot_time,snapshot_world
local modules={}
local waiting,wait_serial,next_turn={},{},0
local sequence=0

local function read(name)
    local file=io.open(paths.broker_data()..'/'..name,'rb')
    if not file then return end
    local text=file:read('*a');file:close()
    local ok,value=pcall(json.decode,text)
    return ok and type(value)=='table' and value or nil
end

function broker(force)
    local now=os.time()
    if force or last_read~=now then
        last_read=now;cached=read('broker-status.json')
        local control=read('translation-controls.json')
        if control and control.version==1 and type(control.backgroundPaused)=='boolean' then
            paused=control.backgroundPaused
        end
    end
    return cached
end

function paused_background() broker();return paused end

function background_allowed()
    local data=broker()
    if paused then return false end
    if not data or type(data.timestamp)~='number' or math.abs(os.time()-data.timestamp/1000)>=5 then
        return false
    end
    if not dfhack.isWorldLoaded() or data.world~=dfhack.getSavePath() then return false end
    local r=data.runtime or {}
    return (data.foregroundActive or 0)+(data.foregroundQueued or 0)+
        (r.foregroundQueued or 0)+(r.foregroundActive or 0)==0
end

function claim_background(name)
    if not background_allowed() then waiting,wait_serial={},{};return false end
    local now=dfhack.getTickCount and dfhack.getTickCount() or os.time()*1000
    if not waiting[name] then
        sequence=sequence+1;waiting[name]=true;wait_serial[name]=sequence
    end
    if now<next_turn then return false end
    for other in pairs(waiting) do
        if wait_serial[other]<wait_serial[name] then return false end
    end
    waiting[name],wait_serial[name]=nil,nil
    next_turn=now+250
    return true
end

function set_paused(value)
    assert(type(value)=='boolean')
    local path=paths.broker_data()..'/translation-controls.json'
    local file=assert(io.open(path..'.tmp','wb'))
    assert(file:write(json.encode({version=1,backgroundPaused=value},{pretty=false})));assert(file:close())
    os.remove(path)
    assert(os.rename(path..'.tmp',path))
    paused=value;last_read=nil
    cached_snapshot=nil
end

local function module_status(name)
    local module=modules[name]
    if not module then
        local ok,value=pcall(reqscript,name)
        if not ok then return {unavailable=true} end
        module=value;modules[name]=module
    end
    local success,value=pcall(module.status)
    return success and value or {unavailable=true}
end

function snapshot(force)
    local current=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    local now=os.time()
    if not force and cached_snapshot and snapshot_time==now and snapshot_world==current then
        return cached_snapshot
    end
    local data=broker(force)
    local online=data and data.version==1 and type(data.timestamp)=='number' and
        math.abs(os.time()-data.timestamp/1000)<5 and data.world==current
    cached_snapshot={online=not not online,paused=paused,broker=online and data or {},
        native=module_status('df-local-zh-native-prewarm'),
        unit=module_status('df-local-zh-unit-prewarm'),
        sources=module_status('df-local-zh-prefetch')}
    snapshot_time,snapshot_world=now,current
    return cached_snapshot
end
