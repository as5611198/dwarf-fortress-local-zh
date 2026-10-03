-- Exercise the native pencil boundary with a detached unit; never rename a save unit.
local source=...
local gui=require('gui')
local unit=df.unit:new();unit.name.nickname='fixture'
local sheet={unit_overview_entering_nickname=true,unit_overview_entering_profession_nickname=false}
local base=dfhack.gui.getCurViewscreen()
local selected=unit
local mock_gui=setmetatable({getSelectedUnit=function() return selected end,
    getCurViewscreen=function() return base end,getDFViewscreen=function() return base end},{__index=dfhack.gui})
local env=setmetatable({dfhack_flags={module=true},
    dfhack=setmetatable({gui=mock_gui},{__index=dfhack}),
    df=setmetatable({global={game={main_interface={view_sheets=sheet}}},
        viewscreen_dwarfmodest={is_instance=function() return true end}},{__index=df})},{__index=_G})
assert(loadfile(source..'/df-local-zh-rename.lua','t',env))()
local opened
local ok,err=xpcall(function()
    assert(type(env.poll_native)=='function','Native nickname pencil has no Chinese editor adapter')
    opened=env.poll_native()
    assert(opened and not sheet.unit_overview_entering_nickname,'Native entry must transfer to the Chinese editor')
    assert(opened.subviews.name_edit.focus and opened.subviews.name_edit.text=='fixture')
    opened.subviews.name_edit:setText('測試𠮷')
    opened:dismiss();opened=nil
    assert(unit.name.nickname=='fixture','Cancel must preserve the original nickname')
    assert(not env.poll_native(),'An inactive native entry must not reopen')
    selected=nil;sheet.unit_overview_entering_nickname=true
    assert(not env.poll_native() and sheet.unit_overview_entering_nickname,'Missing selection must leave native entry usable')
    selected=unit;sheet.unit_overview_entering_nickname=false;sheet.unit_overview_entering_profession_nickname=true
    assert(not env.poll_native(),'Profession entry must not rename the unit')
end,debug.traceback)
if opened then opened:dismiss() end
unit:delete()
assert(ok,err)
print('RENAME_NATIVE_ENTRY PASS: pencil handoff, focused editor, cancel, missing unit, profession isolation')
