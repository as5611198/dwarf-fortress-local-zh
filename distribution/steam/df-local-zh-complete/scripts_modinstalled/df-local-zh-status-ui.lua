--@module=true
local gui=require('gui')
local widgets=require('gui.widgets')
local overlay=require('plugins.overlay')
local status=reqscript('df-local-zh-status')
local runtime=reqscript('df-local-zh-runtime')
local mod=reqscript('df-local-zh-core/mod')
local labels,label_world={},nil
local test_mode=false

function set_test_mode(enabled)
    test_mode=enabled==true
end

function is_test_mode() return test_mode end

local function label(text)
    if text:match('^[%d /%.%-]+$') then return text end
    local world=(dfhack.isWorldLoaded() and dfhack.getSavePath() or '')..':'..(runtime.language and runtime.language() or 'zh-Hant')
    if world~=label_world then labels={};label_world=world end
    if labels[text] then return labels[text] end
    local key=runtime.literal_key(text)
    local expected=runtime.localize_text and runtime.localize_text(text) or text
    if key and mod.async_translate(key)==expected then labels[text]=key;return key end
    return ''
end

local function paint(x,y,text,color)
    local key=label(text)
    if key~='' then runtime.draw_key(x,y,color or COLOR_WHITE,0,key) end
end

function background_state(data)
    if data.paused then return '已暫停' end
    if not data.online then return '服務離線' end
    local b=data.broker or {};local r=b.runtime or {}
    if (b.backgroundActive or 0)+(b.backgroundQueued or 0)+
            (r.backgroundActive or 0)+(r.backgroundQueued or 0)>0 then return '翻譯中' end
    local n,u,s=data.native or {},data.unit or {},data.sources or {}
    local initial=(n.pending or 0)+(n.queued or 0)+
        math.max(0,(u.templates or 0)-(u.templates_ready or 0))
    local collecting=s.pending or 0
    if initial+collecting>0 then
        if test_mode then return '待處理 '..(initial+collecting) end
        return initial>0 and '初次載入' or '背景整理'
    end
    if (n.stalled or 0)+(s.errors or 0)>0 then return '有停滯' end
    return '目前已清'
end

