-- Isolated UI action fixture: load production methods, no game or player state.
local source=...
local calls,reply,queued={},nil,nil
local fake={submit=function(request,callback)
    calls[#calls+1]=request
    if reply then callback(reply) else queued=callback end
    return true
end}
local env=setmetatable({dfhack_flags={module=true},
    require=function() return {} end,
    reqscript=function(name) if name=='df-local-zh-settings' then return fake end;return {} end,
    defclass=function() return {ATTRS=function() end} end},{__index=_G})
assert(loadfile(source..'/df-local-zh-settings-ui.lua','t',env))()
local option=true
local view=setmetatable({draft={officialAutoDownload=true,translationPrompt='未套用'},
    profile={key='draft-secret'},subviews={officialAutoDownload={setOption=function(_,value) option=value end}},
    isActive=function() return true end},{__index=env.SettingsScreen})
assert(not view:clear_official() and #calls==0)
assert(view:clear_official() and #calls==1)
assert(calls[1].action=='official-clear' and calls[1].settings==nil and calls[1].profile==nil)
queued({ok=true})
assert(option==false and view.draft.officialAutoDownload==false)
assert(view.draft.translationPrompt=='未套用' and view.profile.key=='draft-secret')
assert(view.message:find('請重開遊戲'))
-- Failed clears must not be presented as successful; they can be retried.
reply={ok=false,error='fixture failure'}
assert(not view:clear_official());assert(view:clear_official())
assert(view.message=='fixture failure' and not view.clear_official_armed)
reply={ok=true}
assert(not view:clear_official());assert(view:clear_official())
assert(view.message:find('請重開遊戲'),'Synchronous completion must not be replaced by progress text')
print('OFFICIAL_CLEAR_UI PASS: confirmation, no draft/key saving, async completion, failure and retry')
