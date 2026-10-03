-- Exercise installed Lua -> native -> translation with a detached unit only.
local reference=assert(df.unit.find(16285),'Load the test world first')
local original=reference.name.nickname
local unit=df.unit:new()
local native=reqscript('df-local-zh-core/native')
local display=reqscript('df-local-zh-nickname-display')
local runtime=reqscript('df-local-zh-runtime')
local core=reqscript('df-local-zh-core/mod')
local json=require('json')
local ok,err=xpcall(function()
    unit.name:assign(dfhack.units.getVisibleName(reference))
    unit.name.nickname='測試𠮷 A1'
    unit.race=reference.race;unit.caste=reference.caste;unit.sex=reference.sex;unit.profession=reference.profession
    local s=display.snapshot(unit)
    local f=assert(io.open(reqscript('df-local-zh-paths').broker_source()..'/name-dictionary.json','rb'))
    local dictionary=json.decode(f:read('*a'));f:close()
    local first=dictionary[s.first] or dictionary[s.first:gsub('^%l',string.upper)]
    local rows=display.prepare(s,function(text)
        return text==s.profession and runtime.translation(text) or runtime.unit_name_translation(text)
    end,first and native.localize_text(first))
    assert(#rows==6,'Expected canonical name and profession to be available')
    for iteration=1,2 do
        assert(native.native_nickname_rows_set(json.encode(rows)))
        for _,row in ipairs(rows) do
            assert(core.sync_translate(row.source)==row.translation,'Sync path must bypass Chinese early-return')
            assert(core.async_translate(row.source)==row.translation,'Render path must bypass Chinese early-return')
            assert(row.translation:find(s.nickname,1,true),'Nickname must remain byte exact')
        end
        assert(native.native_nickname_rows_set('[]'))
        assert(core.sync_translate(s.native)==s.native,'Clearing must remove transient bindings')
    end
    local sheet={open=true,active_id=unit.id}
    local env=setmetatable({dfhack_flags={module=true},
        df=setmetatable({global={game={main_interface={view_sheets=sheet}}},
            unit=setmetatable({find=function() return unit end},{__index=df.unit})},{__index=df}),
        dfhack=setmetatable({gui=setmetatable({getFocusStrings=function() return {'dwarfmode/ViewSheets/UNIT/Overview'} end},
            {__index=dfhack.gui})},{__index=dfhack})},{__index=_G})
    assert(loadfile(dfhack.findScript('df-local-zh-nickname-display'),'t',env))()
    local bridge={translation=runtime.unit_translation,name_translation=runtime.unit_name_translation}
    for iteration=1,2 do
        sheet.open=true;env.poll(bridge);env.poll(bridge)
        for _,row in ipairs(rows) do assert(core.sync_translate(row.source)==row.translation,'Production polling and renewal must publish canonical rows') end
        sheet.open=false;env.poll(bridge)
        assert(core.sync_translate(s.native)==s.native,'Closing sheet must clear its bindings')
    end
    assert(unit.name.nickname=='測試𠮷 A1','Display must not mutate nickname')
    print('NICKNAME_INSTALLED PASS: 6 variants, sync and render paths, production poll/renewal/close/reopen, literal supplementary Unicode')
end,debug.traceback)
native.native_nickname_rows_set('[]');unit:delete()
assert(reference.name.nickname==original,'Save unit must remain unchanged')
assert(ok,err)
print('SAVE_UNIT_UNCHANGED PASS')
