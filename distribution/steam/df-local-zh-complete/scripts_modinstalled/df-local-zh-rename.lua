--@module=true
-- Independent UTF-8 nickname entry; writes only when the player accepts.
local gui=require('gui')
local widgets=require('gui.widgets')
local input=reqscript('df-local-zh-search')
local native=reqscript('df-local-zh-core/native')

function valid(text)
    return type(text)=='string' and utf8.len(text)~=nil and utf8.len(text)<=64 and not text:find('[%z\1-\31]')
end
local function name_text(value)
    return reqscript('df-local-zh-unicode').decode(value)
end
NameEdit=defclass(NameEdit,widgets.EditField)
function NameEdit:onRenderBody(dc)
    input.track(self,{get=function() return self.text end,set=function(text) self:setText(text,self.cursor) end,
        cursor=function() return self.cursor end,set_cursor=function(cursor) self:setCursor(cursor) end,
        rect=self.text_area.frame_body,max_bytes=256})
end
RenameScreen=defclass(RenameScreen,gui.ZScreen)
RenameScreen.ATTRS{focus_path='df-local-zh/rename',unit=DEFAULT_NIL}
function RenameScreen:init()
    assert(self.unit,'Select a unit to rename')
    self.original=self.unit.name.nickname
    self:addviews{widgets.Window{frame={w=54,h=8},frame_title='中文暱稱',subviews={
        NameEdit{view_id='name_edit',frame={l=1,t=1,r=1},text=name_text(self.original),on_submit=function() self:accept() end},
        -- Ctrl+S is DF's global SAVE_MACRO; use the field's existing submit key.
        widgets.HotkeyLabel{frame={l=1,b=1,w=24},key='SELECT',label='套用',on_activate=function() self:accept() end},
        widgets.HotkeyLabel{frame={l=29,b=1,w=20},key='LEAVESCREEN',label='取消',on_activate=function() self:dismiss() end},
    }}}
    self.subviews.name_edit:setFocus(true)
end
function RenameScreen:accept()
    local value=self.subviews.name_edit.text
    if not valid(value) then return end
    assert(self.unit.name.nickname==self.original,'Nickname changed externally; reopen the editor')
    -- DFHack updates unit, soul and historical-figure nicknames consistently.
    dfhack.units.setNickname(self.unit,value)
    self:dismiss()
end
function show(unit)
    unit=unit or dfhack.gui.getSelectedUnit(true)
    if not unit then qerror('Select a unit before opening the Chinese nickname editor') end
    return RenameScreen{unit=unit}:show()
end
-- The vanilla unit-sheet pencil is a legacy byte editor, not a searchable
-- widget. Transfer entry before it consumes text; only accept writes a name.
function poll_native()
    local screen=dfhack.gui.getCurViewscreen()
    if screen~=dfhack.gui.getDFViewscreen() or not df.viewscreen_dwarfmodest:is_instance(screen) then return end
    local sheet=df.global.game.main_interface.view_sheets
    if not sheet.unit_overview_entering_nickname then return end
    local unit=dfhack.gui.getSelectedUnit(true)
    if not unit then return end
    local opened=show(unit)
    sheet.unit_overview_entering_nickname=false
    return opened
end
if not dfhack_flags.module then show() end
