--@module=true
local gui=require('gui')
local widgets=require('gui.widgets')
local overlay=require('plugins.overlay')
local native=reqscript('df-local-zh-core/native')
local unicode=reqscript('df-local-zh-unicode')
local json=require('json')
local refs={
    {'victim_hf','victim','historical_figure'},{'slayer_hf','slayer','historical_figure'},
    {'creator_hfid','creator','historical_figure'},{'builder_hf','builder','historical_figure'},
    {'histfig','figure','historical_figure'},{'hfid','figure','historical_figure'},{'hf','figure','historical_figure'},
    {'hf_target','target','historical_figure'},{'target_hf','target','historical_figure'},
    {'civ','entity','historical_entity'},{'entity','entity','historical_entity'},
    {'site','site','world_site'},{'artifact_id','artifact','artifact_record'},{'artifact','artifact','artifact_record'},
}
local function read(object,key) local ok,value=pcall(function() return object[key] end);return ok and value or nil end
local function resolve(class,id)
    local ok,object=pcall(function() return df[class].find(id) end)
    if not ok or not object then return '' end
    local name=read(object,'name')
    if not name then return '' end
    local ok,value=pcall(dfhack.translation.translateName,name,false)
    return ok and unicode.decode(value) or ''
end
function structured(event,resolver)
    resolver=resolver or resolve
    local ok,kind=pcall(function() return event:getType() end)
    if not ok then return end
    kind=type(kind)=='string' and kind or df.history_event_type[kind]
    if type(kind)~='string' then return end
    local row={id=read(event,'id') or -1,kind=kind,year=read(event,'year') or -1,references={}}
    for _,ref in ipairs(refs) do
        local id=read(event,ref[1])
        if type(id)=='number' and id>=0 then
            row.references[#row.references+1]={role=ref[2],id=id,name=resolver(ref[3],id) or ''}
        end
    end
    return row
end
function describe(event)
    local row=structured(event)
    return row and native.history_event_render(json.encode(row))
end
HistoryScreen=defclass(HistoryScreen,gui.ZScreen)
HistoryScreen.ATTRS{focus_path='df-local-zh/history',page_size=200,offset=DEFAULT_NIL}
function HistoryScreen:init()
    assert(dfhack.isWorldLoaded(),'Load a world to browse its historical events')
    self.world=dfhack.getSavePath()
    local count=#df.global.world.history.events
    self.offset=self.offset or math.max(0,count-self.page_size)
    self:addviews{widgets.Window{frame={w=math.min(100,select(1,dfhack.screen.getWindowSize())-2),h=28},frame_title='結構化歷史事件',subviews={
        widgets.FilteredList{view_id='search',frame={l=1,t=0,r=1,b=3},choices={}},
        widgets.HotkeyLabel{frame={l=1,b=1},key='CUSTOM_CTRL_B',label='較早事件',on_activate=function() self:page(-1) end},
        widgets.HotkeyLabel{frame={l=22,b=1},key='CUSTOM_CTRL_N',label='較晚事件',on_activate=function() self:page(1) end},
        widgets.HotkeyLabel{frame={r=1,b=1},key='LEAVESCREEN',label='關閉',on_activate=function() self:dismiss() end},
    }}}
    self:load_page()
end
function HistoryScreen:load_page()
    local generation=(self.generation or 0)+1;self.generation=generation
    local rows,index={},self.offset
    local function step()
        if not self:isActive() or self.generation~=generation then return end
        if not dfhack.isWorldLoaded() or dfhack.getSavePath()~=self.world then self:dismiss();return end
        local events=df.global.world.history.events
        local limit=math.min(#events,self.offset+self.page_size)
        for _=1,32 do
            if index>=limit then self.subviews.search:setChoices(rows);return end
            local event=events[index]
            local value=describe(event)
            rows[#rows+1]={text=value or ('事件 #'..tostring(read(event,'id') or index)),id=read(event,'id')}
            index=index+1
        end
        self.subviews.search:setChoices(rows)
        dfhack.timeout(1,'frames',step)
    end
    dfhack.timeout(1,'frames',step)
end
function HistoryScreen:page(delta)
    if not dfhack.isWorldLoaded() then self:dismiss();return end
    self.offset=math.max(0,math.min(math.max(0,#df.global.world.history.events-self.page_size),self.offset+delta*self.page_size))
    self:load_page()
end
function show() return HistoryScreen{}:show() end
HistoryOverlay=defclass(HistoryOverlay,overlay.OverlayWidget)
HistoryOverlay.ATTRS{desc='Browse independent structured Chinese history summaries',default_enabled=true,
    viewscreens={'legends'},default_pos={x=-24,y=-4},frame={w=22,h=1}}
function HistoryOverlay:init()
    self:addviews{widgets.HotkeyLabel{frame={l=0,t=0},key='CUSTOM_CTRL_H',label='中文事件',on_activate=show}}
end
OVERLAY_WIDGETS={history=HistoryOverlay}
if not dfhack_flags.module then show() end
