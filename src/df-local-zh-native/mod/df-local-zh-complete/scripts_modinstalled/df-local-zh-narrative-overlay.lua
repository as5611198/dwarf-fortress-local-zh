--@module=true

local overlay=require('plugins.overlay')
local widgets=require('gui.widgets')
local gui=require('gui')
local narrative=reqscript('df-local-zh-narrative')
local runtime=reqscript('df-local-zh-runtime')

NarrativeOverlay=defclass(NarrativeOverlay,overlay.OverlayWidget)
NarrativeOverlay.ATTRS{
    desc='Traditional Chinese Legends narratives with original link targets',
    default_enabled=true,
    viewscreens='legends',
    full_interface=true,
    fullscreen=true,
    default_pos={x=1,y=1},
    frame={l=0,t=0,r=0,b=0},
}

function NarrativeOverlay:init()
    local width,height=dfhack.screen.getWindowSize()
    self.frame={l=0,t=0,w=width,h=height}
    self:addviews{widgets.Scrollbar{view_id='scrollbar',frame={r=2,t=9,b=2},
        on_scroll=function(value)
            local state=narrative.view(runtime)
            if not state then return end
            local deltas={up_small=-3,down_small=3,up_large=-state.height,down_large=state.height}
            narrative.scroll(type(value)=='number' and value-1-state.scroll or deltas[value] or 0)
        end}}
end

function NarrativeOverlay:render(dc)
    local state=narrative.view(runtime)
    if not state then return end
    local now=dfhack.getTickCount()
    if not self.next_refresh_ms or now>=self.next_refresh_ms then
        self.next_refresh_ms=now+100
        runtime.poll()
        narrative.poll(runtime)
    end
    local width,height=dfhack.screen.getWindowSize()
    self.frame={l=0,t=0,w=width,h=height}
    self:updateLayout(gui.ViewRect{rect=gui.mkdims_wh(0,0,width,height)})
    self.subviews.scrollbar:update(state.scroll+1,state.height,math.max(state.height,state.total))
    NarrativeOverlay.super.render(self,dc)
end

function NarrativeOverlay:onRenderBody()
    local state=narrative.view(runtime)
    if not state then return end
    local width,height=dfhack.screen.getWindowSize()
    local mouse_x,mouse_y=dfhack.screen.getMousePos()
    dfhack.screen.fillRect({ch=32,fg=COLOR_WHITE,bg=COLOR_BLACK},1,9,width-2,height-2)
    for _,chunk in ipairs(state.chunks) do
        local y=9+chunk.y-state.scroll
        if y>=9 and y<9+state.height then
            chunk.key=chunk.key or runtime.literal_key(chunk.text)
            if chunk.key then
                local x=2+chunk.x
                local hovered=chunk.link and mouse_y==y and mouse_x and
                    mouse_x>=x and mouse_x<x+chunk.width
                runtime.draw_key(x,y,hovered and COLOR_YELLOW or chunk.color,0,chunk.key)
            end
        end
    end
end

function NarrativeOverlay:onInput(keys)
    if narrative.dispatching() then return false end
    local state=narrative.view(runtime)
    if not state then return false end
    if self.subviews.scrollbar:onInput(keys) then return true end
    local deltas={STANDARDSCROLL_UP=-1,KEYBOARD_CURSOR_UP=-1,
        STANDARDSCROLL_DOWN=1,KEYBOARD_CURSOR_DOWN=1,
        STANDARDSCROLL_PAGEUP=-state.height,KEYBOARD_CURSOR_UP_FAST=-state.height,
        STANDARDSCROLL_PAGEDOWN=state.height,KEYBOARD_CURSOR_DOWN_FAST=state.height}
    for key,delta in pairs(deltas) do if keys[key] then return narrative.scroll(delta) end end
    if not keys._MOUSE_L then return false end
    local x,y=dfhack.screen.getMousePos()
    if not x or not y or y<9 or y>=9+state.height then return false end
    for _,chunk in ipairs(state.chunks) do
        if chunk.link and y==9+chunk.y-state.scroll and
                x>=2+chunk.x and x<2+chunk.x+chunk.width then
            return narrative.click(chunk.link)
        end
    end
    return true
end

OVERLAY_WIDGETS={narratives=NarrativeOverlay}
