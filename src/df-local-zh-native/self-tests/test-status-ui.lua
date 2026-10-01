local root=dfhack.getDFPath()
local script_root=(...) or reqscript('df-local-zh-paths').source()..'/scripts_modinstalled'
local json=require('json')
local now=100
local milliseconds=100000
local module_reads=0
local contents={['broker-status.json']=json.encode({version=1,timestamp=100000,world='fortress',
    providerConfigured=true,providerQueued=3,providerActive=1,runtime={unresolved=2}})}
local status_env=setmetatable({
    require=require,os={time=function() return now end},
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return 'fortress' end,
        getTickCount=function() return milliseconds end},
    io={open=function(path,mode)
        local name=path:match('([^/]+)$');local content=contents[name]
        if mode=='rb' then
            if not content then return end
            return {read=function() return content end,close=function() return true end}
        end
    end},
    reqscript=function(name)
        if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture' end} end
        module_reads=module_reads+1
        return {status=function() return {fixed=868,fixed_loaded=868,ready=7,loaded=10,queued=1} end}
    end,
},{__index=_G})
assert(loadfile(script_root..'/df-local-zh-status.lua','t',status_env))()
assert(status_env.snapshot().online and status_env.background_allowed(),'Fresh matching-world service should be usable')
for _=1,100 do status_env.snapshot() end
assert(module_reads==3,'Rendering must reuse one statistics snapshot per second')
assert(status_env.claim_background,'Prewarm sources need one shared real-time scheduler')
assert(status_env.claim_background('unit'),'The first eligible worker should run')
assert(not status_env.claim_background('native'),'Other workers must not pile onto the same frame')
milliseconds=milliseconds+250
assert(not status_env.claim_background('unit'),'The worker already waiting should keep priority')
assert(status_env.claim_background('native'),'Shared throttling must not starve another source')
now=106
assert(not status_env.snapshot().online and not status_env.background_allowed(),'Stale service status must not allow background AI')
now=100
local draws,keys,ready={}, {},false
local data=status_env.snapshot(true)
local runtime={literal_key=function(text)
    keys[text]=keys[text] or 'L'..string.format('%06d',#draws+1)..text
    return keys[text]
end,draw_key=function(x,y,color,bg,key) draws[#draws+1]={x=x,y=y,key=key} end}
local language='zh-Hant'
runtime.language=function() return language end
runtime.localize_text=function(text) return language=='zh-Hans' and text:gsub('預','预'):gsub('譯','译') or text end
local mod={async_translate=function(key)
    if ready then for text,value in pairs(keys) do if value==key then return runtime.localize_text(text) end end end
end}
local classes={}
local env=setmetatable({require=function(name)
    if name=='gui' then return {ZScreen={},getKeyDisplay=function() return 'r' end} end
    if name=='gui.widgets' then return {Panel={},Window={},HotkeyLabel={}} end
    if name=='plugins.overlay' then return {OverlayWidget={}} end
    return require(name)
end,dfhack=status_env.dfhack,dfhack_flags={module=true},
reqscript=function(name)
    if name=='df-local-zh-status' then return {snapshot=function() return data end} end
    if name=='df-local-zh-runtime' then return runtime end
    if name=='df-local-zh-core/mod' then return mod end
end,defclass=function()
    local cls={ATTRS=function() end};classes[#classes+1]=cls;return cls
end,COLOR_WHITE=7,COLOR_LIGHTCYAN=11,COLOR_LIGHTGREEN=10,COLOR_LIGHTRED=12,COLOR_YELLOW=14},
{__index=_G})
assert(loadfile(script_root..'/df-local-zh-status-ui.lua','t',env))()
data.sources={pending=67}
data.native={pending=0,queued=0,stalled=41}
assert(env.background_state(data)=='背景整理','Ongoing text collection must not look like an initial prewarm')
data.native.queued=2
assert(env.background_state(data)=='初次載入','Finite native publication needs a distinct initial-load state')
data.native.queued=0
env.set_test_mode(true)
assert(env.background_state(data)=='待處理 67','Test mode must retain pending diagnostics')
env.set_test_mode(false)
data.broker.backgroundActive=1
assert(env.background_state(data)=='翻譯中','Actual background work must be identified')
data.broker.backgroundActive=0
data.sources.pending=0
assert(env.background_state(data)=='有停滯','Native stalls must remain visible after the queue clears')
data.native.stalled=0
assert(env.background_state(data)=='目前已清','An empty current backlog must not claim all future content is done')
data.paused=true
assert(env.background_state(data)=='已暫停','Pause takes precedence over backlog state')
data.paused=false
env.StatusBody.onRenderBody({frame_body={x1=0,y1=0}})
for _,row in ipairs(draws) do assert(not row.key:match('^L'),'UI must not expose an unready L-code') end
ready=true;draws={}
env.StatusBody.onRenderBody({frame_body={x1=0,y1=0}})
assert(#draws==28,'Every label and value should render when ready')
language='zh-Hans'
draws={}
env.StatusBody.onRenderBody({frame_body={x1=0,y1=0}})
assert(#draws==28,'Simplified status labels must keep rendering after a language switch')
language='zh-Hant'
for _,row in ipairs(draws) do assert(row.x>=0 and row.x<60 and row.y>=0 and row.y<14,'UI row outside its panel') end
local rows=env.lines(data)
assert(rows[3][2]=='868 / 868','Fixed Needs progress describes loaded translations, not unused color combinations')
assert(rows[10][2]=='3' and rows[11][2]=='1' and rows[14][2]=='2','Queue numbers must come from live status')
assert(env.NativeButton,'Chinese controls need a native rendering widget with a matching click rectangle')
draws={}
env.NativeButton.onRenderBody({frame_body={x1=0,y1=0},key='CUSTOM_R',caption='重新整理'})
assert(draws[1].key==keys['r: '], 'Shortcut prefixes must use literal aliases, never raw model input')
local activated=0
assert(env.NativeButton.onInput({key='CUSTOM_P',on_activate=function() activated=activated+1 end,
    getMousePos=function() return 2,0 end},{_MOUSE_L=true}),'Click anywhere in the visible button must activate')
assert(activated==1,'Mouse activation must run exactly once')
data.sources.visible={collected=40,ready=35,active=4,pending=1,errors=2,log_errors=1}
rows=env.lines(data)
assert(rows[15] and rows[15][2]=='3 / 4','The panel must show actual ready versus active visible text')
assert(rows[16] and rows[16][2]=='3','Visible source and log errors must be reflected in the panel')
draws={}
env.StatusBody.onRenderBody({frame_body={x1=0,y1=0}})
assert(#draws==32,'All sixteen status rows must render when the native labels are ready')
for _,row in ipairs(draws) do
    assert(row.x>=0 and row.x<60 and row.y>=0 and row.y<16,
        'Expanded visible-source status must stay within its body rectangle')
end
print('PASS status staleness, current-world data, native label readiness and UI row bounds')

env.dfhack.isMapLoaded=function() return true end
local overlay_widget={frame_body={x1=0,y1=0},getMousePos=function() return 1,1 end}
draws={}
env.StatusOverlay.onRenderBody(overlay_widget)
assert(#draws==2,'Release mode must retain the compact prewarm entry without debug counters')
local opened=0
env.show=function() opened=opened+1 end
assert(env.StatusOverlay.onInput(overlay_widget,{_MOUSE_L=true}) and opened==1,
    'The compact entry must open the detailed status panel')
env.set_test_mode(true)
draws={}
env.StatusOverlay.onRenderBody(overlay_widget)
assert(#draws==6,'Test mode must retain all status overlay fields')
env.set_test_mode(false)
draws={}
env.StatusOverlay.onRenderBody(overlay_widget)
assert(#draws==2,'Leaving test mode must hide debug counters while retaining the status entry')
print('PASS release status entry and test-only debug counters')