function lines(data)
    local b=data.broker or {};local r=b.runtime or {}
    local n,u,s=data.native or {},data.unit or {},data.sources or {}
    local v=s.visible
    local rows={
        {'服務',data.online and (b.providerConfigured and '已連線' or '未設定模型') or '離線'},
        {'背景作業',background_state(data)},
        {'需求範本已載入',string.format('%d / %d',u.fixed_loaded or 0,u.fixed or 0)},
        {'已知偏好',string.format('%d / %d',u.templates_ready or 0,u.templates or 0)},
        {'原生快取',string.format('%d / %d',n.ready or 0,(n.loaded or 0)+(n.queued or 0))},
        {'收集文字',string.format('%d / %d',s.ready or 0,s.collected or 0)},
        {'原生等待',tostring((n.pending or 0)+(n.queued or 0))},
        {'原生停滯',tostring(n.stalled or 0)},
        {'收集錯誤',tostring(s.errors or 0)},
        {'模型排隊',tostring(b.providerQueued or 0)},
        {'模型處理中',tostring(b.providerActive or 0)},
        {'前景待辦',tostring(r.foregroundQueued or 0)},
        {'背景待辦',tostring(r.backgroundQueued or 0)},
        {'本世界未解決',tostring(r.unresolved or 0)},
    }
    if v then
        rows[#rows+1]={'目前畫面文字',string.format('%d / %d',
            math.max(0,(v.active or 0)-(v.pending or 0)),v.active or 0)}
        rows[#rows+1]={'畫面收集錯誤',tostring((v.errors or 0)+(v.log_errors or 0))}
    end
    return rows
end

StatusBody=defclass(StatusBody,widgets.Panel)
function StatusBody:onRenderBody()
    local data=status.snapshot()
    local rect=self.frame_body
    if self.parent_view then
        local parent=self.parent_view.frame_body
        paint(parent.x1+2,parent.y1-2,'翻譯狀態',COLOR_WHITE)
    end
    for index,row in ipairs(lines(data)) do
        paint(rect.x1+1,rect.y1+index-1,row[1],COLOR_WHITE)
        paint(rect.x1+31,rect.y1+index-1,row[2],COLOR_LIGHTCYAN)
    end
end

NativeButton=defclass(NativeButton,widgets.Panel)
NativeButton.ATTRS{key=DEFAULT_NIL,caption=DEFAULT_NIL,on_activate=DEFAULT_NIL}
function NativeButton:onRenderBody()
    local rect=self.frame_body
    local key=gui.getKeyDisplay(self.key)..': '
    paint(rect.x1,rect.y1,key,COLOR_LIGHTGREEN)
    local text=type(self.caption)=='function' and self.caption() or self.caption
    paint(rect.x1+#key,rect.y1,text,COLOR_WHITE)
end
function NativeButton:onInput(keys)
    if keys[self.key] or keys._MOUSE_L and self:getMousePos() then
        self.on_activate();return true
    end
end

StatusScreen=defclass(StatusScreen,gui.ZScreen)
StatusScreen.ATTRS{focus_path='df-local-zh/status'}
function StatusScreen:init()
    self:addviews{widgets.Window{
        frame={w=62,h=27},frame_title='',resizable=false,draggable=false,
        subviews={StatusBody{frame={l=1,t=1,r=1,h=16}},
            NativeButton{frame={l=2,t=19,w=36,h=1},key='CUSTOM_P',
                caption=function() return status.paused_background() and
                    '繼續背景整理' or '暫停背景整理' end,
                on_activate=function() status.set_paused(not status.paused_background()) end},
            NativeButton{frame={l=2,t=21,w=24,h=1},key='CUSTOM_R',
                caption='重新整理',on_activate=function() status.snapshot(true) end},
            NativeButton{frame={r=2,t=21,w=16,h=1},key='LEAVESCREEN',
                caption='關閉',on_activate=function() self:dismiss() end},
        }}}
end

local screen
function show()
    if screen and screen:isActive() then screen:raise();return end
    screen=StatusScreen{};screen:show()
end

StatusOverlay=defclass(StatusOverlay,overlay.OverlayWidget)
StatusOverlay.ATTRS{desc='翻譯狀態',default_enabled=true,
    default_pos={x=4,y=-17},viewscreens='dwarfmode',frame={w=38,h=3}}
function StatusOverlay:onRenderBody()
    if not dfhack.isMapLoaded() then return end
    local data=status.snapshot();local b=data.broker or {}
    local rect=self.frame_body
    paint(rect.x1,rect.y1,'翻譯狀態',data.online and COLOR_LIGHTGREEN or COLOR_LIGHTRED)
    paint(rect.x1+20,rect.y1,background_state(data),COLOR_YELLOW)
    if not test_mode then return end
    paint(rect.x1,rect.y1+1,'模型排隊',COLOR_WHITE)
    paint(rect.x1+18,rect.y1+1,tostring(b.providerQueued or 0),COLOR_LIGHTCYAN)
    paint(rect.x1,rect.y1+2,'模型處理中',COLOR_WHITE)
    paint(rect.x1+18,rect.y1+2,tostring(b.providerActive or 0),COLOR_LIGHTCYAN)
end
function StatusOverlay:onInput(keys)
    if keys._MOUSE_L and self:getMousePos() then show();return true end
end
OVERLAY_WIDGETS={status=StatusOverlay}
if not dfhack_flags.module then
    local mode=({...})[1]
    if mode=='--test' or mode=='--release' then
        set_test_mode(mode=='--test')
        dfhack.run_command('overlay','enable','df-local-zh-status-ui.status')
    else show() end
end
