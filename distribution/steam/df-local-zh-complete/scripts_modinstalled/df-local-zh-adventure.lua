--@module=true
-- Read-only adapter for the public 53.16 adventure journal structures.
local gui=require('gui')
local widgets=require('gui.widgets')
local overlay=require('plugins.overlay')
local unicode=reqscript('df-local-zh-unicode')
local runtime=reqscript('df-local-zh-runtime')
local function field(object,key)
    local ok,value=pcall(function() return object[key] end);return ok and value or nil
end
local groups={{'adventure_log_event','事件'},{'site_entry','地點'},
    {'histfig_entry','人物'},{'entity_entry','組織'},{'artifact_entry','神器'},
    {'agreement_entry','協議'},{'bestiary_entry','生物'}}
function collect(screen)
    local rows={}
    for _,group in ipairs(groups) do
        local entries=field(screen,group[1])
        if entries then
            for _,entry in ipairs(entries) do
                if #rows>=512 then return rows end
                local text=field(entry,'summary')
                if type(text)~='string' or text=='' then text=field(entry,'list_name') end
                if type(text)~='string' or text=='' then text=field(entry,'simple_list_name') end
                if type(text)=='string' and text~='' then
                    rows[#rows+1]={source=unicode.decode(text),category=group[2]}
                end
            end
        end
    end
    return rows
end
AdventureScreen=defclass(AdventureScreen,gui.ZScreen)
AdventureScreen.ATTRS{focus_path='df-local-zh/adventure',source_screen=DEFAULT_NIL}
function AdventureScreen:init()
    self.rows=collect(self.source_screen)
    self.world=dfhack.getSavePath()
    self:addviews{widgets.Window{frame={w=math.min(100,select(1,dfhack.screen.getWindowSize())-2),h=28},
        frame_title='冒險日誌中文閱讀',subviews={
            widgets.FilteredList{view_id='search',frame={l=1,t=0,r=1,b=3},choices={}},
            widgets.HotkeyLabel{frame={l=1,b=1},key='CUSTOM_CTRL_E',label='更新譯文',on_activate=function() self:refresh() end},
            widgets.HotkeyLabel{frame={r=1,b=1},key='LEAVESCREEN',label='關閉',on_activate=function() self:dismiss() end},
        }}}
    self:refresh()
end
function AdventureScreen:refresh()
    if not dfhack.isWorldLoaded() or dfhack.getSavePath()~=self.world then self:dismiss();return end
    local choices={}
    for _,row in ipairs(self.rows) do
        -- Uses the existing player's language/API policy and name-aware broker.
        local value=runtime.translation(row.source) or row.source
        choices[#choices+1]={text=row.category..'：'..value,source=row.source}
    end
    if #choices==0 then choices={{text='目前日誌沒有可讀取的項目'}} end
    self.subviews.search:setChoices(choices)
end
function show(screen)
    screen=screen or dfhack.gui.getDFViewscreen()
    assert(dfhack.isWorldLoaded() and df.viewscreen_adventure_logst:is_instance(screen),'Open the adventure journal first')
    return AdventureScreen{source_screen=screen}:show()
end
AdventureOverlay=defclass(AdventureOverlay,overlay.OverlayWidget)
AdventureOverlay.ATTRS{desc='Chinese reader and UTF-8 search for the adventure journal',
    default_enabled=true,viewscreens={'adventure_log'},default_pos={x=-24,y=-4},frame={w=22,h=1}}
function AdventureOverlay:init()
    self:addviews{widgets.HotkeyLabel{key='CUSTOM_CTRL_H',label='中文日誌',on_activate=show}}
end
OVERLAY_WIDGETS={adventure=AdventureOverlay}
if not dfhack_flags.module then show() end
