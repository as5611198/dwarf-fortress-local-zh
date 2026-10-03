-- Use isolated module environments and no shown screens or save writes.
local source=...
local function module(name)
    local env=setmetatable({dfhack_flags={module=true}},{__index=_G})
    assert(loadfile(source..'/'..name..'.lua','t',env))()
    return env
end
local history=module('df-local-zh-history')
history.HistoryScreen.load_page=function() end
local h=history.HistoryScreen{}
local pages={}
h.page=function(_,delta) pages[#pages+1]=delta end
h.subviews.search.edit:setFocus(true)
assert(h.subviews[1]:onInput{CUSTOM_CTRL_B=true},'Previous-page key lost to focused search')
assert(h.subviews[1]:onInput{CUSTOM_CTRL_N=true},'Next-page key lost to focused search')
assert(#pages==2 and pages[1]==-1 and pages[2]==1)
local adventure=module('df-local-zh-adventure')
adventure.AdventureScreen.refresh=function() end
local a=adventure.AdventureScreen{source_screen={}}
local refreshes=0
a.refresh=function() refreshes=refreshes+1 end
a.subviews.search.edit:setFocus(true)
assert(a.subviews[1]:onInput{CUSTOM_CTRL_E=true},'Refresh key lost to focused search')
assert(refreshes==1)
-- No view may advertise global macro controls.
local function no_macros(view)
    assert(view.key~='CUSTOM_CTRL_S' and view.key~='CUSTOM_CTRL_R' and view.key~='CUSTOM_CTRL_P')
    for _,sub in ipairs(view.subviews or {}) do no_macros(sub) end
end
no_macros(h);no_macros(a)
print('SHORTCUT_ROUTING PASS: focused history pagination and journal refresh; no save writes')
