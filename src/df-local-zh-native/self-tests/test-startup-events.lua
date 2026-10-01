local root=dfhack.getDFPath()
local calls,handlers={},{}
local paths={broker_source=function() return 'fixture/broker' end}
local apply_count=0
local env=setmetatable({dfhack={onStateChange=handlers,isWorldLoaded=function() return false end,
    timeout=function() end,
    printerr=function(message) error(message) end,run_command=function(...)
        calls[#calls+1]=table.concat({...},' ')
    end},reqscript=function(name)
        if name=='df-local-zh-paths' then return paths end
        if name=='df-local-zh-settings' then return {apply_native=function() apply_count=apply_count+1 end} end
        return {start=function() end,load_simple_dict=function() end,load_translation_rulesets=function() end}
    end,package={loadlib=function() return function() end end},
    SC_CORE_INITIALIZED=1,SC_VIEWSCREEN_CHANGED=2,SC_WORLD_LOADED=3,SC_WORLD_UNLOADED=4,
},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh.lua','t',env))()
local writes=#calls
for _=1,100 do handlers.df_local_zh(2) end
assert(#calls==writes,'View changes must not repeatedly write overlay configuration')
assert(apply_count==1,'View changes must not repeatedly serialize and apply unchanged settings')
handlers.df_local_zh(4)
assert(apply_count==2,'World unload must immediately restore global settings')
print('STARTUP_EVENTS PASS zero repeated overlay writes across 100 view changes')
