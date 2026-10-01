local draws,fills={},{}
local screen={}
local source='An old book'
local env=setmetatable({
    COLOR_WHITE=7,COLOR_BLACK=0,
    defclass=function() return {ATTRS=function() end} end,
    require=function(name)
        if name=='plugins.overlay' then return {OverlayWidget={}} end
        return require(name)
    end,
    reqscript=function() return {
        short_lookup=function(text) assert(text==source);return 'L000001' end,
        pending_key=function() error('Unexpected pending key') end,
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
print('PASS text viewer foreground, brightness and background preservation')
