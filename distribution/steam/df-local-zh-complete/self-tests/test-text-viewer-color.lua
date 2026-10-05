local draws,fills={},{}
local screen={}
local source='An old book'
local result,result_status='L000001','ready'
local env=setmetatable({
    COLOR_WHITE=7,COLOR_BLACK=0,
    defclass=function() return {ATTRS=function() end} end,
    require=function(name)
        if name=='plugins.overlay' then return {OverlayWidget={}} end
        return require(name)
    end,
    reqscript=function() return {
        short_lookup=function(text) assert(text==source);return result,result_status end,
        pending_key=function(status)
            assert(status==result_status,'The viewer must pass through the actual lookup status')
            return status=='queued' and 'P_____' or nil
        end,
        draw_key=function(...) draws[#draws+1]={...} end,
    } end,
    dfhack={df2utf=function(s) return s end,
        gui={getCurViewscreen=function() return screen end,getFocusString=function() return 'textviewer' end},
        screen={getWindowSize=function() return #source,1 end,
            readTile=function(x) return {ch=source:byte(x+1),fg=14,bg=3} end,
            fillRect=function(pen) fills[#fills+1]=pen end}},
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-text-overlay.lua','t',env))()
env.TextOverlay.onRenderBody({})
assert(#draws==1 and draws[1][3]==14 and draws[1][4]==3,
    'Text viewer must send the captured foreground and background to persistent drawing')
assert(fills[1].bg==3,'Erasing original text must retain the same background')
result=nil
for _,status in ipairs({'disabled','failed','unavailable','rendering'}) do
    result_status=status
    env.TextOverlay.onRenderBody({})
    assert(#fills==1 and #draws==1,'Unavailable translations must not erase native viewer text')
end
result_status='queued'
env.TextOverlay.onRenderBody({})
assert(#draws==2 and draws[2][5]=='P_____','Accepted AI jobs may show their waiting status')
print('PASS text viewer foreground, brightness and background preservation')
